import AppKit
import ApplicationServices
import DisplayCore

/// Short AX timeouts and typed reads; never read titles or window content.
enum WindowAccessibility {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.06)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        value(element, attribute) as? Bool ?? false
    }
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        guard pid > 0, AXIsProcessTrusted(), let raw = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), let s = value(window, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        let frame = CGRect(origin: point, size: size)
        return WindowPlacementPolicy.valid(frame) ? frame : nil
    }
    static func canManage(_ window: AXUIElement) -> Bool {
        guard value(window, kAXRoleAttribute) as? String == kAXWindowRole,
              value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              !bool(window, kAXMinimizedAttribute), !bool(window, "AXFullScreen"), !bool(window, kAXModalAttribute) else { return false }
        var position = DarwinBoolean(false); var size = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &position) == .success
            && AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &size) == .success
            && position.boolValue && size.boolValue
    }
    static func write(_ frame: CGRect, to window: AXUIElement) -> CGRect? {
        guard let original = self.frame(window) else { return nil }
        func apply(_ changes: [WindowFrameChange]) -> Bool {
            for change in changes {
                let attribute: String
                let value: AXValue?
                switch change {
                case .size(var size):
                    attribute = kAXSizeAttribute; value = AXValueCreate(.cgSize, &size)
                case .position(var point):
                    attribute = kAXPositionAttribute; value = AXValueCreate(.cgPoint, &point)
                }
                guard let value,
                      AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success else { return false }
            }
            return true
        }
        guard apply(WindowPlacementPolicy.changes(from: original, to: frame)) else {
            if let partial = self.frame(window) {
                _ = apply(WindowPlacementPolicy.changes(from: partial, to: original))
            }
            return nil
        }
        return self.frame(window)
    }
}
