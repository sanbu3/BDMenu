import XCTest
import ApplicationServices
@testable import BDMenu

final class PasswordPreferenceTests: XCTestCase {
    func testSettingsAuthorizationSheetsAreEligibleButOrdinarySettingsAreNot() {
        XCTAssertEqual(PasswordFallbackPolicy.scope(bundleID: "com.apple.systempreferences", path: "/System/Applications/System Settings.app"), .settingsSheets)
        XCTAssertNil(PasswordFallbackPolicy.scope(bundleID: "com.apple.systempreferences", path: "/Applications/Fake Settings.app"))
        XCTAssertTrue(PasswordFallbackPolicy.mayInspectRoot(scope: .settingsSheets, role: kAXSheetRole as String, subrole: ""))
        XCTAssertFalse(PasswordFallbackPolicy.mayInspectRoot(scope: .settingsSheets, role: kAXWindowRole as String, subrole: kAXStandardWindowSubrole as String))
    }

    func testFocusTargetsOnlySecurePasswordFields() {
        XCTAssertTrue(PasswordFallbackPolicy.isSecureField(role: kAXTextFieldRole as String, subrole: kAXSecureTextFieldSubrole as String))
        XCTAssertTrue(PasswordFallbackPolicy.isSecureField(role: "AXSecureTextField", subrole: ""))
        XCTAssertFalse(PasswordFallbackPolicy.isSecureField(role: kAXTextFieldRole as String, subrole: ""))
        XCTAssertFalse(PasswordFallbackPolicy.isSecureField(role: kAXTextAreaRole as String, subrole: ""))
    }

    func testActionSuccessAloneCannotConfirmAuthenticationTransition() {
        XCTAssertEqual(AuthenticationTransition.state(targetVisible: false, elapsed: 0), .waiting)
        XCTAssertEqual(AuthenticationTransition.state(targetVisible: false, elapsed: 3), .timedOut)
        XCTAssertEqual(AuthenticationTransition.state(targetVisible: true, elapsed: 1), .ready)
    }

    func testOnlyAppleAuthenticationServicesAreEligible() {
        XCTAssertTrue(PasswordFallbackPolicy.isSystemAuthenticationApp(
            bundleID: "com.apple.SecurityAgent", path: "/System/Library/Frameworks/Security.framework/SecurityAgent.bundle"))
        XCTAssertTrue(PasswordFallbackPolicy.isSystemAuthenticationApp(
            bundleID: "com.apple.LocalAuthentication.UIAgent", path: "/System/Library/Frameworks/LocalAuthentication.framework/Support/coreautha.bundle"))
        XCTAssertFalse(PasswordFallbackPolicy.isSystemAuthenticationApp(
            bundleID: "com.apple.SecurityAgent", path: "/Applications/Example.app"))
        XCTAssertFalse(PasswordFallbackPolicy.isSystemAuthenticationApp(
            bundleID: "com.example.passwords", path: "/System/Library/Example.app"))
        XCTAssertFalse(PasswordFallbackPolicy.isSystemAuthenticationApp(
            bundleID: "com.apple.loginwindow", path: "/System/Library/CoreServices/loginwindow.app"))
    }

    func testLocalizedPasswordFallbackButtonsAreRecognized() {
        for label in ["使用密码…", "使用密码...", "输入密码", "使用密码验证", "Use Password…", "Enter Password...", " use password… "] {
            XCTAssertTrue(PasswordFallbackPolicy.isPasswordFallback(role: kAXButtonRole as String,
                label: label, enabled: true, supportsPress: true), label)
        }
    }

    func testNeverSelectsSubmitCancelOrOtherAuthenticationActions() {
        for label in ["好", "解锁", "允许", "取消", "确认密码", "Password", "Continue", "OK", "Unlock", "Allow", "Use Touch ID", "Change Password", "Use Password to erase disk"] {
            XCTAssertFalse(PasswordFallbackPolicy.isPasswordFallback(role: kAXButtonRole as String,
                label: label, enabled: true, supportsPress: true), label)
        }
    }

    func testTextFieldsDisabledButtonsAndNonActionsAreIgnored() {
        XCTAssertFalse(PasswordFallbackPolicy.isPasswordFallback(role: kAXTextFieldRole as String,
            label: "使用密码", enabled: true, supportsPress: true))
        XCTAssertFalse(PasswordFallbackPolicy.isPasswordFallback(role: kAXButtonRole as String,
            label: "使用密码", enabled: false, supportsPress: true))
        XCTAssertFalse(PasswordFallbackPolicy.isPasswordFallback(role: kAXButtonRole as String,
            label: "使用密码", enabled: true, supportsPress: false))
    }

    func testAuthenticationFollowsActualScreenAndBiometricAvailability() {
        XCTAssertEqual(AuthenticationPreferencePolicy.preferred(builtinActive: true, hasActiveDisplay: true, touchIDAvailable: true), .touchID)
        // Manual disable, closed lid and automation all have the same actual state.
        XCTAssertEqual(AuthenticationPreferencePolicy.preferred(builtinActive: false, hasActiveDisplay: true, touchIDAvailable: true), .password)
        // Desktops without an internal screen, missing or disabled biometrics.
        XCTAssertEqual(AuthenticationPreferencePolicy.preferred(builtinActive: false, hasActiveDisplay: true, touchIDAvailable: false), .password)
        XCTAssertEqual(AuthenticationPreferencePolicy.preferred(builtinActive: true, hasActiveDisplay: true, touchIDAvailable: false), .password)
        XCTAssertNil(AuthenticationPreferencePolicy.preferred(builtinActive: false, hasActiveDisplay: false, touchIDAvailable: true))
        // Re-enabling the internal screen restores the preference in both directions.
        XCTAssertEqual(AuthenticationPreferencePolicy.preferred(builtinActive: true, hasActiveDisplay: true, touchIDAvailable: true), .touchID)
    }

    func testLitMirroredBuiltinIsUsableButSleepingOrDisabledIsNot() {
        XCTAssertTrue(AuthenticationPreferencePolicy.builtinUsable(active: true, mirrored: false, asleep: false))
        XCTAssertTrue(AuthenticationPreferencePolicy.builtinUsable(active: false, mirrored: true, asleep: false))
        XCTAssertFalse(AuthenticationPreferencePolicy.builtinUsable(active: false, mirrored: false, asleep: false))
        XCTAssertFalse(AuthenticationPreferencePolicy.builtinUsable(active: true, mirrored: true, asleep: true))
    }

    func testOnlyExplicitTouchIDMethodButtonsMatch() {
        for label in ["Use Touch ID", "使用触控 ID…", "使用 Touch ID", "使用触控ID"] {
            XCTAssertTrue(PasswordFallbackPolicy.isMethodButton(.touchID, role: kAXButtonRole as String,
                label: label, enabled: true, supportsPress: true))
        }
        for label in ["Unlock", "Allow", "Touch ID", "取消", "Use Password", "Use Touch ID to erase disk"] {
            XCTAssertFalse(PasswordFallbackPolicy.isMethodButton(.touchID, role: kAXButtonRole as String,
                label: label, enabled: true, supportsPress: true))
        }
        XCTAssertFalse(PasswordFallbackPolicy.isMethodButton(.touchID, role: kAXButtonRole as String,
            label: "Use Touch ID", enabled: false, supportsPress: true))
    }

    @MainActor
    func testDisabledPreferenceDoesNotMonitor() {
        let preference = PasswordPreferenceController()
        preference.update(enabled: false)
        XCTAssertEqual(preference.status, .disabled)
        preference.stop()
    }
}
