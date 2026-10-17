import AppKit
import ApplicationServices

/// Ask Dock.app to show its own live menu. Never copy app-defined menu contents
/// or simulate a different menu in the companion. The system chooses placement.
final class NativeDockMenu: @unchecked Sendable {
    enum Result: Sendable { case shown, permissionRequired, itemMissing, unavailable }
    private let lock = NSLock()
    private var generation = 0
    func cancel() { lock.withLock { generation += 1 } }
    private func permits(_ token: Int) -> Bool { lock.withLock { generation == token } }
    private let queue = DispatchQueue(label: "com.local.BDMenu.nativeDockMenu", qos: .userInitiated)

    func show(for url: URL) async -> Result {
        guard AXIsProcessTrusted() else { return .permissionRequired }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first(where: {
            $0.bundleURL?.standardizedFileURL.path == "/System/Library/CoreServices/Dock.app"
        })?.processIdentifier else { return .unavailable }
        let token = lock.withLock { generation += 1; return generation }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: show(url: url, pid: pid, token: token)) }
        }
    }
    private func show(url: URL, pid: pid_t, token: Int) -> Result {
        guard permits(token) else { return .unavailable }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.05)
        let deadline = Date().addingTimeInterval(1.2)
        let lists = elements(dock, kAXChildrenAttribute).filter { string($0, kAXRoleAttribute) == kAXListRole as String }
        for list in lists {
            AXUIElementSetMessagingTimeout(list, 0.04)
            for item in elements(list, kAXChildrenAttribute) where Date() < deadline {
                AXUIElementSetMessagingTimeout(item, 0.04)
                let raw = attribute(item, "AXURL")
                let actual = (raw as? URL) ?? (raw as? String).flatMap { URL(string: $0) }
                guard let actual, CompanionAppAction.matchingPath(actual, url) else { continue }
                var actions: CFArray?
                guard AXUIElementCopyActionNames(item, &actions) == .success,
                      (actions as? [String])?.contains(kAXShowMenuAction as String) == true,
                      permits(token), AXIsProcessTrusted(), AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success else { return .unavailable }
                // Confirm a real menu appeared instead of equating AXPress success with UI success.
                for _ in 0..<8 {
                    let shown = attribute(item, "AXShownMenuUIElement")
                    if let menus = shown as? [AXUIElement], !menus.isEmpty { return .shown }
                    if let shown, CFGetTypeID(shown) == AXUIElementGetTypeID() { return .shown }
                    if elements(item, kAXChildrenAttribute).contains(where: { string($0, kAXRoleAttribute) == kAXMenuRole as String }) { return .shown }
                    Thread.sleep(forTimeInterval: 0.04)
                }
                return .unavailable
            }
        }
        return .itemMissing
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private func string(_ element: AXUIElement, _ key: String) -> String? { attribute(element, key) as? String }
    private func elements(_ element: AXUIElement, _ key: String) -> [AXUIElement] { attribute(element, key) as? [AXUIElement] ?? [] }
}
