import AppKit
import ApplicationServices
import Observation

struct DockScreen: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
}

enum DockRoutingPolicy {
    static func target(uuid: String, screens: [DockScreen]) -> DockScreen? {
        guard screens.count > 1 else { return nil }
        let matches = screens.filter { $0.uuid == uuid }
        return matches.count == 1 ? matches[0] : nil
    }

    static func hasExposedBottom(_ screen: DockScreen, screens: [DockScreen]) -> Bool {
        guard screen.bounds.width > 24, screen.bounds.height > 0 else { return false }
        var intervals: [ClosedRange<CGFloat>] = [(screen.bounds.minX + 12)...(screen.bounds.maxX - 12)]
        for other in screens where other.id != screen.id && other.bounds.minY <= screen.bounds.maxY + 1 && other.bounds.maxY > screen.bounds.maxY + 1 {
            intervals = intervals.flatMap { interval -> [ClosedRange<CGFloat>] in
                let lower = max(interval.lowerBound, other.bounds.minX)
                let upper = min(interval.upperBound, other.bounds.maxX)
                guard lower < upper else { return [interval] }
                var remainder: [ClosedRange<CGFloat>] = []
                if interval.lowerBound < lower { remainder.append(interval.lowerBound...lower) }
                if upper < interval.upperBound { remainder.append(upper...interval.upperBound) }
                return remainder
            }
        }
        return intervals.contains { $0.upperBound - $0.lowerBound >= 8 }
    }

    /// CG coordinates: y grows downwards. Leave corners and routes to lower
    /// displays intact; never trap a pointer travelling between displays.
    static func guardedPoint(_ point: CGPoint, target: CGDirectDisplayID, screens: [DockScreen]) -> CGPoint {
        guard screens.count > 1, screens.contains(where: { $0.id == target }),
              let screen = screens.first(where: { $0.bounds.contains(point) }), screen.id != target else { return point }
        let b = screen.bounds
        guard point.y >= b.maxY - 6, point.x > b.minX + 12, point.x < b.maxX - 12 else { return point }
        let beyond = CGPoint(x: point.x, y: b.maxY + 1)
        guard !screens.contains(where: { $0.id != screen.id && $0.bounds.contains(beyond) }) else { return point }
        return CGPoint(x: point.x, y: b.maxY - 7)
    }
}

@MainActor @Observable
final class DockController {
    enum Mode: String, CaseIterable, Identifiable {
        case mouse, fixed
        var id: String { rawValue }
        var title: String { self == .mouse ? "跟随鼠标" : "固定屏幕" }
    }
    private(set) var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "dockRoutingMode") ?? "") ?? .mouse
    private(set) var fixedUUID = UserDefaults.standard.string(forKey: "dockFixedUUID") ?? ""
    private(set) var screens: [DockScreen] = []
    private(set) var mirrored = false
    private(set) var status = "同时启用两块屏幕后，可管理 Dock 的归属。"
    private(set) var currentDisplayName: String?
    private(set) var installed = false
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var task: Task<Void, Never>?

    var target: DockScreen? { DockRoutingPolicy.target(uuid: fixedUUID, screens: screens) }
    var canGuideTarget: Bool { target.map { DockRoutingPolicy.hasExposedBottom($0, screens: screens) } ?? false }
    var multipleDisplays: Bool { screens.count > 1 && !mirrored }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    func update(displays: [DisplayManager.DisplayInfo], mirrored: Bool) {
        self.mirrored = mirrored
        screens = displays.filter(\.enabled).compactMap { display in
            let bounds = CGDisplayBounds(display.id)
            guard !bounds.isEmpty else { return nil }
            return DockScreen(id: display.id, uuid: display.uuid, name: display.name, bounds: bounds)
        }
        refresh()
    }
    func setMode(_ mode: Mode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "dockRoutingMode")
        refresh()
    }
    func setFixedUUID(_ uuid: String) {
        fixedUUID = uuid
        UserDefaults.standard.set(uuid, forKey: "dockFixedUUID")
        refresh()
    }
    func refresh() {
        currentDisplayName = observedDockScreen()?.name
        guard multipleDisplays else { uninstall(); status = mirrored ? "镜像模式下只有一个桌面，已暂停 Dock 固定。" : "同时启用两块屏幕后，可管理 Dock 的归属。"; return }
        guard mode == .fixed else { uninstall(); status = "移到目标屏幕底边并继续下移，即可在那里呼出 Dock。指针不会被移动。"; return }
        guard let target else { uninstall(); status = "指定屏幕未启用或尚未选择，固定保护已暂停。"; return }
        guard DockRoutingPolicy.hasExposedBottom(target, screens: screens) else {
            uninstall(); status = "指定屏幕的底边被另一块屏幕完全覆盖，macOS 无法在此呼出底部 Dock。请调整屏幕排列或选择另一块屏幕。"; return
        }
        let dockPreferences = UserDefaults(suiteName: "com.apple.dock")
        guard (dockPreferences?.string(forKey: "orientation") ?? "bottom") == "bottom" else {
            uninstall(); status = "固定保护适用于底部 Dock。请先在系统设置中将 Dock 放在底部。"; return
        }
        guard AXIsProcessTrusted() else { uninstall(); status = "需要辅助功能权限，才能防止 Dock 被其他屏幕底边误触带走。"; return }
        install()
        status = installed ? "固定保护已开启。请先在“\(target.name)”底边呼出 Dock；其他屏幕的普通底边移动不会带走它。" : "Dock 固定监听未就绪，请重新检测权限。"
    }

    private func install() {
        guard tap == nil else { return }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<DockController>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if AXIsProcessTrusted(), let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    // Never alter clicks, drags, or movement while any button is held.
                    if type == .mouseMoved, NSEvent.pressedMouseButtons == 0, owner.mode == .fixed,
                       owner.multipleDisplays, NSScreen.screens.count > 1, let target = owner.target {
                        event.location = DockRoutingPolicy.guardedPoint(event.location, target: target.id, screens: owner.screens)
                    }
                    return Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installed = true
    }
    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; installed = false
    }
    func stop() { task?.cancel(); task = nil; uninstall() }

    private func observedDockScreen() -> DockScreen? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.dockWindow)),
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary), rect.width > 0, rect.height > 0 else { continue }
            if let screen = screens.first(where: { $0.bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) }),
               rect.width < screen.bounds.width || rect.height < screen.bounds.height { return screen }
        }
        return nil
    }
}
