import SwiftUI
import DisplayCore

@MainActor
struct DisplayModeControls: View {
    @Environment(DisplayManager.self) private var dm
    let display: DisplayManager.DisplayInfo
    let current: DisplayMode
    let modes: [DisplayMode]

    private var refreshRates: [Int] {
        Set(modes.filter { $0.width == current.width && $0.height == current.height && $0.scaling == current.scaling }
            .compactMap(\.hertz)).sorted(by: >)
    }
    private var resolutions: [DisplayMode] {
        var seen = Set<String>()
        return modes.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.scaling != $1.scaling { return $0.scaling }
            if ($0.hertz == current.hertz) != ($1.hertz == current.hertz) { return $0.hertz == current.hertz }
            if $0.hertz != $1.hertz { return ($0.hertz ?? 0) > ($1.hertz ?? 0) }
            return $0.id < $1.id
        }.filter { seen.insert("\($0.width)x\($0.height)-\($0.scaling)").inserted }
    }

    var body: some View {
        CapsuleMenu(title: "分辨率", value: "\(current.width) × \(current.height)\(current.scaling ? " · HiDPI" : "")") {
            ForEach(resolutions) { mode in
                Button(mode.label) { Task { await dm.setMode(display, mode) } }
                    .disabled(DisplayModePolicy.sameFormat(mode, current))
            }
        }
        .disabled(dm.isApplying || dm.mirrored)
        CapsuleMenu(title: "刷新率", value: current.hertz.map { "\($0) Hz" } ?? "系统自动") {
            ForEach(refreshRates, id: \.self) { rate in
                Button("\(rate) Hz") { Task { await dm.setRefreshRate(display, hertz: rate) } }
                    .disabled(rate == current.hertz)
            }
        }
        .disabled(dm.isApplying || dm.mirrored || refreshRates.isEmpty)
    }
}
