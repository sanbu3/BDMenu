import XCTest
@testable import BDMenu

final class CompanionAppActionTests: XCTestCase {
    func testClickingForegroundAppHidesAndHiddenAppRestores() {
        XCTAssertEqual(CompanionAppAction.primary(running: true, hidden: false, active: true, toggleEnabled: true), .hide)
        XCTAssertEqual(CompanionAppAction.primary(running: true, hidden: true, active: false, toggleEnabled: true), .reveal)
        XCTAssertEqual(CompanionAppAction.primary(running: true, hidden: true, active: true, toggleEnabled: true), .reveal)
    }
    func testBackgroundAndStoppedAppsOpenAndToggleCanBeDisabled() {
        XCTAssertEqual(CompanionAppAction.primary(running: true, hidden: false, active: false, toggleEnabled: true), .open)
        XCTAssertEqual(CompanionAppAction.primary(running: false, hidden: false, active: false, toggleEnabled: true), .open)
        XCTAssertEqual(CompanionAppAction.primary(running: true, hidden: false, active: true, toggleEnabled: false), .open)
    }
    func testFinderCannotBeQuitAndAppPathsMustMatchExactly() {
        XCTAssertFalse(CompanionAppAction.mayQuit(bundleIdentifier: "com.apple.finder"))
        XCTAssertTrue(CompanionAppAction.mayQuit(bundleIdentifier: "com.example.app"))
        XCTAssertTrue(CompanionAppAction.matchingPath(URL(fileURLWithPath: "/Applications/A.app"), URL(fileURLWithPath: "/Applications/A.app")))
        XCTAssertFalse(CompanionAppAction.matchingPath(URL(fileURLWithPath: "/Applications/A.app"), URL(fileURLWithPath: "/Applications/B.app")))
        XCTAssertFalse(CompanionAppAction.matchingPath(URL(fileURLWithPath: "/Applications/A.app"), URL(string: "https://example.com/Applications/A.app")!))
    }
}
