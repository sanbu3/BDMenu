import AppKit
import SwiftUI

@MainActor
struct ControlCenterView: View {
    @Environment(DisplayManager.self) private var dm
    @Environment(AppPresentation.self) private var presentation

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BDMenu").font(.system(size: 24, weight: .semibold))
                        Text("让每块屏幕，都刚刚好。")
                            .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { presentation.showQuickControls?() } label: {
                        Label("快捷面板", systemImage: "menubar.rectangle")
                    }
                    .buttonStyle(BDMenuCapsuleButtonStyle())
                }
                HStack(spacing: 6) {
                    ForEach(AppPresentation.Page.allCases) { page in
                        Button {
                            presentation.page = page
                        } label: {
                            Label(page.title, systemImage: page.symbol)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: presentation.page == page))
                        .accessibilityAddTraits(presentation.page == page ? .isSelected : [])
                        .help("⌘\(page.rawValue + 1)")
                    }
                }
                .padding(5)
                .background(Color.primary.opacity(0.035), in: Capsule())
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(presentation.page.title).font(BDMenuStyle.title)
                        Text(presentation.page.subtitle).font(BDMenuStyle.body).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)
                    if let error = dm.lastError { ErrorNotice(message: error) }
                    switch presentation.page {
                    case .displays: DisplaysPage()
                    case .keyboard: KeyboardSettingsView()
                    case .automation: AutomationPage()
                    case .application: ApplicationPage()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(presentation.page)
            Divider().opacity(0.6)
            HStack(spacing: 8) {
                Circle().fill(dm.displays.contains(where: \.enabled) ? .green : .orange).frame(width: 6, height: 6)
                Text("\(dm.displays.filter(\.enabled).count) 块屏幕在线")
                Text("·").foregroundStyle(.tertiary)
                Text("BDMenu \(dm.version)").foregroundStyle(.secondary)
                Spacer()
                if dm.isApplying { ProgressView().controlSize(.small); Text("正在应用…") }
                else { Text("设置自动保存").foregroundStyle(.secondary) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
        }
        .font(BDMenuStyle.body)
        .tint(BDMenuStyle.accent)
        .toggleStyle(BDMenuSwitchStyle())
        .buttonStyle(BDMenuCapsuleButtonStyle())
        .controlSize(.large)
        .frame(minWidth: 720, minHeight: 560)
        .background(BDMenuBackground())
        .onExitCommand { dm.cancelRecording() }
        .onChange(of: presentation.page) { _, _ in dm.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in dm.cancelRecording() }
    }
}

