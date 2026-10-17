import AppKit
import ApplicationServices
import Observation
import LocalAuthentication
import os

/// Select only an explicit authentication-method button in Apple's UI. This never
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
        return isMethodButton(.password, role: role, label: label, enabled: enabled, supportsPress: supportsPress)
    }

    static func isMethodButton(_ method: AuthenticationMethod, role: String, label: String, enabled: Bool, supportsPress: Bool) -> Bool {
        guard role == kAXButtonRole as String, enabled, supportsPress else { return false }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".… ")).lowercased()
        let labels = method == .password
            ? ["使用密码", "使用密码验证", "输入密码", "use password", "enter password"]
            : ["使用触控 id", "使用触控id", "使用 touch id", "使用touch id", "use touch id"]
        return labels.contains(normalized)
    }
}

enum AuthenticationMethod: String, Equatable, Sendable {
    case password, touchID
    var title: String { self == .password ? "密码" : "Touch ID" }
}

/// Actual display state is authoritative, regardless of which workflow changed it.
enum AuthenticationPreferencePolicy {
    static func preferred(builtinActive: Bool, hasActiveDisplay: Bool, touchIDAvailable: Bool) -> AuthenticationMethod? {
        guard hasActiveDisplay else { return nil }
        return builtinActive && touchIDAvailable ? .touchID : .password
    }

    static func builtinUsable(active: Bool, mirrored: Bool, asleep: Bool) -> Bool {
        (active || mirrored) && !asleep
    }

    static func current() -> AuthenticationMethod? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(64, &ids, &count) == .success else { return nil }
        var online = [CGDirectDisplayID](repeating: 0, count: 64)
        var onlineCount: UInt32 = 0
        guard CGGetOnlineDisplayList(64, &online, &onlineCount) == .success else { return nil }
        // Hardware-mirrored secondary displays are lit but omitted from the active list.
        let builtinActive = online.prefix(Int(onlineCount)).contains { id in
            CGDisplayIsBuiltin(id) != 0 && builtinUsable(active: CGDisplayIsActive(id) != 0,
                mirrored: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay, asleep: CGDisplayIsAsleep(id) != 0)
        }
        let context = LAContext()
        context.interactionNotAllowed = true
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            && context.biometryType == .touchID
        return preferred(builtinActive: builtinActive, hasActiveDisplay: count > 0, touchIDAvailable: available)
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

    func permits(_ expected: Int, method: AuthenticationMethod) -> Bool {
        guard isCurrent(expected), AuthenticationPreferencePolicy.current() == method else { return false }
        return isCurrent(expected)
    }

    private func isCurrent(_ expected: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == expected
    }
}

@MainActor @Observable
final class PasswordPreferenceController {
    enum Status: Equatable {
        case disabled, waitingForDisplay, needsAccessibility
        case watching(AuthenticationMethod), switched(AuthenticationMethod), unavailable(AuthenticationMethod)

        var text: String {
            switch self {
            case .disabled: return "已关闭自动切换，验证方式由系统决定。"
            case .waitingForDisplay: return "正在确认屏幕状态。"
            case .needsAccessibility: return "需要辅助功能权限，才能切换系统验证窗口。"
            case .watching(.touchID): return "内建屏可用，优先 Touch ID。"
            case .watching(.password): return "内建屏或 Touch ID 不可用，优先密码。"
            case .switched(let method): return "已选择\(method.title)验证，请在系统窗口中完成。"
            case .unavailable(let method): return "系统未允许自动切换，请在验证窗口选择\(method.title)。"
            }
        }
        var needsAttention: Bool {
            switch self { case .needsAccessibility, .unavailable: return true; default: return false }
        }
    }

    private static let logger = Logger(subsystem: "com.local.BDMenu", category: "PasswordPreference")
    var status: Status = .disabled {
        didSet {
            if status != oldValue {
                Self.logger.notice("Mode: \(String(describing: self.status), privacy: .public)")
            }
        }
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSwitchAt: Date?
    @ObservationIgnored private var lastMethod: AuthenticationMethod?
    @ObservationIgnored private let gate = PasswordPreferenceGate()
    @ObservationIgnored private let worker = PasswordDialogWorker()

    func update(enabled: Bool) {
        guard enabled else { stop(); status = .disabled; return }
        guard task == nil else { return }
        let generation = gate.invalidate()
        status = AXIsProcessTrusted() ? .waitingForDisplay : .needsAccessibility
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let pids = NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
                    guard let bundle = app.bundleIdentifier, let path = app.bundleURL?.path,
                          PasswordFallbackPolicy.isSystemAuthenticationApp(bundleID: bundle, path: path) else { return nil }
                    return app.processIdentifier
                }
                let (method, result) = await self.worker.scan(pids: pids, gate: self.gate, generation: generation)
                guard !Task.isCancelled else { return }
                if self.lastMethod != method { self.lastSwitchAt = nil; self.lastMethod = method }
                if !AXIsProcessTrusted() { self.status = .needsAccessibility }
                else if let method {
                    switch result {
                    case .switched: self.status = .switched(method); self.lastSwitchAt = Date()
                    case .unavailable: self.status = .unavailable(method)
                    case .noChange:
                        if self.lastSwitchAt.map({ Date().timeIntervalSince($0) < 5 }) != true { self.status = .watching(method) }
                    }
                } else { self.status = .waitingForDisplay }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            }
        }
    }

    func stop() {
        _ = gate.invalidate()
        task?.cancel()
        task = nil
        lastMethod = nil
        lastSwitchAt = nil
    }
}

// All mutable worker state is confined to its private serial queue.
private final class PasswordDialogWorker: @unchecked Sendable {
    enum Result { case noChange, switched, unavailable }
    private let queue = DispatchQueue(label: "com.local.BDMenu.passwordFallback", qos: .utility)
    // Read and updated only on queue. Retain pressed elements until their dialog closes.
    private struct Selection { let window: AXUIElement; let method: AuthenticationMethod }
    private var pressed: [pid_t: [Selection]] = [:]

    func scan(pids: [pid_t], gate: PasswordPreferenceGate, generation: Int) async -> (AuthenticationMethod?, Result) {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let preference = AuthenticationPreferencePolicy.current()
                guard let method = preference, AXIsProcessTrusted() else {
                    continuation.resume(returning: (preference, .noChange)); return
                }
                pressed = pressed.filter { pids.contains($0.key) }
                var result = Result.noChange
                for pid in pids {
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.04)
                    let windows = elements(app, kAXWindowsAttribute)
                    pressed[pid] = pressed[pid, default: []].filter { previous in
                        windows.contains { CFEqual($0, previous.window) }
                    }
                    for window in windows {
                        guard bool(window, kAXMinimizedAttribute) != true else { continue }
                        let matches = fallbackButtons(in: window, method: method)
                        guard !matches.isEmpty else { continue }
                        guard !pressed[pid, default: []].contains(where: { CFEqual($0.window, window) && $0.method == method }) else { continue }
                        // Ambiguous or unfamiliar UI stays under the user's control.
                        guard matches.count == 1, gate.permits(generation, method: method), AXIsProcessTrusted() else { continue }
                        if AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success {
                            pressed[pid, default: []].removeAll { CFEqual($0.window, window) }
                            pressed[pid, default: []].append(Selection(window: window, method: method))
                            result = .switched
                        } else if result != .switched { result = .unavailable }
                    }
                }
                continuation.resume(returning: (method, result))
            }
        }
    }

    private func fallbackButtons(in root: AXUIElement, method: AuthenticationMethod) -> [AXUIElement] {
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
                if PasswordFallbackPolicy.isMethodButton(method, role: role, label: label,
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
