import Foundation

/// A dead band retains the last decision; invalid or missing samples never disable a display.
public struct LidAnglePolicy {
    public private(set) var externalOnly = false
    private var candidate: Bool?
    private var candidateSince: TimeInterval = 0

    public init() {}

    public mutating func update(angle: Double?, close: Double, open: Double,
                                now: TimeInterval) -> Bool? {
        guard let angle, angle.isFinite, (0...180).contains(angle),
              close.isFinite, open.isFinite, close < open else {
            candidate = nil
            return nil
        }
        let desired: Bool
        if angle <= close { desired = true }
        else if angle >= open { desired = false }
        else { candidate = nil; return nil }
        guard candidate == desired else {
            candidate = desired
            candidateSince = now
            return nil
        }
        guard now - candidateSince >= 0.8 else { return nil }
        externalOnly = desired
        return desired
    }
}
