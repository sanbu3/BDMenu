import XCTest
import ApplicationServices
@testable import BDMenu

final class PasswordPreferenceTests: XCTestCase {
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

    @MainActor
    func testNoMonitoringWhenDisabledOrNoConfirmedDisabledBuiltin() async {
        let preference = PasswordPreferenceController()
        preference.update(enabled: false, disabledBuiltinID: nil)
        XCTAssertEqual(preference.status, .disabled)
        preference.update(enabled: true, disabledBuiltinID: nil)
        XCTAssertEqual(preference.status, .waitingForDisplay)
        preference.update(enabled: false, disabledBuiltinID: 12345)
        XCTAssertEqual(preference.status, .disabled)
        preference.stop()
    }
}
