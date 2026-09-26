import SwiftUI

@main
struct BDMenuApp: App {
    @State private var dm = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(dm)
        } label: {
            Image(systemName: dm.externalOnline ? "display.2" : "display")
        }
        .menuBarExtraStyle(.window)
    }
}
