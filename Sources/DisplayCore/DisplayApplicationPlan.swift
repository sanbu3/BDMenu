import Foundation

/// displayplacer cannot address a panel that SkyLight has removed from the
/// online list. Wake required panels first; turn off requested panels last.
public struct DisplayApplicationPlan: Sendable {
    public let arguments: [String]
    public let enabledIDs: Set<String>
    public let disabledIDs: Set<String>
    public init(_ arguments: [String]) {
        let disabled = arguments.filter { $0.split(whereSeparator: \.isWhitespace).contains("enabled:false") }
        disabledIDs = DisplaySnapshot.referencedIDs(disabled)
        self.arguments = arguments.filter { !$0.split(whereSeparator: \.isWhitespace).contains("enabled:false") }
        enabledIDs = DisplaySnapshot.referencedIDs(self.arguments)
    }
}
