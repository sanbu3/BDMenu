import SwiftUI
import DisplayCore

@MainActor
struct DisplayArrangementView: View {
    @Environment(DisplayManager.self) private var dm
    @State private var draft: [DisplayLayout] = []
    @State private var selected = ""
    @State private var main = ""
    @State private var dirty = false
    @State private var presetName = ""

    private func name(_ uuid: String) -> String { dm.displays.first { $0.uuid == uuid }?.name ?? "显示器" }
    private var active: [DisplayLayout] { draft.filter(\.enabled) }
    private var selectedIndex: Int? { draft.firstIndex { $0.uuid == selected && $0.enabled } }

    var body: some View {
        BDMenuCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "屏幕排列与预设", subtitle: "拖动屏幕调整相对位置，或使用常用排列。顶部白条表示主屏。", symbol: "rectangle.3.group")
                if dm.mirrored {
                    Text("镜像显示时共用画面，关闭镜像后可以分别排列。")
                        .foregroundStyle(.secondary)
                } else if !active.isEmpty {
                    DisplayArrangementCanvas(layouts: $draft, selected: $selected, main: main,
                                             names: Dictionary(uniqueKeysWithValues: dm.displays.map { ($0.uuid, $0.name) }),
                                             changed: { dirty = true })
                        .frame(height: 220)
                    HStack {
                        ForEach(DisplayArrangement.allCases) { arrangement in
                            Button(arrangement.title) {
                                draft = arrangement.arrange(draft, main: main); dirty = true
                            }
                        }
                    }
                    if let index = selectedIndex {
                        HStack {
                            Text(name(selected)).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text("X")
                            TextField("横坐标", value: coordinate(index, x: true), format: .number.grouping(.never))
                                .frame(width: 78).textFieldStyle(.roundedBorder)
                            Text("Y")
                            TextField("纵坐标", value: coordinate(index, x: false), format: .number.grouping(.never))
                                .frame(width: 78).textFieldStyle(.roundedBorder)
                            Button(main == selected ? "当前主屏" : "设为主屏") { main = selected; dirty = true }
                                .disabled(main == selected)
                        }
                        .font(BDMenuStyle.detail)
                    }
                    HStack {
                        Label("排列说明", systemImage: "info.circle")
                            .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                            .help("坐标以界面尺寸计；相邻边缘会自动吸附。排列先试用 15 秒。")
                        Spacer()
                        Button("还原编辑") { reload() }
                        Button("试用排列") { Task { await dm.applyArrangement(draft, main: main) } }
                            .buttonStyle(BDMenuCapsuleButtonStyle(prominent: true))
                    }
                }
                Divider()
                Toggle("启动时恢复这组显示器最近使用的配置", isOn: Binding(
                    get: { dm.restoreRecentOnLaunch }, set: { dm.setRestoreRecentOnLaunch($0) }))
                    .help("自动记住已确认的排列、主屏、启停、分辨率、刷新率和色彩描述文件；不同显示器组合分别记忆。未确认的试用不会作为最近配置。")
                HStack {
                    TextField("预设名称，例如：双屏写作", text: $presetName).textFieldStyle(.roundedBorder)
                    Button("保存当前配置") {
                        let name = presetName
                        Task { await dm.saveConfigurationPreset(name); presetName = "" }
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(dm.configurationPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name).fontWeight(.medium)
                            Text("\(preset.layouts.filter(\.enabled).count) 块启用 · \(dm.presetAvailable(preset) ? "可应用" : "请连接对应显示器")")
                                .font(BDMenuStyle.detail).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("试用预设") { Task { await dm.applyConfigurationPreset(preset) } }
                            .disabled(!dm.presetAvailable(preset))
                        Button("删除", role: .destructive) { dm.deleteConfigurationPreset(preset.id) }
                    }
                }
            }
            .disabled(dm.isApplying)
        }
        .onAppear { reload() }
        .onChange(of: dm.currentLayouts) { old, new in
            let previous = Set(old.filter(\.enabled).map(\.uuid))
            let current = Set(new.filter(\.enabled).map(\.uuid))
            if !dirty || previous != current { reload() }
        }

    }

    private func coordinate(_ index: Int, x: Bool) -> Binding<Int> {
        Binding(get: { x ? draft[index].x : draft[index].y }, set: { value in
            if x { draft[index].x = min(32000, max(-32000, value)) }
            else { draft[index].y = min(32000, max(-32000, value)) }
            dirty = true
        })
    }

    private func reload() {
        draft = dm.currentLayouts
        main = dm.displays.first { $0.id == dm.mainID }?.uuid ?? active.first?.uuid ?? ""
        if !active.contains(where: { $0.uuid == selected }) { selected = main }
        dirty = false
    }
}
