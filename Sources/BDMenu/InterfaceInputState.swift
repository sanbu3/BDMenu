import AppKit
import Observation

/// Keep keyboard navigation visible without leaving a ring after mouse clicks.
@MainActor @Observable
final class InterfaceInputState {
    static let shared = InterfaceInputState()
    var keyboardNavigation = false
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == 48 { self.keyboardNavigation = true }
                else if event.type != .keyDown { self.keyboardNavigation = false }
            }
            return event
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
