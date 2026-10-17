import AppKit
import SwiftUI

@MainActor
struct KeyboardSettingsView: View {
    @Environment(DisplayManager.self) private var dm

    private var windowHeight: CGFloat {
        min(780, max(500, (NSScreen.main?.visibleFrame.height ?? 900) - 110))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("亮度快捷键", systemImage: "keyboard")
                        .font(.system(size: 25, weight: .semibold))
                    Text("选择控制的屏幕，绑定你习惯的按键。")
                        .font(BDMenuStyle.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                BDMenuCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("启用亮度快捷键", isOn: Binding(
                            get: { dm.keyboardEnabled }, set: { dm.setKeyboardEnabled($0) }
                        ))
                        Divider()
                        Picker("控制目标", selection: Binding(
                            get: { dm.brightnessTarget }, set: { dm.setBrightnessTarget($0) }
                        )) {
                            ForEach(BrightnessTarget.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Text("跟随当前活动窗口；窗口跨屏时选择占用面积最大的屏幕。没有可读取的窗口时，使用鼠标所在屏幕。")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                BDMenuCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("按键绑定").font(BDMenuStyle.section)
                        bindingRow(.decrease, shortcut: dm.decreaseShortcut)
                        bindingRow(.increase, shortcut: dm.increaseShortcut)
                        if let action = dm.recordingAction {
                            HStack {
                                Text("请按下用于“\(action.title)”的按键，Esc 取消。")
                                    .font(BDMenuStyle.detail)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Button("取消") { dm.cancelRecording() }
                            }
                        }
                        if let message = dm.shortcutMessage {
                            Text(message).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("支持 F 键、媒体键和组合键。按住可连续调节，额外按 ⇧⌥ 可精细调节。绑定会自动保存。")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("同时接管原生亮度键（含 F14/F15）", isOn: Binding(
                            get: { dm.nativeBrightnessKeys }, set: { dm.setNativeBrightnessKeys($0) }
                        ))
                        Button("恢复 F4 / F5") { dm.resetShortcuts() }
                        Text("罗技键盘：如果 F4/F5 触发键盘自带功能，可在这里录制实际按键；若无法录制，请在 Logi Options+ 中设为标准 F 键，或尝试 Fn＋F4/F5。")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                BDMenuCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("按键权限").font(BDMenuStyle.section)
                        HStack(spacing: 10) {
                            Image(systemName: dm.keysInstalled ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(dm.keysInstalled ? .green : .orange)
                            Text(dm.keysInstalled ? "正在监听按键" : dm.keysTrusted ? "按键监听未启用" : "需要辅助功能权限")
                            Spacer()
                            Button("打开权限设置") { dm.requestKeyboardAccess() }
                        }
                        Text("在系统设置中允许 BDMenu 控制此电脑。授权后会自动启用监听；若状态未更新，请重新打开 BDMenu。")
                            .font(BDMenuStyle.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(BDMenuStyle.body)
            .toggleStyle(BDMenuSwitchStyle())
            .buttonStyle(BDMenuCapsuleButtonStyle())
            .controlSize(.large)
            .padding(24)
        }
        .frame(width: 600, height: windowHeight)
        .background {
            Rectangle().fill(.ultraThinMaterial)
            RadialGradient(colors: [.blue.opacity(0.07), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 500)
        }
        .onDisappear { dm.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            dm.cancelRecording()
        }
    }

    private func bindingRow(_ action: BrightnessAction, shortcut: BrightnessShortcut) -> some View {
        HStack(spacing: 12) {
            Text(action.title)
            Spacer()
            Text(shortcut.label)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
            Button(dm.recordingAction == action ? "等待按键…" : "录制") { dm.beginRecording(action) }
                .disabled(dm.recordingAction == action)
        }
    }
}
