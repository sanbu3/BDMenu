import AppKit
import ApplicationServices

@MainActor
final class FocusedDisplayResolver {
    private var previousApplication: NSRunningApplication?
    private var observer: NSObjectProtocol?
    init() {
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.remember(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
    }
    private func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousApplication = app
    }
    func focusedDisplay(in displays: [DisplayManager.DisplayInfo]) -> CGDirectDisplayID? {
        remember(NSWorkspace.shared.frontmostApplication)
        guard let app = previousApplication, !app.isTerminated else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &rawWindow) == .success,
              let rawWindow, CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = rawWindow as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.05)
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success,
              let rawPosition, let rawSize,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
        // AX and CGDisplayBounds both use global coordinates with the origin at the top left.
        return Self.display(for: CGRect(origin: point, size: size),
                            screens: displays.filter(\.enabled).map { ($0.id, CGDisplayBounds($0.id)) })
    }
    static func display(for window: CGRect, screens: [(CGDirectDisplayID, CGRect)]) -> CGDirectDisplayID? {
        guard !window.isEmpty else { return nil }
        let center = CGPoint(x: window.midX, y: window.midY)
        var best: (CGDirectDisplayID, CGFloat, Bool)?
        for (id, bounds) in screens {
            let intersection = window.intersection(bounds)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let area = intersection.width * intersection.height
            let containsCenter = bounds.contains(center)
            if best == nil || area > best!.1 || (area == best!.1 && containsCenter && !best!.2) {
                best = (id, area, containsCenter)
            }
        }
        return best?.0
    }
    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
