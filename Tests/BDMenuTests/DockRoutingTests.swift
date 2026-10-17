import XCTest
@testable import BDMenu

final class DockRoutingTests: XCTestCase {
    private let left = DockScreen(id: 1, uuid: "left", name: "Left", bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    private let right = DockScreen(id: 2, uuid: "right", name: "Right", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))

    func testPinUsesPersistentIdentityAndPausesWhenScreenIsAbsent() {
        XCTAssertEqual(DockRoutingPolicy.target(uuid: "left", screens: [right, left])?.id, 1)
        XCTAssertNil(DockRoutingPolicy.target(uuid: "missing", screens: [left, right]))
        XCTAssertNil(DockRoutingPolicy.target(uuid: "left", screens: [left]))
        XCTAssertNil(DockRoutingPolicy.target(uuid: "left", screens: [left, left]))
    }
    func testOnlyWrongScreensBottomTriggerZoneIsGuarded() {
        let screens = [left, right]
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: 500, y: 1079), target: 1, screens: screens), CGPoint(x: 500, y: 1073))
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: -500, y: 1079), target: 1, screens: screens), CGPoint(x: -500, y: 1079))
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: 500, y: 800), target: 1, screens: screens), CGPoint(x: 500, y: 800))
    }
    func testCornersAndVerticalScreenPassagesRemainReachable() {
        let below = DockScreen(id: 3, uuid: "below", name: "Below", bounds: CGRect(x: 0, y: 1080, width: 960, height: 1080))
        let screens = [left, right, below]
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: 500, y: 1079), target: 1, screens: screens).y, 1079)
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: 1500, y: 1079), target: 1, screens: screens).y, 1073)
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(CGPoint(x: 2, y: 1079), target: 1, screens: screens).y, 1079)
    }
    func testCompletelyCoveredBottomCannotBeUsedForDockSummoning() {
        let below = DockScreen(id: 3, uuid: "below", name: "Below", bounds: CGRect(x: 0, y: 1080, width: 1920, height: 1080))
        XCTAssertFalse(DockRoutingPolicy.hasExposedBottom(right, screens: [right, below]))
        XCTAssertTrue(DockRoutingPolicy.hasExposedBottom(below, screens: [right, below]))
        let partial = DockScreen(id: 4, uuid: "partial", name: "Partial", bounds: CGRect(x: 289, y: 1080, width: 1470, height: 956))
        XCTAssertTrue(DockRoutingPolicy.hasExposedBottom(right, screens: [right, partial]))
    }

    func testSingleScreenAndInvalidTargetNeverChangeMovement() {
        let point = CGPoint(x: -500, y: 1079)
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(point, target: 2, screens: [left]), point)
        XCTAssertEqual(DockRoutingPolicy.guardedPoint(point, target: 99, screens: [left, right]), point)
    }
}
