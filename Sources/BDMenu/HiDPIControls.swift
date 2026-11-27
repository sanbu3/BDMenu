import SwiftUI
import DisplayCore

@MainActor
struct HiDPIControls: View {
    @Environment(DisplayManager.self) private var dm
    let display: DisplayManager.DisplayInfo
    let current: DisplayMode
    let modes: [DisplayMode]

    private var target: DisplayMode? {
        DisplayModePolicy.scalingMode(!current.scaling, current: current, available: modes)
    }
    private var choices: [DisplayMode] {
        DisplayModePolicy.hiDPIModes(current: current, available: modes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("文字清晰度", systemImage: "textformat.size").font(.headline)
                    .help("HiDPI 让文字和图标边缘更细腻，可能增加图形负载。仅提供系统已开放的模式；试用 15 秒，未保留会自动恢复。")
                Spacer()
                StatusPill(title: current.scaling ? "HiDPI 已开启" : "普通模式")
            }
            if let target {
                Button("试用\(target.scaling ? " HiDPI" : "普通模式") · \(target.width) × \(target.height)") {
                    Task { await dm.setMode(display, target) }
                }
                .buttonStyle(BDMenuCapsuleButtonStyle())
                .accessibilityLabel("\(display.name)：试用\(target.label)")
                if target.width != current.width || target.height != current.height {
                    Text("当前尺寸没有同刷新率的 HiDPI；将试用 \(target.width) × \(target.height)，文字与界面会变大，保持 \(current.hertz ?? 0) Hz。")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                }
            } else {
                Text(current.scaling
                     ? "当前尺寸没有同刷新率的普通模式，可从下方显示模式选择其他尺寸。"
                     : "当前刷新率下没有合适的 HiDPI 模式，可从下方显示模式选择其他尺寸或刷新率。")
                    .font(BDMenuStyle.detail).foregroundStyle(.secondary)
            }
            if !choices.isEmpty {
                CapsuleMenu(title: "HiDPI 尺寸", value: current.scaling ? "\(current.width) × \(current.height)" : "选择试用尺寸") {
                    ForEach(choices) { mode in
                        Button(mode.label + (DisplayModePolicy.sameFormat(mode, current) ? " · 当前" : "")) {
                            Task { await dm.setMode(display, mode) }
                        }
                        .disabled(DisplayModePolicy.sameFormat(mode, current))
                    }
                }
            }
        }
        .disabled(dm.isApplying || dm.mirrored)
    }
}
