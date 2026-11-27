import SwiftUI

@MainActor
struct ModeTrialNotice: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        if let label = dm.modeTrialLabel {
            BDMenuCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("保留这组显示配置？", systemImage: "timer")
                        .font(.headline)
                    Text(label).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    Text("未确认将在 \(dm.modeTrialSeconds) 秒后恢复。现在可拖动窗口或播放视频作对照。")
                        .font(BDMenuStyle.detail)
                    HStack {
                        Button("恢复原配置") { Task { await dm.restoreModeTrial() } }
                        Spacer()
                        Button("保留此配置") { dm.keepModeTrial() }
                            .buttonStyle(BDMenuCapsuleButtonStyle(prominent: true))
                            .disabled(dm.modeTrialSeconds <= 0)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
