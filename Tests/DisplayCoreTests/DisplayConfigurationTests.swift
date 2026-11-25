import XCTest
@testable import DisplayCore

final class DisplayConfigurationTests: XCTestCase {
    let first = "AAAAAAAA-0000-0000-0000-000000000001"
    let second = "AAAAAAAA-0000-0000-0000-000000000002"
    private func screen(_ id: String, _ width: Int, _ height: Int) -> DisplayLayout {
        var item = DisplayLayout(); item.uuid = id; item.width = width; item.height = height
        item.enabled = true; item.hertz = 144; return item
    }

    func testArrangementsKeepModesAndDisabledScreensAndHonorRotation() {
        let a = screen(first, 2560, 1440)
        var b = screen(second, 1920, 1080); b.rotation = 90
        var c = screen("AAAAAAAA-0000-0000-0000-000000000003", 1000, 700); c.enabled = false; c.x = -500
        let row = DisplayArrangement.horizontal.arrange([b, c, a], main: first)
        XCTAssertEqual(row[0].x, 2560); XCTAssertEqual(row[0].hertz, 144)
        XCTAssertEqual(row[1], c); XCTAssertEqual(row[2].x, 0)
        let column = DisplayArrangement.vertical.arrange([a, b], main: first)
        XCTAssertEqual(column[1].y, 1440); XCTAssertEqual(column[1].x, 0)
        c.enabled = true
        let grid = DisplayArrangement.grid.arrange([a, b, c], main: first)
        XCTAssertEqual(grid[2].x, 0); XCTAssertEqual(grid[2].y, 1920)
    }

    func testPresetRequiresExactTopologyAndPersistsColorAndDisabledScreens() throws {
        let a = screen(first, 2560, 1440)
        var b = screen(second, 1470, 956); b.enabled = false
        var snapshot = DisplaySnapshot(""); snapshot.layouts = [a, b]; snapshot.arguments = [a.argument, b.argument]
        let config = DisplayConfiguration(name: "桌面", snapshot: snapshot, profiles: [first: "/Profiles/P3.icc"])
        XCTAssertTrue(config.matches([first, second]))
        XCTAssertFalse(config.matches([first]))
        XCTAssertFalse(config.matches([first, second, "extra"]))
        let decoded = try JSONDecoder().decode(DisplayConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertTrue(config.hasSameLayout(as: snapshot))
        snapshot.layouts[0].x = 100
        XCTAssertFalse(config.hasSameLayout(as: snapshot))
    }

    func testUnsupportedRefreshOrScalingIsNotSubstitutedDuringRestore() {
        let a = screen(first, 2560, 1440)
        var snapshot = DisplaySnapshot(""); snapshot.layouts = [a]; snapshot.arguments = [a.argument]
        let config = DisplayConfiguration(name: "桌面", snapshot: snapshot, profiles: [:])
        snapshot.modes[first] = [DisplayMode(id: 1, width: 2560, height: 1440, hertz: 60, scaling: false, isCurrent: false)]
        XCTAssertFalse(config.isSupported(by: snapshot))
        snapshot.modes[first]?[0].hertz = 144
        XCTAssertTrue(config.isSupported(by: snapshot))
        snapshot.modes[first]?[0].scaling = true
        XCTAssertFalse(config.isSupported(by: snapshot))
    }
}

extension DisplayConfigurationTests {
    func testOfflinePanelIsIncludedAndHandledOutsideDisplayplacer() {
        let a = screen(first, 2560, 1440)
        var snapshot = DisplaySnapshot(""); snapshot.layouts = [a]; snapshot.arguments = [a.argument]
        let full = snapshot.includingDisabled([second])
        XCTAssertEqual(full.layouts.count, 2)
        XCTAssertFalse(full.layouts[1].enabled)
        let plan = DisplayApplicationPlan(full.arguments)
        XCTAssertEqual(plan.arguments, [a.argument])
        XCTAssertEqual(plan.enabledIDs, [first]); XCTAssertEqual(plan.disabledIDs, [second])
        var desired = full; desired.layouts[1] = screen(second, 1470, 956)
        let preset = DisplayConfiguration(name: "双屏", snapshot: desired, profiles: [:])
        snapshot = full
        snapshot.modes[first] = [DisplayMode(id: 1, width: 2560, height: 1440, hertz: 144, scaling: false, isCurrent: true)]
        XCTAssertTrue(preset.isSupported(by: snapshot))
    }
}
