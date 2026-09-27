import XCTest
@testable import DisplayCore

final class DisplaySnapshotTests: XCTestCase {
    let first = "AAAAAAAA-0000-0000-0000-000000000001"
    let second = "AAAAAAAA-0000-0000-0000-000000000002"
    func testParsesDistinctModesMissingHertzAndDisabledDisplay() {
        let snapshot = DisplaySnapshot("""
        Persistent screen id: \(first)
        Resolution: 1920x1080
        Hertz: N/A
        Color Depth: 8
        Scaling: on
        Origin: (-1920,-240) - main display
        Rotation: 90
        Enabled: true
          mode 0: res:1280x720 color_depth:8
          mode 12: res:1920x1080 hz:60 color_depth:8 scaling:on <-- current mode
        Persistent screen id: \(second)
        Resolution: 0x0
        Hertz: 0
        Enabled: false
        Execute the command below to set your screens to the current arrangement.
        displayplacer "id:\(first) res:1920x1080 enabled:true origin:(-1920,-240) degree:90" "id:\(second) enabled:false"
        """)
        XCTAssertEqual(snapshot.layouts.count, 2)
        XCTAssertEqual(snapshot.layouts[0].x, -1920)
        XCTAssertEqual(snapshot.layouts[0].y, -240)
        XCTAssertEqual(snapshot.layouts[0].rotation, 90)
        XCTAssertNil(snapshot.layouts[0].hertz)
        XCTAssertFalse(snapshot.layouts[0].argument.contains(" hz:"))
        XCTAssertEqual(snapshot.layouts[1].argument, "id:\(second) enabled:false")
        XCTAssertEqual(snapshot.modes[first]?.map(\.id), [0, 12])
        XCTAssertEqual(snapshot.modes[first]?.first(where: \.isCurrent)?.id, 12)
        XCTAssertEqual(snapshot.arguments.count, 2)
    }
    func testMalformedOutputDoesNotProduceUsableConfiguration() {
        let snapshot = DisplaySnapshot("Persistent screen id: unknown\nResolution:\nOrigin: nonsense\nEnabled: true\n mode nonsense")
        XCTAssertTrue(snapshot.layouts.isEmpty)
        XCTAssertTrue(snapshot.arguments.isEmpty)
    }
    func testMoveMainPreservesRelativePositionAndRotation() throws {
        var a = DisplayLayout(); a.uuid = first; a.enabled = true; a.width = 1920; a.height = 1080
        var b = a; b.uuid = second; b.x = -1200; b.y = 240; b.rotation = 90
        let moved = try XCTUnwrap(DisplaySnapshot.movingMain(to: second, in: [a, b]))
        XCTAssertEqual(moved[1].x, 0); XCTAssertEqual(moved[1].y, 0)
        XCTAssertEqual(moved[0].x, 1200); XCTAssertEqual(moved[0].y, -240)
        XCTAssertEqual(moved[1].rotation, 90)
    }
    func testRestoreRequiresSameMonitorsAndAtLeastOneEnabledScreen() {
        let args = ["id:\(first) enabled:true", "id:\(second) enabled:false"]
        XCTAssertTrue(DisplaySnapshot.canRestore(args, connectedIDs: [first, second]))
        XCTAssertFalse(DisplaySnapshot.canRestore(args, connectedIDs: [first]))
        XCTAssertFalse(DisplaySnapshot.canRestore(["id:\(first) enabled:false"], connectedIDs: [first]))
        XCTAssertTrue(DisplaySnapshot.canRestore(["id:\(first)+\(second) enabled:true"], connectedIDs: [first, second]))
    }
    func testQuotedArgumentsStayWholeAndRejectShellSuffix() {
        XCTAssertEqual(DisplaySnapshot.quotedArguments("\"id:\(first) enabled:true origin:(0,0)\""), ["id:\(first) enabled:true origin:(0,0)"])
        XCTAssertNil(DisplaySnapshot.quotedArguments("\"id:\(first) enabled:true\"; echo bad"))
        XCTAssertNil(DisplaySnapshot.quotedArguments("\"id:unterminated"))
    }
}
