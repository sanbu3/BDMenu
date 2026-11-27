import SwiftUI
import DisplayCore

@MainActor
struct AdaptiveSettingsView: View {
    @Environment(DisplayManager.self) private var dm
    @State private var ruleBundleID = ""
    @State private var rulePreset: PerformancePreset = .lowPower
    @State private var windowApplications = ""

    var body: some View {
        @Bindable var performance = dm.performance
        @Bindable var windows = dm.windowCoordinator
        HStack(spacing: 12) {
            StatusPill(title: dm.deviceState.topologyIsStable ? "显示配置稳定" : "正在协调显示配置", color: dm.deviceState.topologyIsStable ? .green : .orange)
            Spacer()
            Text("GPU \(dm.hardware.gpuLabel)").monospacedDigit()
            if dm.hardware.onBattery { Label("电池供电", systemImage: "battery.50percent") }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "跨屏窗口适配", subtitle: "鼠标释放并稳定后才调整窗口；全屏、最小化、不可缩放与系统授权窗口自动跳过。记忆仅保留本次应用运行会话，不读取窗口内容。", symbol: "macwindow.on.rectangle")
                Toggle("自动适配跨屏窗口", isOn: $windows.enabled)
                    .onChange(of: windows.enabled) { _, _ in windows.configure() }
                Toggle("平滑调整窗口尺寸", isOn: $windows.smoothResizing)
                    .onChange(of: windows.smoothResizing) { _, _ in windows.configure() }
                    .help("松开鼠标后用约 0.18 秒的短过渡完成适配；再次按下鼠标即停止。系统减少动态效果开启时直接完成。")
                Toggle("显示器重连与分辨率恢复时还原窗口", isOn: $windows.restoreOnReconnect)
                    .onChange(of: windows.restoreOnReconnect) { _, _ in windows.configure() }
                    .help("保留原屏幕窗口尺寸，避免临时缩小覆盖原有记忆；用户手动调整会成为新记忆。")
                HStack {
                    Text(windows.status).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(windows.observedWindows) 个窗口 · 已适配 \(windows.adjustedWindows) 次")
                        .font(BDMenuStyle.detail).monospacedDigit()
                }
                if windows.enabled && !windows.trusted {
                    Button("打开辅助功能权限") { dm.requestPermission() }
                }
                DisclosureGroup("应用参与规则") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("仅管理列表中的应用", isOn: $windows.allowlistOnly)
                            .onChange(of: windows.allowlistOnly) { _, _ in windows.configure() }
                            .help("关闭时，列表为排除名单；开启时，列表为允许名单。使用应用 Bundle ID，每行一个。")
                        TextEditor(text: $windowApplications).font(.system(.body, design: .monospaced)).frame(height: 82)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.2)))
                            .accessibilityLabel("窗口规则应用 Bundle ID 列表")
                        HStack {
                            Button("保存规则") { windows.applicationList = windowApplications; windows.configure() }
                            Spacer()
                            Button("清除窗口记忆") { windows.forget() }
                        }
                    }.padding(.top, 12)
                }
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "智能性能", subtitle: "默认仅监测；开启后优先降低刷新率，保持逻辑尺寸与 HiDPI。拖动、全屏、切换显示器与手动试用期间暂停，低负载稳定 60 秒后尝试恢复，切换冷却 90 秒。", symbol: "gauge.with.needle")
                Toggle("持续高负载时自动降低刷新率", isOn: $performance.automaticReduction)
                    .onChange(of: performance.automaticReduction) { _, _ in performance.persist() }
                Toggle("同时在空闲 3 分钟后降低刷新率", isOn: $performance.reduceWhenIdle)
                    .onChange(of: performance.reduceWhenIdle) { _, _ in performance.persist() }
                    .disabled(!performance.automaticReduction)
                    .help("沿用同尺寸刷新率策略，拖动和全屏时暂停；恢复活动后按低负载恢复规则处理。")
                HStack {
                    Text("GPU 阈值")
                    Slider(value: $performance.highThreshold, in: 40...95, step: 5)
                    Text("\(Int(performance.highThreshold))%").monospacedDigit().frame(width: 42)
                }.onChange(of: performance.highThreshold) { _, _ in performance.persist() }
                HStack {
                    Text("持续时间")
                    Slider(value: $performance.sustainedSeconds, in: 10...120, step: 5)
                    Text("\(Int(performance.sustainedSeconds)) 秒").monospacedDigit().frame(width: 55)
                }.onChange(of: performance.sustainedSeconds) { _, _ in performance.persist() }
                Text(performance.status).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                if let warning = performance.loadWarning {
                    HStack {
                        Label(warning, systemImage: "gauge.with.needle").foregroundStyle(.orange)
                        Spacer()
                        Button("关闭提醒") { performance.dismissWarning() }
                    }.font(BDMenuStyle.detail)
                }
            }
        }
        forEachPreset
        BDMenuCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "前台应用策略", subtitle: "稳定停留 3 秒后应用；自动规则只改变同逻辑尺寸与 HiDPI 的刷新率。离开时尝试恢复，手动显示操作优先并暂停自动策略 90 秒。排除应用不会触发自动降载。", symbol: "app.badge")
                HStack {
                    TextField("应用 Bundle ID，例如 com.apple.Safari", text: $ruleBundleID)
                        .textFieldStyle(.roundedBorder)
                    Picker("预设", selection: $rulePreset) {
                        ForEach(PerformancePreset.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 120)
                    Button("添加") { addRule() }.disabled(ruleBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(performance.applicationRules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.id).lineLimit(1).help(rule.id)
                            Text(rule.excluded ? "不参与自动性能策略" : (rule.preset?.title ?? "无预设"))
                                .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(rule.excluded ? "启用规则" : "排除自动策略") {
                            if let i = performance.applicationRules.firstIndex(where: { $0.id == rule.id }) {
                                performance.applicationRules[i].excluded.toggle(); performance.persist(); performance.applicationChanged()
                            }
                        }
                        Button("删除") {
                            performance.applicationRules.removeAll { $0.id == rule.id }
                            performance.persist(); performance.applicationChanged()
                        }
                    }
                }
                if performance.applicationRules.isEmpty {
                    Text("未添加应用规则").font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { windowApplications = dm.windowCoordinator.applicationList }
    }

    private var forEachPreset: some View {
        ForEach(dm.displays.filter { $0.enabled && !$0.isBuiltin }) { display in
            BDMenuCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "\(display.name) · 性能预设", subtitle: "每个模板可绑定系统提供的任意模式；手动试用保留 15 秒确认。预设名称是目标，不代表已测得功耗改善。", symbol: "display")
                    ForEach(PerformancePreset.allCases) { preset in
                        HStack {
                            Text(preset.title).frame(width: 90, alignment: .leading)
                            Picker(preset.title, selection: presetBinding(preset, display: display)) {
                                let modes = dm.state(display.id).modes
                                let spec = dm.performance.spec(preset, uuid: display.uuid)
                                if !modes.contains(where: spec.matches) { Text("不可用：\(spec.label)").tag(-1) }
                                ForEach(modes) { Text($0.label).tag($0.id) }
                            }.labelsHidden()
                            Button("试用") { Task { await dm.performance.applyPreset(preset, to: display) } }
                                .disabled(dm.isApplying || !dm.state(display.id).modes.contains(where: dm.performance.spec(preset, uuid: display.uuid).matches))
                        }
                    }
                }
            }
        }
    }
    private func presetBinding(_ preset: PerformancePreset, display: DisplayManager.DisplayInfo) -> Binding<Int> {
        Binding(get: {
            dm.state(display.id).modes.first(where: dm.performance.spec(preset, uuid: display.uuid).matches)?.id ?? -1
        }, set: { id in
            if let mode = dm.state(display.id).modes.first(where: { $0.id == id }) {
                dm.performance.setSpec(preset, uuid: display.uuid, mode: mode)
            }
        })
    }
    private func addRule() {
        let bundle = ruleBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundle.isEmpty else { return }
        dm.performance.applicationRules.removeAll { $0.id == bundle }
        dm.performance.applicationRules.append(.init(id: bundle, preset: rulePreset))
        dm.performance.persist(); dm.performance.applicationChanged()
        ruleBundleID = ""
    }
}
