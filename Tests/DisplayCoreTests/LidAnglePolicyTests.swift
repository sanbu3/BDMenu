import XCTest
@testable import DisplayCore

final class LidAnglePolicyTests: XCTestCase {
    func testTentThenExtendedWithHysteresis() {
        var policy = LidAnglePolicy()
        XCTAssertNil(policy.update(angle: 55, close: 65, open: 80, now: 0))
        XCTAssertEqual(policy.update(angle: 55, close: 65, open: 80, now: 1), true)
        XCTAssertNil(policy.update(angle: 72, close: 65, open: 80, now: 2))
        XCTAssertTrue(policy.externalOnly)
        XCTAssertNil(policy.update(angle: 100, close: 65, open: 80, now: 3))
        XCTAssertEqual(policy.update(angle: 100, close: 65, open: 80, now: 4), false)
    }

    func testBriefMovementAndMissingSamplesResetDwell() {
        var policy = LidAnglePolicy()
        XCTAssertNil(policy.update(angle: 40, close: 65, open: 80, now: 0))
        XCTAssertNil(policy.update(angle: 90, close: 65, open: 80, now: 0.5))
        XCTAssertNil(policy.update(angle: 40, close: 65, open: 80, now: 0.6))
        XCTAssertNil(policy.update(angle: nil, close: 65, open: 80, now: 1))
        XCTAssertNil(policy.update(angle: 40, close: 65, open: 80, now: 2))
        XCTAssertFalse(policy.externalOnly)
        XCTAssertEqual(policy.update(angle: 40, close: 65, open: 80, now: 3), true)
    }

    func testInvalidReportsCannotDisableScreen() {
        var policy = LidAnglePolicy()
        for angle in [Double.nan, .infinity, -1, 65535] {
            XCTAssertNil(policy.update(angle: angle, close: 65, open: 80, now: 0))
            XCTAssertNil(policy.update(angle: angle, close: 65, open: 80, now: 10))
        }
        XCTAssertFalse(policy.externalOnly)
    }
}
