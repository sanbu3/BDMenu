import AppKit
import SwiftUI

@MainActor
struct DockSettingsCard: View {
    @Environment(DisplayManager.self) private var dm
    private var dock: DockController { dm.dock }

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Dock 显示方式", subtitle: "始终可选，单屏时保存偏好，多屏时应用。", symbol: "dock.rectangle")
                ForEach(DockController.Mode.allCases) { mode in
                    Button { dock.setMode(mode) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: dock.mode == mode ? "checkmark.circle.fill" : "circle")
                            Text(mode.title)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BDMenuCapsuleButtonStyle(prominent: dock.mode == mode))
                    .accessibilityAddTraits(dock.mode == mode ? .isSelected : [])
                    Text(mode == .mouse
                         ? "鼠标到哪块屏幕的底边并继续下移，就在那里呼出。仅把鼠标移到另一块屏幕，不会自动移动 Dock。"
                         : "先在指定屏幕底边呼出 Dock，再保护它不被其他屏幕的普通底边动作带走。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "指定屏幕", subtitle: "点选固定目标，或在该屏幕查看底边呼出引导。", symbol: "display.2")
                ForEach(dm.presentationDisplays) { display in
                    Button { dock.setFixedUUID(display.uuid) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            Text(display.name).lineLimit(1)
                            Spacer()
                            Text(display.enabled ? (display.id == dm.mainID ? "主屏" : "已启用") : "已停用")
                            if dock.fixedUUID == display.uuid { Image(systemName: "checkmark") }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BDMenuCapsuleButtonStyle(prominent: dock.fixedUUID == display.uuid))
                    .disabled(!display.enabled)
                    .accessibilityAddTraits(dock.fixedUUID == display.uuid ? .isSelected : [])
                }
                if let target = dock.target {
                    Text("已选：\(target.name)\(dock.mode == .mouse ? " · 当前为底边跟随，尚未启用固定保护。" : "")")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                } else if !dock.fixedUUID.isEmpty {
                    Text("之前指定的屏幕当前未启用。可选择其他在线屏幕，或启用原屏幕后继续使用。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
                HStack {
                    Button("所选屏幕呼出引导") {
                        guard let target = dock.target else { return }
                        dm.identification.show(displays: dm.presentationDisplays, guiding: target.id)
                    }
                    .disabled(!dock.canGuideTarget || dock.mirrored)
                    Button("识别全部屏幕") { dm.identification.show(displays: dm.presentationDisplays) }
                        .disabled(dock.screens.isEmpty)
                    Spacer()
                }
                Text("引导会标出目标位置，随后由你移到该屏幕底边呼出；不会跳动指针。已停用的屏幕不能显示 Dock，需先在“显示器”中启用。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "当前运行状态", subtitle: "\(dock.screens.count) 块屏幕已启用", symbol: "info.circle")
                if let name = dock.currentDisplayName { StatusPill(title: "检测到 Dock：\(name)", color: .secondary) }
                Text(dock.status).font(BDMenuStyle.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("重新检测") { dm.scheduleRefresh(); dock.refresh() }
                    Button("系统 Dock 设置…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                    }
                    if dock.mode == .fixed && !dm.keysTrusted { Button("打开权限设置…") { dm.requestPermission() } }
                    Spacer()
                }
                Text("固定保护适用于底部 Dock。拖动、边角、跨屏通道和系统唤醒仍可能改变 Dock 所在屏幕，可在目标底边再次呼出。不会改变主屏、排列或系统自动隐藏偏好。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
