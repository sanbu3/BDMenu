/// Refresh-rate experiments must keep resolution and HiDPI unchanged so the
/// comparison changes one setting at a time. Never invent unsupported modes.
public enum DisplayModePolicy {
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
