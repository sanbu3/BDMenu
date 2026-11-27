import AppKit
import Observation
import DisplayCore

struct ApplicationDisplayRule: Codable, Identifiable, Equatable {
    var id: String // bundle identifier, never a window title
    var preset: PerformancePreset?
    var excluded = false
}

@MainActor @Observable
final class PerformanceController {
    var automaticReduction = UserDefaults.standard.bool(forKey: "performance.automatic.v1")
    var reduceWhenIdle = UserDefaults.standard.bool(forKey: "performance.idle.v1")
    var highThreshold = min(95, max(40, UserDefaults.standard.object(forKey: "performance.high.v1") as? Double ?? 80))
    var sustainedSeconds = min(120, max(10, UserDefaults.standard.object(forKey: "performance.duration.v1") as? Double ?? 20))
    var applicationRules: [ApplicationDisplayRule] = {
        guard let data = UserDefaults.standard.data(forKey: "performance.appRules.v1") else { return [] }
        return (try? JSONDecoder().decode([ApplicationDisplayRule].self, from: data)) ?? []
    }()
    var overrides: [String: [String: DisplayModeSpec]] = {
        guard let data = UserDefaults.standard.data(forKey: "performance.presets.v1") else { return [:] }
        return (try? JSONDecoder().decode([String: [String: DisplayModeSpec]].self, from: data)) ?? [:]
    }()
    private(set) var status = "自动降载已关闭"
    private(set) var loadWarning: String?
    private(set) var isReduced = false
    @ObservationIgnored weak var manager: DisplayManager?
    @ObservationIgnored private let state: DeviceStateStore
    @ObservationIgnored private var policy = PerformancePolicy()
    @ObservationIgnored private var warningPolicy = PerformancePolicy()
    @ObservationIgnored private var baseline: [String: DisplayModeSpec] = [:]
    @ObservationIgnored private var reducedModes: [String: DisplayModeSpec] = [:]
    @ObservationIgnored private var lastInteraction = Date.distantPast
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var appTask: Task<Void, Never>?
    @ObservationIgnored private var appBaseline: [String: DisplayModeSpec] = [:]
    @ObservationIgnored private var activeRule: String?
    @ObservationIgnored private var version = 0
    @ObservationIgnored private var pendingSample: Task<Void, Never>?

