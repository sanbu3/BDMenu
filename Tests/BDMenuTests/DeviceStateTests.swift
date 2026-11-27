import XCTest
@testable import BDMenu

@MainActor
final class DeviceStateTests: XCTestCase {
    func testConfigurationAndEmergencyRevisionsDoNotBecomeStablePrematurely() async {
        let state = DeviceStateStore()
        XCTAssertFalse(state.automaticActionsAllowed)
        let revision = state.actionRevision
        state.cancelActions()
        XCTAssertGreaterThan(state.actionRevision, revision)
        let topology = state.topologyVersion
        state.configurationChanged(true)
        XCTAssertTrue(state.isConfiguring)
        XCTAssertGreaterThan(state.topologyVersion, topology)
        XCTAssertFalse(state.topologyIsStable)
        state.configurationChanged(false)
        // A stopped service cannot schedule a false stable event.
        XCTAssertFalse(state.automaticActionsAllowed)
    }
    func testPerformanceTemplatesArePerDisplayAndDoNotInventModes() async {
        let state = DeviceStateStore()
        let performance = PerformanceController(state: state)
        let display = UUID().uuidString
        XCTAssertEqual(performance.spec(.lowPower, uuid: display).hertz, 60)
        XCTAssertTrue(performance.spec(.quality, uuid: display).scaling)
        XCTAssertFalse(performance.spec(.performance, uuid: display).scaling)
    }
}
