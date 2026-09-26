import Foundation
import CoreGraphics
import Observation
import ServiceManagement

@Observable
final class DisplayManager {

    struct DisplayInfo: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let uuid: String
        let name: String
        let isBuiltin: Bool
        var enabled: Bool
    }

    struct LayoutRecord {
        var uuid = ""
        var w = 0
        var h = 0
        var hz = 0
        var depth = 8
        var scaling = "on"
        var x = 0
        var y = 0
        var isMain: Bool { x == 0 && y == 0 }
    }

    struct ModeInfo {
        var num = 0
        var w = 0
        var h = 0
        var hz = 0
        var depth = 8
        var scaling = "on"
        var label: String { "\(w)x\(h) @ \(hz)Hz" + (scaling == "on" ? " (HiDPI)" : "") }
    }

    var displays: [DisplayInfo] = []
    var builtinBrightness: Double = 50
    var externalBrightness: Double = 50
    var externalVolume: Double = 50
    var hasVolume = false
    var externalInput = 0
    var externalModes: [ModeInfo] = []
    var currentMode = -1
    var mirrored = false
    var mainID: CGDirectDisplayID = 0
    var lastError: String?
    var autoWorkflow: Bool
    var dimMode = "ddc"

    private var wasExternalOnline = false
    private var wasExternalPresent = false
    private var started = false
    private var pendingWork: DispatchWorkItem?
    private var lastAutoCapture = Date.distantPast
    private var workflowPreBrightness: Double?

    let inputOptions: [(Int, String)] = [(15, "DP 1"), (16, "DP 2"), (17, "HDMI 1"), (18, "HDMI 2"), (27, "USB-C")]

    init() {
        autoWorkflow = UserDefaults.standard.bool(forKey: "autoWorkflow")
    }

    var builtin: DisplayInfo? { displays.first { $0.isBuiltin } }
    var external: DisplayInfo? { displays.first { !$0.isBuiltin } }
    var builtinID: CGDirectDisplayID? { builtin?.id }
    var externalUUID: String? { external?.uuid }
    var externalOnline: Bool { external?.enabled ?? false }
    var externalPresent: Bool { external != nil }
    var builtinOnline: Bool { builtin?.enabled ?? false }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func start() {
        guard !started else { return }
        started = true
        CGDisplayRegisterReconfigurationCallback({ _, _, ctx in
            guard let ctx else { return }
            let mgr = Unmanaged<DisplayManager>.fromOpaque(ctx).takeUnretainedValue()
            mgr.scheduleHandleChange()
        }, Unmanaged.passUnretained(self).toOpaque())
        scheduleHandleChange()
    }

    func scheduleHandleChange() {
        pendingWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.handleDisplayChange() }
        pendingWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    func handleDisplayChange() {
        refresh()
        if externalPresent, !externalOnline, !wasExternalPresent {
            if let e = external {
                _ = PrivateAPI.setDisplayEnabled(id: e.id, enabled: true)
            }
            scheduleHandleChange()
            return
        }
        if !externalPresent {
            if let b = builtin, !b.enabled {
                _ = PrivateAPI.setDisplayEnabled(id: b.id, enabled: true)
                if let v = workflowPreBrightness {
                    setBuiltinBrightness(v)
                    workflowPreBrightness = nil
                }
            } else if builtin == nil {
                for id: CGDirectDisplayID in [1, 2, 3, 4] {
                    _ = PrivateAPI.setDisplayEnabled(id: id, enabled: true)
                }
            }
            scheduleHandleChange()
            return
        }
        if externalOnline, !wasExternalOnline {
            probeExternal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.captureAutoLayout()
            }
            if autoWorkflow {
                restoreLayout(applyBrightness: false)
                if let b = builtin, b.enabled {
                    workflowPreBrightness = builtinBrightness
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.applyWorkflowIfRelevant()
                    }
                }
            }
        }
        if externalOnline {
            refreshExternalModes()
        } else {
            externalModes = []
            currentMode = -1
            hasVolume = false
        }
        wasExternalOnline = externalOnline
        wasExternalPresent = externalPresent
    }

    func applyWorkflowIfRelevant() {
        guard autoWorkflow, externalOnline, let b = builtin, b.enabled else { return }
        _ = PrivateAPI.setDisplayEnabled(id: b.id, enabled: false)
        scheduleHandleChange()
    }

    func setAutoWorkflow(_ on: Bool) {
        autoWorkflow = on
        UserDefaults.standard.set(on, forKey: "autoWorkflow")
        if on {
            if externalPresent, !externalOnline, let e = external {
                _ = PrivateAPI.setDisplayEnabled(id: e.id, enabled: true)
            } else if externalOnline {
                restoreLayout(applyBrightness: false)
                if let b = builtin, b.enabled {
                    workflowPreBrightness = builtinBrightness
                    _ = PrivateAPI.setDisplayEnabled(id: b.id, enabled: false)
                }
            }
            scheduleHandleChange()
        } else {
            if let b = builtin, !b.enabled {
                _ = PrivateAPI.setDisplayEnabled(id: b.id, enabled: true)
                if let v = workflowPreBrightness {
                    setBuiltinBrightness(v)
                    workflowPreBrightness = nil
                }
            }
            scheduleHandleChange()
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "登录启动设置失败,请在 系统设置→登录项 手动添加"
        }
    }

    func refresh() {
        var online = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &online, &count)
        let onlineSet = Set(online.prefix(Int(count)))
        let allIDs = PrivateAPI.allDisplayIDs()

        var result: [DisplayInfo] = []
        for id in onlineSet.sorted() {
            let info = PrivateAPI.displayInfo(id) ?? [:]
            let uuid = info["kCGDisplayUUID"] as? String ?? ""
            let names = info["DisplayProductName"] as? [String: String]
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let isVirtual = (info["kCGDisplayIsVirtualDevice"] as? Bool ?? false)
                || (info["kCGDisplayIsAirPlay"] as? Bool ?? false)
            if isVirtual && !isBuiltin { continue }
            let name = names?["en_US"] ?? names?.values.first ?? (isBuiltin ? "内建显示器" : "外置显示器")
            result.append(DisplayInfo(id: id, uuid: uuid, name: name, isBuiltin: isBuiltin, enabled: true))
        }
        for id in allIDs where !onlineSet.contains(id) {
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            result.append(DisplayInfo(id: id, uuid: "", name: isBuiltin ? "内建显示器" : "外置显示器", isBuiltin: isBuiltin, enabled: false))
        }
        displays = result
        mainID = CGMainDisplayID()

        if let b = builtinID, let v = PrivateAPI.getBrightness(b) {
            builtinBrightness = v * 100
        }
        if externalOnline, dimMode == "ddc", let u = externalUUID,
           let s = Subprocess.m1ddc(["display", u, "get", "luminance"]),
           let v = Double(s) {
            externalBrightness = v
        }

        if externalOnline, Date().timeIntervalSince(lastAutoCapture) > 8 {
            captureAutoLayout()
        }
    }

    func captureAutoLayout() {
        guard externalOnline else { return }
        lastAutoCapture = Date()
        let recs = layoutRecords()
        guard !recs.isEmpty else { return }
        UserDefaults.standard.set(emitConfig(recs), forKey: "savedLayout")
        UserDefaults.standard.set(builtinBrightness, forKey: "savedBrightness")
    }

    func probeExternal() {
        guard let u = externalUUID else { return }
        if let s = Subprocess.m1ddc(["display", u, "get", "luminance"]), let v = Double(s) {
            dimMode = "ddc"
            externalBrightness = v
        } else {
            dimMode = "soft"
            if let id = external?.id {
                applySoftwareDim(id, externalBrightness)
            }
        }
        if let s = Subprocess.m1ddc(["display", u, "get", "volume"]), let v = Double(s) {
            hasVolume = true
            externalVolume = v
        } else {
            hasVolume = false
        }
        if let s = Subprocess.m1ddc(["display", u, "get", "input"]), let v = Int(s), v > 0 {
            externalInput = v
        }
    }

    func refreshExternalModes() {
        guard let u = externalUUID else { return }
        let out = Subprocess.displayplacer(["list"]) ?? ""
        var inBlock = false
        var modes: [ModeInfo] = []
        var current = -1
        for raw in out.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Persistent screen id:") {
                inBlock = line.contains(u)
                continue
            }
            guard inBlock else { continue }
            if line.hasPrefix("Execute") { break }
            guard line.hasPrefix("mode ") else { continue }
            var m = ModeInfo()
            for p in line.components(separatedBy: " ") {
                if p.hasPrefix("mode") && p.contains(":") {
                    m.num = Int(p.split(separator: ":").last ?? "0") ?? 0
                } else if p.hasPrefix("res:") {
                    let wh = p.dropFirst(4).split(separator: "x")
                    if wh.count == 2 {
                        m.w = Int(wh[0]) ?? 0
                        m.h = Int(wh[1]) ?? 0
                    }
                } else if p.hasPrefix("hz:") {
                    m.hz = Int(p.dropFirst(3)) ?? 0
                } else if p.hasPrefix("color_depth:") {
                    m.depth = Int(p.dropFirst(12)) ?? 8
                } else if p.hasPrefix("scaling:") {
                    m.scaling = String(p.dropFirst(8))
                }
            }
            modes.append(m)
            if line.contains("<-- current mode") { current = m.num }
        }
        externalModes = modes
        currentMode = current
    }

    func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        let ok = PrivateAPI.setDisplayEnabled(id: id, enabled: enabled)
        scheduleHandleChange()
        return ok
    }

    func toggleDisplay(_ d: DisplayInfo) {
        if d.enabled {
            let othersActive = displays.contains { $0.enabled && $0.id != d.id }
            guard othersActive else {
                lastError = "至少需要保留一个显示器"
                return
            }
            _ = setEnabled(d.id, false)
        } else {
            _ = setEnabled(d.id, true)
        }
    }

    func wakeAll() {
        for d in displays where !d.enabled {
            _ = setEnabled(d.id, true)
        }
        if !builtinOnline {
            for id: CGDirectDisplayID in [1, 2, 3, 4] {
                _ = PrivateAPI.setDisplayEnabled(id: id, enabled: true)
            }
        }
        scheduleHandleChange()
    }

    func setBuiltinBrightness(_ v: Double) {
        guard let b = builtinID else { return }
        if PrivateAPI.setBrightness(b, v / 100) {
            builtinBrightness = v
        }
    }

    func setExternalBrightness(_ v: Double) {
        externalBrightness = v
        if dimMode == "soft" {
            if let id = external?.id { applySoftwareDim(id, v) }
            return
        }
        guard let u = externalUUID else { return }
        let out = Subprocess.m1ddc(["display", u, "set", "luminance", "\(Int(v))"])
        if out == nil || (out ?? "").contains("DDC communication failure") {
            dimMode = "soft"
            if let id = external?.id { applySoftwareDim(id, v) }
        }
    }

    func applySoftwareDim(_ id: CGDirectDisplayID, _ v: Double) {
        let g = Float(max(0.01, min(1, v / 100)))
        _ = CGSetDisplayTransferByFormula(id, 0, g, 1, 0, g, 1, 0, g, 1)
    }

    func setExternalVolume(_ v: Double) {
        guard let u = externalUUID else { return }
        _ = Subprocess.m1ddc(["display", u, "set", "volume", "\(Int(v))"])
        externalVolume = v
    }

    func setExternalInput(_ n: Int) {
        guard let u = externalUUID else { return }
        _ = Subprocess.m1ddc(["display", u, "set", "input", "\(n)"])
        externalInput = n
        scheduleHandleChange()
    }

    func layoutRecords() -> [LayoutRecord] {
        let out = Subprocess.displayplacer(["list"]) ?? ""
        var recs: [LayoutRecord] = []
        var cur: LayoutRecord?
        for raw in out.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Persistent screen id:") {
                if let c = cur { recs.append(c) }
                cur = LayoutRecord()
                cur?.uuid = String(line.split(separator: " ").last ?? "")
            } else if var c = cur {
                if line.hasPrefix("Resolution:") {
                    let wh = line.components(separatedBy: " ")[1].split(separator: "x")
                    if wh.count == 2 {
                        c.w = Int(wh[0]) ?? 0
                        c.h = Int(wh[1]) ?? 0
                    }
                } else if line.hasPrefix("Hertz:") {
                    c.hz = Int(line.components(separatedBy: " ")[1]) ?? 0
                } else if line.hasPrefix("Color Depth:") {
                    c.depth = Int(line.components(separatedBy: " ")[2]) ?? 8
                } else if line.hasPrefix("Scaling:") {
                    c.scaling = line.components(separatedBy: " ")[1]
                } else if line.hasPrefix("Origin:") {
                    let o = line.components(separatedBy: " ")[1]
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .split(separator: ",")
                    if o.count == 2 {
                        c.x = Int(o[0]) ?? 0
                        c.y = Int(o[1]) ?? 0
                    }
                } else if line.hasPrefix("Enabled:") {
                    recs.append(c)
                    cur = nil
                }
                if cur != nil { cur = c }
            }
        }
        return recs
    }

    func emitConfig(_ recs: [LayoutRecord]) -> String {
        recs.map {
            "\"id:\($0.uuid) res:\($0.w)x\($0.h) hz:\($0.hz) color_depth:\($0.depth) enabled:true scaling:\($0.scaling) origin:(\($0.x),\($0.y)) degree:0\""
        }.joined(separator: " ")
    }

    @discardableResult
    func applyRecords(_ recs: [LayoutRecord]) -> Bool {
        guard !recs.isEmpty else { return false }
        return Subprocess.displayplacer(Subprocess.tokenize(emitConfig(recs))) != nil
    }

    func restoreLayout(applyBrightness: Bool = true) {
        guard let cfg = UserDefaults.standard.string(forKey: "savedLayout") else {
            lastError = "还没有保存过布局"
            return
        }
        _ = Subprocess.displayplacer(Subprocess.tokenize(cfg))
        if applyBrightness, let v = UserDefaults.standard.object(forKey: "savedBrightness") as? Double {
            setBuiltinBrightness(v)
        }
    }

    func setMirror(_ on: Bool) {
        if on {
            let recs = layoutRecords()
            guard let main = recs.first(where: { $0.isMain }) ?? recs.first else { return }
            UserDefaults.standard.set(emitConfig(recs), forKey: "preMirrorConfig")
            let ids = recs.map(\.uuid).joined(separator: "+")
            let cfg = "id:\(ids) res:\(main.w)x\(main.h) hz:\(main.hz) color_depth:\(main.depth) enabled:true scaling:\(main.scaling) origin:(0,0) degree:0"
            _ = Subprocess.displayplacer(Subprocess.tokenize(cfg))
            mirrored = true
        } else {
            if let cfg = UserDefaults.standard.string(forKey: "preMirrorConfig") {
                _ = Subprocess.displayplacer(Subprocess.tokenize(cfg))
            }
            mirrored = false
        }
        scheduleHandleChange()
    }

    func setMain(_ target: DisplayInfo) {
        var recs = layoutRecords()
        guard let i = recs.firstIndex(where: { $0.uuid == target.uuid }) else { return }
        let oldMain = recs.firstIndex(where: { $0.isMain })
        let t = recs[i]
        recs[i].x = 0
        recs[i].y = 0
        if let o = oldMain, o != i {
            recs[o].x = t.w
            recs[o].y = 0
        }
        _ = applyRecords(recs)
        scheduleHandleChange()
    }

    func setExternalMode(_ m: ModeInfo) {
        guard let u = externalUUID else { return }
        var recs = layoutRecords()
        guard let i = recs.firstIndex(where: { $0.uuid == u }) else { return }
        recs[i].w = m.w
        recs[i].h = m.h
        recs[i].hz = m.hz
        recs[i].depth = m.depth
        recs[i].scaling = m.scaling
        _ = applyRecords(recs)
        currentMode = m.num
        scheduleHandleChange()
    }
}
