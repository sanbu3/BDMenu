import AppKit
import SwiftUI
import Observation

struct CompanionScreen: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
}

enum CompanionBarRouting {
    enum Mode: String, CaseIterable, Identifiable {
        case fixed, mouse
        var id: String { rawValue }
        var title: String { self == .fixed ? "固定到指定屏幕" : "跟随鼠标所在屏幕" }
    }
    static func target(mode: Mode, uuid: String, screens: [CompanionScreen], pointer: CGPoint,
                       currentID: CGDirectDisplayID?, interacting: Bool) -> CompanionScreen? {
        guard !screens.isEmpty else { return nil }
        if screens.count == 1 { return screens[0] }
        if mode == .fixed {
            let matches = screens.filter { $0.uuid == uuid }
            return matches.count == 1 ? matches[0] : nil
        }
        if interacting, let current = screens.first(where: { $0.id == currentID }) { return current }
        return screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first(where: { $0.id == currentID })
    }
    static func frame(screen: CompanionScreen, itemCount: Int) -> CGRect {
        let limit = min(1100, max(160, screen.frame.width - 32))
        let slots = max(1, min(itemCount, Int((limit - 128) / 60)))
        let width = min(limit, CGFloat(slots) * 60 + 128)
        // Stay inside this screen, including when another screen touches its bottom.
        let y = min(max(screen.frame.minY + 10, screen.visibleFrame.minY + 10), screen.frame.maxY - 96)
        return CGRect(x: screen.frame.midX - width / 2, y: y, width: width, height: 86)
    }
    static func orderedURLs(pinned: [URL], running: [URL]) -> [URL] {
        var seen = Set<String>()
        return (pinned + running).filter { url in
            guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

struct CompanionApp: Identifiable {
    let url: URL
    let name: String
    let icon: NSImage
    let running: Bool
    let frontmost: Bool
    var id: String { url.standardizedFileURL.path }
}

@MainActor @Observable
final class CompanionBarController {
    typealias Mode = CompanionBarRouting.Mode
    private(set) var enabled = UserDefaults.standard.bool(forKey: "companionBarEnabled")
    private(set) var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "companionBarMode") ?? "") ?? .fixed
    private(set) var fixedUUID = UserDefaults.standard.string(forKey: "companionBarTarget")
        ?? UserDefaults.standard.string(forKey: "dockFixedUUID") ?? ""
    private(set) var autoHide = UserDefaults.standard.bool(forKey: "companionBarAutoHide")
    private(set) var includePinned = UserDefaults.standard.object(forKey: "companionBarIncludePinned") as? Bool ?? true
    private(set) var screens: [CompanionScreen] = []
    private(set) var apps: [CompanionApp] = []
    private(set) var activeScreenName: String?
    private(set) var status = "扩展应用栏未启用。"
    private(set) var lastError: String?
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored var onEnabledChanged: ((Bool) -> Void)?
    @ObservationIgnored private var panel: CompanionPanel?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeID: CGDirectDisplayID?
    @ObservationIgnored private var candidateID: CGDirectDisplayID?
    @ObservationIgnored private var candidateSince = Date.distantPast
    @ObservationIgnored private var lastInside = Date.distantPast
    @ObservationIgnored private var lastAppsRefresh = Date.distantPast

    var target: CompanionScreen? { screens.first { $0.uuid == fixedUUID } }

    func start() {
        guard task == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshApps() }
            })
        }
        onEnabledChanged?(enabled)
        refreshApps()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPosition()
                if let self, self.enabled, Date().timeIntervalSince(self.lastAppsRefresh) > 5 { self.refreshApps() }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    func stop() {
        task?.cancel(); task = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        panel?.orderOut(nil); panel = nil
    }
    func update(displays: [DisplayManager.DisplayInfo]) {
        screens = displays.filter(\.enabled).compactMap { display in
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }) else { return nil }
            return CompanionScreen(id: display.id, uuid: display.uuid, name: display.name,
                                   frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        if fixedUUID.isEmpty, let initial = screens.first(where: { $0.id == CGMainDisplayID() }) ?? screens.first {
            setTarget(initial.uuid)
        }
        refreshPosition(immediate: true)
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "companionBarEnabled")
        onEnabledChanged?(value)
        lastInside = Date()
        refreshApps(); refreshPosition(immediate: true)
    }
    func setMode(_ value: Mode) {
        mode = value; UserDefaults.standard.set(value.rawValue, forKey: "companionBarMode")
        refreshPosition(immediate: true)
    }
    func setTarget(_ uuid: String) {
        fixedUUID = uuid; UserDefaults.standard.set(uuid, forKey: "companionBarTarget")
        refreshPosition(immediate: true)
    }
    func setAutoHide(_ value: Bool) {
        autoHide = value; UserDefaults.standard.set(value, forKey: "companionBarAutoHide")
        lastInside = Date(); refreshPosition(immediate: true)
    }
    func setIncludePinned(_ value: Bool) {
        includePinned = value; UserDefaults.standard.set(value, forKey: "companionBarIncludePinned"); refreshApps()
    }
    func reveal() { lastInside = Date(); refreshPosition(immediate: true) }
    func refreshApps() {
        guard enabled else { return }
        lastAppsRefresh = Date()
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !$0.isTerminated
        }
        let pinned = includePinned ? systemPinnedApps() : []
        let urls = CompanionBarRouting.orderedURLs(pinned: pinned, running: running.compactMap(\.bundleURL))
        apps = urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map { url in
            let matches = running.filter { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path }
            return CompanionApp(url: url,
                name: matches.first?.localizedName ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                icon: NSWorkspace.shared.icon(forFile: url.path), running: !matches.isEmpty,
                frontmost: matches.contains(where: \.isActive))
        }
    }
    private func systemPinnedApps() -> [URL] {
        let tiles = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any], let raw = file["_CFURLString"] as? String,
                  let url = URL(string: raw), url.isFileURL else { return nil }
            return url
        }
    }
    func activate(_ app: CompanionApp) {
        lastError = nil
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in self?.lastError = "无法打开\(app.name)：\(error.localizedDescription)" }
        }
    }
    private func refreshPosition(immediate: Bool = false) {
        guard enabled else { panel?.orderOut(nil); activeScreenName = nil; publishStatus("扩展应用栏未启用，系统 Dock 保持原样。"); return }
        let point = NSEvent.mouseLocation
        let interacting = NSEvent.pressedMouseButtons != 0 || (panel?.isVisible == true && panel?.frame.insetBy(dx: -10, dy: -10).contains(point) == true)
        guard let target = CompanionBarRouting.target(mode: mode, uuid: fixedUUID, screens: screens, pointer: point,
                                                       currentID: activeID, interacting: interacting) else {
            panel?.orderOut(nil); activeID = nil; activeScreenName = nil
            publishStatus("指定屏幕未启用，扩展栏已暂停。请选择在线屏幕；原目标重新连接后会恢复。"); return
        }
        if !immediate, mode == .mouse, target.id != activeID {
            if candidateID != target.id { candidateID = target.id; candidateSince = Date(); return }
            if Date().timeIntervalSince(candidateSince) < 0.3 { return }
        }
        candidateID = nil
        if activeID != target.id { activeID = target.id; lastInside = Date() }
        if activeScreenName != target.name { activeScreenName = target.name }
        publishStatus("扩展应用栏位于“\(target.name)”\(mode == .fixed ? "，已固定。" : "，跟随鼠标切换屏幕。")上下排列的屏幕也可使用，无需跨屏底边手势。")
        ensurePanel()
        let frame = CompanionBarRouting.frame(screen: target, itemCount: apps.count)
        if panel?.frame != frame { panel?.setFrame(frame, display: true) }
        let trigger = CGRect(x: frame.minX, y: frame.minY - 10, width: frame.width, height: frame.height + 20)
        if trigger.contains(point) { lastInside = Date() }
        if !autoHide || trigger.contains(point) || Date().timeIntervalSince(lastInside) < 1 || panel?.isKeyWindow == true {
            if panel?.isVisible != true { panel?.orderFrontRegardless() }
        } else { panel?.orderOut(nil) }
    }
    private func publishStatus(_ text: String) { if status != text { status = text } }
    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "BDMenu 扩展应用栏"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: CompanionBarView(controller: self))
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        self.panel = panel
    }
}

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct CompanionBarView: View {
    let controller: CompanionBarController
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Image(systemName: "display.2").foregroundStyle(.blue)
                Text("BD").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 28).accessibilityLabel("BDMenu 扩展应用栏")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(controller.apps) { app in CompanionAppButton(app: app, controller: controller) }
                }
                .padding(.horizontal, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Button { controller.openSettings?() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 34, height: 48)
            }
            .buttonStyle(BDMenuCapsuleButtonStyle(compact: true))
            .accessibilityLabel("扩展应用栏设置")
            .contextMenu {
                Button("扩展应用栏设置…") { controller.openSettings?() }
                Button("跟随鼠标所在屏幕") { controller.setMode(.mouse) }
                Menu("固定到屏幕") {
                    ForEach(controller.screens, id: \.uuid) { screen in
                        Button(screen.name) { controller.setTarget(screen.uuid); controller.setMode(.fixed) }
                    }
                }
                Divider()
                Button("关闭扩展应用栏") { controller.setEnabled(false) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }
}

private struct CompanionAppButton: View {
    let app: CompanionApp
    let controller: CompanionBarController
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button { controller.activate(app) } label: {
            VStack(spacing: 3) {
                Image(nsImage: app.icon).resizable().frame(width: 48, height: 48)
                Circle().fill(app.running ? (app.frontmost ? Color.blue : Color.primary.opacity(0.6)) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 56, height: 66)
            .background(Color.primary.opacity(hovered || (focused && InterfaceInputState.shared.keyboardNavigation) ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).focusEffectDisabled().focused($focused)
        .onHover { hovered = $0 }.help(app.name)
        .accessibilityLabel(app.name + (app.running ? "，正在运行" : "，打开应用"))
        .accessibilityValue(app.frontmost ? "当前应用" : (app.running ? "运行中" : "未运行"))
        .contextMenu {
            Button("打开或切换到\(app.name)") { controller.activate(app) }
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}
