import AppKit
import SwiftUI

@MainActor
struct DockSettingsCard: View {
    @Environment(DisplayManager.self) private var dm
    private var bar: CompanionBarController { dm.appBar }

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "BDMenu 扩展应用栏", subtitle: "在屏幕内部显示，支持上大下小的双屏排列。", symbol: "dock.rectangle")
                Toggle("启用扩展应用栏", isOn: Binding(get: { bar.enabled }, set: { bar.setEnabled($0) }))
                Text("这是 BDMenu 提供的应用栏，显示固定应用和正在运行的应用，点击即可打开或切换。系统 Dock 保持原样；不会移动指针或改变屏幕排列。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(CompanionBarController.Mode.allCases) { mode in
                        Button(mode.title) { bar.setMode(mode) }
                            .buttonStyle(BDMenuCapsuleButtonStyle(prominent: bar.mode == mode))
                            .accessibilityAddTraits(bar.mode == mode ? .isSelected : [])
                    }
                    Spacer()
                }
                Text(bar.mode == .fixed
                     ? "应用栏始终留在所选屏幕底部，不需要先把系统 Dock 移过去。单屏时自动使用唯一在线屏幕。"
                     : "鼠标进入另一块屏幕后，应用栏会随之切换，无需触碰底边。拖动或操作应用栏时暂停跟随，避免打断点击。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "固定目标屏幕", subtitle: "屏幕底部与其他屏幕相连，也可以直接固定。", symbol: "display.2")
                ForEach(dm.presentationDisplays) { display in
                    Button { bar.setTarget(display.uuid) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            Text(display.name).lineLimit(1)
                            Spacer()
                            Text(display.enabled ? (display.id == dm.mainID ? "主屏" : "已启用") : "已停用")
                            if bar.fixedUUID == display.uuid { Image(systemName: "checkmark") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BDMenuCapsuleButtonStyle(prominent: bar.fixedUUID == display.uuid))
                    .disabled(!display.enabled)
                    .accessibilityAddTraits(bar.fixedUUID == display.uuid ? .isSelected : [])
                }
                if bar.mode == .mouse {
                    Text("当前跟随鼠标；这里的选择为下次切回固定模式保留。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
                HStack {
                    Button("显示应用栏") { bar.reveal() }.disabled(!bar.enabled)
                    Button("识别全部屏幕") { dm.identification.show(displays: dm.presentationDisplays) }
                    Spacer()
                }
                Text(bar.status).font(BDMenuStyle.body).fixedSize(horizontal: false, vertical: true)
                if let error = bar.lastError { ErrorNotice(message: error) }
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "显示与内容", subtitle: "这些设置只影响扩展应用栏。", symbol: "slider.horizontal.3")
                Toggle("自动隐藏扩展应用栏", isOn: Binding(get: { bar.autoHide }, set: { bar.setAutoHide($0) }))
                Text("开启后，将鼠标移到应用栏所在位置附近即可显示。触发区域位于当前屏幕内，不需要穿过上下屏幕的接缝。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("显示系统 Dock 中固定的应用", isOn: Binding(get: { bar.includePinned }, set: { bar.setIncludePinned($0) }))
                Text("同时显示正在运行的普通应用；不包含文件夹、废纸篓、窗口预览和系统 Dock 的完整拖放功能。应用较多时可横向滚动。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("原生 Dock 与上下布局") .font(BDMenuStyle.section)
                Text("上方外置屏底部连接着下方内建屏时，原生 Dock 的底边呼出可能无法在上方生效。旧版“固定”只有底边拦截，并不能搬移系统 Dock；本版已停用该拦截，改用可直接定位的扩展应用栏。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
