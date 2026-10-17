import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let manager = DisplayManager()
    private lazy var presentation = AppPresentation(manager: manager)
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager.start()
        presentation.applyAppearance()
        configureMenus()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "BDMenu.StatusItem"
        if let button = item.button {
            let image = NSImage(systemSymbolName: "display", accessibilityDescription: "BDMenu")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "BDMenu · 显示器控制"
            button.setAccessibilityLabel("BDMenu 显示器控制")
            button.target = self
            button.action = #selector(toggleQuickControls)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let hosting = NSHostingController(rootView: MenuView().environment(manager).environment(presentation))
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        self.popover = popover
        presentation.dismissQuickControls = { [weak self] in self?.popover?.performClose(nil) }
        presentation.showQuickControls = { [weak self] in self?.toggleQuickControls() }
        if UserDefaults.standard.string(forKey: "introducedInterfaceVersion") != "2"
            || CommandLine.arguments.contains("--control-center") {
            presentation.show()
            UserDefaults.standard.set("2", forKey: "introducedInterfaceVersion")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentation.show()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { manager.stop() }
    func popoverWillShow(_ notification: Notification) { manager.panelOpened() }

    @objc private func toggleQuickControls() {
        guard let button = statusItem?.button, let popover else { return }
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(item("控制中心…", action: #selector(openCenter)))
            menu.addItem(item("快捷键…", action: #selector(openKeyboard)))
            menu.addItem(.separator())
            menu.addItem(item("退出 BDMenu", action: #selector(quit)))
            if let event = NSApplication.shared.currentEvent { NSMenu.popUpContextMenu(menu, with: event, for: button) }
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    @objc private func openCenter() { popover?.performClose(nil); presentation.show(.displays) }
    @objc private func openKeyboard() { popover?.performClose(nil); presentation.show(.keyboard) }
    @objc private func openApplication() { popover?.performClose(nil); presentation.show(.application) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func selectPage(_ sender: NSMenuItem) {
        guard let page = AppPresentation.Page(rawValue: sender.tag) else { return }
        presentation.show(page)
    }
    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    private func configureMenus() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "BDMenu")
        appMenu.addItem(item("关于与权限…", action: #selector(openApplication)))
        appMenu.addItem(item("控制中心…", action: #selector(openCenter), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 BDMenu", action: #selector(quit), key: "q"))
        appItem.submenu = appMenu
        root.addItem(appItem)
        let pages = NSMenu(title: "控制")
        for page in AppPresentation.Page.allCases {
            let entry = item(page.title, action: #selector(selectPage(_:)), key: "\(page.rawValue + 1)")
            entry.tag = page.rawValue
            pages.addItem(entry)
        }
        let pagesItem = NSMenuItem(); pagesItem.submenu = pages; root.addItem(pagesItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; root.addItem(editItem)
        let windows = NSMenu(title: "窗口")
        windows.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windows.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        let windowsItem = NSMenuItem(); windowsItem.submenu = windows; root.addItem(windowsItem)
        NSApplication.shared.windowsMenu = windows
        NSApplication.shared.mainMenu = root
    }
}

@main @MainActor
enum BDMenuApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
