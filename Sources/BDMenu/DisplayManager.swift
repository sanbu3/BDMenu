import Foundation
import CoreGraphics
import Observation
import ServiceManagement
import AppKit
import SwiftUI
import DisplayCore

private let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in manager.scheduleRefresh() }
}

@MainActor @Observable
final class DisplayManager {
    enum Dimming: String { case unknown, hardware, software }
    struct DisplayInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let uuid: String
        let name: String
        let isBuiltin: Bool
        var enabled: Bool
    }
    struct Controls {
        var brightness: Double = 100
        var maximumBrightness: Double = 100
        var input = 0
        var hasInput = false
        var dimming: Dimming = .unknown
        var modes: [DisplayMode] = []
        var currentMode = -1
        var renderDescription = ""
        var colorProfiles: [DisplayColorProfile] = []
        var colorProfile = ""
    }
    private struct Gamma {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    var currentLayouts: [DisplayLayout] = []
    var configurationPresets = DisplayManager.loadConfigurations("display.presets.v1")
    var recentConfigurations = DisplayManager.loadConfigurations("display.recent.v1")
    var restoreRecentOnLaunch = UserDefaults.standard.object(forKey: "restoreRecentOnLaunch") as? Bool ?? true
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTrialSnapshot: DisplaySnapshot?
    @ObservationIgnored private var pendingProfiles: [String: String] = [:]
    var displays: [DisplayInfo] = []
    var controls: [CGDirectDisplayID: Controls] = [:]
    var mainID: CGDirectDisplayID = 0
    var mirrored = false
    var lastError: String?
    var isApplying = false
    var modeTrialSeconds = 0
    var modeTrialLabel: String?
    @ObservationIgnored private var modeTrialTask: Task<Void, Never>?
    private let modeRecoveryKey = "pendingModeRecovery.v1"
    let hardware = HardwareMonitor()
    var lidAutomation = UserDefaults.standard.bool(forKey: "lidAutomation")
    var lidCloseAngle = min(145, max(10, UserDefaults.standard.object(forKey: "lidCloseAngle") as? Double ?? 65))
    var lidOpenAngle = min(150, max(15, UserDefaults.standard.object(forKey: "lidOpenAngle") as? Double ?? 80))
    @ObservationIgnored private var lidPolicy = LidAnglePolicy()
    @ObservationIgnored private var lastLidWrite = Date.distantPast
    var autoWorkflow = UserDefaults.standard.bool(forKey: "autoWorkflow")
    var preferPasswordWhenBuiltinOff = UserDefaults.standard.object(forKey: "preferPasswordWhenBuiltinOff") as? Bool ?? true
    let passwordPreference = PasswordPreferenceController()
    let identification = DisplayIdentification()
    var syncKeyboardBacklight = UserDefaults.standard.object(forKey: "syncKeyboardBacklight") as? Bool ?? true
    var keyboardEnabled = UserDefaults.standard.object(forKey: "brightnessKeyboardEnabled") as? Bool ?? true
    var brightnessTarget = BrightnessTarget(rawValue: UserDefaults.standard.string(forKey: "brightnessTarget") ?? "") ?? .focusedWindow
    var decreaseShortcut = DisplayManager.loadShortcut("brightnessDecrease") ?? .defaultDecrease
    var increaseShortcut = DisplayManager.loadShortcut("brightnessIncrease") ?? .defaultIncrease
    var nativeBrightnessKeys = UserDefaults.standard.object(forKey: "nativeBrightnessKeys") as? Bool ?? true
    var recordingAction: BrightnessAction?
    var shortcutMessage: String?
    var keysTrusted = false
    var keysInstalled = false
    var loginStatus = SMAppService.mainApp.status

    @ObservationIgnored private let keys = BrightnessKeys()
    @ObservationIgnored private let focusResolver = FocusedDisplayResolver()
    @ObservationIgnored private let keyboardBacklight = KeyboardBacklightController()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var originalGamma: [CGDirectDisplayID: Gamma] = [:]
    @ObservationIgnored private var knownBuiltinID: CGDirectDisplayID?
    @ObservationIgnored private var previousExternals = Set<String>()
    @ObservationIgnored private var previousExternalOnline = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var preWorkflowBrightness: Double?
    @ObservationIgnored private var changedBuiltinForWorkflow = false
    @ObservationIgnored private var workflowHoldsBuiltinOff = false
    @ObservationIgnored private var userRestoredBuiltin = false
    @ObservationIgnored private var lastExternalSeen = Date.distantPast
    @ObservationIgnored private var lastWorkflowWrite = Date.distantPast
    @ObservationIgnored private var toggleChecks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    @ObservationIgnored private var suppressCaptureUntil = Date.distantPast
    @ObservationIgnored private var hud: NSPanel?
    @ObservationIgnored private var hudHideTask: Task<Void, Never>?

    static let displayToggleError = "显示器开关操作失败，当前 macOS 可能不支持此接口。"
    let inputOptions: [(Int, String)] = [(15, "DP 1"), (16, "DP 2"), (17, "HDMI 1"), (18, "HDMI 2"), (27, "USB-C")]
    var builtin: DisplayInfo? { displays.first { $0.isBuiltin } }
    var externalOnline: Bool { displays.contains { !$0.isBuiltin && $0.enabled } }
    var keyboardBacklightAvailable: Bool { keyboardBacklight != nil }
    var launchAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2" }
    private var connectedIDs: Set<String> { Set(displays.map(\.uuid).filter { !$0.isEmpty }) }
    private var activeDisplayIDs: Set<String> { Set(displays.filter(\.enabled).map(\.uuid)) }
    private var layoutKey: String { "layout.v2." + connectedIDs.sorted().joined(separator: "+") }
    func state(_ id: CGDirectDisplayID) -> Controls { controls[id] ?? Controls() }
    private func mutateState(_ id: CGDirectDisplayID, _ update: (inout Controls) -> Void) {
        guard var value = controls[id] else { return }
        update(&value)
        controls[id] = value
    }

    func start() {
        guard !started else { return }
        started = true
        lidOpenAngle = min(150, max(lidCloseAngle + 5, UserDefaults.standard.object(forKey: "lidOpenAngle") as? Double ?? 80))
        if lidAutomation { autoWorkflow = false }
        hardware.onAngle = { [weak self] angle in self?.handleLidAngle(angle) }
        hardware.start()
        CGDisplayRegisterReconfigurationCallback(displayCallback, Unmanaged.passUnretained(self).toOpaque())
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission(); self?.loginStatus = SMAppService.mainApp.status }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission(); self?.scheduleRefresh(reprobe: true) }
        })
        keys.onRecord = { [weak self] shortcut in self?.finishRecording(shortcut) }
        keys.onAdjust = { [weak self] delta, fine in self?.handleBrightnessKey(delta: delta, fine: fine) ?? false }
        refreshPermission()
        monitorPermissionIfNeeded()
        if UserDefaults.standard.stringArray(forKey: modeRecoveryKey) != nil {
            isApplying = true
            Task { [weak self] in await self?.restoreModeTrial() }
        } else {
            isApplying = true
            startupTask = Task { [weak self] in await self?.restoreRecentAtStartup() }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        hardware.stop()
        startupTask?.cancel()
        let hadUnconfirmedTrial = UserDefaults.standard.stringArray(forKey: modeRecoveryKey) != nil
        modeTrialTask?.cancel()
        // Termination cannot await. A bounded recovery keeps an unconfirmed mode
        // from surviving a normal quit; failed recovery stays journaled for launch.
        if let args = UserDefaults.standard.stringArray(forKey: modeRecoveryKey) {
            scanDisplays()
            if DisplaySnapshot.canRestore(args, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs),
               applyConfigurationOnQuit(args) {
                UserDefaults.standard.removeObject(forKey: modeRecoveryKey)
            }
        }
        // Capture before restoring the built-in screen owned by the workflow.
        scanDisplays()
        if !hadUnconfirmedTrial, UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil,
           let path = Bundle.main.url(forResource: "displayplacer", withExtension: nil)?.path {
            let result = CommandRunner.run(path, ["list"])
            if result.succeeded { saveRecent(completeSnapshot(DisplaySnapshot(result.output))) }
        }
        CGDisplayRemoveReconfigurationCallback(displayCallback, Unmanaged.passUnretained(self).toOpaque())
        changeTask?.cancel(); detailsTask?.cancel(); captureTask?.cancel(); workflowTask?.cancel(); permissionTask?.cancel(); hudHideTask?.cancel()
        brightnessTasks.values.forEach { $0.cancel() }
        toggleChecks.values.forEach { $0.cancel() }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll(); workspaceObservers.removeAll()
        keys.uninstall()
        passwordPreference.stop()
        identification.stop()
        recordingAction = nil
        for id in Array(originalGamma.keys) { restoreGamma(id) }
        workflowHoldsBuiltinOff = false
        userRestoredBuiltin = false
        if changedBuiltinForWorkflow, let id = knownBuiltinID {
            if PrivateAPI.setDisplayEnabled(id: id, enabled: true) {
                restoreKeyboardBacklight(reportFailure: false)
                if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
            }
        }
        hud?.orderOut(nil)
    }

    func setPreferPasswordWhenBuiltinOff(_ enabled: Bool) {
        preferPasswordWhenBuiltinOff = enabled
        UserDefaults.standard.set(enabled, forKey: "preferPasswordWhenBuiltinOff")
        synchronizePasswordPreference()
        if enabled && !BrightnessKeys.isTrusted() { requestPermission() }
    }

    private func synchronizePasswordPreference() {
        passwordPreference.update(enabled: started && preferPasswordWhenBuiltinOff)
    }

    func setSyncKeyboardBacklight(_ enabled: Bool) {
        syncKeyboardBacklight = enabled
        UserDefaults.standard.set(enabled, forKey: "syncKeyboardBacklight")
        scanDisplays()
        if enabled {
            synchronizeKeyboardBacklight()
        } else {
            restoreKeyboardBacklight()
        }
    }

    private func storedKeyboardBacklightSnapshot() -> [UInt64: Float]? {
        guard let stored = UserDefaults.standard.dictionary(forKey: "keyboardBacklight.savedBrightness") else {
            return nil
        }
        var snapshot: [UInt64: Float] = [:]
        for (key, rawValue) in stored {
            guard let id = UInt64(key), let number = rawValue as? NSNumber else { continue }
            let value = number.floatValue
            if value.isFinite, value >= 0, value <= 1 {
                snapshot[id] = value
            }
        }
        return snapshot.isEmpty ? nil : snapshot
    }

    private func storeKeyboardBacklightSnapshot(_ snapshot: [UInt64: Float]) {
        let stored = Dictionary(uniqueKeysWithValues: snapshot.map { (String($0.key), Double($0.value)) })
        UserDefaults.standard.set(stored, forKey: "keyboardBacklight.savedBrightness")
    }

    private func dimKeyboardBacklight() {
        guard syncKeyboardBacklight, let keyboardBacklight else { return }
        if storedKeyboardBacklightSnapshot() == nil {
            let snapshot = keyboardBacklight.snapshot()
            guard !snapshot.isEmpty else {
                lastError = "内置屏已关闭，但无法读取键盘背光亮度。"
                return
            }
            storeKeyboardBacklightSnapshot(snapshot)
        }
        if !keyboardBacklight.setBrightness(0) {
            lastError = "内置屏已关闭，但键盘背光同步失败。"
        }
    }

    private func restoreKeyboardBacklight(reportFailure: Bool = true) {
        guard let snapshot = storedKeyboardBacklightSnapshot() else { return }
        guard let keyboardBacklight, keyboardBacklight.restore(snapshot) else {
            if reportFailure { lastError = "键盘背光恢复失败。" }
            return
        }
        UserDefaults.standard.removeObject(forKey: "keyboardBacklight.savedBrightness")
    }

    private func synchronizeKeyboardBacklight() {
        guard keyboardBacklightAvailable else { return }
        if syncKeyboardBacklight, externalOnline, builtin?.enabled == false {
            dimKeyboardBacklight()
        } else if !syncKeyboardBacklight || builtin?.enabled == true {
            restoreKeyboardBacklight()
        }
    }

    private static func loadShortcut(_ key: String, defaults: UserDefaults = .standard) -> BrightnessShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BrightnessShortcut.self, from: data)
    }

    func setKeyboardEnabled(_ on: Bool) {
        keyboardEnabled = on
        UserDefaults.standard.set(on, forKey: "brightnessKeyboardEnabled")
        if on && !BrightnessKeys.isTrusted() { _ = BrightnessKeys.requestAccess() }
        refreshPermission(); monitorPermissionIfNeeded()
    }

    func setBrightnessTarget(_ target: BrightnessTarget) {
        brightnessTarget = target
        UserDefaults.standard.set(target.rawValue, forKey: "brightnessTarget")
    }

    func setNativeBrightnessKeys(_ on: Bool) {
        nativeBrightnessKeys = on
        UserDefaults.standard.set(on, forKey: "nativeBrightnessKeys")
        refreshPermission(); monitorPermissionIfNeeded()
    }

    func requestKeyboardAccess() { requestPermission() }

    func beginRecording(_ action: BrightnessAction) {
        shortcutMessage = nil
        guard BrightnessKeys.isTrusted() else {
            shortcutMessage = "请先授予 BDMenu 辅助功能权限，再录制按键。"
            requestKeyboardAccess()
            return
        }
        recordingAction = action
        refreshPermission(); monitorPermissionIfNeeded()
        if !keysInstalled {
            recordingAction = nil
            shortcutMessage = "按键监听启动失败，请检查权限并重新打开 BDMenu。"
        }
    }

    func cancelRecording() {
        recordingAction = nil
        keys.recording = nil
        refreshPermission(); monitorPermissionIfNeeded()
    }

    private func finishRecording(_ shortcut: BrightnessShortcut?) {
        guard let action = recordingAction else { return }
        guard let shortcut else { cancelRecording(); return }
        guard shortcut.isAllowed else {
            shortcutMessage = "普通字符键请搭配 ⌘、⌃ 或 ⌥，也可以直接使用 F 键或媒体键。"
            return
        }
        let other = action == .decrease ? increaseShortcut : decreaseShortcut
        guard !shortcut.hasSameBinding(as: other) else {
            shortcutMessage = "提高和降低亮度需要使用不同按键，请再按一个键。"
            return
        }
        // Fine-step combinations must not overlap a second explicit binding.
        let overlaps = other.match(kind: shortcut.kind, code: shortcut.code, flags: CGEventFlags(rawValue: shortcut.modifiers)) != nil
            || shortcut.match(kind: other.kind, code: other.code, flags: CGEventFlags(rawValue: other.modifiers)) != nil
        guard !overlaps else {
            shortcutMessage = "这组按键与另一按键的精细调节组合冲突，请换一个。"
            return
        }
        if action == .decrease { decreaseShortcut = shortcut } else { increaseShortcut = shortcut }
        persistShortcuts()
        shortcutMessage = "已将“\(action.title)”绑定到 \(shortcut.label)。"
        cancelRecording()
    }

    func resetShortcuts() {
        decreaseShortcut = .defaultDecrease
        increaseShortcut = .defaultIncrease
        persistShortcuts()
        shortcutMessage = "已恢复 F4 降低、F5 提高亮度。"
        cancelRecording()
    }

    private func persistShortcuts() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(decreaseShortcut), forKey: "brightnessDecrease")
        defaults.set(try? JSONEncoder().encode(increaseShortcut), forKey: "brightnessIncrease")
    }

    func requestPermission() {
        _ = BrightnessKeys.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        refreshPermission()
        monitorPermissionIfNeeded()
    }
    func refreshPermission() {
        keysTrusted = BrightnessKeys.isTrusted()
        keys.enabled = keyboardEnabled
        keys.decrease = decreaseShortcut
        keys.increase = increaseShortcut
        keys.nativeKeysEnabled = nativeBrightnessKeys
        keys.recording = recordingAction
        if (keyboardEnabled || recordingAction != nil) && keysTrusted {
            keys.install()
            keysInstalled = keys.installed
        } else {
            keys.uninstall()
            keysInstalled = false
        }
    }
    private func monitorPermissionIfNeeded() {
        permissionTask?.cancel()
        guard keyboardEnabled || recordingAction != nil else { return }
        // Independent of the menu view: granting or revoking access works with the panel closed.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                self.refreshPermission()
            }
        }
    }

    func panelOpened() {
        refreshPermission()
        loginStatus = SMAppService.mainApp.status
        scanDisplays()
        synchronizeKeyboardBacklight()
        refreshDetails(reprobe: false)
    }
    func scheduleRefresh(reprobe: Bool = false) {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, self.started else { return }
            let old = self.previousExternals
            let wasOnline = self.previousExternalOnline
            self.scanDisplays()
            self.synchronizeKeyboardBacklight()
            let now = Set(self.displays.filter { !$0.isBuiltin }.map(\.uuid))
            self.previousExternals = now
            self.previousExternalOnline = self.externalOnline
            if !now.isEmpty { self.lastExternalSeen = Date() }
            self.recoverBuiltinIfNeeded()
            if !self.isApplying { self.reassertWorkflowIfNeeded() }
            // A freshly attached screen needs a moment before it counts as online, so
            // that transition is a trigger too - waiting only for a new UUID missed it.
            if !self.isApplying && self.autoWorkflow && (!now.subtracting(old).isEmpty || (self.externalOnline && !wasOnline)) {
                self.scheduleWorkflow()
            }
            self.refreshDetails(reprobe: reprobe)
        }
    }

    private func scanDisplays() {
        var online = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(64, &online, &count) == .success else { return }
        let onlineIDs = Set(online.prefix(Int(count)))
        let allIDs = Set(PrivateAPI.allDisplayIDs()).union(onlineIDs)
        let previous = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        var result: [DisplayInfo] = []
        for id in allIDs.sorted() {
            let info = PrivateAPI.displayInfo(id) ?? [:]
            let isBuiltin = CGDisplayIsBuiltin(id) != 0 || previous[id]?.isBuiltin == true || id == knownBuiltinID
            let virtual = (info["kCGDisplayIsVirtualDevice"] as? Bool ?? false) || (info["kCGDisplayIsAirPlay"] as? Bool ?? false)
            if virtual && !isBuiltin { continue }
            let names = info["DisplayProductName"] as? [String: String]
            let systemUUID: String?
            if let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                systemUUID = CFUUIDCreateString(nil, value) as String
            } else { systemUUID = nil }
            let uuid = DisplayIdentityPolicy.stableUUID([
                info["kCGDisplayUUID"] as? String, systemUUID, previous[id]?.uuid,
                isBuiltin ? UserDefaults.standard.string(forKey: "display.builtinUUID.v1") : nil
            ]) ?? ""
            if isBuiltin && !uuid.isEmpty { UserDefaults.standard.set(uuid, forKey: "display.builtinUUID.v1") }
            // Unknown offline IDs cannot safely be used as physical display targets. A screen
            // that is lit right now must stay visible as "connected" so a hot-plug with a
            // UUID that has not resolved yet is not mistaken for an unplug; inactive ghosts
            // left behind by a disabled display are still dropped.
            guard !uuid.isEmpty || isBuiltin || (onlineIDs.contains(id) && CGDisplayIsActive(id) != 0) else { continue }
            let name = names?["zh_CN"] ?? names?["en_US"] ?? names?.values.sorted().first
                ?? previous[id]?.name ?? (isBuiltin ? "内建显示器" : "外置显示器")
            let enabled = onlineIDs.contains(id) && (CGDisplayIsActive(id) != 0 || CGDisplayIsInMirrorSet(id) != 0)
            result.append(DisplayInfo(id: id, uuid: uuid, name: name, isBuiltin: isBuiltin, enabled: enabled))
            if isBuiltin { knownBuiltinID = id }
            if controls[id] == nil || previous[id]?.uuid != uuid {
                var value = Controls()
                let saved = UserDefaults.standard.object(forKey: "brightness.\(uuid)") as? Double ?? 100
                value.brightness = saved.isFinite ? min(100, max(0, saved)) : 100
                controls[id] = value
            }
            if isBuiltin, let value = PrivateAPI.getBrightness(id) {
                mutateState(id) { $0.brightness = value * 100 }
            }
        }
        if result != displays { generation += 1 }
        let retained = Set(result.map(\.id))
        for id in Array(controls.keys) where !retained.contains(id) {
            brightnessTasks.removeValue(forKey: id)?.cancel()
            originalGamma.removeValue(forKey: id)
            controls.removeValue(forKey: id)
        }
        displays = result.sorted { a, b in a.isBuiltin != b.isBuiltin ? a.isBuiltin : a.id < b.id }
        mainID = CGMainDisplayID()
        mirrored = displays.contains { $0.enabled && CGDisplayIsInMirrorSet($0.id) != 0 }
        synchronizePasswordPreference()
    }

    private func recoverBuiltinIfNeeded() {
        guard let id = builtin?.id ?? knownBuiltinID else { return }
        // Presence, not "online", decides this: during a hot-plug the external screen
        // is already attached but has not finished becoming active yet, and treating
        // that gap as an unplug is what used to switch the built-in panel back on.
        let externalPresent = displays.contains { !$0.isBuiltin }
        let builtinEnabled = builtin?.enabled == true
        guard DisplayWorkflow.shouldRecoverBuiltin(externalPresent: externalPresent,
                                                   secondsSinceExternalSeen: Date().timeIntervalSince(lastExternalSeen),
                                                   builtinEnabled: builtinEnabled,
                                                   workflowClearedBuiltin: changedBuiltinForWorkflow) else { return }
        if !builtinEnabled {
            guard PrivateAPI.setDisplayEnabled(id: id, enabled: true) else {
                lastError = "内建屏恢复失败，请尝试“全部点亮”或重新连接外置屏。"
                return
            }
        }
        if lastError == Self.displayToggleError { lastError = nil }
        restoreKeyboardBacklight()
        if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
        changedBuiltinForWorkflow = false
        preWorkflowBrightness = nil
        workflowHoldsBuiltinOff = false
        userRestoredBuiltin = false
        // The system reconfiguration callback schedules the follow-up. No perpetual polling loop.
    }

    /// Re-applies the workflow when macOS turns the built-in panel back on by itself.
    private func reassertWorkflowIfNeeded() {
        guard let builtin,
              DisplayWorkflow.shouldKeepBuiltinOff(autoWorkflow: autoWorkflow,
                                                   workflowHoldsBuiltinOff: workflowHoldsBuiltinOff,
                                                   userRestoredBuiltin: userRestoredBuiltin,
                                                   externalOnline: externalOnline,
                                                   builtinEnabled: builtin.enabled),
              Date().timeIntervalSince(lastWorkflowWrite) > DisplayWorkflow.minimumWriteInterval else { return }
        lastWorkflowWrite = Date()
        suppressCaptureUntil = Date().addingTimeInterval(3)
        if setEnabled(builtin.id, false, verify: false) { changedBuiltinForWorkflow = true }
    }

    private func refreshDetails(reprobe: Bool) {
        detailsTask?.cancel()
        let expected = generation
        let devices = displays.filter { $0.enabled && !$0.isBuiltin }
        detailsTask = Task { [weak self] in
            guard let self else { return }
            for device in devices {
                guard !Task.isCancelled, self.generation == expected else { return }
                if reprobe || self.state(device.id).dimming == .unknown { await self.probe(device, generation: expected) }
                if self.state(device.id).dimming == .software {
                    self.applySoftwareDim(device.id, self.state(device.id).brightness)
                }
            }
            guard !Task.isCancelled, self.generation == expected else { return }
            guard let snapshot = await self.readSnapshot(), !Task.isCancelled, self.generation == expected else { return }
            self.currentLayouts = snapshot.layouts
            for device in self.displays.filter(\.enabled) {
                let modes = snapshot.modes[device.uuid] ?? []
                self.mutateState(device.id) {
                    $0.modes = modes
                    $0.currentMode = modes.first(where: \.isCurrent)?.id ?? -1
                    if reprobe || $0.colorProfiles.isEmpty { $0.colorProfiles = DisplayColorProfiles.options(device.id) }
                    $0.colorProfile = DisplayColorProfiles.current(device.id) ?? ""
                    if let mode = CGDisplayCopyDisplayMode(device.id) {
                        $0.renderDescription = "界面 \(mode.width) × \(mode.height) · 渲染 \(mode.pixelWidth) × \(mode.pixelHeight)"
                    }
                }
            }
            if !self.isApplying && Date() >= self.suppressCaptureUntil {
                self.saveLayout(snapshot)
            } else {
                self.scheduleCapture()
            }
        }
    }

    private func scheduleCapture() {
        captureTask?.cancel()
        let expected = generation
        let delay = max(1, suppressCaptureUntil.timeIntervalSinceNow + 0.3)
        captureTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(Int(delay * 1000))) } catch { return }
            guard let self, self.started, !self.isApplying, self.generation == expected,
                  Date() >= self.suppressCaptureUntil else { return }
            guard let snapshot = await self.readSnapshot(), !Task.isCancelled, self.generation == expected else { return }
            self.saveLayout(snapshot)
        }
    }

    private func probe(_ display: DisplayInfo, generation expected: Int) async {
        let uuid = display.uuid
        guard !uuid.isEmpty else { return }
        var luminance = await Subprocess.run("m1ddc", ["display", uuid, "get", "luminance"], timeout: 2)
        guard !Task.isCancelled, generation == expected else { return }
        if !luminance.succeeded || Double(luminance.output) == nil {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            luminance = await Subprocess.run("m1ddc", ["display", uuid, "get", "luminance"], timeout: 2)
        }
        guard !Task.isCancelled, generation == expected else { return }
        if luminance.succeeded, let value = Double(luminance.output), value.isFinite, value >= 0 {
            let maximum = await Subprocess.run("m1ddc", ["display", uuid, "max", "luminance"], timeout: 2)
            guard !Task.isCancelled, generation == expected else { return }
            let maxValue = maximum.succeeded ? Double(maximum.output) ?? 100 : 100
            let maximumBrightness = maxValue.isFinite && maxValue > 0 ? maxValue : 100
            // A concurrent slider write wins over an older probe result.
            mutateState(display.id) {
                $0.maximumBrightness = maximumBrightness
                if brightnessTasks[display.id] == nil {
                    $0.brightness = min(100, max(0, value / maximumBrightness * 100))
                }
                $0.dimming = .hardware
            }
            restoreGamma(display.id)
        } else {
            mutateState(display.id) { $0.dimming = .software }
        }
        let input = await Subprocess.run("m1ddc", ["display", uuid, "get", "input"], timeout: 2)
        guard !Task.isCancelled, generation == expected else { return }
        let inputValue = input.succeeded ? Int(input.output) ?? 0 : 0
        mutateState(display.id) {
            $0.input = inputValue
            $0.hasInput = inputValue > 0
        }
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Double) {
        guard value.isFinite, let display = displays.first(where: { $0.id == id && $0.enabled }) else { return }
        let value = min(100, max(0, value))
        if display.isBuiltin {
            if PrivateAPI.setBrightness(id, value / 100) { mutateState(id) { $0.brightness = value } }
            else { lastError = "无法设置内建屏亮度。" }
            return
        }
        guard state(id).dimming != .unknown else { return }
        mutateState(id) { $0.brightness = value }
        UserDefaults.standard.set(value, forKey: "brightness.\(display.uuid)")
        guard brightnessTasks[id] == nil else { return }
        // One worker per display drains the latest value at a bounded rate. Continuous
        // key repeat must not postpone every write until the user releases the key.
        brightnessTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.brightnessTasks[id] = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
                guard self.displays.contains(where: { $0.id == id && $0.uuid == display.uuid && $0.enabled }) else { return }
                let target = self.state(id).brightness
                if self.state(id).dimming == .software {
                    self.applySoftwareDim(id, target)
                } else {
                    let raw = Int((target / 100 * self.state(id).maximumBrightness).rounded())
                    let result = await Subprocess.run("m1ddc", ["display", display.uuid, "set", "luminance", "\(raw)"], timeout: 2)
                    guard !Task.isCancelled, self.displays.contains(where: { $0.id == id && $0.uuid == display.uuid && $0.enabled }) else { return }
                    if !result.succeeded || result.output.localizedCaseInsensitiveContains("DDC communication failure") {
                        self.lastError = "\(display.name) 的硬件亮度写入失败，请点击刷新重试检测。"
                        return
                    }
                }
                if self.state(id).brightness == target { return }
            }
        }
    }


    func setInput(_ display: DisplayInfo, _ value: Int) async {
        guard !isApplying, state(display.id).hasInput else { return }
        isApplying = true
        defer { isApplying = false }
        let result = await Subprocess.run("m1ddc", ["display", display.uuid, "set", "input", "\(value)"], timeout: 2)
        if result.succeeded { mutateState(display.id) { $0.input = value }; scheduleRefresh() }
        else { lastError = "输入源切换失败，请检查显示器是否支持该输入源。" }
    }

    private func applySoftwareDim(_ id: CGDirectDisplayID, _ value: Double) {
        if originalGamma[id] == nil {
            let capacity = CGDisplayGammaTableCapacity(id)
            guard capacity > 0 else { lastError = "当前显示器不支持软件调光。"; return }
            var red = [CGGammaValue](repeating: 0, count: Int(capacity))
            var green = red; var blue = red; var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
                lastError = "无法读取显示器色彩曲线，已停止软件调光。"; return
            }
            originalGamma[id] = Gamma(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
        }
        guard let gamma = originalGamma[id] else { return }
        let factor = Float(max(0.05, min(1, value / 100)))
        let red = gamma.red.map { $0 * factor }; let green = gamma.green.map { $0 * factor }; let blue = gamma.blue.map { $0 * factor }
        if CGSetDisplayTransferByTable(id, UInt32(red.count), red, green, blue) != .success {
            lastError = "软件调光失败，当前显示模式可能不支持此操作。"
        }
    }
    private func restoreGamma(_ id: CGDirectDisplayID) {
        guard let gamma = originalGamma.removeValue(forKey: id) else { return }
        _ = CGSetDisplayTransferByTable(id, UInt32(gamma.red.count), gamma.red, gamma.green, gamma.blue)
    }

    @discardableResult
    func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool, verify: Bool = true) -> Bool {
        scanDisplays()
        let isBuiltin = id == knownBuiltinID || displays.contains { $0.id == id && $0.isBuiltin }
        if !enabled && !displays.contains(where: { $0.id != id && $0.enabled }) {
            lastError = "至少需要保留一块可用的实体显示器。"; return false
        }
        guard PrivateAPI.setDisplayEnabled(id: id, enabled: enabled) else {
            lastError = Self.displayToggleError; return false
        }
        // A stale switch error must not sit in the panel after a successful write.
        if lastError == Self.displayToggleError { lastError = nil }
        if isBuiltin {
            if enabled {
                restoreKeyboardBacklight()
            } else {
                dimKeyboardBacklight()
            }
        }
        if verify { confirmToggle(id, enabled) }
        synchronizePasswordPreference()
        scheduleRefresh()
        return true
    }

    /// The private API reports success before the display server has finished
    /// reconfiguring, so confirm the real state and only then stay quiet.
    private func confirmToggle(_ id: CGDirectDisplayID, _ enabled: Bool) {
        toggleChecks[id]?.cancel()
        toggleChecks[id] = Task { [weak self] in
            for delay in [1.0, 2.0] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if self.isDisplayActive(id) == enabled { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.lastError = Self.displayToggleError
        }
    }

    private func isDisplayActive(_ id: CGDirectDisplayID) -> Bool {
        var online = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &online, &count) == .success else { return CGDisplayIsActive(id) != 0 }
        return online.prefix(Int(count)).contains(id) && CGDisplayIsActive(id) != 0
    }

    func toggleDisplay(_ display: DisplayInfo) {
        guard !isApplying else { return }
        // An explicit "启用" on the built-in panel wins over the workflow until the
        // next connection change; the workflow must not immediately undo the click.
        if display.isBuiltin && !display.enabled { userRestoredBuiltin = true }
        _ = setEnabled(display.id, !display.enabled)
    }
    func wakeAll() {
        // Explicit recovery also pauses the automation that would immediately switch it off again.
        clearModeTrial()
        isApplying = false
        lidAutomation = false
        UserDefaults.standard.set(false, forKey: "lidAutomation")
        autoWorkflow = false
        UserDefaults.standard.set(false, forKey: "autoWorkflow")
        workflowTask?.cancel()
        workflowHoldsBuiltinOff = false
        userRestoredBuiltin = false
        scanDisplays()
        var ids = Set(displays.map(\.id))
        if let knownBuiltinID { ids.insert(knownBuiltinID) }
        for id in ids { _ = setEnabled(id, true); restoreGamma(id) }
        if let id = knownBuiltinID { _ = PrivateAPI.setBrightness(id, max(20, preWorkflowBrightness ?? 70) / 100) }
        changedBuiltinForWorkflow = false
        preWorkflowBrightness = nil
        scheduleRefresh(reprobe: true)
    }

    func setLidAutomation(_ enabled: Bool) {
        if enabled { setAutoWorkflow(false) }
        lidAutomation = enabled
        UserDefaults.standard.set(enabled, forKey: "lidAutomation")
        lidPolicy = LidAnglePolicy()
        userRestoredBuiltin = false
        if !enabled, changedBuiltinForWorkflow, let id = knownBuiltinID {
            if setEnabled(id, true) {
                if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
                changedBuiltinForWorkflow = false
                preWorkflowBrightness = nil
                workflowHoldsBuiltinOff = false
            }
        }
    }

    func setLidThreshold(close: Double? = nil, open: Double? = nil) {
        if let close { lidCloseAngle = min(lidOpenAngle - 5, max(10, close)) }
        if let open { lidOpenAngle = max(lidCloseAngle + 5, min(150, open)) }
        UserDefaults.standard.set(lidCloseAngle, forKey: "lidCloseAngle")
        UserDefaults.standard.set(lidOpenAngle, forKey: "lidOpenAngle")
        lidPolicy = LidAnglePolicy()
        userRestoredBuiltin = false
    }

    private func handleLidAngle(_ angle: Double?) {
        guard lidAutomation, !isApplying, modeTrialLabel == nil else { return }
        guard let externalOnly = lidPolicy.update(angle: angle, close: lidCloseAngle,
                open: lidOpenAngle, now: ProcessInfo.processInfo.systemUptime) else { return }
        if userRestoredBuiltin, !externalOnly { userRestoredBuiltin = false }
        guard externalOnline, let builtin, !userRestoredBuiltin,
              Date().timeIntervalSince(lastLidWrite) >= 3 else { return }
        let enabled = !externalOnly
        guard builtin.enabled != enabled else { return }
        lastLidWrite = Date()
        suppressCaptureUntil = Date().addingTimeInterval(4)
        if externalOnly { preWorkflowBrightness = state(builtin.id).brightness }
        if setEnabled(builtin.id, enabled) {
            changedBuiltinForWorkflow = externalOnly
            workflowHoldsBuiltinOff = externalOnly
            if enabled {
                if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(builtin.id, value / 100) }
                preWorkflowBrightness = nil
            }
        }
    }

    func setAutoWorkflow(_ enabled: Bool) {
        if enabled, lidAutomation { setLidAutomation(false) }
        autoWorkflow = enabled
        UserDefaults.standard.set(enabled, forKey: "autoWorkflow")
        workflowTask?.cancel()
        userRestoredBuiltin = false
        if enabled { scheduleWorkflow() }
        else if changedBuiltinForWorkflow, let id = knownBuiltinID {
            if setEnabled(id, true) {
                if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
                changedBuiltinForWorkflow = false
                preWorkflowBrightness = nil
            }
        }
    }
    private func scheduleWorkflow() {
        guard !isApplying, UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil else { return }
        workflowTask?.cancel()
        userRestoredBuiltin = false
        suppressCaptureUntil = Date().addingTimeInterval(8)
        workflowTask = Task { [weak self] in
            // macOS can take several seconds to bring a freshly plugged screen online.
            // The old single 1s probe gave up there and left the built-in panel on.
            for attempt in 0..<6 {
                do { try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 0.8)) } catch { return }
                guard let self, self.autoWorkflow, !self.isApplying else { return }
                self.scanDisplays()
                if self.externalOnline { break }
            }
            guard let self, self.autoWorkflow, self.externalOnline, !self.isApplying else { return }
            if let builtin = self.builtin, builtin.enabled {
                self.preWorkflowBrightness = self.state(builtin.id).brightness
            }
            await self.restoreLayout(silent: true)
            guard !Task.isCancelled, self.autoWorkflow else { return }
            self.scanDisplays()
            guard self.externalOnline, let builtin = self.builtin else { return }
            if builtin.enabled {
                self.changedBuiltinForWorkflow = self.setEnabled(builtin.id, false, verify: false)
            } else if self.preWorkflowBrightness != nil {
                self.changedBuiltinForWorkflow = true
            }
            self.workflowHoldsBuiltinOff = self.builtin?.enabled == false
            self.lastWorkflowWrite = Date()
        }
    }

    private func readSnapshot() async -> DisplaySnapshot? {
        let result = await Subprocess.run("displayplacer", ["list"])
        return result.succeeded ? completeSnapshot(DisplaySnapshot(result.output)) : nil
    }
    private func completeSnapshot(_ snapshot: DisplaySnapshot) -> DisplaySnapshot {
        snapshot.includingDisabled(Set(displays.filter { !$0.enabled }.map(\.uuid)))
    }
    private func saveLayout(_ snapshot: DisplaySnapshot) {
        if !isApplying { saveRecent(snapshot) }
        guard UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil,
              externalOnline, DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else { return }
        UserDefaults.standard.set(workflowLayout(snapshot.arguments), forKey: layoutKey)
    }

    /// While the workflow owns the built-in panel, a captured arrangement must not
    /// remember it as enabled; restoring such a snapshot is what silently switched
    /// the panel back on at the next connection.
    private func workflowLayout(_ arguments: [String]) -> [String] {
        guard autoWorkflow, workflowHoldsBuiltinOff, !userRestoredBuiltin,
              let uuid = builtin?.uuid, !uuid.isEmpty else { return arguments }
        return DisplaySnapshot.disabling(uuid, in: arguments)
    }
    private func apply(_ arguments: [String], expected: Int) async -> Bool {
        guard generation == expected, DisplaySnapshot.canRestore(arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else {
            lastError = "显示器连接已变化，请刷新后重试。"; return false
        }
        let topology = connectedIDs
        let plan = DisplayApplicationPlan(arguments)
        suppressCaptureUntil = Date().addingTimeInterval(2)
        var woke = false
        for display in displays where plan.enabledIDs.contains(display.uuid) && !display.enabled {
            guard PrivateAPI.setDisplayEnabled(id: display.id, enabled: true) else {
                lastError = "无法启用 \(display.name)。"; return false
            }
            woke = true
        }
        if woke { try? await Task.sleep(for: .milliseconds(400)) }
        scanDisplays()
        guard connectedIDs == topology else { lastError = "连接已变化，已停止应用旧配置。"; return false }
        let result = await Subprocess.run("displayplacer", plan.arguments)
        guard result.succeeded else {
            lastError = result.timedOut ? "显示设置操作超时。" : "显示设置未成功应用，请尝试其他模式。"
            scheduleRefresh(); return false
        }
        scanDisplays()
        guard connectedIDs == topology else { lastError = "连接已变化，已停止应用旧配置。"; return false }
        for display in displays where plan.disabledIDs.contains(display.uuid) && display.enabled {
            guard PrivateAPI.setDisplayEnabled(id: display.id, enabled: false) else {
                lastError = "无法停用 \(display.name)。"; return false
            }
        }
        scanDisplays()
        scheduleRefresh()
        return true
    }

    private func applyConfigurationOnQuit(_ arguments: [String]) -> Bool {
        guard let path = Bundle.main.url(forResource: "displayplacer", withExtension: nil)?.path else { return false }
        let plan = DisplayApplicationPlan(arguments)
        var woke = false
        for display in displays where plan.enabledIDs.contains(display.uuid) && !display.enabled {
            guard PrivateAPI.setDisplayEnabled(id: display.id, enabled: true) else { return false }
            woke = true
        }
        if woke { Thread.sleep(forTimeInterval: 0.4) }
        guard CommandRunner.run(path, plan.arguments).succeeded else { return false }
        for display in displays where plan.disabledIDs.contains(display.uuid) {
            if CGDisplayIsActive(display.id) != 0 && !PrivateAPI.setDisplayEnabled(id: display.id, enabled: false) { return false }
        }
        return true
    }
    func restoreLayout(silent: Bool = false) async {
        guard !isApplying else { return }
        scanDisplays()
        guard let saved = UserDefaults.standard.stringArray(forKey: layoutKey) else {
            if !silent { lastError = "这组显示器还没有可恢复的布局。" }
            return
        }
        let arguments = workflowLayout(saved)
        guard DisplaySnapshot.canRestore(arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else {
            if !silent { lastError = "这组显示器还没有可恢复的布局。" }
            return
        }
        isApplying = true
        defer { isApplying = false }
        _ = await apply(arguments, expected: generation)
    }
    func setMain(_ display: DisplayInfo) async {
        guard !isApplying, display.enabled, !mirrored else { return }
        isApplying = true
        defer { isApplying = false }
        let expected = generation
        guard let snapshot = await readSnapshot(), let records = DisplaySnapshot.movingMain(to: display.uuid, in: snapshot.layouts) else { return }
        _ = await apply(records.map(\.argument), expected: expected)
    }
    func setRefreshRate(_ display: DisplayInfo, hertz: Int) async {
        let state = state(display.id)
        guard let current = state.modes.first(where: { $0.id == state.currentMode }),
              let mode = DisplayModePolicy.refreshMode(hertz, current: current, available: state.modes),
              !DisplayModePolicy.sameFormat(current, mode) else { return }
        await setMode(display, mode)
    }

    func setMode(_ display: DisplayInfo, _ mode: DisplayMode) async {
        guard !isApplying, !mirrored, display.enabled else { return }
        guard UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil else {
            lastError = "上次显示模式尚未恢复，请先重新启动 BDMenu 或使用“全部点亮”。"; return
        }
        isApplying = true
        let expected = generation
        guard let snapshot = await readSnapshot(), generation == expected,
              let record = snapshot.layouts.first(where: { $0.uuid == display.uuid && $0.enabled }),
              let fresh = snapshot.modes[display.uuid]?.first(where: {
                  $0.id == mode.id && DisplayModePolicy.sameFormat($0, mode)
              }), DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else {
            lastError = "显示模式列表已变化或无法保存恢复配置，请刷新后重试。"
            isApplying = false
            return
        }
        if fresh.isCurrent { isApplying = false; return }
        lastError = nil
        workflowTask?.cancel()
        captureTask?.cancel()
        saveRecent(snapshot)
        UserDefaults.standard.set(snapshot.arguments, forKey: modeRecoveryKey)
        // Ensure the recovery journal reaches disk before touching the display.
        UserDefaults.standard.synchronize()
        let args = snapshot.layouts.map { item in
            item.uuid == display.uuid
                ? "id:\(item.uuid) mode:\(fresh.id) enabled:true origin:(\(record.x),\(record.y)) degree:\(record.rotation)"
                : item.argument
        }
        guard await apply(args, expected: expected) else {
            await restoreModeTrial()
            return
        }
        // A successful process exit alone does not prove that the mode changed.
        try? await Task.sleep(for: .milliseconds(700))
        guard let actual = await readSnapshot(),
              let current = actual.modes[display.uuid]?.first(where: \.isCurrent),
              DisplayModePolicy.sameFormat(current, fresh) else {
            lastError = "未能确认新显示模式，正在恢复。"
            await restoreModeTrial()
            return
        }
        pendingTrialSnapshot = actual
        beginTrialCountdown("\(display.name) · \(fresh.label)")
    }

    private func beginTrialCountdown(_ label: String) {
        modeTrialLabel = label
        modeTrialSeconds = 15
        let deadline = Date().addingTimeInterval(15)
        modeTrialTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.modeTrialSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if self.modeTrialSeconds == 0 { await self.restoreModeTrial(); return }
            }
        }
    }

    func keepModeTrial() {
        guard modeTrialLabel != nil, modeTrialSeconds > 0 else { return }
        let profiles = pendingProfiles
        let confirmed = pendingTrialSnapshot
        clearModeTrial()
        lastError = nil
        scanDisplays()
        applyProfiles(profiles)
        if builtin?.enabled == true { userRestoredBuiltin = true; workflowHoldsBuiltinOff = false }
        isApplying = false
        if let confirmed { saveRecent(confirmed) }
        suppressCaptureUntil = Date().addingTimeInterval(1)
        scheduleRefresh()
    }

    private func clearModeTrial() {
        modeTrialTask?.cancel(); modeTrialTask = nil
        modeTrialLabel = nil; modeTrialSeconds = 0
        pendingProfiles = [:]
        pendingTrialSnapshot = nil
        UserDefaults.standard.removeObject(forKey: modeRecoveryKey)
        UserDefaults.standard.synchronize()
    }

    func restoreModeTrial() async {
        modeTrialTask?.cancel(); modeTrialTask = nil
        modeTrialLabel = nil; modeTrialSeconds = 0
        isApplying = true
        defer { isApplying = false; scheduleRefresh(reprobe: true) }
        guard let args = UserDefaults.standard.stringArray(forKey: modeRecoveryKey) else { return }
        scanDisplays()
        guard DisplaySnapshot.canRestore(args, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else {
            // Do not apply an old layout to a different set of connected screens.
            clearModeTrial()
            lastError = "显示器连接已变化，已取消旧模式恢复；可使用“全部点亮”。"
            return
        }
        if await apply(args, expected: generation) {
            clearModeTrial()
            adoptRestoredConfiguration()
        } else {
            lastError = "原显示模式恢复失败，请打开系统显示器设置或使用“全部点亮”。下次启动将重试。"
        }
    }
    private func adoptRestoredConfiguration() {
        scanDisplays()
        userRestoredBuiltin = builtin?.enabled == true
        workflowHoldsBuiltinOff = builtin?.enabled == false && externalOnline && autoWorkflow
        changedBuiltinForWorkflow = workflowHoldsBuiltinOff
        previousExternals = Set(displays.filter { !$0.isBuiltin }.map(\.uuid))
        previousExternalOnline = externalOnline
    }

    private static func loadConfigurations(_ key: String) -> [DisplayConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return ((try? JSONDecoder().decode([DisplayConfiguration].self, from: data)) ?? []).filter {
            $0.screenIDs.allSatisfy { DisplayIdentityPolicy.stableUUID([$0]) != nil }
        }
    }

    private func persistConfigurations() {
        UserDefaults.standard.set(try? JSONEncoder().encode(configurationPresets), forKey: "display.presets.v1")
        UserDefaults.standard.set(try? JSONEncoder().encode(recentConfigurations), forKey: "display.recent.v1")
        UserDefaults.standard.synchronize()
    }

    private func profileSnapshot() -> [String: String] {
        Dictionary(uniqueKeysWithValues: displays.filter(\.enabled).compactMap { display in
            DisplayColorProfiles.current(display.id).map { (display.uuid, $0) }
        })
    }

    private func saveRecent(_ snapshot: DisplaySnapshot) {
        guard UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil,
              Set(snapshot.layouts.map(\.uuid)) == connectedIDs,
              DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else { return }
        let config = DisplayConfiguration(name: "最近使用", snapshot: snapshot, profiles: profileSnapshot())
        recentConfigurations.removeAll { $0.screenIDs == config.screenIDs }
        recentConfigurations.insert(config, at: 0)
        recentConfigurations = Array(recentConfigurations.prefix(20))
        persistConfigurations()
    }

    func setRestoreRecentOnLaunch(_ enabled: Bool) {
        restoreRecentOnLaunch = enabled
        UserDefaults.standard.set(enabled, forKey: "restoreRecentOnLaunch")
    }

    private func restoreRecentAtStartup() async {
        // A short bounded delay lets display services enumerate attached devices.
        do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
        guard started, !Task.isCancelled else { return }
        scanDisplays()
        var restored = false
        if restoreRecentOnLaunch, let config = recentConfigurations.first(where: { $0.matches(connectedIDs) }) {
            let expected = generation
            if let baseline = await readSnapshot(), config.isSupported(by: baseline),
               DisplaySnapshot.canRestore(baseline.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) {
                UserDefaults.standard.set(baseline.arguments, forKey: modeRecoveryKey)
                UserDefaults.standard.synchronize()
                let success = await apply(config.arguments, expected: expected)
                if success { try? await Task.sleep(for: .milliseconds(700)) }
                scanDisplays()
                let actual = await readSnapshot()
                if !success || actual.map({ !config.hasSameLayout(as: $0) }) != false {
                    await restoreModeTrial()
                    lastError = "最近配置未能完整恢复，已尝试还原启动前的布局。"
                } else {
                    clearModeTrial()
                    scanDisplays()
                    applyProfiles(config.profiles)
                    adoptRestoredConfiguration()
                    restored = true
                }
            } else { lastError = "最近配置包含当前不可用的模式，已保留系统现有配置。" }
        }
        // Mark the initial topology seen so the older attach workflow cannot
        // immediately overwrite a deliberately restored recent configuration.
        if restored {
            previousExternals = Set(displays.filter { !$0.isBuiltin }.map(\.uuid))
            previousExternalOnline = externalOnline
        }
        if lidAutomation {
            userRestoredBuiltin = false
            lidPolicy = LidAnglePolicy()
        }
        isApplying = false
        scheduleRefresh(reprobe: true)
    }

    func saveConfigurationPreset(_ name: String) async {
        guard !isApplying else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty else { return }
        let expected = generation
        guard let snapshot = await readSnapshot(), expected == generation,
              Set(snapshot.layouts.map(\.uuid)) == connectedIDs,
              DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs) else {
            lastError = "无法读取完整配置，请重新检测后保存。"; return
        }
        configurationPresets.append(DisplayConfiguration(name: trimmed, snapshot: snapshot, profiles: profileSnapshot()))
        persistConfigurations()
    }

    func deleteConfigurationPreset(_ id: UUID) {
        configurationPresets.removeAll { $0.id == id }
        persistConfigurations()
    }

    func presetAvailable(_ config: DisplayConfiguration) -> Bool { config.matches(connectedIDs) }

    func applyConfigurationPreset(_ config: DisplayConfiguration) async {
        guard config.matches(connectedIDs) else { lastError = "请先连接预设中相同的显示器组合。"; return }
        await trialConfiguration(arguments: config.arguments, layouts: config.layouts,
                                 label: "预设 · " + config.name, profiles: config.profiles)
    }

    func applyArrangement(_ layouts: [DisplayLayout], main: String) async {
        guard !mirrored, Set(layouts.map(\.uuid)) == connectedIDs,
              let normalized = DisplaySnapshot.movingMain(to: main, in: layouts) else { return }
        await trialConfiguration(arguments: normalized.map(\.argument), layouts: normalized, label: "屏幕排列")
    }

    private func trialConfiguration(arguments: [String], layouts: [DisplayLayout], label: String,
                                    profiles: [String: String] = [:]) async {
        guard !isApplying, UserDefaults.standard.stringArray(forKey: modeRecoveryKey) == nil else { return }
        isApplying = true
        let expected = generation
        guard let snapshot = await readSnapshot(), generation == expected,
              DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs, activeIDs: activeDisplayIDs),
              DisplayConfiguration(name: label, snapshot: {
                  var requested = snapshot; requested.layouts = layouts; requested.arguments = arguments; return requested
              }(), profiles: profiles).isSupported(by: snapshot) else {
            isApplying = false; lastError = "预设中的显示模式已不可用，请重新选择分辨率或刷新率。"; return
        }
        workflowTask?.cancel(); captureTask?.cancel()
        lastError = nil
        saveRecent(snapshot)
        UserDefaults.standard.set(snapshot.arguments, forKey: modeRecoveryKey)
        UserDefaults.standard.synchronize()
        guard await apply(arguments, expected: expected) else { await restoreModeTrial(); return }
        try? await Task.sleep(for: .milliseconds(700))
        guard let actual = await readSnapshot(), layouts.allSatisfy({ wanted in
            actual.layouts.contains { value in
                value.uuid == wanted.uuid && value.enabled == wanted.enabled
                    && (!wanted.enabled || (value.width == wanted.width && value.height == wanted.height
                        && value.hertz == wanted.hertz && value.scaling == wanted.scaling
                        && value.x == wanted.x && value.y == wanted.y && value.rotation == wanted.rotation))
            }
        }) else {
            lastError = "未能确认完整排列，正在恢复原配置。"; await restoreModeTrial(); return
        }
        pendingProfiles = profiles
        pendingTrialSnapshot = actual
        beginTrialCountdown(label)
    }

    private func applyProfiles(_ profiles: [String: String]) {
        for display in displays where display.enabled {
            if let path = profiles[display.uuid], !DisplayColorProfiles.set(path, display: display.id) {
                lastError = "\(display.name) 的色彩描述文件不可用或系统拒绝应用。"
            }
        }
    }

    func setColorProfile(_ display: DisplayInfo, path: String) {
        guard !isApplying, display.enabled else { return }
        if DisplayColorProfiles.set(path, display: display.id) {
            mutateState(display.id) { $0.colorProfile = DisplayColorProfiles.current(display.id) ?? "" }
            scheduleRefresh(reprobe: true)
        } else { lastError = "色彩描述文件应用失败，请确认文件仍存在且系统允许更改。" }
    }

    func setMirror(_ enabled: Bool) async {
        guard !isApplying, displays.filter(\.enabled).count >= 2 else { return }
        isApplying = true
        defer { isApplying = false }
        let expected = generation
        let key = "preMirror." + layoutKey
        if enabled {
            guard let snapshot = await readSnapshot(), !snapshot.arguments.isEmpty else { return }
            UserDefaults.standard.set(snapshot.arguments, forKey: key)
            let ids = displays.filter(\.enabled).sorted { $0.id == mainID && $1.id != mainID }.map(\.uuid).joined(separator: "+")
            var args = ["id:\(ids) enabled:true origin:(0,0)"]
            args += snapshot.layouts.filter { !$0.enabled }.map(\.argument)
            _ = await apply(args, expected: expected)
        } else if let args = UserDefaults.standard.stringArray(forKey: key) {
            _ = await apply(args, expected: expected)
        } else { lastError = "没有镜像前的布局，请在系统显示器设置中改为扩展显示。" }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { lastError = "登录启动设置失败：\(error.localizedDescription)"; loginStatus = SMAppService.mainApp.status }
    }

    private func handleBrightnessKey(delta: Int, fine: Bool) -> Bool {
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let pointerID = (pointerScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let id = brightnessTarget == .focusedWindow
            ? focusResolver.focusedDisplay(in: displays) ?? pointerID : pointerID
        guard let id,
              let display = displays.first(where: { $0.id == id && $0.enabled }),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
              }), display.isBuiltin || state(id).dimming != .unknown else { return false }
        // setBrightness already coalesces external writes off the main actor.
        let current = display.isBuiltin ? (PrivateAPI.getBrightness(id).map { $0 * 100 } ?? state(id).brightness) : state(id).brightness
        let value = min(100, max(0, current + Double(delta) * (fine ? 1.5625 : 6.25)))
        setBrightness(display.id, value)
        showHUD(Int(value.rounded()), screen: screen)
        return true
    }
    func previewHUD() {
        // A preview never writes to display hardware or changes keyboard focus.
        guard let screen = NSApplication.shared.keyWindow?.screen ?? NSScreen.main else { return }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let value = id.map { Int(state($0).brightness.rounded()) } ?? 50
        showHUD(value, screen: screen, duration: 6)
    }

    private func showHUD(_ value: Int, screen: NSScreen, duration: Double = 1.5) {
        let size = HUDLayout.size
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "BDMenu 亮度提示"
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: HUDView(value: value))
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting
            hud = panel
        }
        (hud?.contentView as? NSHostingView<HUDView>)?.rootView = HUDView(value: value)
        hud?.setFrame(HUDLayout.frame(screen: screen.frame, visible: screen.visibleFrame, scale: screen.backingScaleFactor), display: true)
        hud?.orderFrontRegardless()
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            self?.hud?.orderOut(nil)
        }
    }
}
