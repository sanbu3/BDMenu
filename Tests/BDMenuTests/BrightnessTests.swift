import XCTest
import AppKit
@testable import BDMenu

@MainActor
final class BrightnessTests: XCTestCase {
    private func key(_ code: Int, flags: CGEventFlags = [], down: Bool = true, repeatKey: Bool = false,
                     kind: BrightnessShortcut.Kind = .keyboard) -> BrightnessKeyEvent {
        BrightnessKeyEvent(kind: kind, code: code, flags: flags, isDown: down, isRepeat: repeatKey,
                           label: BrightnessShortcut.functionKeys[code] ?? "Test")
    }

    func testF4F5AndFineAdjustments() async {
        let keys = BrightnessKeys()
        keys.enabled = true
        var calls: [(Int, Bool)] = []
        keys.onAdjust = { calls.append(($0, $1)); return true }
        XCTAssertTrue(keys.handle(key(118)))
        XCTAssertTrue(keys.handle(key(118, down: false)))
        XCTAssertTrue(keys.handle(key(96, flags: [.maskAlternate, .maskShift])))
        XCTAssertEqual(calls.map(\.0), [-1, 1])
        XCTAssertEqual(calls.map(\.1), [false, true])
        XCTAssertTrue(keys.handle(key(96, down: false)))
        XCTAssertFalse(keys.handle(key(96, flags: .maskCommand)))
        XCTAssertFalse(keys.handle(key(97)))
        XCTAssertEqual(calls.count, 2)
    }

    func testReleaseAndRepeatOwnership() async {
        let keys = BrightnessKeys()
        keys.enabled = true
        var count = 0
        keys.onAdjust = { _, _ in count += 1; return true }
        XCTAssertTrue(keys.handle(key(118)))
        XCTAssertTrue(keys.handle(key(118, repeatKey: true)))
        // A modifier change before release must not leak an unmatched keyUp.
        XCTAssertTrue(keys.handle(key(118, flags: .maskCommand, down: false)))
        XCTAssertFalse(keys.handle(key(118, down: false)))
        XCTAssertEqual(count, 2)
        keys.onAdjust = { _, _ in false }
        XCTAssertFalse(keys.handle(key(118)))
        XCTAssertFalse(keys.handle(key(118, down: false)))
    }

    func testDisabledKeysAndNativeMedia() async {
        let keys = BrightnessKeys()
        var calls: [Int] = []
        keys.onAdjust = { delta, _ in calls.append(delta); return true }
        XCTAssertFalse(keys.handle(key(118)))
        keys.enabled = true
        XCTAssertTrue(keys.handle(key(3, kind: .media)))
        XCTAssertTrue(keys.handle(key(2, kind: .media)))
        XCTAssertTrue(keys.handle(key(107)))
        XCTAssertTrue(keys.handle(key(113)))
        XCTAssertEqual(calls, [-1, 1, -1, 1])
        XCTAssertFalse(keys.handle(key(0, kind: .media)))
        keys.nativeKeysEnabled = false
        XCTAssertTrue(keys.handle(key(3, down: false, kind: .media)))
        XCTAssertFalse(keys.handle(key(3, kind: .media)))
    }

    func testRecordDoesNotAdjustAndHeldKeyDoesNotActivateNewBinding() async {
        let keys = BrightnessKeys()
        keys.enabled = true
        keys.recording = .decrease
        var recorded: BrightnessShortcut?
        var count = 0
        keys.onAdjust = { _, _ in count += 1; return true }
        keys.onRecord = { recorded = $0; keys.decrease = $0!; keys.recording = nil }
        XCTAssertTrue(keys.handle(key(97)))
        XCTAssertEqual(recorded?.code, 97)
        XCTAssertTrue(keys.handle(key(97, repeatKey: true)))
        XCTAssertTrue(keys.handle(key(97, down: false)))
        XCTAssertEqual(count, 0)
        XCTAssertTrue(keys.handle(key(97)))
        XCTAssertEqual(count, 1)
    }

    func testShortcutPersistenceAndExactModifiers() async throws {
        let shortcut = BrightnessShortcut(kind: .keyboard, code: 0, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "A")
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(BrightnessShortcut.self, from: data), shortcut)
        XCTAssertTrue(shortcut.isAllowed)
        XCTAssertEqual(shortcut.match(kind: .keyboard, code: 0, flags: [.maskCommand, .maskAlphaShift]), false)
        XCTAssertEqual(shortcut.match(kind: .keyboard, code: 0, flags: [.maskCommand, .maskShift, .maskAlternate]), true)
        XCTAssertNil(shortcut.match(kind: .keyboard, code: 0, flags: .maskControl))
        XCTAssertFalse(BrightnessShortcut(kind: .keyboard, code: 0, modifiers: 0, keyLabel: "A").isAllowed)
    }

    func testCGEventDecoding() async throws {
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 118, keyDown: true))
        let decoded = try XCTUnwrap(BrightnessKeyEvent.decode(type: .keyDown, event: down))
        XCTAssertEqual(decoded.code, 118)
        XCTAssertEqual(decoded.label, "F4")
        XCTAssertTrue(decoded.isDown)
        let ns = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8, data1: (3 << 16) | (0x0a << 8), data2: -1))
        let cg = try XCTUnwrap(ns.cgEvent)
        let media = try XCTUnwrap(BrightnessKeyEvent.decode(type: CGEventType(rawValue: 14)!, event: cg))
        XCTAssertEqual(media.kind, .media)
        XCTAssertEqual(media.code, 3)
        XCTAssertTrue(media.isDown)
    }

    func testFocusTargetAcrossHorizontalVerticalAndSpanningWindows() async {
        let screens: [(CGDirectDisplayID, CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            (2, CGRect(x: -2560, y: 0, width: 2560, height: 1440)),
            (3, CGRect(x: 0, y: -1440, width: 2560, height: 1440))
        ]
        XCTAssertEqual(FocusedDisplayResolver.display(for: CGRect(x: 50, y: 50, width: 900, height: 600), screens: screens), 1)
        XCTAssertEqual(FocusedDisplayResolver.display(for: CGRect(x: -2200, y: 50, width: 900, height: 600), screens: screens), 2)
        XCTAssertEqual(FocusedDisplayResolver.display(for: CGRect(x: 50, y: -1200, width: 900, height: 600), screens: screens), 3)
        XCTAssertEqual(FocusedDisplayResolver.display(for: CGRect(x: -600, y: 50, width: 1000, height: 600), screens: screens), 2)
        XCTAssertNil(FocusedDisplayResolver.display(for: CGRect(x: 9000, y: 0, width: 900, height: 600), screens: screens))
        XCTAssertNil(FocusedDisplayResolver.display(for: .zero, screens: screens))
    }
}
