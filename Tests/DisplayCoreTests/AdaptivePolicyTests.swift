import XCTest
@testable import DisplayCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class AdaptivePolicyTests: XCTestCase {
    private let large = ScreenRegion(id: "large", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                     visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1370))
    private let small = ScreenRegion(id: "small", frame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
                                     visibleFrame: CGRect(x: -1440, y: 225, width: 1440, height: 820))
    func testFitPreservesAspectAndVisibleAreaAcrossNegativeCoordinates() {
        let original = CGRect(x: -1700, y: 100, width: 1800, height: 1200)
        let result = WindowPlacementPolicy.fit(original, into: small.visibleFrame)
        XCTAssertTrue(small.visibleFrame.contains(result))
        XCTAssertEqual(result.width / result.height, 1.5, accuracy: 0.01)
        XCTAssertLessThanOrEqual(result.width, original.width)
    }
    func testScreenCoordinatesRespectMenuBarAndPrimaryOrigin() {
        let appKit = CGRect(x: -1440, y: -400, width: 1440, height: 800)
        XCTAssertEqual(WindowPlacementPolicy.axRect(appKit, primaryTop: 900),
                       CGRect(x: -1440, y: 500, width: 1440, height: 800))
    }
    func testCrossScreenRoundTripRestoresOriginalSize() {
        var memory = WindowPlacementMemory()
        let original = CGRect(x: 100, y: 100, width: 1800, height: 1000)
        XCTAssertNil(memory.observe(id: "window", frame: original, screens: [large, small]))
        let dragged = CGRect(x: -1400, y: 240, width: 1800, height: 1000)
        let fitted = memory.observe(id: "window", frame: dragged, screens: [large, small])!
        memory.didWrite(id: "window", actual: fitted, screens: [large, small])
        XCTAssertTrue(small.visibleFrame.contains(fitted))
        let returning = CGRect(x: 150, y: 100, width: fitted.width, height: fitted.height)
        XCTAssertEqual(memory.observe(id: "window", frame: returning, screens: [large, small]), original)
    }
    func testDisconnectAndReconnectKeepsSourceMemory() {
        var memory = WindowPlacementMemory()
        let original = CGRect(x: 200, y: 120, width: 1900, height: 1100)
        _ = memory.observe(id: "window", frame: original, screens: [large, small])
        let osMoved = CGRect(x: -1400, y: 230, width: 1900, height: 1100)
        let fitted = memory.observe(id: "window", frame: osMoved, screens: [small], topologyChange: true)!
        memory.didWrite(id: "window", actual: fitted, screens: [small])
        XCTAssertEqual(memory.observe(id: "window", frame: fitted, screens: [large, small], topologyChange: true), original)
    }
    func testUserResizeDuringDisconnectionSupersedesOldHome() {
        var memory = WindowPlacementMemory()
        let original = CGRect(x: 100, y: 100, width: 1800, height: 1000)
        _ = memory.observe(id: "window", frame: original, screens: [large, small])
        let shifted = CGRect(x: -1400, y: 230, width: 1800, height: 1000)
        let fitted = memory.observe(id: "window", frame: shifted, screens: [small], topologyChange: true)!
        memory.didWrite(id: "window", actual: fitted, screens: [small])
        let edited = CGRect(x: -1300, y: 300, width: 800, height: 600)
        _ = memory.observe(id: "window", frame: edited, screens: [small])
        XCTAssertNil(memory.observe(id: "window", frame: edited, screens: [large, small], topologyChange: true))
    }
    func testResolutionRollbackRestoresPreShrinkFrame() {
        var memory = WindowPlacementMemory()
        let original = CGRect(x: 100, y: 100, width: 1800, height: 1000)
        _ = memory.observe(id: "w", frame: original, screens: [large])
        let smaller = ScreenRegion(id: large.id, frame: CGRect(x: 0, y: 0, width: 1280, height: 720),
                                   visibleFrame: CGRect(x: 0, y: 25, width: 1280, height: 650))
        let fitted = memory.observe(id: "w", frame: original, screens: [smaller], topologyChange: true)!
        memory.didWrite(id: "w", actual: fitted, screens: [smaller])
        // Our own AX notifications must not overwrite the larger saved rectangle.
        XCTAssertNil(memory.observe(id: "w", frame: fitted, screens: [smaller]))
        XCTAssertEqual(memory.observe(id: "w", frame: fitted, screens: [large], topologyChange: true), original)
    }
    func testIndependentWindowIdentityAndNoScreensAreSafe() {
        var memory = WindowPlacementMemory()
        let one = CGRect(x: 100, y: 100, width: 500, height: 400)
        let two = CGRect(x: 200, y: 200, width: 800, height: 600)
        XCTAssertNil(memory.observe(id: "a", frame: one, screens: []))
        _ = memory.observe(id: "a", frame: one, screens: [large])
        _ = memory.observe(id: "b", frame: two, screens: [large])
        memory.remove("a")
        XCTAssertNil(memory.observe(id: "b", frame: two, screens: [large], topologyChange: true))
    }
    func testPerformanceDwellMissingDataAndCooldown() {
        var policy = PerformancePolicy()
        XCTAssertNil(policy.evaluate(usage: 90, now: 0, blocked: false, reduced: false))
        XCTAssertNil(policy.evaluate(usage: nil, now: 10, blocked: false, reduced: false))
        XCTAssertNil(policy.evaluate(usage: 90, now: 15, blocked: false, reduced: false))
        XCTAssertEqual(policy.evaluate(usage: 90, now: 36, blocked: false, reduced: false), .reduce)
        XCTAssertNil(policy.evaluate(usage: 20, now: 40, blocked: false, reduced: true))
        XCTAssertNil(policy.evaluate(usage: 20, now: 105, blocked: false, reduced: true))
        XCTAssertEqual(policy.evaluate(usage: 20, now: 130, blocked: false, reduced: true), .restore)
    }
    func testDraggingAndInvalidSamplesNeverTriggerModeWrites() {
        var policy = PerformancePolicy()
        for sample in [Double.nan, .infinity, -1, 101] {
            XCTAssertNil(policy.evaluate(usage: sample, now: 0, blocked: false, reduced: false))
            XCTAssertNil(policy.evaluate(usage: sample, now: 500, blocked: false, reduced: false))
        }
        XCTAssertNil(policy.evaluate(usage: 95, now: 600, blocked: false, reduced: false))
        XCTAssertNil(policy.evaluate(usage: 95, now: 650, blocked: true, reduced: false))
        XCTAssertNil(policy.evaluate(usage: 95, now: 660, blocked: false, reduced: false))
        XCTAssertEqual(policy.evaluate(usage: 95, now: 681, blocked: false, reduced: false), .reduce)
    }
    func testRefreshReductionNeverChangesDesktopOrHiDPI() {
        let current = DisplayMode(id: 1, width: 1920, height: 1080, hertz: 144, scaling: true, isCurrent: true)
        let choices = [DisplayMode(id: 2, width: 2560, height: 1440, hertz: 120, scaling: false, isCurrent: false),
                       DisplayMode(id: 3, width: 1920, height: 1080, hertz: 120, scaling: true, isCurrent: false),
                       DisplayMode(id: 4, width: 1920, height: 1080, hertz: 60, scaling: true, isCurrent: false)]
        XCTAssertEqual(PerformancePolicy.lowerRefresh(current: current, available: choices)?.id, 3)
        XCTAssertNil(PerformancePolicy.lowerRefresh(current: current, available: [choices[0]]))
    }
    func testEnlargeMovesBeforeGrowingAgainstAppKitConstraints() {
        let area = CGRect(x: 0, y: 30, width: 1920, height: 962)
        var actual = CGRect(x: 40, y: 208, width: 1470, height: 724)
        let target = CGRect(x: 40, y: 109, width: 1670, height: 823)
        for change in WindowPlacementPolicy.changes(from: actual, to: target) {
            switch change {
            case .position(let origin): actual.origin = origin
            case .size(let size):
                // Model AppKit's clamping at the current origin, the real 40-point regression.
                actual.size = CGSize(width: min(size.width, area.maxX-actual.minX),
                                     height: min(size.height, area.maxY-actual.minY))
            }
        }
        XCTAssertEqual(actual, target)
    }
    func testSmoothTransitionHasExactEndpointsAndNoOvershoot() {
        let from = CGRect(x: -1400, y: 250, width: 1800, height: 1000)
        let to = CGRect(x: -1440, y: 250, width: 1400, height: 778)
        XCTAssertEqual(WindowPlacementPolicy.interpolate(from: from, to: to, progress: 0), from)
        XCTAssertEqual(WindowPlacementPolicy.interpolate(from: from, to: to, progress: 1), to)
        var lastWidth = from.width
        for step in 1...10 {
            let frame = WindowPlacementPolicy.interpolate(from: from, to: to, progress: Double(step)/10)
            XCTAssertLessThanOrEqual(frame.width, lastWidth)
            XCTAssertGreaterThanOrEqual(frame.width, to.width)
            XCTAssertGreaterThan(frame.height, 0)
            lastWidth = frame.width
        }
    }
    func testAutomaticLeaseRejectsChangedModeOrTopology() {
        let id = UUID().uuidString
        var snapshot = DisplaySnapshot("")
        let mode = DisplayMode(id: 1, width: 1920, height: 1080, hertz: 60, scaling: true, isCurrent: true)
        snapshot.modes[id] = [mode]
        let lease = AutomaticDisplayLease(originalArguments: [], appliedModes: [id: .init(mode)], connectedIDs: [id])
        XCTAssertTrue(lease.stillOwns(snapshot, connectedIDs: [id]))
        XCTAssertFalse(lease.stillOwns(snapshot, connectedIDs: []))
        snapshot.modes[id]?[0].hertz = 120
        XCTAssertFalse(lease.stillOwns(snapshot, connectedIDs: [id]))
    }
}
