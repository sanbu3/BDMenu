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
                DisclosureGroup("开合与重连配置") {
                    VStack(spacing: 12) {
                        Picker("仅外屏预设", selection: Binding(get: { dm.lidExternalConfiguration }, set: { dm.lidExternalConfiguration = $0; dm.persistLidConfigurations() })) {
                            Text("仅切换内建屏").tag("")
                            ForEach(dm.configurationPresets.filter { config in
                                config.layouts.first(where: { $0.uuid == dm.builtin?.uuid })?.enabled == false
                            }) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Picker("展开后预设", selection: Binding(get: { dm.lidOpenConfiguration }, set: { dm.lidOpenConfiguration = $0; dm.persistLidConfigurations() })) {
                            Text("仅切换内建屏").tag("")
                            ForEach(dm.configurationPresets.filter { config in
                                config.layouts.first(where: { $0.uuid == dm.builtin?.uuid })?.enabled == true
                            }) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Toggle("外屏重连时恢复最近显示配置", isOn: Binding(get: { dm.restoreOnReconnect }, set: { dm.restoreOnReconnect = $0; dm.persistLidConfigurations() }))
                            .help("只向同一显示器组合恢复已确认配置；窗口恢复共用自适应窗口管理器。")
                    }.padding(.top, 10)
                }
                HStack {
                    Text(dm.hardware.lidClosed.map { $0 ? "系统开合状态：合盖" : "系统开合状态：开盖" } ?? "系统开合状态不可用")
                        .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    Spacer()
                }
                if dm.hardware.lidAngle == nil {
                    Label(dm.hardware.lidClosed == nil ? "角度与开合状态均不可用，等待设备恢复" : "角度不可用，回退到系统开合状态", systemImage: "info.circle")
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
