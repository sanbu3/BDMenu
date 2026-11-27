import SwiftUI

@MainActor
struct LidAutomationView: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeading(title: "按开合角度切换", subtitle: "小角度用于人字形摆放，展开后恢复扩展屏。", symbol: "laptopcomputer")
                    Spacer()
                    Text(dm.hardware.angleLabel)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("当前开合角度 \(dm.hardware.angleLabel)")
                }
                Toggle("自动切换内建屏", isOn: Binding(get: { dm.lidAutomation }, set: { dm.setLidAutomation($0) }))
                    .help("仅在外接屏已启用时切换。连续稳定 0.8 秒后生效，切换至少间隔 3 秒；退出、拔线或关闭此选项会恢复内建屏。")
                Divider()
                thresholdRow(title: "仅用外屏", symbol: "display", value: dm.lidCloseAngle,
                             range: 10...(dm.lidOpenAngle - 5), below: true) { dm.setLidThreshold(close: $0) }
                thresholdRow(title: "恢复扩展屏", symbol: "display.2", value: dm.lidOpenAngle,
                             range: (dm.lidCloseAngle + 5)...150, below: false) { dm.setLidThreshold(open: $0) }
                HStack {
                    Label(dm.lidAutomation ? (dm.externalOnline ? "角度自动切换已开启" : "等待外接屏") : "角度自动切换已关闭", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("中间区间保持当前模式")
                        .foregroundStyle(.secondary)
                        .help("两个阈值之间不触发切换，避免开合角度轻微变化时反复开关屏幕。")
                }
                .font(BDMenuStyle.detail)
                if dm.hardware.lidAngle == nil {
                    Label("当前无法读取角度，自动切换暂不执行", systemImage: "exclamationmark.triangle")
                        .font(BDMenuStyle.detail).foregroundStyle(.orange)
                }
            }
        }
    }

    private func thresholdRow(title: String, symbol: String, value: Double,
                              range: ClosedRange<Double>, below: Bool,
                              change: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack(spacing: 16) {
            Label(title, systemImage: symbol).frame(width: 140, alignment: .leading)
            Slider(value: Binding(get: { value }, set: change), in: range, step: 1)
                .accessibilityLabel(title + "角度阈值")
            Text("\(below ? "≤" : "≥") \(Int(value))°")
                .monospacedDigit().frame(width: 74, alignment: .trailing)
        }
    }
}
