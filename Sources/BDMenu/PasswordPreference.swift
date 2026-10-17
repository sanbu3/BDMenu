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

    enum Scope: Equatable, Sendable { case service, settingsSheets }
    struct Process: Sendable { let pid: pid_t; let scope: Scope }

    static func scope(bundleID: String, path: String) -> Scope? {
        if isSystemAuthenticationApp(bundleID: bundleID, path: path) { return .service }
        if bundleID == "com.apple.systempreferences",
           (path as NSString).standardizingPath == "/System/Applications/System Settings.app" { return .settingsSheets }
        return nil
    }

    static func mayInspectRoot(scope: Scope, role: String, subrole: String) -> Bool {
        scope == .service || role == kAXSheetRole as String
            || (role == kAXWindowRole as String && subrole == kAXSystemDialogSubrole as String)
    }

    static func isSecureField(role: String, subrole: String) -> Bool {
        role == "AXSecureTextField" || (role == kAXTextFieldRole as String && subrole == kAXSecureTextFieldSubrole as String)
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

enum AuthenticationTransition {
    enum State: Equatable { case waiting, ready, timedOut }
    static func state(targetVisible: Bool, elapsed: TimeInterval) -> State {
        if targetVisible { return .ready }
        return elapsed < 3 ? .waiting : .timedOut
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
        case watching(AuthenticationMethod), switching(AuthenticationMethod), switched(AuthenticationMethod), unavailable(AuthenticationMethod)

        var text: String {
            switch self {
            case .disabled: return "已关闭自动切换，验证方式由系统决定。"
            case .waitingForDisplay: return "正在确认屏幕状态。"
            case .needsAccessibility: return "需要辅助功能权限，才能切换系统验证窗口。"
            case .watching(.touchID): return "内建屏可用，优先 Touch ID。"
            case .watching(.password): return "内建屏或 Touch ID 不可用，优先密码。"
            case .switching(let method): return "正在切换到\(method.title)，等待确认输入页面。"
            case .switched(.password): return "已进入密码输入页，请在系统窗口中输入。"
            case .switched(.touchID): return "已进入 Touch ID 验证页。"
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
    var diagnostics = "等待系统授权窗口。"
    var testMessage: String?
    var isTesting = false
    @ObservationIgnored private var testContext: LAContext?
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
                let processes = NSWorkspace.shared.runningApplications.compactMap { app -> PasswordFallbackPolicy.Process? in
                    guard let bundle = app.bundleIdentifier, let path = app.bundleURL?.path,
                          let scope = PasswordFallbackPolicy.scope(bundleID: bundle, path: path) else { return nil }
                    return PasswordFallbackPolicy.Process(pid: app.processIdentifier, scope: scope)
                }
                let (method, result, diagnostics) = await self.worker.scan(processes: processes, gate: self.gate, generation: generation)
                guard !Task.isCancelled else { return }
                self.diagnostics = diagnostics
                if self.lastMethod != method { self.lastSwitchAt = nil; self.lastMethod = method }
                if !AXIsProcessTrusted() { self.status = .needsAccessibility }
                else if let method {
                    switch result {
                    case .switching: self.status = .switching(method)
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

    func testAuthentication() {
        testContext?.invalidate()
        let context = LAContext()
        context.localizedFallbackTitle = "使用密码"
        testContext = context
        isTesting = true
        testMessage = "测试验证窗口已打开，可以直接取消，不会修改系统设置。"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "测试跟随屏幕的验证方式。可以取消，不会修改任何系统设置。") { [weak self] success, _ in
            Task { @MainActor in
                guard self?.testContext === context else { return }
                self?.isTesting = false
                self?.testMessage = success ? "已完成测试验证。" : "测试已结束或取消，没有修改系统设置。"
                self?.testContext = nil
            }
        }
    }

    func cancelTest() {
        if isTesting { testMessage = "测试已取消，没有修改系统设置。" }
        isTesting = false
        testContext?.invalidate(); testContext = nil
    }

    func stop() {
        cancelTest()
        _ = gate.invalidate()
        task?.cancel()
        task = nil
        lastMethod = nil
        lastSwitchAt = nil
    }
}

// All mutable worker state is confined to its private serial queue.
private final class PasswordDialogWorker: @unchecked Sendable {
    enum Result { case noChange, switching, switched, unavailable }
    private var scanComplete = true
    private var lastAXError: Int32 = 0
    private let queue = DispatchQueue(label: "com.local.BDMenu.passwordFallback", qos: .utility)
    // Read and updated only on queue. Retain pressed elements until their dialog closes.
    private struct Selection {
        let window: AXUIElement
        let method: AuthenticationMethod
        let attemptedAt: Date
        var confirmed: Bool
    }
    private struct Dialog {
        var methodButtons: [AXUIElement] = []
        var secureFields: [AXUIElement] = []
        var hasPasswordFallback = false
    }
    private var pressed: [pid_t: [Selection]] = [:]

    func scan(processes: [PasswordFallbackPolicy.Process], gate: PasswordPreferenceGate, generation: Int) async -> (AuthenticationMethod?, Result, String) {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let pids = processes.map(\.pid)
                scanComplete = true
                lastAXError = 0
                var windowCount = 0
                var matchCount = 0
                let preference = AuthenticationPreferencePolicy.current()
                guard let method = preference, AXIsProcessTrusted() else {
                    continuation.resume(returning: (preference, .noChange, "系统认证服务 \(pids.count) 个；等待可读取的授权窗口。")); return
                }
                pressed = pressed.filter { pids.contains($0.key) }
                var result = Result.noChange
                for process in processes {
                    let pid = process.pid
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.04)
                    let windows = dialogRoots(in: app, scope: process.scope)
                    windowCount += windows.count
                    pressed[pid] = pressed[pid, default: []].filter { previous in
                        windows.contains { CFEqual($0, previous.window) }
                    }
                    for window in windows {
                        guard bool(window, kAXMinimizedAttribute) != true else { continue }
                        let dialog = inspectDialog(in: window, method: method)
                        let matches = dialog.methodButtons
                        matchCount += matches.count
                        let targetVisible = method == .password ? dialog.secureFields.count == 1
                            : dialog.hasPasswordFallback && dialog.secureFields.isEmpty
                        if let selected = pressed[pid, default: []].first(where: { CFEqual($0.window, window) && $0.method == method }) {
                            guard !selected.confirmed else { continue }
                            switch AuthenticationTransition.state(targetVisible: targetVisible, elapsed: Date().timeIntervalSince(selected.attemptedAt)) {
                            case .ready:
                                guard gate.permits(generation, method: method), AXIsProcessTrusted() else { continue }
                                if method == .password { focusPassword(dialog.secureFields) }
                                pressed[pid]?.removeAll { CFEqual($0.window, window) }
                                pressed[pid, default: []].append(Selection(window: window, method: method, attemptedAt: selected.attemptedAt, confirmed: true))
                                result = .switched
                            case .waiting: if result == .noChange { result = .switching }
                            case .timedOut: if result != .switched { result = .unavailable }
                            }
                            continue
                        }
                        // A password page may already be showing when monitoring begins.
                        if method == .password, targetVisible, gate.permits(generation, method: method), AXIsProcessTrusted() {
                            focusPassword(dialog.secureFields)
                            pressed[pid, default: []].append(Selection(window: window, method: method, attemptedAt: Date(), confirmed: true))
                            result = .switched
                            continue
                        }
                        guard matches.count == 1, gate.permits(generation, method: method), AXIsProcessTrusted() else { continue }
                        if AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success {
                            pressed[pid, default: []].removeAll { CFEqual($0.window, window) }
                            pressed[pid, default: []].append(Selection(window: window, method: method, attemptedAt: Date(), confirmed: false))
                            if result != .switched { result = .switching }
                        } else if result != .switched { result = .unavailable }
                    }
                }
                continuation.resume(returning: (method, result, "服务 \(pids.count) · 窗口 \(windowCount) · 入口 \(matchCount) · 完整读取 \(scanComplete ? "是" : "否") · AX \(lastAXError)"))
            }
        }
    }

    private func dialogRoots(in app: AXUIElement, scope: PasswordFallbackPolicy.Scope) -> [AXUIElement] {
        var candidates = elements(app, kAXWindowsAttribute)
        if let raw = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
            candidates.append(raw as! AXUIElement)
        }
        // Settings presents authorization as a sheet, owned by its own process.
        for window in candidates {
            candidates.append(contentsOf: elements(window, "AXSheets"))
            candidates.append(contentsOf: elements(window, kAXChildrenAttribute).filter {
                string($0, kAXRoleAttribute) == kAXSheetRole as String
            })
        }
        var roots: [AXUIElement] = []
        for candidate in candidates where !roots.contains(where: { CFEqual($0, candidate) }) {
            if PasswordFallbackPolicy.mayInspectRoot(scope: scope,
                role: string(candidate, kAXRoleAttribute) ?? "", subrole: string(candidate, kAXSubroleAttribute) ?? "") {
                roots.append(candidate)
            }
        }
        return roots
    }

    private func inspectDialog(in root: AXUIElement, method: AuthenticationMethod) -> Dialog {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var dialog = Dialog()
        let deadline = Date().addingTimeInterval(0.15)
        var visited = 0
        while visited < 120, Date() < deadline, let (element, depth) = pending.popLast() {
            visited += 1
            AXUIElementSetMessagingTimeout(element, 0.03)
            let role = string(element, kAXRoleAttribute) ?? ""
            // Never inspect children or values of editable controls.
            if role == kAXTextFieldRole as String || role == "AXSecureTextField" {
                if PasswordFallbackPolicy.isSecureField(role: role, subrole: string(element, kAXSubroleAttribute) ?? "") {
                    dialog.secureFields.append(element)
                }
                continue
            }
            if role == kAXTextAreaRole as String { continue }
            if role == kAXButtonRole as String {
                let title = string(element, kAXTitleAttribute) ?? ""
                let label = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? string(element, kAXDescriptionAttribute) ?? "" : title
                var actions: CFArray?
                AXUIElementCopyActionNames(element, &actions)
                let supportsPress = (actions as? [String])?.contains(kAXPressAction as String) == true
                if PasswordFallbackPolicy.isMethodButton(method, role: role, label: label,
                    enabled: bool(element, kAXEnabledAttribute) == true, supportsPress: supportsPress) {
                    dialog.methodButtons.append(element)
                }
                if PasswordFallbackPolicy.isPasswordFallback(role: role, label: label,
                    enabled: bool(element, kAXEnabledAttribute) == true, supportsPress: supportsPress) {
                    dialog.hasPasswordFallback = true
                }
            }
            let children = elements(element, kAXChildrenAttribute)
            if depth >= 9 && !children.isEmpty { scanComplete = false; return Dialog() }
            pending.append(contentsOf: children.map { ($0, depth + 1) })
        }
        // A partial traversal cannot establish that a match is unique.
        if !pending.isEmpty { scanComplete = false }
        return pending.isEmpty ? dialog : Dialog()
    }

    private func focusPassword(_ fields: [AXUIElement]) {
        guard fields.count == 1 else { return }
        // Only set focus. Never read a field's value or synthesize a keystroke.
        _ = AXUIElementSetAttributeValue(fields[0], kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &result)
        guard error == .success else { lastAXError = error.rawValue; return nil }
        return result
    }
    private func elements(_ element: AXUIElement, _ key: String) -> [AXUIElement] { attribute(element, key) as? [AXUIElement] ?? [] }
    private func string(_ element: AXUIElement, _ key: String) -> String? { attribute(element, key) as? String }
    private func bool(_ element: AXUIElement, _ key: String) -> Bool? { attribute(element, key) as? Bool }
}
