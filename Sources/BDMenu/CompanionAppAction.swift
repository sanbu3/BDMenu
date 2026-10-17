import Foundation

enum CompanionAppAction {
    enum Primary: Equatable { case hide, reveal, open }
    static func primary(running: Bool, hidden: Bool, active: Bool, toggleEnabled: Bool) -> Primary {
        guard running else { return .open }
        if hidden { return .reveal }
        return active && toggleEnabled ? .hide : .open
    }
    static func mayQuit(bundleIdentifier: String?) -> Bool {
        bundleIdentifier != "com.apple.finder" && bundleIdentifier != Bundle.main.bundleIdentifier
    }
    static func matchingPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.isFileURL && rhs.isFileURL && lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
