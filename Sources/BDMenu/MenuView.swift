import SwiftUI

struct MenuView: View {
    @Environment(DisplayManager.self) private var dm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(dm.displays) { d in
                displaySection(d)
                if d.id != dm.displays.last?.id { Divider() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("自动工作流", isOn: Binding(
                    get: { dm.autoWorkflow },
                    set: { dm.setAutoWorkflow($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("接入外置屏:自动关内建屏、以外置为主屏;断开:自动恢复内建屏与亮度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("亮度键跟随鼠标", isOn: Binding(
                    get: { dm.followPointerEnabled },
                    set: { dm.setFollowPointer($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                if dm.followPointerEnabled && !dm.keysTrusted {
                    Text("需要辅助功能权限:系统设置 → 隐私与安全性 → 辅助功能,勾选 BDMenu 后生效")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 14) {
                    Toggle("镜像模式", isOn: Binding(
                        get: { dm.mirrored },
                        set: { dm.setMirror($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(dm.external == nil || !dm.externalOnline)

                    Toggle("登录时启动", isOn: Binding(
                        get: { dm.launchAtLogin },
                        set: { dm.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            HStack {
                if let err = dm.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button("全部点亮") { dm.wakeAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack {
                Text("BDMenu v1.1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
        .padding(12)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            dm.start()
            while !Task.isCancelled {
                dm.refresh()
                dm.installKeysIfNeeded()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private func displaySection(_ d: DisplayManager.DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: d.isBuiltin ? "laptopcomputer" : "display.2")
                    .foregroundStyle(.secondary)
                Text(d.name)
                    .font(.body)
                    .lineLimit(1)
                if d.id == dm.mainID {
                    Text("主屏")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Circle()
                    .fill(d.enabled ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Button(d.enabled ? "关闭" : "打开") { dm.toggleDisplay(d) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if !d.enabled {
                HStack(spacing: 6) {
                    Text("已断开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("设为主屏并打开") {
                        dm.setEnabled(d.id, true)
                        dm.setMain(d)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }

            if d.isBuiltin && d.enabled {
                brightnessRow(system: "sun.max", value: dm.builtinBrightness) { dm.setBuiltinBrightness($0) }
            }

            if !d.isBuiltin && d.enabled {
                brightnessRow(system: "sun.max", value: dm.externalBrightness, badge: dm.dimMode == "soft" ? "软件调光" : nil) { dm.setExternalBrightness($0) }

                if dm.hasVolume {
                    brightnessRow(system: "speaker.wave.2", value: dm.externalVolume) { dm.setExternalVolume($0) }
                }

                HStack(spacing: 10) {
                    Picker("输入源", selection: Binding(
                        get: { dm.externalInput },
                        set: { dm.setExternalInput($0) }
                    )) {
                        if dm.externalInput > 0 && !dm.inputOptions.contains(where: { $0.0 == dm.externalInput }) {
                            Text("自定义 (\(dm.externalInput))").tag(dm.externalInput)
                        }
                        ForEach(dm.inputOptions, id: \.0) { opt in
                            Text(opt.1).tag(opt.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)

                    if !dm.externalModes.isEmpty {
                        Picker("分辨率", selection: Binding(
                            get: { dm.currentMode },
                            set: { n in
                                if let m = dm.externalModes.first(where: { $0.num == n }) {
                                    dm.setExternalMode(m)
                                }
                            }
                        )) {
                            ForEach(dm.externalModes, id: \.num) { m in
                                Text(m.label).tag(m.num)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func brightnessRow(system: String, value: Double, badge: String? = nil, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: Binding(get: { value }, set: set), in: 0...100)
            Text("\(Int(value))%")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
