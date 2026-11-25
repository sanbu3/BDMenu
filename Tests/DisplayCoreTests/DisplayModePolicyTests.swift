import XCTest
@testable import DisplayCore

final class DisplayModePolicyTests: XCTestCase {
    private func mode(_ id: Int, hz: Int?, scaling: Bool = true, current: Bool = false) -> DisplayMode {
        DisplayMode(id: id, width: 2048, height: 1152, hertz: hz, scaling: scaling, isCurrent: current)
    }

    func testRefreshChangePreservesSizeAndScaling() {
        let current = mode(1, hz: 180, current: true)
        let modes = [mode(2, hz: 60, scaling: false), mode(3, hz: 60), mode(4, hz: 120)]
        XCTAssertEqual(DisplayModePolicy.refreshMode(60, current: current, available: modes)?.id, 3)
        XCTAssertEqual(DisplayModePolicy.refreshMode(120, current: current, available: modes)?.id, 4)
        XCTAssertNil(DisplayModePolicy.refreshMode(75, current: current, available: modes))
    }

    func testAlreadyAtRequestedRefreshReturnsCurrentAndUnknownRefreshIsNotGuessed() {
        let current = mode(1, hz: 60, current: true)
        XCTAssertEqual(DisplayModePolicy.refreshMode(60, current: current, available: [current, mode(2, hz: 60)])?.id, 1)
        XCTAssertNil(DisplayModePolicy.refreshMode(60, current: mode(3, hz: nil), available: [mode(4, hz: nil)]))
    }

    func testModeComparisonIgnoresCurrentMarkerButRequiresSameFormat() {
        XCTAssertTrue(DisplayModePolicy.sameFormat(mode(1, hz: 60), mode(8, hz: 60, current: true)))
        XCTAssertFalse(DisplayModePolicy.sameFormat(mode(1, hz: 60), mode(2, hz: 60, scaling: false)))
    }
}
