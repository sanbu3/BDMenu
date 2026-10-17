import AppKit
import SwiftUI

private struct QuickContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor
struct MenuView: View {
    @Environment(DisplayManager.self) private var dm
    @Environment(AppPresentation.self) private var presentation
    @State private var contentHeight: CGFloat = 240

    private var maximumContentHeight: CGFloat {
        max(180, min(560, (NSScreen.main?.visibleFrame.height ?? 800) - 200))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "display.2").font(.system(size: 23)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("显示器").font(.system(size: 20, weight: .semibold))
                    Text("\(dm.displays.filter(\.enabled).count) 块屏幕在线")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
                Spacer()
                Button { presentation.show(.displays) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(BDMenuCapsuleButtonStyle(compact: true))
                    .accessibilityLabel("打开控制中心")
                    .help("控制中心")
            }
            ScrollView {
                VStack(spacing: 12) {
                    if dm.displays.isEmpty {
                        ProgressView("正在检测显示器…").frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ForEach(dm.presentationDisplays) { DisplayCard(display: $0, compact: true) }
                    if let error = dm.lastError { ErrorNotice(message: error) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: QuickContentHeight.self, value: proxy.size.height)
                })
            }
            .frame(height: min(contentHeight, maximumContentHeight))
            .scrollIndicators(contentHeight > maximumContentHeight ? .visible : .hidden)
            .onPreferenceChange(QuickContentHeight.self) { value in
                if value > 0, abs(contentHeight - value) > 1 { contentHeight = ceil(value) }
            }
            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(dm.decreaseShortcut.label) 降低 · \(dm.increaseShortcut.label) 提高")
                        .font(.system(size: 13, weight: .medium))
                    Text(dm.keyboardEnabled ? dm.brightnessTarget.title : "快捷键已暂停")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("设置") { presentation.show(.keyboard) }
                    .buttonStyle(BDMenuCapsuleButtonStyle(compact: true))
            }
            .padding(.horizontal, 4)
            Divider()
            HStack(spacing: 10) {
                Button("全部点亮") { dm.wakeAll() }
                    .help("恢复屏幕与亮度，同时暂停自动工作流")
                Button("Dock 设置") { presentation.show(.dock) }
                Spacer()
                Button("控制中心") { presentation.show() }
                    .buttonStyle(BDMenuCapsuleButtonStyle(prominent: true))
            }
            .buttonStyle(BDMenuCapsuleButtonStyle())
        }
        .font(BDMenuStyle.body)
        .tint(BDMenuStyle.accent)
        .padding(18)
        .frame(width: 440)
        .background(BDMenuBackground())
    }
}
