import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ScreenRegion: Equatable, Sendable {
    public var id: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

/// Logical points in global AX coordinates (origin at the top left).
public enum WindowFrameChange: Equatable, Sendable {
    case size(CGSize)
    case position(CGPoint)
}

public enum WindowPlacementPolicy {
    /// Shrink before moving; grow only after the new origin is valid. AppKit may clamp
    /// an enlargement against the old origin before a subsequent position write.
    public static func changes(from current: CGRect, to desired: CGRect) -> [WindowFrameChange] {
        [.size(CGSize(width: min(current.width, desired.width), height: min(current.height, desired.height))),
         .position(desired.origin), .size(desired.size), .position(desired.origin)]
    }
    public static func interpolate(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        let t = min(1, max(0, progress))
        let eased = t * t * (3 - 2 * t)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b-a)*eased }
        return CGRect(x: mix(from.minX,to.minX), y: mix(from.minY,to.minY),
                      width: mix(from.width,to.width), height: mix(from.height,to.height))
    }

    public static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
    public static func screen(for rect: CGRect, in screens: [ScreenRegion]) -> ScreenRegion? {
        guard valid(rect) else { return nil }
        return screens.filter { valid($0.visibleFrame) }.max { a, b in
            func score(_ screen: ScreenRegion) -> Double {
                let overlap = rect.intersection(screen.frame)
                if !overlap.isNull && !overlap.isEmpty { return overlap.width * overlap.height }
                return -hypot(screen.frame.midX - rect.midX, screen.frame.midY - rect.midY)
            }
            return score(a) < score(b)
        }
    }
    public static func fit(_ rect: CGRect, into area: CGRect) -> CGRect {
        guard valid(rect), valid(area) else { return rect }
        // Preserve aspect when shrinking, but never enlarge a small window.
        let scale = min(1, area.width / rect.width, area.height / rect.height)
        let size = CGSize(width: floor(rect.width * scale), height: floor(rect.height * scale))
        return CGRect(x: min(max(rect.minX, area.minX), area.maxX - size.width),
                      y: min(max(rect.minY, area.minY), area.maxY - size.height),
                      width: size.width, height: size.height)
    }
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) < 3 && abs(a.minY-b.minY) < 3
            && abs(a.width-b.width) < 3 && abs(a.height-b.height) < 3
    }
    /// Convert NSScreen's bottom-left coordinate space to AX global coordinates.
    public static func axRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Session-only identity: callers assign a token to a verified AX window, never a title/PID guess.
public struct WindowPlacementMemory {
    private struct Entry {
        var screen: String
        var frames: [String: CGRect]
        var displacedFrom: String?
        var lastObserved: CGRect
        var lastWritten: CGRect?
    }
    private var entries: [String: Entry] = [:]
    public init() {}
    public mutating func remove(_ id: String) { entries.removeValue(forKey: id) }
    public mutating func clear() { entries.removeAll() }

    /// Returns a proposed frame. Call `didWrite` only after a verified AX write.
    public mutating func observe(id: String, frame: CGRect, screens: [ScreenRegion],
                                 topologyChange: Bool = false) -> CGRect? {
        guard let target = WindowPlacementPolicy.screen(for: frame, in: screens) else { return nil }
        guard var entry = entries[id] else {
            entries[id] = Entry(screen: target.id, frames: [target.id: frame], lastObserved: frame)
            let fitted = WindowPlacementPolicy.fit(frame, into: target.visibleFrame)
            return WindowPlacementPolicy.approximatelyEqual(frame, fitted) ? nil : fitted
        }
        let isOwnWrite = entry.lastWritten.map { WindowPlacementPolicy.approximatelyEqual($0, frame) } ?? false
        var desired = frame
        let sourceMissing = !screens.contains { $0.id == entry.screen }
        if topologyChange {
            if sourceMissing {
                entry.displacedFrom = entry.displacedFrom ?? entry.screen
                desired = WindowPlacementPolicy.fit(frame, into: target.visibleFrame)
            } else if let original = entry.displacedFrom,
                      let returning = screens.first(where: { $0.id == original }),
                      let saved = entry.frames[original] {
                desired = WindowPlacementPolicy.fit(saved, into: returning.visibleFrame)
                entry.screen = original
                entry.displacedFrom = nil
            } else if let saved = entry.frames[entry.screen],
                      let sameScreen = screens.first(where: { $0.id == entry.screen }) {
                desired = WindowPlacementPolicy.fit(saved, into: sameScreen.visibleFrame)
            } else {
                desired = WindowPlacementPolicy.fit(frame, into: target.visibleFrame)
            }
        } else if !isOwnWrite {
            // A real user move/resize supersedes an emergency relocation.
            entry.displacedFrom = nil
            if target.id != entry.screen {
                desired = WindowPlacementPolicy.fit(entry.frames[target.id] ?? frame, into: target.visibleFrame)
            } else {
                entry.frames[target.id] = frame
                desired = WindowPlacementPolicy.fit(frame, into: target.visibleFrame)
            }
            entry.screen = target.id
            entry.lastWritten = nil
        }
        entry.lastObserved = frame
        entries[id] = entry
        return WindowPlacementPolicy.approximatelyEqual(frame, desired) ? nil : desired
    }

    public mutating func didWrite(id: String, actual: CGRect, screens: [ScreenRegion], rememberNewScreen: Bool = true) {
        guard var entry = entries[id] else { return }
        entry.lastWritten = actual
        entry.lastObserved = actual
        if entry.displacedFrom == nil, let screen = WindowPlacementPolicy.screen(for: actual, in: screens) {
            entry.screen = screen.id
            // Keep the pre-shrink frame, so mode rollback/return to a larger screen can restore it.
            if rememberNewScreen, entry.frames[screen.id] == nil { entry.frames[screen.id] = actual }
        }
        entries[id] = entry
    }
}
