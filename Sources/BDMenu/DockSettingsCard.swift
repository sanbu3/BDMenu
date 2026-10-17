import AppKit
import SwiftUI

@MainActor
struct DockSettingsCard: View {
    @Environment(DisplayManager.self) private var dm
    private var dock: DockController { dm.dock }
    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "程序坞 · Dock", subtitle: "多屏同时启用时，选择 Dock 在哪里出现。", symbol: "dock.rectangle")
                HStack(spacing: 8) {
                    ForEach(DockController.Mode.allCases) { mode in
                        Button(mode.title) {
                            if mode == .fixed, dock.fixedUUID.isEmpty,
                               let screen = dock.screens.first(where: { $0.id == dm.mainID }) ?? dock.screens.first {
                                dock.setFixedUUID(screen.uuid)
                            }
                            dock.setMode(mode)
                        }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: dock.mode == mode))
                        .accessibilityAddTraits(dock.mode == mode ? .isSelected : [])
                    }
                    Spacer()
                }
                .disabled(!dock.multipleDisplays)
                if dock.mode == .fixed {
                    CapsuleMenu(title: "指定屏幕", value: dock.target?.name ?? "选择一块在线屏幕") {
                        ForEach(dock.screens, id: \.uuid) { screen in
                            Button { dock.setFixedUUID(screen.uuid) } label: {
                                Label(screen.name, systemImage: dock.fixedUUID == screen.uuid ? "checkmark" : "display")
                            }
                        }
                    }
                    .disabled(!dock.multipleDisplays)
                    HStack {
                        Button("定位并引导呼出") {
                            guard let target = dock.target else { return }
                            dm.identification.show(displays: dm.presentationDisplays, guiding: target.id)
                        }
                        .disabled(!dock.multipleDisplays || !dock.canGuideTarget)
                        if !dm.keysTrusted {
                            Button("打开权限设置…") { dm.requestPermission() }
                        }
                        Spacer()
                    }
                }
                Text(dock.status).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let name = dock.currentDisplayName {
                    StatusPill(title: "当前 Dock：\(name)", color: .secondary)
                }
                Text(dock.mode == .fixed
                     ? "固定保护适用于底部 Dock，并保留边角、拖动和跨屏通道。若系统将 Dock 换走，可在指定屏幕底边再次呼出。"
                     : "沿用 macOS 的边缘呼出方式，不跳动指针，也不改变主屏、菜单栏或显示器排列。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
