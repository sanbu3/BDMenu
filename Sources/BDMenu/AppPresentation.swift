import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class AppPresentation: NSObject, NSWindowDelegate {
    enum Page: Int, CaseIterable, Identifiable {
        case displays, keyboard, automation, application, dock
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .displays: return "显示器"
            case .keyboard: return "快捷键"
            case .automation: return "自动化"
            case .application: return "应用与权限"
            case .dock: return "Dock"
            }
        }
        var symbol: String {
            switch self {
            case .displays: return "display.2"
            case .keyboard: return "keyboard"
            case .automation: return "switch.2"
            case .application: return "slider.horizontal.3"
            case .dock: return "dock.rectangle"
            }
        }
        var subtitle: String {
            switch self {
            case .displays: return "每块屏幕，都有适合它的亮度与布局。"
            case .keyboard: return "把常用的亮度调节，交给你习惯的按键。"
            case .automation: return "接入外接屏以后，让桌面按你的习惯运行。"
            case .application: return "管理外观与权限，随时了解当前运行状态。"
            case .dock: return "把扩展应用栏固定到任意在线屏幕，或让它跟随鼠标。"
            }
        }
    }
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
        var native: NSAppearance? {
            self == .system ? nil : NSAppearance(named: self == .light ? .aqua : .darkAqua)
        }
    }

    var page: Page = .displays
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "interfaceAppearance") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "interfaceAppearance")
            applyAppearance()
        }
    }
    @ObservationIgnored let manager: DisplayManager
    @ObservationIgnored var dismissQuickControls: (() -> Void)?
    @ObservationIgnored var showQuickControls: (() -> Void)?
    @ObservationIgnored private var window: NSWindow?

    init(manager: DisplayManager) {
        self.manager = manager
        super.init()
    }

    func applyAppearance() { NSApplication.shared.appearance = appearance.native }

    func show(_ page: Page? = nil) {
        dismissQuickControls?()
        if let page { self.page = page }
        manager.panelOpened()
        if window == nil {
            let hosting = NSHostingController(rootView: ControlCenterView().environment(manager).environment(self))
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
            let window = BDMenuWindow(contentRect: .zero, styleMask: [.borderless, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.contentViewController = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.title = "BDMenu · 控制中心"
            window.contentMinSize = NSSize(width: 720, height: 560)
            let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
            window.setContentSize(NSSize(width: min(840, available.width - 60), height: min(760, available.height - 80)))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("BDMenu.ControlCenter.v3")
            if !window.setFrameUsingName("BDMenu.ControlCenter.v3") { window.center() }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() { window?.performClose(nil) }
    func minimize() { window?.miniaturize(nil) }

    func windowWillClose(_ notification: Notification) { manager.cancelRecording() }
}
