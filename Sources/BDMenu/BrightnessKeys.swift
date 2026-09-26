import AppKit
import CoreGraphics
import ApplicationServices

final class BrightnessKeys {
    var onAdjust: ((Int, Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static func isTrusted() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func requestAccess() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    var installed: Bool { tap != nil }

    func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                guard keycode == 144 || keycode == 145 else { return Unmanaged.passUnretained(event) }
                let selfRef = Unmanaged<BrightnessKeys>.fromOpaque(ctx!).takeUnretainedValue()
                let flags = event.flags
                let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
                let delta: Int = keycode == 145 ? 1 : -1
                if selfRef.onAdjust?(delta, fine) == true {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func uninstall() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
        }
        if let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes)
        }
        tap = nil
        source = nil
    }
}
