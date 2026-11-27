/// Refresh-rate experiments must keep resolution and HiDPI unchanged so the
/// comparison changes one setting at a time. Never invent unsupported modes.
public enum DisplayModePolicy {
    /// HiDPI shortcuts preserve refresh rate and aspect ratio. If the current
    /// desktop size has no HiDPI variant, offer the largest smaller desktop
    /// explicitly rather than silently reducing refresh rate or stretching it.
    public static func hiDPIModes(current: DisplayMode, available: [DisplayMode]) -> [DisplayMode] {
        guard let hertz = current.hertz else { return [] }
        var sizes = Set<String>()
        return available.filter {
            $0.scaling && $0.hertz == hertz
                && $0.width * current.height == current.width * $0.height
        }.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.id < $1.id
        }.filter { sizes.insert("\($0.width)x\($0.height)").inserted }
    }

    public static func scalingMode(_ enabled: Bool, current: DisplayMode, available: [DisplayMode]) -> DisplayMode? {
        if current.scaling == enabled { return current }
        guard let hertz = current.hertz else { return nil }
        if let exact = available.first(where: {
            $0.width == current.width && $0.height == current.height
                && $0.hertz == hertz && $0.scaling == enabled
        }) { return exact }
        guard enabled else { return nil }
        return hiDPIModes(current: current, available: available).first {
            $0.width <= current.width && $0.height <= current.height
        }
    }

    public static func sameFormat(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.scaling == rhs.scaling && lhs.hertz == rhs.hertz
    }

    public static func refreshMode(_ hertz: Int, current: DisplayMode, available: [DisplayMode]) -> DisplayMode? {
        if current.hertz == hertz { return current }
        return available.first {
            $0.width == current.width && $0.height == current.height
                && $0.scaling == current.scaling && $0.hertz == hertz
        }
    }
}
