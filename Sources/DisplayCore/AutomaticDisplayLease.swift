import Foundation

/// A temporary, verified mode change owns only the modes it actually wrote.
public struct AutomaticDisplayLease: Codable {
    public var originalArguments: [String]
    public var originalModes: [String: DisplayModeSpec]
    public var appliedModes: [String: DisplayModeSpec]
    public var connectedIDs: Set<String>
    public init(originalArguments: [String], appliedModes: [String: DisplayModeSpec], connectedIDs: Set<String>, originalModes: [String: DisplayModeSpec] = [:]) {
        self.originalModes = originalModes
        self.originalArguments = originalArguments; self.appliedModes = appliedModes; self.connectedIDs = connectedIDs
    }
    public func stillOwns(_ snapshot: DisplaySnapshot, connectedIDs: Set<String>) -> Bool {
        guard self.connectedIDs == connectedIDs, !appliedModes.isEmpty else { return false }
        return appliedModes.allSatisfy { id, spec in
            snapshot.modes[id]?.first(where: \.isCurrent).map(spec.matches) == true
        }
    }
}
