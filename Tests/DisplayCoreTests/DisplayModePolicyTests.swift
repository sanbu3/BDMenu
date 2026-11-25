import XCTest
@testable import DisplayCore

final class DisplayModePolicyTests: XCTestCase {
    func testHiDPIShortcutPrefersSameSizeAndKeepsRefreshRate() {
        let current = mode(1, hz: 144, scaling: false)
        let exact = mode(3, hz: 144)
        XCTAssertEqual(DisplayModePolicy.scalingMode(true, current: current,
            available: [mode(2, hz: 60), exact])?.id, 3)
        XCTAssertNil(DisplayModePolicy.scalingMode(true, current: current,
            available: [mode(2, hz: 60)]))
        XCTAssertEqual(DisplayModePolicy.scalingMode(false, current: exact,
            available: [current])?.id, 1)
    }

    func testHiDPIFallbackAvoidsStretchingAndDoesNotPickLargerDesktop() {
        let current = DisplayMode(id: 1, width: 2560, height: 1440, hertz: 144, scaling: false, isCurrent: true)
        let smaller = mode(2, hz: 144)
        let duplicate = mode(3, hz: 144)
        let wrongAspect = DisplayMode(id: 4, width: 2304, height: 1440, hertz: 144, scaling: true, isCurrent: false)
        let larger = DisplayMode(id: 5, width: 3840, height: 2160, hertz: 144, scaling: true, isCurrent: false)
        let modes = [wrongAspect, larger, smaller, duplicate, mode(6, hz: 60)]
        XCTAssertEqual(DisplayModePolicy.scalingMode(true, current: current, available: modes)?.id, 2)
        XCTAssertEqual(DisplayModePolicy.hiDPIModes(current: current, available: modes).map(\.id), [5, 2])
        XCTAssertNil(DisplayModePolicy.scalingMode(false, current: smaller, available: [current]))
        XCTAssertNil(DisplayModePolicy.scalingMode(true, current: mode(7, hz: nil, scaling: false), available: modes))
    }

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
