import AppKit
import CoreGraphics
import ApplicationServices

@MainActor
final class BrightnessKeys {
    var decrease = BrightnessShortcut.defaultDecrease
    var increase = BrightnessShortcut.defaultIncrease
    var enabled = false
    var nativeKeysEnabled = true
    var recording: BrightnessAction?
    var onRecord: ((BrightnessShortcut?) -> Void)?
    // Resolve the target and schedule work; never perform DDC I/O in this callback.
    var onAdjust: ((Int, Bool) -> Bool)?
    private var consumed = Set<String>()
    private var recordingHeld = Set<String>()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static func isTrusted() -> Bool { AXIsProcessTrusted() }
    static func requestAccess() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    var installed: Bool { tap != nil }

    func install() {
        guard tap == nil, Self.isTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue) | CGEventMask(1 << 14)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                guard let ctx else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let keys = Unmanaged<BrightnessKeys>.fromOpaque(ctx).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        keys.consumed.removeAll()
                        keys.recordingHeld.removeAll()
                        if BrightnessKeys.isTrusted(), let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    guard let input = BrightnessKeyEvent.decode(type: type, event: event) else {
                        return Unmanaged.passUnretained(event)
                    }
                    return keys.handle(input) ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    /// Consume only keys owned by BDMenu and their matching releases.
    func handle(_ input: BrightnessKeyEvent) -> Bool {
        if !input.isDown {
            recordingHeld.remove(input.identity)
            return consumed.remove(input.identity) != nil
        }
        if recordingHeld.contains(input.identity) { return true }
        if recording != nil {
            consumed.insert(input.identity)
            recordingHeld.insert(input.identity)
            if !input.isRepeat {
                let cancel = input.kind == .keyboard && input.code == 53
                onRecord?(cancel ? nil : input.shortcut)
            }
            return true
        }
        guard enabled else { return consumed.contains(input.identity) }
        if input.isRepeat && !consumed.contains(input.identity) { return false }
        for (binding, delta) in [(decrease, -1), (increase, 1)] {
            if let fine = binding.match(kind: input.kind, code: input.code, flags: input.flags) {
                if onAdjust?(delta, fine) == true {
                    consumed.insert(input.identity)
                    return true
                }
                return consumed.contains(input.identity)
            }
        }
        if nativeKeysEnabled {
            let delta: Int?
            if input.kind == .media { delta = input.code == 2 ? 1 : input.code == 3 ? -1 : nil }
            else { delta = [113, 145].contains(input.code) ? 1 : [107, 144].contains(input.code) ? -1 : nil }
            if let delta {
                let pressed = input.flags.intersection(BrightnessShortcut.modifierMask)
                guard pressed.isEmpty || pressed == BrightnessShortcut.fineModifiers || pressed == BrightnessShortcut.legacyFineModifiers else {
                    return consumed.contains(input.identity)
                }
                if onAdjust?(delta, !pressed.isEmpty) == true {
                    consumed.insert(input.identity)
                    return true
                }
            }
        }
        return consumed.contains(input.identity)
    }

    func uninstall() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        consumed.removeAll()
        recordingHeld.removeAll()
    }

}
