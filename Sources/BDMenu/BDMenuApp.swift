import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = DisplayManager()
    func applicationDidFinishLaunching(_ notification: Notification) { manager.start() }
    func applicationWillTerminate(_ notification: Notification) { manager.stop() }
}

@main
struct BDMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            MenuView().environment(delegate.manager)
        } label: {
            Image(systemName: delegate.manager.externalOnline ? "display.2" : "display")
        }
        .menuBarExtraStyle(.window)
    }
}
