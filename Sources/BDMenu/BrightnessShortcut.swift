import AppKit

enum BrightnessAction: String, Codable, CaseIterable, Identifiable {
    case decrease, increase
    var id: String { rawValue }
    var title: String { self == .decrease ? "降低亮度" : "提高亮度" }
    var delta: Int { self == .decrease ? -1 : 1 }
}

enum BrightnessTarget: String, CaseIterable, Identifiable {
    case focusedWindow, mousePointer
    var id: String { rawValue }
    var title: String { self == .focusedWindow ? "活动窗口所在屏幕" : "鼠标所在屏幕" }
}

struct BrightnessShortcut: Codable, Equatable {
    enum Kind: String, Codable { case keyboard, media }
    let kind: Kind
    let code: Int
    let modifiers: UInt64
    let keyLabel: String
    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static let fineModifiers: CGEventFlags = [.maskAlternate, .maskShift]
    static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]
    static let defaultDecrease = Self(kind: .keyboard, code: 118, modifiers: 0, keyLabel: "F4")
    static let defaultIncrease = Self(kind: .keyboard, code: 96, modifiers: 0, keyLabel: "F5")

    var label: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return (flags.contains(.maskControl) ? "⌃" : "") + (flags.contains(.maskAlternate) ? "⌥" : "")
            + (flags.contains(.maskShift) ? "⇧" : "") + (flags.contains(.maskCommand) ? "⌘" : "") + keyLabel
    }
    var isAllowed: Bool {
        kind == .media || Self.functionKeys[code] != nil
            || modifiers & (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue) != 0
    }
    func hasSameBinding(as other: Self) -> Bool {
        kind == other.kind && code == other.code && modifiers == other.modifiers
    }
    func match(kind: Kind, code: Int, flags: CGEventFlags) -> Bool? {
        guard self.kind == kind, self.code == code else { return nil }
        let pressed = flags.intersection(Self.modifierMask).rawValue
        if pressed == modifiers { return false }
        let fine = Self.fineModifiers.rawValue
        if modifiers & fine == 0, pressed == modifiers | fine { return true }
        return nil
    }
}

struct BrightnessKeyEvent {
    let kind: BrightnessShortcut.Kind
    let code: Int
    let flags: CGEventFlags
    let isDown: Bool
    let isRepeat: Bool
    let label: String
    var identity: String { "\(kind.rawValue):\(code)" }
    var shortcut: BrightnessShortcut {
        BrightnessShortcut(kind: kind, code: code,
                           modifiers: flags.intersection(BrightnessShortcut.modifierMask).rawValue, keyLabel: label)
    }
    static func decode(type: CGEventType, event: CGEvent) -> Self? {
        if type == .keyDown || type == .keyUp {
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let label = BrightnessShortcut.functionKeys[code]
                ?? NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? "键 \(code)"
            return Self(kind: .keyboard, code: code, flags: event.flags, isDown: type == .keyDown,
                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, label: label)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let code = (ns.data1 >> 16) & 0xffff
        let state = (ns.data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        let labels = [2: "屏幕亮度＋", 3: "屏幕亮度－", 21: "键盘背光＋", 22: "键盘背光－",
                      0: "音量＋", 1: "音量－", 7: "静音", 16: "播放/暂停", 17: "下一首", 18: "上一首"]
        return Self(kind: .media, code: code, flags: event.flags, isDown: state == 0x0a,
                    isRepeat: ns.data1 & 1 != 0, label: labels[code] ?? "媒体键 \(code)")
    }
}
