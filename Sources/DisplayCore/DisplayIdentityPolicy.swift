import Foundation

public enum DisplayIdentityPolicy {
    /// Offline display services sometimes return a syntactically valid all-zero
    /// UUID. It must never become a persisted physical-screen identity.
    public static func stableUUID(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            if let candidate, let uuid = UUID(uuidString: candidate),
               uuid.uuidString != "00000000-0000-0000-0000-000000000000" { return uuid.uuidString }
        }
        return nil
    }
}
