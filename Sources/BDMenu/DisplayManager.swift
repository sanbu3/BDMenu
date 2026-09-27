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
        var volume: Double = 50
        var maximumBrightness: Double = 100
        var maximumVolume: Double = 100
        var input = 0
        var hasVolume = false
        var hasInput = false
        var dimming: Dimming = .unknown
        var modes: [DisplayMode] = []
        var currentMode = -1
    }
    private struct Gamma {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    var displays: [DisplayInfo] = []
    var controls: [CGDirectDisplayID: Controls] = [:]
    var mainID: CGDirectDisplayID = 0
    var mirrored = false
    var lastError: String?
    var isApplying = false
    var autoWorkflow = UserDefaults.standard.bool(forKey: "autoWorkflow")
    var followPointerEnabled = UserDefaults.standard.bool(forKey: "followPointer")
    var keysTrusted = false
    var keysInstalled = false
    var loginStatus = SMAppService.mainApp.status

    @ObservationIgnored private let keys = BrightnessKeys()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    @ObservationIgnored private var volumeTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var originalGamma: [CGDirectDisplayID: Gamma] = [:]
    @ObservationIgnored private var knownBuiltinID: CGDirectDisplayID?
    @ObservationIgnored private var previousExternals = Set<String>()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var preWorkflowBrightness: Double?
    @ObservationIgnored private var changedBuiltinForWorkflow = false
    @ObservationIgnored private var suppressCaptureUntil = Date.distantPast
    @ObservationIgnored private var hud: NSPanel?
    @ObservationIgnored private var hudHideTask: Task<Void, Never>?

    let inputOptions: [(Int, String)] = [(15, "DP 1"), (16, "DP 2"), (17, "HDMI 1"), (18, "HDMI 2"), (27, "USB-C")]
    var builtin: DisplayInfo? { displays.first { $0.isBuiltin } }
    var externalOnline: Bool { displays.contains { !$0.isBuiltin && $0.enabled } }
    var launchAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2" }
    private var connectedIDs: Set<String> { Set(displays.map(\.uuid).filter { !$0.isEmpty }) }
    private var layoutKey: String { "layout.v2." + connectedIDs.sorted().joined(separator: "+") }
    func state(_ id: CGDirectDisplayID) -> Controls { controls[id] ?? Controls() }

    func start() {
        guard !started else { return }
        started = true
        CGDisplayRegisterReconfigurationCallback(displayCallback, Unmanaged.passUnretained(self).toOpaque())
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission(); self?.loginStatus = SMAppService.mainApp.status }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission(); self?.scheduleRefresh(reprobe: true) }
        })
        keys.onAdjust = { [weak self] delta, fine in self?.handleBrightnessKey(delta: delta, fine: fine) ?? false }
        refreshPermission()
        monitorPermissionIfNeeded()
        scheduleRefresh(reprobe: true)
    }

    func stop() {
        guard started else { return }
        started = false
        CGDisplayRemoveReconfigurationCallback(displayCallback, Unmanaged.passUnretained(self).toOpaque())
        changeTask?.cancel(); detailsTask?.cancel(); captureTask?.cancel(); workflowTask?.cancel(); permissionTask?.cancel(); hudHideTask?.cancel()
        brightnessTasks.values.forEach { $0.cancel() }; volumeTasks.values.forEach { $0.cancel() }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll(); workspaceObservers.removeAll()
        keys.uninstall()
        for id in Array(originalGamma.keys) { restoreGamma(id) }
        if changedBuiltinForWorkflow, let id = knownBuiltinID {
            _ = PrivateAPI.setDisplayEnabled(id: id, enabled: true)
            if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
        }
        hud?.orderOut(nil)
    }

    func setFollowPointer(_ enabled: Bool) {
        followPointerEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "followPointer")
        if enabled && !BrightnessKeys.isTrusted() { BrightnessKeys.requestAccess() }
        refreshPermission()
        monitorPermissionIfNeeded()
    }
    func requestPermission() {
        BrightnessKeys.requestAccess()
        BrightnessKeys.openSettings()
        refreshPermission()
        monitorPermissionIfNeeded()
    }
    func refreshPermission() {
        keysTrusted = BrightnessKeys.isTrusted()
        if followPointerEnabled && keysTrusted {
            keysInstalled = keys.install()
        } else {
            keys.uninstall()
            keysInstalled = false
        }
    }
    private func monitorPermissionIfNeeded() {
        permissionTask?.cancel()
        guard followPointerEnabled else { return }
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
        refreshDetails(reprobe: false)
    }
    func scheduleRefresh(reprobe: Bool = false) {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, self.started else { return }
            let old = self.previousExternals
            self.scanDisplays()
            let now = Set(self.displays.filter { !$0.isBuiltin }.map(\.uuid))
            self.previousExternals = now
            self.recoverBuiltinIfNeeded()
            if self.autoWorkflow && !now.subtracting(old).isEmpty {
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
            var uuid = info["kCGDisplayUUID"] as? String ?? previous[id]?.uuid ?? ""
            if uuid.isEmpty, let displayUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(nil, displayUUID) as String
            }
            // Unknown offline IDs cannot safely be used as physical display targets.
            guard !uuid.isEmpty || isBuiltin else { continue }
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
            if isBuiltin, let value = PrivateAPI.getBrightness(id) { controls[id]?.brightness = value * 100 }
        }
        if result != displays { generation += 1 }
        let retained = Set(result.map(\.id))
        for id in Array(controls.keys) where !retained.contains(id) {
            brightnessTasks.removeValue(forKey: id)?.cancel()
            volumeTasks.removeValue(forKey: id)?.cancel()
            originalGamma.removeValue(forKey: id)
            controls.removeValue(forKey: id)
        }
        displays = result.sorted { a, b in a.isBuiltin != b.isBuiltin ? a.isBuiltin : a.id < b.id }
        mainID = CGMainDisplayID()
        mirrored = displays.contains { $0.enabled && CGDisplayIsInMirrorSet($0.id) != 0 }
    }

    private func recoverBuiltinIfNeeded() {
        guard !externalOnline else { return }
        guard let id = builtin?.id ?? knownBuiltinID else { return }
        if builtin?.enabled != true {
            if PrivateAPI.setDisplayEnabled(id: id, enabled: true) {
                if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
                changedBuiltinForWorkflow = false
                preWorkflowBrightness = nil
                // The system reconfiguration callback schedules the follow-up. No perpetual polling loop.
            } else { lastError = "内建屏恢复失败，请尝试“全部点亮”或重新连接外置屏。" }
        } else if changedBuiltinForWorkflow {
            if let value = preWorkflowBrightness { _ = PrivateAPI.setBrightness(id, value / 100) }
            changedBuiltinForWorkflow = false
            preWorkflowBrightness = nil
        }
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
            for device in devices {
                let modes = snapshot.modes[device.uuid] ?? []
                self.controls[device.id]?.modes = modes
                self.controls[device.id]?.currentMode = modes.first(where: \.isCurrent)?.id ?? -1
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
            controls[display.id]?.maximumBrightness = maxValue.isFinite && maxValue > 0 ? maxValue : 100
            // A concurrent slider write wins over an older probe result.
            if brightnessTasks[display.id] == nil {
                controls[display.id]?.brightness = min(100, max(0, value / state(display.id).maximumBrightness * 100))
            }
            controls[display.id]?.dimming = .hardware
            restoreGamma(display.id)
        } else {
            controls[display.id]?.dimming = .software
        }
        let volume = await Subprocess.run("m1ddc", ["display", uuid, "get", "volume"], timeout: 2)
        guard !Task.isCancelled, generation == expected else { return }
        if volume.succeeded, let value = Double(volume.output), value.isFinite, value >= 0 {
            let maximum = await Subprocess.run("m1ddc", ["display", uuid, "max", "volume"], timeout: 2)
            guard !Task.isCancelled, generation == expected else { return }
            let maxValue = maximum.succeeded ? Double(maximum.output) ?? 100 : 100
            controls[display.id]?.maximumVolume = maxValue.isFinite && maxValue > 0 ? maxValue : 100
            controls[display.id]?.hasVolume = true
            if volumeTasks[display.id] == nil { controls[display.id]?.volume = min(100, value / state(display.id).maximumVolume * 100) }
        } else { controls[display.id]?.hasVolume = false }
        let input = await Subprocess.run("m1ddc", ["display", uuid, "get", "input"], timeout: 2)
        guard !Task.isCancelled, generation == expected else { return }
        controls[display.id]?.input = input.succeeded ? Int(input.output) ?? 0 : 0
        controls[display.id]?.hasInput = state(display.id).input > 0
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Double) {
        guard value.isFinite, let display = displays.first(where: { $0.id == id && $0.enabled }) else { return }
        let value = min(100, max(0, value))
        if display.isBuiltin {
            if PrivateAPI.setBrightness(id, value / 100) { controls[id]?.brightness = value }
            else { lastError = "无法设置内建屏亮度。" }
            return
        }
        guard state(id).dimming != .unknown else { return }
        controls[id]?.brightness = value
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

    func setVolume(_ display: DisplayInfo, _ value: Double) {
        guard value.isFinite, state(display.id).hasVolume else { return }
        let value = min(100, max(0, value))
        controls[display.id]?.volume = value
        guard volumeTasks[display.id] == nil else { return }
        volumeTasks[display.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.volumeTasks[display.id] = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.displays.contains(where: { $0.id == display.id && $0.uuid == display.uuid && $0.enabled }) else { return }
                let target = self.state(display.id).volume
                let raw = Int((target / 100 * self.state(display.id).maximumVolume).rounded())
                let result = await Subprocess.run("m1ddc", ["display", display.uuid, "set", "volume", "\(raw)"], timeout: 2)
                guard !Task.isCancelled else { return }
                if !result.succeeded { self.lastError = "显示器音量设置失败。"; return }
                if self.state(display.id).volume == target { return }
            }
        }
    }

    func setInput(_ display: DisplayInfo, _ value: Int) async {
        guard !isApplying, state(display.id).hasInput else { return }
        isApplying = true
        defer { isApplying = false }
        let result = await Subprocess.run("m1ddc", ["display", display.uuid, "set", "input", "\(value)"], timeout: 2)
        if result.succeeded { controls[display.id]?.input = value; scheduleRefresh() }
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
    func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        scanDisplays()
        if !enabled && !displays.contains(where: { $0.id != id && $0.enabled }) {
            lastError = "至少需要保留一块可用的实体显示器。"; return false
        }
        guard PrivateAPI.setDisplayEnabled(id: id, enabled: enabled) else {
            lastError = "显示器开关操作失败，当前 macOS 可能不支持此接口。"; return false
        }
        scheduleRefresh()
        return true
    }
    func toggleDisplay(_ display: DisplayInfo) {
        guard !isApplying else { return }
        _ = setEnabled(display.id, !display.enabled)
    }
    func wakeAll() {
        // Explicit recovery also pauses the automation that would immediately switch it off again.
        autoWorkflow = false
        UserDefaults.standard.set(false, forKey: "autoWorkflow")
        workflowTask?.cancel()
        scanDisplays()
        var ids = Set(displays.map(\.id))
        if let knownBuiltinID { ids.insert(knownBuiltinID) }
        for id in ids { _ = setEnabled(id, true); restoreGamma(id) }
        if let id = knownBuiltinID { _ = PrivateAPI.setBrightness(id, max(20, preWorkflowBrightness ?? 70) / 100) }
        changedBuiltinForWorkflow = false
        preWorkflowBrightness = nil
        scheduleRefresh(reprobe: true)
    }

    func setAutoWorkflow(_ enabled: Bool) {
        autoWorkflow = enabled
        UserDefaults.standard.set(enabled, forKey: "autoWorkflow")
        workflowTask?.cancel()
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
        workflowTask?.cancel()
        suppressCaptureUntil = Date().addingTimeInterval(5)
        workflowTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.autoWorkflow, !self.isApplying else { return }
            self.scanDisplays()
            guard self.externalOnline else { return }
            if let builtin = self.builtin, builtin.enabled {
                self.preWorkflowBrightness = self.state(builtin.id).brightness
            }
            await self.restoreLayout(silent: true)
            guard !Task.isCancelled, self.autoWorkflow else { return }
            self.scanDisplays()
            guard self.externalOnline, let builtin = self.builtin else { return }
            if builtin.enabled {
                self.changedBuiltinForWorkflow = self.setEnabled(builtin.id, false)
            } else if self.preWorkflowBrightness != nil {
                self.changedBuiltinForWorkflow = true
            }
        }
    }

    private func readSnapshot() async -> DisplaySnapshot? {
        let result = await Subprocess.run("displayplacer", ["list"])
        return result.succeeded ? DisplaySnapshot(result.output) : nil
    }
    private func saveLayout(_ snapshot: DisplaySnapshot) {
        guard externalOnline, DisplaySnapshot.canRestore(snapshot.arguments, connectedIDs: connectedIDs) else { return }
        UserDefaults.standard.set(snapshot.arguments, forKey: layoutKey)
    }
    private func apply(_ arguments: [String], expected: Int) async -> Bool {
        guard generation == expected, DisplaySnapshot.canRestore(arguments, connectedIDs: connectedIDs) else {
            lastError = "显示器连接已变化，请刷新后重试。"; return false
        }
        suppressCaptureUntil = Date().addingTimeInterval(2)
        let result = await Subprocess.run("displayplacer", arguments)
        if !result.succeeded { lastError = result.timedOut ? "显示设置操作超时。" : "显示设置未成功应用，请尝试其他模式。" }
        scheduleRefresh()
        return result.succeeded
    }
    func restoreLayout(silent: Bool = false) async {
        guard !isApplying else { return }
        scanDisplays()
        guard let arguments = UserDefaults.standard.stringArray(forKey: layoutKey),
              DisplaySnapshot.canRestore(arguments, connectedIDs: connectedIDs) else {
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
    func setMode(_ display: DisplayInfo, _ mode: DisplayMode) async {
        guard !isApplying, !mirrored else { return }
        isApplying = true
        defer { isApplying = false }
        let expected = generation
        guard let snapshot = await readSnapshot(), let record = snapshot.layouts.first(where: { $0.uuid == display.uuid }),
              snapshot.modes[display.uuid]?.contains(mode) == true else { lastError = "显示模式列表已变化，请刷新后重试。"; return }
        let args = snapshot.layouts.map { item in
            item.uuid == display.uuid
                ? "id:\(item.uuid) mode:\(mode.id) origin:(\(record.x),\(record.y)) degree:\(record.rotation)"
                : item.argument
        }
        // Mode selection implicitly enables the target; make that explicit for validation.
        let explicit = args.map { $0.contains(" mode:") ? $0 + " enabled:true" : $0 }
        _ = await apply(explicit, expected: expected)
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
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        let id = number.uint32Value
        // Native internal display handling retains Apple's HUD and automatic brightness behavior.
        guard let display = displays.first(where: { $0.id == id && $0.enabled && !$0.isBuiltin }),
              state(id).dimming != .unknown else { return false }
        let value = min(100, max(0, state(id).brightness + Double(delta) * (fine ? 1.5625 : 6.25)))
        setBrightness(display.id, value)
        showHUD(Int(value.rounded()), screen: screen)
        return true
    }
    private func showHUD(_ value: Int, screen: NSScreen) {
        let size = NSSize(width: 170, height: 58)
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: HUDView(value: value))
            hud = panel
        }
        (hud?.contentView as? NSHostingView<HUDView>)?.rootView = HUDView(value: value)
        hud?.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + screen.frame.height * 0.2,
                            width: size.width, height: size.height), display: true)
        hud?.orderFrontRegardless()
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.hud?.orderOut(nil)
        }
    }
}
