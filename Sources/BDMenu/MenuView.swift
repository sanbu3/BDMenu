import AppKit
import SwiftUI

private struct MenuContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
struct MenuView: View {
    @Environment(DisplayManager.self) private var dm
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 440

    private var maximumPanelHeight: CGFloat {
        min(780, max(360, (NSScreen.main?.visibleFrame.height ?? 720) - 36))
    }

    private var panelHeight: CGFloat {
        min(contentHeight, maximumPanelHeight)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if dm.displays.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在检测显示器…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(cardBackground)
                }

                ForEach(dm.displays) { display in
                    displaySection(display)
                }

                settings

                if let error = dm.lastError {
                    errorMessage(error)
                }

                actions
                footer
            }
            .font(BDMenuStyle.body)
            .toggleStyle(BDMenuSwitchStyle())
            .buttonStyle(BDMenuCapsuleButtonStyle())
            .controlSize(.large)
            .padding(16)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollIndicators(contentHeight > maximumPanelHeight ? .visible : .hidden)
        .frame(width: 500, height: max(1, panelHeight))
        .onPreferenceChange(MenuContentHeightKey.self) { height in
            guard height > 0, abs(contentHeight - height) > 0.5 else { return }
            contentHeight = ceil(height)
        }
        .onAppear { dm.panelOpened() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("显示器", systemImage: "display.2")
                .font(BDMenuStyle.title)
            Spacer()
            if dm.isApplying {
                ProgressView().controlSize(.small)
            }
            Button { dm.scheduleRefresh(reprobe: true) } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BDMenuCapsuleButtonStyle())
            .buttonBorderShape(.capsule)
            .help("重新检测显示器与亮度控制能力")
            .disabled(dm.isApplying)
        }
        .padding(.horizontal, 2)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(BDMenuStyle.section)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            settingCapsule {
                Toggle("自动工作流", isOn: Binding(get: { dm.autoWorkflow }, set: { dm.setAutoWorkflow($0) }))
            }
            Text("连接外置屏后关闭内置屏；断开后恢复。退出应用时会恢复由自动工作流关闭的内置屏。")
                .font(BDMenuStyle.detail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            settingCapsule {
                Toggle("内置屏关闭时同步键盘背光", isOn: Binding(
                    get: { dm.syncKeyboardBacklight },
                    set: { dm.setSyncKeyboardBacklight($0) }
                ))
                .disabled(!dm.keyboardBacklightAvailable)
            }
            Text(dm.keyboardBacklightAvailable
                 ? "关闭内置屏时保存并关闭内置键盘背光；内置屏恢复或取消同步时还原。"
                 : "当前设备未检测到可控制的内置键盘背光。")
                .font(BDMenuStyle.detail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            settingCapsule {
                Toggle("内建屏关闭时优先密码验证", isOn: Binding(
                    get: { dm.preferPasswordWhenBuiltinOff },
                    set: { dm.setPreferPasswordWhenBuiltinOff($0) }
                ))
            }
            if dm.preferPasswordWhenBuiltinOff {
                Text(dm.passwordPreference.status.text)
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(dm.passwordPreference.status == .needsAccessibility || dm.passwordPreference.status == .unavailable ? .orange : .secondary)
                    .padding(.horizontal, 10)
                if dm.passwordPreference.status == .needsAccessibility {
                    Button("允许自动切换…") { dm.requestPermission() }
                        .padding(.horizontal, 10)
                }
                Text("自动选择支持的系统弹窗中的“使用密码”。不改变锁屏或第三方应用的验证策略。")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }

            settingCapsule {
                Toggle("亮度快捷键", isOn: Binding(get: { dm.keyboardEnabled }, set: { dm.setKeyboardEnabled($0) }))
            }
            HStack {
                Text("自定义亮度按键")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("按键设置…") {
                    openWindow(id: "brightness-keys")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
            .padding(.horizontal, 10)

            Text("\(dm.decreaseShortcut.label) 降低 · \(dm.increaseShortcut.label) 提高 · \(dm.brightnessTarget.title)")
                .font(BDMenuStyle.detail)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            if dm.keyboardEnabled {
                pointerPermissionStatus
                    .padding(.horizontal, 10)
            }

            settingCapsule {
                Toggle("镜像模式", isOn: Binding(
                    get: { dm.mirrored },
                    set: { value in Task { await dm.setMirror(value) } }
                ))
                .disabled(dm.isApplying || dm.displays.filter(\.enabled).count < 2)
            }
            settingCapsule {
                Toggle("登录时启动", isOn: Binding(get: { dm.launchAtLogin }, set: { dm.setLaunchAtLogin($0) }))
            }

            if dm.loginStatus == .requiresApproval {
                Text("登录启动需要在系统设置 → 通用 → 登录项中允许。")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
            }
        }
    }

    @ViewBuilder
    private var pointerPermissionStatus: some View {
        if !dm.keysTrusted {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("等待辅助功能授权。允许后会自动生效。")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Button("打开设置") { dm.requestPermission() }
                    .buttonStyle(BDMenuCapsuleButtonStyle())
                    .buttonBorderShape(.capsule)
            }
        } else if !dm.keysInstalled {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("按键监听未启动。")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Button("重新检测") { dm.refreshPermission() }
                    .buttonStyle(BDMenuCapsuleButtonStyle())
                    .buttonBorderShape(.capsule)
            }
        } else {
            Text("已启用 · ⇧⌥ + 亮度键可精细调节")
                .font(BDMenuStyle.detail)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("恢复布局") { Task { await dm.restoreLayout() } }
                .disabled(dm.isApplying)
            Spacer()
            Button("全部点亮") { dm.wakeAll() }
                .help("恢复屏幕和亮度，并暂停自动工作流")
        }
        .buttonStyle(BDMenuCapsuleButtonStyle())
        .buttonBorderShape(.capsule)
    }

    private var footer: some View {
        HStack {
            Text("BDMenu \(dm.version)")
                .font(BDMenuStyle.detail)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(BDMenuCapsuleButtonStyle())
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
        .padding(.top, 2)
    }

    private func errorMessage(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(BDMenuStyle.detail)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button { dm.lastError = nil } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BDMenuCapsuleButtonStyle())
            .help("关闭提示")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func displaySection(_ display: DisplayManager.DisplayInfo) -> some View {
        let state = dm.state(display.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                Text(display.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .help(display.name)
                if display.id == dm.mainID {
                    Text("主屏")
                        .font(BDMenuStyle.detail)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Spacer()
                Circle()
                    .fill(display.enabled ? .green : .gray)
                    .frame(width: 8, height: 8)
                Button(display.enabled ? "关闭" : "打开") { dm.toggleDisplay(display) }
                    .buttonStyle(BDMenuCapsuleButtonStyle())
                    .buttonBorderShape(.capsule)
                    .disabled(dm.isApplying || (display.enabled && dm.displays.filter(\.enabled).count <= 1))
            }

            if !display.enabled {
                Text("已关闭。打开后可调整显示设置。")
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(.secondary)
            } else {
                slider("亮度", icon: "sun.max", value: state.brightness) { dm.setBrightness(display.id, $0) }
                    .disabled(!display.isBuiltin && state.dimming == .unknown)

                if !display.isBuiltin {
                    if state.dimming == .software {
                        Text("软件调光 · 不改变显示器背光，退出时恢复色彩曲线")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                    } else if state.dimming == .unknown {
                        Text("正在检测亮度控制…")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                    }

                    if state.hasVolume {
                        slider("音量", icon: "speaker.wave.2", value: state.volume) { dm.setVolume(display, $0) }
                    }

                    if state.hasInput {
                        Picker("输入源", selection: Binding(
                            get: { dm.state(display.id).input },
                            set: { value in Task { await dm.setInput(display, value) } }
                        )) {
                            if !dm.inputOptions.contains(where: { $0.0 == state.input }) {
                                Text("当前 (\(state.input))").tag(state.input)
                            }
                            ForEach(dm.inputOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .disabled(dm.isApplying)
                    }

                    if !state.modes.isEmpty {
                        Picker("分辨率", selection: Binding(
                            get: { dm.state(display.id).currentMode },
                            set: { number in
                                if let mode = dm.state(display.id).modes.first(where: { $0.id == number }) {
                                    Task { await dm.setMode(display, mode) }
                                }
                            }
                        )) {
                            if state.currentMode < 0 { Text("当前模式").tag(-1) }
                            ForEach(state.modes) { Text($0.label).tag($0.id) }
                        }
                        .disabled(dm.isApplying || dm.mirrored)
                    }
                }

                if display.id != dm.mainID && !dm.mirrored {
                    Button("设为主屏") { Task { await dm.setMain(display) } }
                        .buttonStyle(BDMenuCapsuleButtonStyle())
                        .buttonBorderShape(.capsule)
                        .disabled(dm.isApplying)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }

    private func settingCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
            )
    }

    private func slider(_ name: String, icon: String, value: Double, set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 17))
                .frame(width: 24)
            Slider(value: Binding(get: { value }, set: set), in: 0...100)
                .controlSize(.large)
                .frame(minHeight: 34)
                .accessibilityLabel(name)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
        }
    }
}
