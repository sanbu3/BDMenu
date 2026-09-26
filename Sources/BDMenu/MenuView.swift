import SwiftUI

struct MenuView: View {
    @Environment(DisplayManager.self) private var dm
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("显示器", systemImage: "display.2").font(.headline)
                    Spacer()
                    if dm.isApplying { ProgressView().controlSize(.small) }
                    Button { dm.scheduleRefresh(reprobe: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("重新检测显示器与 DDC 能力")
                        .disabled(dm.isApplying)
                }
                if dm.displays.isEmpty {
                    Text("正在检测显示器…").foregroundStyle(.secondary)
                }
                ForEach(dm.displays) { display in
                    displaySection(display)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("自动工作流", isOn: Binding(get: { dm.autoWorkflow }, set: dm.setAutoWorkflow))
                    Text("接入外置屏后关闭内建屏；断开后恢复。退出应用会恢复由自动工作流关闭的内建屏。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("亮度键跟随鼠标", isOn: Binding(get: { dm.followPointerEnabled }, set: dm.setFollowPointer))
                    if dm.followPointerEnabled {
                        if !dm.keysTrusted {
                            Text("等待辅助功能授权。允许后会自动生效。")
                                .font(.caption).foregroundStyle(.orange)
                            Button("打开辅助功能设置") { dm.requestPermission() }.controlSize(.small)
                        } else if !dm.keysInstalled {
                            Text("已授权，但按键监听未启动。可尝试重启应用，或重新添加当前应用的辅助功能权限。")
                                .font(.caption).foregroundStyle(.orange)
                            Button("重新检测") { dm.refreshPermission() }.controlSize(.small)
                        } else {
                            Text("已启用 · ⇧⌥ + 亮度键可精细调节")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Toggle("镜像模式", isOn: Binding(get: { dm.mirrored }, set: { value in Task { await dm.setMirror(value) } }))
                            .disabled(dm.isApplying || dm.displays.filter(\.enabled).count < 2)
                        Toggle("登录时启动", isOn: Binding(get: { dm.launchAtLogin }, set: dm.setLaunchAtLogin))
                    }
                    if dm.loginStatus == .requiresApproval {
                        Text("登录启动需要在系统设置 → 通用 → 登录项中允许。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let error = dm.lastError {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        Spacer(minLength: 4)
                        Button { dm.lastError = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).help("关闭提示")
                    }
                }
                HStack {
                    Button("恢复布局") { Task { await dm.restoreLayout() } }.disabled(dm.isApplying)
                    Spacer()
                    Button("全部点亮") { dm.wakeAll() }.help("恢复屏幕和亮度，并暂停自动工作流")
                }
                .controlSize(.small)
                Divider()
                HStack {
                    Text("BDMenu \(dm.version)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.caption)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            .padding(14)
        }
        .frame(width: 410)
        .frame(maxHeight: 680)
        .onAppear { dm.panelOpened() }
    }

    @ViewBuilder
    private func displaySection(_ display: DisplayManager.DisplayInfo) -> some View {
        let state = dm.state(display.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display").foregroundStyle(.secondary)
                Text(display.name).lineLimit(1).help(display.name)
                if display.id == dm.mainID {
                    Text("主屏").font(.caption2).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.blue.opacity(0.12), in: Capsule()).foregroundStyle(.blue)
                }
                Spacer()
                Circle().fill(display.enabled ? .green : .gray).frame(width: 6, height: 6)
                Button(display.enabled ? "关闭" : "打开") { dm.toggleDisplay(display) }
                    .disabled(dm.isApplying || (display.enabled && dm.displays.filter(\.enabled).count <= 1))
            }
            if !display.enabled {
                Text("已断开，点击“打开”后可调整。") .font(.caption).foregroundStyle(.secondary)
            } else {
                slider("亮度", icon: "sun.max", value: state.brightness) { dm.setBrightness(display.id, $0) }
                    .disabled(!display.isBuiltin && state.dimming == .unknown)
                if !display.isBuiltin {
                    if state.dimming == .software {
                        Text("软件调光 · 不改变显示器背光，退出时恢复色彩曲线")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if state.dimming == .unknown {
                        Text("正在检测亮度控制…").font(.caption2).foregroundStyle(.secondary)
                    }
                    if state.hasVolume {
                        slider("音量", icon: "speaker.wave.2", value: state.volume) { dm.setVolume(display, $0) }
                    }
                    if state.hasInput {
                        Picker("输入源", selection: Binding(get: { dm.state(display.id).input }, set: { value in Task { await dm.setInput(display, value) } })) {
                            if !dm.inputOptions.contains(where: { $0.0 == state.input }) { Text("当前 (\(state.input))").tag(state.input) }
                            ForEach(dm.inputOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }.disabled(dm.isApplying)
                    }
                    if !state.modes.isEmpty {
                        Picker("分辨率", selection: Binding(get: { dm.state(display.id).currentMode }, set: { number in
                            if let mode = dm.state(display.id).modes.first(where: { $0.id == number }) {
                                Task { await dm.setMode(display, mode) }
                            }
                        })) {
                            if state.currentMode < 0 { Text("当前模式").tag(-1) }
                            ForEach(state.modes) { Text($0.label).tag($0.id) }
                        }.disabled(dm.isApplying || dm.mirrored)
                    }
                }
                if display.id != dm.mainID && !dm.mirrored {
                    Button("设为主屏") { Task { await dm.setMain(display) } }
                        .buttonStyle(.link).disabled(dm.isApplying)
                }
            }
        }
    }
    private func slider(_ name: String, icon: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: Binding(get: { value }, set: set), in: 0...100).accessibilityLabel(name)
            Text("\(Int(value.rounded()))%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
        }
    }
}
