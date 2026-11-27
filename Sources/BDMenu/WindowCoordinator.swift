import AppKit
import ApplicationServices
import Observation
import DisplayCore

private let windowCallback: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }
    let coordinator = Unmanaged<WindowCoordinator>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in coordinator.received(element, notification: notification as String) }
}

@MainActor @Observable
final class WindowCoordinator {
    private struct Record {
        let token: String
        let pid: pid_t
        let element: AXUIElement
        var failed = false
    }
    var smoothResizing = UserDefaults.standard.object(forKey: "windows.smooth.v1") as? Bool ?? true
    var enabled = UserDefaults.standard.bool(forKey: "windows.enabled.v1")
    var restoreOnReconnect = UserDefaults.standard.object(forKey: "windows.reconnect.v1") as? Bool ?? true
    var allowlistOnly = UserDefaults.standard.bool(forKey: "windows.allowlist.v1")
    var applicationList = UserDefaults.standard.string(forKey: "windows.applications.v1") ?? ""
    private(set) var observedWindows = 0
    private(set) var adjustedWindows = 0
    private(set) var trusted = false
    private(set) var status = "窗口适配已关闭"
    @ObservationIgnored private let state: DeviceStateStore
    @ObservationIgnored private var records: [Record] = []
    @ObservationIgnored private var observers: [pid_t: AXObserver] = [:]
    @ObservationIgnored private var memory = WindowPlacementMemory()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pointerMonitor: Any?
    @ObservationIgnored private var topologyPending = false
    @ObservationIgnored private var needsScan = false
    @ObservationIgnored private var dirtyTokens = Set<String>()
    @ObservationIgnored private var writingTokens = Set<String>()
    @ObservationIgnored private var userEditsDuringTopology = Set<String>()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var reconciling = false

