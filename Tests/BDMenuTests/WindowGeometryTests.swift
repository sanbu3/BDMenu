import XCTest
@testable import BDMenu

final class WindowGeometryTests: XCTestCase {
    func testHUDIsCenteredOnEachScreenIncludingNegativeOrigins() {
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: 0, y: -1080)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
            let visible = screen.insetBy(dx: 0, dy: 40)
            let hud = HUDLayout.frame(screen: screen, visible: visible, scale: 2)
            XCTAssertEqual(hud.midX, screen.midX)
            XCTAssertEqual(hud.minY, visible.minY + 32)
            XCTAssertTrue(screen.contains(hud))
        }
    }

    func testSideDockDoesNotShiftHorizontalCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 80, y: 0, width: 1360, height: 872)
        let hud = HUDLayout.frame(screen: screen, visible: visible)
        XCTAssertEqual(hud.midX, 720)
        XCTAssertEqual(hud.minY, 32)
    }

    func testResizeKeepsTopLeftFixedAndEnforcesMinimum() {
        let original = CGRect(x: -1200, y: 200, width: 840, height: 760)
        let result = WindowGeometry.resized(original, delta: CGSize(width: -900, height: 900), minimum: CGSize(width: 720, height: 560))
        XCTAssertEqual(result.minX, original.minX)
        XCTAssertEqual(result.maxY, original.maxY)
        XCTAssertEqual(result.size, CGSize(width: 720, height: 560))
    }
}
