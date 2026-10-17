import SwiftUI

struct CapsuleMenu<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder var content: Content
    @FocusState private var focused: Bool

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 14))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? .blue : Color.primary.opacity(0.10), lineWidth: focused ? 2 : 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .focused($focused)
    }
}

@MainActor
struct DisplayCard: View {
    @Environment(DisplayManager.self) private var dm
    let display: DisplayManager.DisplayInfo
    var compact = false

    private var state: DisplayManager.Controls { dm.state(display.id) }
    private var brightnessMethod: String {
        if display.isBuiltin { return "原生亮度" }
        switch state.dimming {
        case .hardware: return "硬件亮度"
        case .software: return "软件调光"
        case .unknown: return "检测中"
        }
    }
    private var canDisable: Bool { dm.displays.filter(\.enabled).count > 1 }

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                HStack(spacing: 12) {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                        .font(.system(size: compact ? 22 : 28, weight: .regular))
                        .foregroundStyle(display.enabled ? BDMenuStyle.accent : .secondary)
                        .frame(width: compact ? 32 : 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(display.name)
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                            .lineLimit(1)
                            .help(display.name)
                        Text(display.enabled ? (display.isBuiltin ? "内建显示器" : "外接显示器") : "已停用")
                            .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if display.id == dm.mainID { StatusPill(title: "主屏") }
                    Button(display.enabled ? "停用" : "启用") { dm.toggleDisplay(display) }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: !display.enabled, compact: compact))
                        .disabled(dm.isApplying || (display.enabled && !canDisable))
                        .help(display.enabled && !canDisable ? "至少保留一块屏幕在线" : "\(display.enabled ? "停用" : "启用")\(display.name)")
                        .accessibilityLabel("\(display.enabled ? "停用" : "启用")\(display.name)")
                }

                if display.enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("亮度", systemImage: "sun.max")
                                .font(BDMenuStyle.body).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(state.brightness.rounded()))")
                                .font(.system(size: compact ? 25 : 32, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Text("% ").font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { dm.state(display.id).brightness }, set: { dm.setBrightness(display.id, $0) }), in: 0...100)
                            .controlSize(.large)
                            .frame(minHeight: 30)
                            .disabled(!display.isBuiltin && state.dimming == .unknown)
                            .accessibilityLabel("\(display.name)亮度")
                        HStack {
                            Text(brightnessMethod).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            if !compact {
                                Text(state.dimming == .software ? "调整画面明暗，不改变背光" : "拖动后自动应用")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !compact { advancedControls }
                } else if !compact {
                    Text("启用后可以调节亮度、分辨率和布局。已保存的工作流设置会继续保留。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var advancedControls: some View {
        if state.hasVolume {
            Divider()
            HStack(spacing: 14) {
                Label("音量", systemImage: "speaker.wave.2").font(BDMenuStyle.body)
                Slider(value: Binding(get: { dm.state(display.id).volume }, set: { dm.setVolume(display, $0) }), in: 0...100)
                    .controlSize(.large).accessibilityLabel("\(display.name)音量")
                Text("\(Int(state.volume.rounded()))%")
                    .font(.system(size: 14, design: .monospaced)).frame(width: 48, alignment: .trailing)
            }
        }
        if !state.modes.isEmpty {
            CapsuleMenu(title: "分辨率", value: state.modes.first(where: { $0.id == state.currentMode })?.label ?? "当前模式") {
                Picker("分辨率", selection: Binding(get: { dm.state(display.id).currentMode }, set: { number in
                    if let mode = dm.state(display.id).modes.first(where: { $0.id == number }) {
                        Task { await dm.setMode(display, mode) }
                    }
                })) {
                    if state.currentMode < 0 { Text("当前模式").tag(-1) }
                    ForEach(state.modes) { Text($0.label).tag($0.id) }
                }
            }
            .disabled(dm.isApplying || dm.mirrored)
        }
        if state.hasInput {
            CapsuleMenu(title: "输入源", value: dm.inputOptions.first(where: { $0.0 == state.input })?.1 ?? "当前 (\(state.input))") {
                Picker("输入源", selection: Binding(get: { dm.state(display.id).input }, set: { value in
                    Task { await dm.setInput(display, value) }
                })) {
                    if !dm.inputOptions.contains(where: { $0.0 == state.input }) { Text("当前 (\(state.input))").tag(state.input) }
                    ForEach(dm.inputOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            .disabled(dm.isApplying)
        }
        if display.id != dm.mainID && !dm.mirrored {
            HStack {
                Text("菜单栏与 Dock 的默认屏幕")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                Spacer()
                Button("设为主屏") { Task { await dm.setMain(display) } }
                    .disabled(dm.isApplying)
            }
        }
    }
}

@MainActor
extension DisplayManager {
    /// Keep the screen most likely to be adjusted at the top of both surfaces.
    var presentationDisplays: [DisplayInfo] {
        displays.sorted { a, b in
            if a.enabled != b.enabled { return a.enabled }
            if (a.id == mainID) != (b.id == mainID) { return a.id == mainID }
            if a.isBuiltin != b.isBuiltin { return a.isBuiltin }
            return a.id < b.id
        }
    }
}
