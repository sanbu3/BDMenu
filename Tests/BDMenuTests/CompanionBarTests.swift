import XCTest
@testable import BDMenu

final class CompanionBarTests: XCTestCase {
    private let external = CompanionScreen(id: 1, uuid: "external", name: "External",
        frame: CGRect(x: 0, y: 0, width: 2048, height: 1152), visibleFrame: CGRect(x: 0, y: 0, width: 2048, height: 1128))
    private let builtin = CompanionScreen(id: 2, uuid: "builtin", name: "Built-in",
        frame: CGRect(x: 289, y: -956, width: 1470, height: 956), visibleFrame: CGRect(x: 289, y: -880, width: 1470, height: 856))

    func testFixedBarIgnoresMouseOnLowerDisplay() {
        let selected = CompanionBarRouting.target(mode: .fixed, uuid: "external", screens: [external, builtin],
            pointer: CGPoint(x: 800, y: -500), currentID: 2, interacting: false)
        XCTAssertEqual(selected?.id, 1)
    }
    func testBarStaysInsideUpperScreenAcrossSharedSeam() {
        let frame = CompanionBarRouting.frame(screen: external, itemCount: 40)
        XCTAssertTrue(external.frame.contains(frame))
        XCTAssertFalse(builtin.frame.intersects(frame))
        XCTAssertEqual(frame.midX, external.frame.midX)
        XCTAssertGreaterThan(frame.minY, external.frame.minY)
    }
    func testFollowingMovesDirectlyByScreenAndFreezesDuringInteraction() {
        let point = CGPoint(x: 800, y: -500)
        XCTAssertEqual(CompanionBarRouting.target(mode: .mouse, uuid: "external", screens: [external, builtin],
            pointer: point, currentID: 1, interacting: false)?.id, 2)
        XCTAssertEqual(CompanionBarRouting.target(mode: .mouse, uuid: "external", screens: [external, builtin],
            pointer: point, currentID: 1, interacting: true)?.id, 1)
    }
    func testDisconnectedTargetPausesInMultiScreenAndSingleScreenRemainsUsable() {
        XCTAssertNil(CompanionBarRouting.target(mode: .fixed, uuid: "missing", screens: [external, builtin],
            pointer: .zero, currentID: 1, interacting: false))
        XCTAssertEqual(CompanionBarRouting.target(mode: .fixed, uuid: "external", screens: [builtin],
            pointer: .zero, currentID: 1, interacting: false)?.id, 2)
        XCTAssertNil(CompanionBarRouting.target(mode: .mouse, uuid: "external", screens: [],
            pointer: .zero, currentID: 1, interacting: false))
    }
    func testLowerScreenPlacementAvoidsSystemDockInset() {
        let frame = CompanionBarRouting.frame(screen: builtin, itemCount: 3)
        XCTAssertTrue(builtin.frame.contains(frame))
        XCTAssertGreaterThan(frame.minY, builtin.visibleFrame.minY)
    }
    func testPinnedAppsComeFirstWithoutDuplicatesOrNonApplicationURLs() {
        let a = URL(fileURLWithPath: "/Applications/A.app")
        let b = URL(fileURLWithPath: "/Applications/B.app")
        XCTAssertEqual(CompanionBarRouting.orderedURLs(pinned: [a, a], running: [a, b]), [a, b])
        XCTAssertEqual(CompanionBarRouting.orderedURLs(pinned: [URL(string: "https://example.com/A.app")!],
            running: [URL(fileURLWithPath: "/tmp/note.txt"), b]), [b])
    }
}
