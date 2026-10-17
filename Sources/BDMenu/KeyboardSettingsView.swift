import SwiftUI

@MainActor
struct KeyboardSettingsView: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "亮度跟随哪块屏幕", subtitle: "切换工作位置时，不用重新绑定按键。", symbol: "scope")
                Toggle("启用亮度快捷键", isOn: Binding(get: { dm.keyboardEnabled }, set: { dm.setKeyboardEnabled($0) }))
                Divider()
                HStack(spacing: 12) {
                    ForEach(BrightnessTarget.allCases) { target in
                        Button { dm.setBrightnessTarget(target) } label: {
                            Label(target == .focusedWindow ? "活动窗口所在屏幕" : "鼠标所在屏幕",
                                  systemImage: target == .focusedWindow ? "macwindow" : "cursorarrow")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: dm.brightnessTarget == target))
                        .accessibilityAddTraits(dm.brightnessTarget == target ? .isSelected : [])
                    }
                }
                Text(dm.brightnessTarget == .focusedWindow
                     ? "窗口跨屏时，调节占用面积最大的一块；没有可读取的窗口时，回退到鼠标所在屏幕。"
                     : "把鼠标移到目标屏幕，再按亮度快捷键。无需点击窗口。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "你的两颗亮度键", subtitle: "默认 F4 降低、F5 提高。也可以录制其他按键或组合键。", symbol: "keyboard")
                bindingRow(.decrease, shortcut: dm.decreaseShortcut)
                bindingRow(.increase, shortcut: dm.increaseShortcut)
                if let action = dm.recordingAction {
                    HStack(spacing: 12) {
                        Image(systemName: "record.circle").foregroundStyle(.blue)
                        Text("按下用于“\(action.title)”的按键，Esc 取消。")
                            .font(BDMenuStyle.detail)
                        Spacer()
                        Button("取消录制") { dm.cancelRecording() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(14)
                    .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                if let message = dm.shortcutMessage {
                    Text(message).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap").foregroundStyle(.blue)
                    Text("按住连续调节 · 额外按 ⇧ 精细调节")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复 F4 / F5") { dm.resetShortcuts() }
                }
                Toggle("同时接管原生屏幕亮度键", isOn: Binding(get: { dm.nativeBrightnessKeys }, set: { dm.setNativeBrightnessKeys($0) }))
                DisclosureGroup("罗技 F4 / F5 没有响应？") {
                    Text("部分罗技键盘会把 F4/F5 作为媒体键或其他功能键。先点“录制”再按实体按键；如果无法录制，请在 Logi Options+ 中切换为标准 F 键，或试试 Fn＋F4/F5。原生亮度键选项也包含 F14/F15。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .font(BDMenuStyle.detail)
            }
        }
        PermissionCard()
    }

    private func bindingRow(_ action: BrightnessAction, shortcut: BrightnessShortcut) -> some View {
        HStack(spacing: 16) {
            Image(systemName: action == .decrease ? "sun.min" : "sun.max")
                .font(.system(size: 20)).foregroundStyle(.blue).frame(width: 30)
            Text(action.title).fontWeight(.medium)
            Spacer()
            Text(shortcut.label)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 72, minHeight: 48)
                .padding(.horizontal, 12)
                .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            Button(dm.recordingAction == action ? "等待按键…" : "录制") { dm.beginRecording(action) }
                .disabled(dm.recordingAction == action)
                .accessibilityLabel("录制\(action.title)快捷键")
        }
    }
}
