import AppKit
import CoreGraphics
import ApplicationServices

@MainActor
final class BrightnessKeys {
    var onAdjust: ((Int, Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handledPresses = Set<Int>()

    static func isTrusted() -> Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        // This call returns the CURRENT state. Authorization happens asynchronously.
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
    var installed: Bool { tap != nil }

    @discardableResult
    func install() -> Bool {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        guard Self.isTrusted() else { return false }
        let systemDefined = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << systemDefined.rawValue)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // The tap's run loop source is explicitly installed on the main run loop.
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
                    return owner.handle(type, event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else { return false }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handledPresses.removeAll()
            if Self.isTrusted(), let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        var key: Int
        var delta: Int
        var isDown: Bool
        var isRepeat = false
        if type.rawValue == NSEvent.EventType.systemDefined.rawValue {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let mediaKey = (ns.data1 >> 16) & 0xffff
            guard mediaKey == 2 || mediaKey == 3 else { return Unmanaged.passUnretained(event) }
            let state = (ns.data1 >> 8) & 0xff
            guard state == 0x0a || state == 0x0b else { return Unmanaged.passUnretained(event) }
            key = mediaKey + 1000
            delta = mediaKey == 2 ? 1 : -1
            isDown = state == 0x0a
            isRepeat = (ns.data1 & 1) != 0
        } else {
            key = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard key == 144 || key == 145 else { return Unmanaged.passUnretained(event) }
            delta = key == 145 ? 1 : -1
            isDown = type == .keyDown
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        }
        if !isDown {
            return handledPresses.remove(key) != nil ? nil : Unmanaged.passUnretained(event)
        }
        // Never start swallowing half of a press when the pointer moves between screens.
        if isRepeat && !handledPresses.contains(key) { return Unmanaged.passUnretained(event) }
        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        if onAdjust?(delta, fine) == true {
            handledPresses.insert(key)
            return nil
        }
        return handledPresses.contains(key) ? nil : Unmanaged.passUnretained(event)
    }

    func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        handledPresses.removeAll()
    }
}
