import XCTest
@testable import BDMenu

@MainActor
final class DisplayStatusTests: XCTestCase {
    func testStatusReflectsExternalUseRatherThanConnectionAlone() async {
        let manager = DisplayManager()
        manager.displays = [.init(id: 1, uuid: "builtin", name: "Built-in", isBuiltin: true, enabled: true)]
        XCTAssertFalse(manager.externalOnline)
        manager.displays.append(.init(id: 2, uuid: "external", name: "External", isBuiltin: false, enabled: false))
        XCTAssertFalse(manager.externalOnline)
        manager.displays[1].enabled = true
        XCTAssertTrue(manager.externalOnline)
        manager.displays = []
        XCTAssertFalse(manager.externalOnline)
    }
}