@MainActor
private struct DisplaysPage: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        HStack {
            StatusPill(title: "\(dm.displays.count) 块已连接", color: .secondary)
            if dm.mirrored { StatusPill(title: "镜像显示") }
            Spacer()
            Button { dm.scheduleRefresh(reprobe: true) } label: { Label("重新检测", systemImage: "arrow.clockwise") }
                .disabled(dm.isApplying)
        }
        if dm.displays.isEmpty {
            BDMenuCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "正在寻找显示器", subtitle: "连接完成后，屏幕会自动显示在这里。", symbol: "display")
                    ProgressView().controlSize(.small)
                }
            }
        }
        ForEach(dm.presentationDisplays) { DisplayCard(display: $0) }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "布局与恢复", subtitle: "切换镜像，或找回暂时关闭的屏幕。", symbol: "rectangle.2.swap")
                Toggle("镜像显示", isOn: Binding(get: { dm.mirrored }, set: { value in Task { await dm.setMirror(value) } }))
                    .disabled(dm.isApplying || dm.displays.filter(\.enabled).count < 2)
                Divider()
                HStack {
                    Button("恢复已记忆布局") { Task { await dm.restoreLayout() } }.disabled(dm.isApplying)
                    Spacer()
                    Button("全部点亮") { dm.wakeAll() }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: true))
                }
                Text("“全部点亮”会恢复可识别的屏幕与亮度，并暂停自动关闭内建屏的工作流。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct AutomationPage: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "外接屏工作流", subtitle: "接上外接屏，切换到桌面；拔下线，回到内建屏。", symbol: "cable.connector")
                Toggle(isOn: Binding(get: { dm.autoWorkflow }, set: { dm.setAutoWorkflow($0) })) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("连接外接屏时停用内建屏").fontWeight(.medium)
                        Text("断开外接屏或退出应用时，恢复由此工作流停用的内建屏。")
                            .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(isOn: Binding(get: { dm.syncKeyboardBacklight }, set: { dm.setSyncKeyboardBacklight($0) })) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("同步内置键盘背光").fontWeight(.medium)
                        Text(dm.keyboardBacklightAvailable ? "内建屏停用时关闭背光，恢复时还原先前亮度。" : "当前设备没有可控制的内置键盘背光。")
                            .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    }
                }
                .disabled(!dm.keyboardBacklightAvailable)
            }
        }
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "用外接键盘输入密码", subtitle: "内建屏关闭时，减少触摸指纹感应器的需要。", symbol: "key.horizontal")
                Toggle("优先切换到密码验证", isOn: Binding(get: { dm.preferPasswordWhenBuiltinOff }, set: { dm.setPreferPasswordWhenBuiltinOff($0) }))
                Text(dm.passwordPreference.status.text)
                    .font(BDMenuStyle.detail)
                    .foregroundStyle(dm.passwordPreference.status == .needsAccessibility || dm.passwordPreference.status == .unavailable ? .orange : .secondary)
                if dm.preferPasswordWhenBuiltinOff && dm.passwordPreference.status == .needsAccessibility {
                    Button("允许自动切换…") { dm.requestPermission() }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: true))
                }
                Divider()
                Text("适用于系统设置、安装软件等提供“使用密码”入口的系统授权弹窗。它只切换输入方式，不读取或提交密码；锁屏和第三方应用不保证适用。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct PermissionCard: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "辅助功能", subtitle: "让亮度按键和系统密码入口切换正常工作。", symbol: "hand.raised")
                HStack {
                    StatusPill(title: dm.keysTrusted ? "系统已允许" : "尚未允许", color: dm.keysTrusted ? .green : .orange)
                    if dm.keyboardEnabled && dm.keysInstalled { Text("亮度按键正在监听").font(BDMenuStyle.detail).foregroundStyle(.secondary) }
                    Spacer()
                    Button(dm.keysTrusted ? "管理权限…" : "打开权限设置…") { dm.requestPermission() }
                        .buttonStyle(BDMenuCapsuleButtonStyle(prominent: !dm.keysTrusted))
                }
                if dm.keyboardEnabled && dm.keysTrusted && !dm.keysInstalled {
                    HStack {
                        Text("按键监听尚未就绪，请重新检测；仍无效时退出并重新打开 BDMenu。")
                            .font(BDMenuStyle.detail).foregroundStyle(.orange)
                        Spacer()
                        Button("重新检测") { dm.refreshPermission() }
                    }
                }
                Text("在系统设置 → 隐私与安全性 → 辅助功能中允许 BDMenu。暂不授权也可以用面板上的滑块控制亮度。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
private struct ApplicationPage: View {
    @Environment(DisplayManager.self) private var dm
    @Environment(AppPresentation.self) private var presentation

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: "外观与启动", subtitle: "让 BDMenu 融入你的桌面。", symbol: "paintpalette")
                HStack {
                    Text("界面外观").fontWeight(.medium)
                    Spacer()
                    ForEach(AppPresentation.Appearance.allCases) { appearance in
                        Button(appearance.title) { presentation.appearance = appearance }
                            .buttonStyle(BDMenuCapsuleButtonStyle(prominent: presentation.appearance == appearance))
                            .accessibilityAddTraits(presentation.appearance == appearance ? .isSelected : [])
                    }
                }
                Divider()
                Toggle("登录时启动", isOn: Binding(get: { dm.launchAtLogin }, set: { dm.setLaunchAtLogin($0) }))
                if dm.loginStatus == .requiresApproval {
                    Text("请到系统设置 → 通用 → 登录项允许 BDMenu。")
                        .font(BDMenuStyle.detail).foregroundStyle(.orange)
                }
            }
        }
        PermissionCard()
        BDMenuCard {
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 10) {
                    Text("BDMenu \(dm.version)").font(.system(size: 20, weight: .semibold))
                    Text("常用显示器控制，触手可及。")
                        .font(BDMenuStyle.body).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        StatusPill(title: "本机控制", color: .secondary)
                        StatusPill(title: "无需账号", color: .secondary)
                    }
                }
                Spacer()
                Button("退出应用") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