    init(state: DeviceStateStore) { self.state = state }
    var excludedBundleIDs: Set<String> {
        Set(applicationList.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    func configure() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "windows.enabled.v1")
        defaults.set(smoothResizing, forKey: "windows.smooth.v1")
        defaults.set(restoreOnReconnect, forKey: "windows.reconnect.v1")
        defaults.set(allowlistOnly, forKey: "windows.allowlist.v1")
        defaults.set(applicationList, forKey: "windows.applications.v1")
        stop()
        start()
    }
    func start() {
        guard enabled else { status = "窗口适配已关闭"; return }
        trusted = AXIsProcessTrusted()
        guard trusted else { status = "需要辅助功能权限"; return }
        guard !running else { return }
        running = true
        refreshApplications()
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.state.topologyIsStable || self.state.isConfiguring,
                   let focused = WindowAccessibility.focusedWindow(pid: self.state.frontmostPID),
                   let record = self.records.first(where: { CFEqual($0.element, focused) }) {
                    self.userEditsDuringTopology.insert(record.token)
                }
                self.schedule()
            }
        }
        status = "监听窗口事件 · 松开鼠标后适配"
    }
    func stop() {
        pending?.cancel(); pending = nil
        running = false
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll(); records.removeAll(); memory.clear()
        observedWindows = 0; topologyPending = false; dirtyTokens.removeAll(); userEditsDuringTopology.removeAll()
    }
    func checkPermission() {
        guard enabled else { return }
        let value = AXIsProcessTrusted()
        if trusted != value { trusted = value; stop(); start() }
    }
    func prepareForConfiguration() {
        guard running, state.topologyIsStable, !state.mouseIsDown else { return }
        for record in records {
            if let frame = WindowAccessibility.frame(record.element) {
                _ = memory.observe(id: record.token, frame: frame, screens: state.screens)
            }
        }
    }
    func suspendForTopology() { pending?.cancel(); topologyPending = true }
    func topologySettled() {
        guard running else { return }
        topologyPending = true
        schedule()
    }
    private func eligible(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated, let bundle = app.bundleIdentifier,
              !["com.apple.systempreferences", "com.apple.loginwindow", "com.apple.SecurityAgent"].contains(bundle) else { return false }
        return allowlistOnly ? excludedBundleIDs.contains(bundle) : !excludedBundleIDs.contains(bundle)
    }
    func refreshApplications() {
        guard running, !state.isSleeping, AXIsProcessTrusted() else { return }
        guard state.topologyIsStable else { needsScan = true; return }
        let apps = NSWorkspace.shared.runningApplications.filter(eligible)
        let active = Set(apps.map(\.processIdentifier))
        for pid in Set(observers.keys).subtracting(active) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            for record in records.filter({ $0.pid == pid }) { memory.remove(record.token) }
            records.removeAll { $0.pid == pid }
        }
        for app in apps where observers[app.processIdentifier] == nil {
            var result: AXObserver?
            guard AXObserverCreate(app.processIdentifier, windowCallback, &result) == .success, let observer = result else { continue }
            observers[app.processIdentifier] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            let element = AXUIElementCreateApplication(app.processIdentifier)
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        discoverWindows()
    }
    private func discoverWindows() {
        for (pid, observer) in observers {
            let app = AXUIElementCreateApplication(pid)
            guard let windows = WindowAccessibility.value(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let live = Array(windows.prefix(48))
            for old in records.filter({ $0.pid == pid && !live.contains($0.element) }) { memory.remove(old.token) }
            records.removeAll { $0.pid == pid && !live.contains($0.element) }
            for window in live where !records.contains(where: { CFEqual($0.element, window) }) {
                guard WindowAccessibility.canManage(window), let frame = WindowAccessibility.frame(window) else { continue }
                let record = Record(token: UUID().uuidString, pid: pid, element: window)
                records.append(record)
                // Registration only: enabling the feature does not immediately move existing windows.
                _ = memory.observe(id: record.token, frame: frame, screens: state.screens)
                for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                    AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
        }
        observedWindows = records.count
    }
    fileprivate func received(_ window: AXUIElement, notification: String) {
        guard running else { return }
        if notification == kAXUIElementDestroyedNotification {
            if let record = records.first(where: { CFEqual($0.element, window) }) { memory.remove(record.token) }
            records.removeAll { CFEqual($0.element, window) }
            observedWindows = records.count
            return
        }
        if let record = records.first(where: { CFEqual($0.element, window) }) {
            guard !writingTokens.contains(record.token) else { return }
            dirtyTokens.insert(record.token)
        }
        needsScan = needsScan || notification == kAXWindowCreatedNotification || notification == kAXFocusedWindowChangedNotification
        // Ignore OS relocation notifications while the topology/transaction is unstable.
        guard state.automaticActionsAllowed else { return }
        schedule()
    }
    private func schedule() {
        guard running, !reconciling, topologyPending || needsScan || !dirtyTokens.isEmpty else { return }
        pending?.cancel()
        let expected = state.topologyVersion
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, self.running, self.state.automaticActionsAllowed,
                  self.state.topologyVersion == expected, !self.state.mouseIsDown else { return }
            if self.needsScan { self.refreshApplications(); self.needsScan = false }
            let topology = self.topologyPending
            self.topologyPending = false
            let dirty = self.dirtyTokens
            self.dirtyTokens.removeAll()
            await self.reconcile(topology: topology, dirty: dirty)
        }
    }
    private func reconcile(topology: Bool, dirty: Set<String>) async {
        guard !reconciling else { return }
        reconciling = true
        defer { reconciling = false; schedule() }
        guard AXIsProcessTrusted() else { checkPermission(); return }
        let screens = state.screens
        guard !screens.isEmpty else { return }
        let candidates = records
        for record in candidates {
            guard !Task.isCancelled, state.automaticActionsAllowed, !state.mouseIsDown else { return }
            guard records.contains(where: { $0.token == record.token }) else { continue }
            guard topology || dirty.contains(record.token) else { continue }
            guard !record.failed, WindowAccessibility.canManage(record.element),
                  let frame = WindowAccessibility.frame(record.element) else { continue }
            let userEdited = userEditsDuringTopology.remove(record.token) != nil
            guard let desired = memory.observe(id: record.token, frame: frame, screens: screens,
                                               topologyChange: topology && restoreOnReconnect && !userEdited) else { continue }
            writingTokens.insert(record.token)
            let actualFrame = await adjust(record, from: frame, to: desired, animated: !topology)
            writingTokens.remove(record.token)
            guard !Task.isCancelled, state.automaticActionsAllowed, !state.mouseIsDown else {
                // Preserve the previous home when an interrupted transition is superseded by a topology change.
                if let actualFrame { memory.didWrite(id: record.token, actual: actualFrame, screens: screens, rememberNewScreen: false) }
                return
            }
            guard let index = records.firstIndex(where: { $0.token == record.token }) else { continue }
            guard let actual = actualFrame else {
                records[index].failed = true
                status = "部分窗口拒绝调整，已跳过；重新开启可重试"
                continue
            }
            memory.didWrite(id: record.token, actual: actual, screens: screens)
            adjustedWindows += 1
            if !WindowPlacementPolicy.approximatelyEqual(desired, actual) {
                records[index].failed = true
                status = "部分应用有最小尺寸限制，已停止重复调整"
            }
        }
    }
    private func adjust(_ record: Record, from: CGRect, to: CGRect, animated: Bool) async -> CGRect? {
        let version = state.topologyVersion
        let shouldAnimate = animated && smoothResizing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let steps = shouldAnimate ? 10 : 1
        var actual = from
        for step in 1...steps {
            guard !Task.isCancelled, running, state.topologyVersion == version,
                  state.automaticActionsAllowed, !state.mouseIsDown else { return actual }
            let started = Date()
            let desired = WindowPlacementPolicy.interpolate(from: from, to: to, progress: Double(step)/Double(steps))
            guard let next = WindowAccessibility.write(desired, to: record.element) else { return nil }
            actual = next
            // Slow or busy AX clients get one final bounded adjustment instead of a backlog of frames.
            if step < steps, Date().timeIntervalSince(started) > 0.035 {
                guard state.topologyVersion == version, !state.mouseIsDown else { return actual }
                return WindowAccessibility.write(to, to: record.element)
            }
            if step < steps {
                do { try await Task.sleep(for: .milliseconds(18)) } catch { return actual }
            }
        }
        return actual
    }
    func forget() { memory.clear(); status = "已清除本次运行的窗口记忆" }
}