    init(state: DeviceStateStore) { self.state = state }
    func spec(_ preset: PerformancePreset, uuid: String) -> DisplayModeSpec {
        overrides[uuid]?[preset.rawValue] ?? preset.defaultSpec
    }
    func setSpec(_ preset: PerformancePreset, uuid: String, mode: DisplayMode) {
        overrides[uuid, default: [:]][preset.rawValue] = DisplayModeSpec(mode)
        persist()
    }
    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(automaticReduction, forKey: "performance.automatic.v1")
        defaults.set(reduceWhenIdle, forKey: "performance.idle.v1")
        defaults.set(highThreshold, forKey: "performance.high.v1")
        defaults.set(sustainedSeconds, forKey: "performance.duration.v1")
        defaults.set(try? JSONEncoder().encode(applicationRules), forKey: "performance.appRules.v1")
        defaults.set(try? JSONEncoder().encode(overrides), forKey: "performance.presets.v1")
        policy.reset(); warningPolicy.reset()
        status = automaticReduction ? "等待持续负载 · 优先降低刷新率" : "自动降载已关闭"
    }
    func manualOverride() {
        guard !applying else { return }
        version += 1
        appTask?.cancel(); pendingSample?.cancel()
        lastInteraction = Date()
        policy.reset(); baseline = [:]; reducedModes = [:]; isReduced = false
        appBaseline = [:]; activeRule = nil
        status = automaticReduction ? "手动操作优先 · 自动策略暂停 90 秒" : "手动显示配置"
    }
    func pauseForTopology() {
        guard !applying else { return }
        version += 1
        appTask?.cancel(); pendingSample?.cancel()
        policy.reset(); warningPolicy.reset()
        baseline = [:]; reducedModes = [:]; isReduced = false
        appBaseline = [:]; activeRule = nil
        lastInteraction = Date()
    }
    func stop() { version += 1; appTask?.cancel(); pendingSample?.cancel() }
    func sample() {
        guard pendingSample == nil else { return }
        pendingSample = Task { [weak self] in
            guard let self else { return }
            defer { self.pendingSample = nil }
            await self.evaluate()
        }
    }
    private func evaluate() async {
        guard let manager else { return }
        let hardware = state.hardware
        let fresh = hardware.sampledAt.map { Date().timeIntervalSince($0) < 5 } ?? false
        let rule = applicationRules.first { $0.id == state.frontmostBundleID }
        let blocked = !state.automaticActionsAllowed || state.mouseIsDown || applying
            || manager.modeTrialLabel != nil || rule?.excluded == true || activeRule != nil
            || Date().timeIntervalSince(lastInteraction) < 90
            || (automaticReduction && state.frontmostIsFullscreen) || !fresh
        let now = ProcessInfo.processInfo.systemUptime
        if warningPolicy.evaluate(usage: hardware.gpuUsage, now: now, blocked: blocked, reduced: false,
                                  high: highThreshold, duration: sustainedSeconds, cooldown: 180) == .reduce {
            loadWarning = "GPU 持续高于 \(Int(highThreshold))% · \(Int(sustainedSeconds)) 秒"
        }
        guard automaticReduction else { policy.reset(); return }
        let effectiveUsage = reduceWhenIdle && state.userIdleSeconds >= 180 ? 100 : hardware.gpuUsage
        let action = policy.evaluate(usage: effectiveUsage, now: now, blocked: blocked,
                                     reduced: isReduced, high: highThreshold, duration: sustainedSeconds)
        guard let action else { return }
        let devices = manager.displays.filter { $0.enabled && !$0.isBuiltin }
        var requested: [String: DisplayModeSpec] = [:]
        if action == .reduce {
            for display in devices {
                let controls = manager.state(display.id)
                guard let current = controls.modes.first(where: \.isCurrent),
                      let lower = PerformancePolicy.lowerRefresh(current: current, available: controls.modes) else { continue }
                baseline[display.uuid] = DisplayModeSpec(current)
                requested[display.uuid] = DisplayModeSpec(lower)
            }
        } else {
            for display in devices {
                let modes = manager.state(display.id).modes
                guard let actual = modes.first(where: \.isCurrent),
                      reducedModes[display.uuid]?.matches(actual) == true,
                      let original = baseline[display.uuid], modes.contains(where: original.matches) else { continue }
                requested[display.uuid] = original
            }
        }
        guard !requested.isEmpty else {
            status = "当前没有保持尺寸和 HiDPI 的可用刷新率切换"
            return
        }
        applying = true
        let success = await manager.applyAutomaticModes(requested)
        applying = false
        if success {
            if action == .reduce { reducedModes = requested; isReduced = true; status = "已降低刷新率 · 桌面尺寸保持不变" }
            else { reducedModes = [:]; baseline = [:]; isReduced = false; status = "持续低负载，已恢复原刷新率" }
        } else {
            automaticReduction = false
            persist()
            status = "自动切换失败，已暂停降载；请检查显示器提示"
        }
    }
    func dismissWarning() { loadWarning = nil }

    func applyPreset(_ preset: PerformancePreset, to display: DisplayManager.DisplayInfo) async {
        guard let manager else { return }
        manualOverride()
        let wanted = spec(preset, uuid: display.uuid)
        guard let mode = manager.state(display.id).modes.first(where: wanted.matches) else {
            status = "该预设不受当前显示器支持，请选择可用模式"
            return
        }
        await manager.setMode(display, mode)
    }
    func applicationChanged() {
        appTask?.cancel()
        guard applicationRules.contains(where: { $0.preset != nil && !$0.excluded }) || !appBaseline.isEmpty else { return }
        let expected = version
        appTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, let manager = self.manager, self.version == expected,
                  self.state.automaticActionsAllowed, !self.state.mouseIsDown,
                  !self.state.frontmostIsFullscreen, !self.applying,
                  Date().timeIntervalSince(self.lastInteraction) >= 90 else { return }
            let selectedRule = self.applicationRules.first { $0.id == self.state.frontmostBundleID }
            let rule = selectedRule?.excluded == true ? nil : selectedRule
            if self.activeRule == rule?.id { return }
            var requested: [String: DisplayModeSpec] = [:]
            for display in manager.displays.filter({ $0.enabled && !$0.isBuiltin }) {
                let modes = manager.state(display.id).modes
                guard let current = modes.first(where: \.isCurrent) else { continue }
                if let preset = rule?.preset {
                    let wanted = self.spec(preset, uuid: display.uuid)
                    // Automatic app rules never silently resize the desktop or change HiDPI.
                    guard wanted.width == current.width, wanted.height == current.height,
                          wanted.scaling == current.scaling, modes.contains(where: wanted.matches) else { continue }
                    self.appBaseline[display.uuid] = self.appBaseline[display.uuid] ?? DisplayModeSpec(current)
                    requested[display.uuid] = wanted
                } else if let original = self.appBaseline[display.uuid], modes.contains(where: original.matches) {
                    requested[display.uuid] = original
                }
            }
            guard !requested.isEmpty else { self.status = "应用策略无同尺寸模式，已跳过"; return }
            self.applying = true
            let success = await manager.applyAutomaticModes(requested)
            self.applying = false
            if success {
                self.activeRule = rule?.id
                if rule?.preset == nil { self.appBaseline = [:] }
                self.status = rule?.preset == nil ? "已恢复应用策略前的刷新率" : "已应用前台应用的刷新率策略"
            } else { self.status = "应用策略失败，等待下一次手动配置"; self.lastInteraction = Date() }
        }
    }
}
