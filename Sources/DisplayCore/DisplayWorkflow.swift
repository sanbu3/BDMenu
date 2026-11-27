import Foundation

/// Pure decisions for the "external display attached => keep the built-in panel off"
/// workflow. Keeping them here makes the hot-plug behaviour testable without hardware.
public enum DisplayWorkflow {
    /// A disconnected external display disappears from the display list almost
    /// immediately, but the reconfigure callbacks arrive in bursts. Wait out that
    /// burst before treating "no external display" as a real unplug.
    public static let absenceGrace: TimeInterval = 1.5
    /// Minimum spacing between two corrective writes so a monitor that keeps
    /// re-enabling itself cannot turn the app into a busy loop.
    public static let minimumWriteInterval: TimeInterval = 2

    public static func shouldRecoverBuiltin(externalPresent: Bool,
                                            secondsSinceExternalSeen: TimeInterval,
                                            builtinEnabled: Bool,
                                            workflowClearedBuiltin: Bool,
                                            absenceGrace: TimeInterval = DisplayWorkflow.absenceGrace) -> Bool {
        guard !externalPresent, secondsSinceExternalSeen >= absenceGrace else { return false }
        return !builtinEnabled || workflowClearedBuiltin
    }

    /// macOS sometimes re-applies its own arrangement right after a hot-plug (or on
    /// wake) and switches the built-in panel back on. The workflow owns that panel
    /// while an external screen is online, so it re-asserts instead of letting a
    /// one-shot edge trigger decide the final state.
    public static func shouldKeepBuiltinOff(autoWorkflow: Bool,
                                            workflowHoldsBuiltinOff: Bool,
                                            userRestoredBuiltin: Bool,
                                            externalOnline: Bool,
                                            builtinEnabled: Bool) -> Bool {
        autoWorkflow && workflowHoldsBuiltinOff && !userRestoredBuiltin && externalOnline && builtinEnabled
    }
}
