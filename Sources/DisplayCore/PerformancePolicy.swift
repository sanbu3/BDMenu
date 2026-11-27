import Foundation

public enum PerformancePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case quality, balanced, performance, lowPower
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .quality: return "画质优先"
        case .balanced: return "均衡模式"
        case .performance: return "性能优先"
        case .lowPower: return "低功耗"
        }
    }
    public var defaultSpec: DisplayModeSpec {
        switch self {
        case .quality: return .init(width: 2560, height: 1440, hertz: 144, scaling: true)
        case .balanced: return .init(width: 1920, height: 1080, hertz: 120, scaling: true)
        case .performance: return .init(width: 2560, height: 1440, hertz: 144, scaling: false)
        case .lowPower: return .init(width: 1920, height: 1080, hertz: 60, scaling: true)
        }
    }
}

public struct DisplayModeSpec: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var hertz: Int?
    public var scaling: Bool
    public init(width: Int, height: Int, hertz: Int?, scaling: Bool) {
        self.width = width; self.height = height; self.hertz = hertz; self.scaling = scaling
    }
    public init(_ mode: DisplayMode) {
        self.init(width: mode.width, height: mode.height, hertz: mode.hertz, scaling: mode.scaling)
    }
    public func matches(_ mode: DisplayMode) -> Bool { self == Self(mode) }
    public var label: String {
        "\(width) × \(height)" + (scaling ? " · HiDPI" : " · 普通") + (hertz.map { " · \($0) Hz" } ?? "")
    }
}

public struct PerformancePolicy {
    public enum Action: Equatable { case reduce, restore }
    private var highSince: TimeInterval?
    private var lowSince: TimeInterval?
    private var lastAction = -Double.infinity
    public init() {}
    public mutating func reset() { highSince = nil; lowSince = nil }
    public mutating func evaluate(usage: Double?, now: TimeInterval, blocked: Bool,
                                 reduced: Bool, high: Double = 80, duration: Double = 20,
                                 restoreDuration: Double = 60, cooldown: Double = 90) -> Action? {
        guard !blocked, let usage, usage.isFinite, (0...100).contains(usage) else { reset(); return nil }
        if usage >= high { highSince = highSince ?? now; lowSince = nil }
        else if usage <= max(0, high - 25) { lowSince = lowSince ?? now; highSince = nil }
        else { reset() }
        guard now - lastAction >= cooldown else { return nil }
        let action: Action?
        if !reduced, let since = highSince, now - since >= duration { action = .reduce }
        else if reduced, let since = lowSince, now - since >= restoreDuration { action = .restore }
        else { action = nil }
        if action != nil { lastAction = now; reset() }
        return action
    }
    /// Automated load reduction is limited to refresh rate, preserving every desktop dimension.
    public static func lowerRefresh(current: DisplayMode, available: [DisplayMode]) -> DisplayMode? {
        guard let rate = current.hertz else { return nil }
        return available.filter {
            $0.width == current.width && $0.height == current.height && $0.scaling == current.scaling
                && ($0.hertz ?? 0) >= 60 && ($0.hertz ?? rate) < rate
        }.max { ($0.hertz ?? 0) < ($1.hertz ?? 0) }
    }
}
