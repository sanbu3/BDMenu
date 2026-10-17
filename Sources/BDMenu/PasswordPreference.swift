import AppKit
import ApplicationServices
import Observation
import os

/// Select only the password fallback in Apple's authentication UI. This never
/// changes authentication policy, reads a text-field value, or submits a dialog.
enum PasswordFallbackPolicy {
    static let bundleIDs: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent",
        "com.apple.tcc.AuthorizationPromptService"
    ]

    static func isSystemAuthenticationApp(bundleID: String, path: String) -> Bool {
        bundleIDs.contains(bundleID) && (path as NSString).standardizingPath.hasPrefix("/System/Library/")
    }

    static func isPasswordFallback(role: String, label: String, enabled: Bool, supportsPress: Bool) -> Bool {
        guard role == kAXButtonRole as String, enabled, supportsPress else { return false }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".… ")).lowercased()
        return ["使用密码", "使用密码验证", "输入密码", "use password", "enter password"].contains(normalized)
    }
}

private final class PasswordPreferenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func invalidate() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    func permits(_ expected: Int, builtinID: CGDirectDisplayID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == expected, CGDisplayIsActive(builtinID) == 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(64, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { $0 != builtinID && CGDisplayIsBuiltin($0) == 0 }
    }
}

@MainActor @Observable
final class PasswordPreferenceController {
    enum Status: Equatable {
        case disabled, waitingForDisplay, needsAccessibility, watching, switched, unavailable

        var text: String {
            switch self {
            case .disabled: return "已关闭自动切换。"
            case .waitingForDisplay: return "确认内建屏关闭且外接屏在线后才会自动切换。"
            case .needsAccessibility: return "需要辅助功能权限，才能切换系统验证窗口。"
            case .watching: return "内建屏已关闭：等待可切换的系统验证窗口。"
            case .switched: return "已切换到密码，请在系统窗口中输入。"
            case .unavailable: return "系统未允许切换，请在验证窗口中手动选择“使用密码”。"
            }
        }
    }

    private static let logger = Logger(subsystem: "com.local.BDMenu", category: "PasswordPreference")
    var status: Status = .disabled {
        didSet {
            if status != oldValue {
                // Log only the mode, never authentication-window contents.
                Self.logger.notice("Mode: \(String(describing: self.status), privacy: .public)")
            }
        }
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSwitchAt: Date?
    @ObservationIgnored private var observedBuiltinID: CGDirectDisplayID?
    @ObservationIgnored private let gate = PasswordPreferenceGate()
    @ObservationIgnored private let worker = PasswordDialogWorker()

    func update(enabled: Bool, disabledBuiltinID: CGDirectDisplayID?) {
        guard enabled, let id = disabledBuiltinID else {
            stop()
            status = enabled ? .waitingForDisplay : .disabled
            return
        }
        guard task == nil || observedBuiltinID != id else { return }
        stop()
        observedBuiltinID = id
        let generation = gate.invalidate()
        status = AXIsProcessTrusted() ? .watching : .needsAccessibility
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if AXIsProcessTrusted() {
                    let pids = NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
                        guard let bundle = app.bundleIdentifier, let path = app.bundleURL?.path,
                              PasswordFallbackPolicy.isSystemAuthenticationApp(bundleID: bundle, path: path) else { return nil }
                        return app.processIdentifier
                    }
                    let result = await self.worker.scan(pids: pids, gate: self.gate, generation: generation, builtinID: id)
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .switched: self.status = .switched; self.lastSwitchAt = Date()
                    case .unavailable: self.status = .unavailable
                    case .noChange:
                        if self.lastSwitchAt.map({ Date().timeIntervalSince($0) < 5 }) != true { self.status = .watching }
                    }
                } else { self.status = .needsAccessibility }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            }
        }
    }

    func stop() {
        _ = gate.invalidate()
        task?.cancel()
        task = nil
        observedBuiltinID = nil
        lastSwitchAt = nil
    }
}

// All mutable worker state is confined to its private serial queue.
private final class PasswordDialogWorker: @unchecked Sendable {
    enum Result { case noChange, switched, unavailable }
    private let queue = DispatchQueue(label: "com.local.BDMenu.passwordFallback", qos: .utility)
    // Read and updated only on queue. Retain pressed elements until their dialog closes.
    private var pressed: [pid_t: [AXUIElement]] = [:]

    func scan(pids: [pid_t], gate: PasswordPreferenceGate, generation: Int, builtinID: CGDirectDisplayID) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard gate.permits(generation, builtinID: builtinID) else {
                    continuation.resume(returning: .noChange); return
                }
                pressed = pressed.filter { pids.contains($0.key) }
                var result = Result.noChange
                for pid in pids {
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.04)
                    let windows = elements(app, kAXWindowsAttribute)
                    pressed[pid] = pressed[pid, default: []].filter { previous in
                        windows.contains { CFEqual($0, previous) }
                    }
                    for window in windows {
                        guard bool(window, kAXMinimizedAttribute) != true else { continue }
                        let matches = fallbackButtons(in: window)
                        if matches.isEmpty {
                            pressed[pid]?.removeAll { CFEqual($0, window) }
                            continue
                        }
                        guard !pressed[pid, default: []].contains(where: { CFEqual($0, window) }) else { continue }
                        // Ambiguous or unfamiliar UI stays under the user's control.
                        guard matches.count == 1, gate.permits(generation, builtinID: builtinID), AXIsProcessTrusted() else { continue }
                        if AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success {
                            pressed[pid, default: []].append(window)
                            result = .switched
                        } else if result != .switched { result = .unavailable }
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func fallbackButtons(in root: AXUIElement) -> [AXUIElement] {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var matches: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(0.15)
        var visited = 0
        while visited < 120, Date() < deadline, let (element, depth) = pending.popLast() {
            visited += 1
            AXUIElementSetMessagingTimeout(element, 0.03)
            let role = string(element, kAXRoleAttribute) ?? ""
            // Never inspect children or values of editable controls.
            if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String { continue }
            if role == kAXButtonRole as String {
                let title = string(element, kAXTitleAttribute) ?? ""
                let label = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? string(element, kAXDescriptionAttribute) ?? "" : title
                var actions: CFArray?
                AXUIElementCopyActionNames(element, &actions)
                let supportsPress = (actions as? [String])?.contains(kAXPressAction as String) == true
                if PasswordFallbackPolicy.isPasswordFallback(role: role, label: label,
                    enabled: bool(element, kAXEnabledAttribute) == true, supportsPress: supportsPress) {
                    matches.append(element)
                }
            }
            let children = elements(element, kAXChildrenAttribute)
            if depth >= 9 && !children.isEmpty { return [] }
            pending.append(contentsOf: children.map { ($0, depth + 1) })
        }
        // A partial traversal cannot establish that a match is unique.
        return pending.isEmpty ? matches : []
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func elements(_ element: AXUIElement, _ key: String) -> [AXUIElement] { attribute(element, key) as? [AXUIElement] ?? [] }
    private func string(_ element: AXUIElement, _ key: String) -> String? { attribute(element, key) as? String }
    private func bool(_ element: AXUIElement, _ key: String) -> Bool? { attribute(element, key) as? Bool }
}
