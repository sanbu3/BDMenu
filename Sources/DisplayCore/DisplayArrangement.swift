import Foundation

public enum DisplayArrangement: String, CaseIterable, Identifiable, Sendable {
    case horizontal, vertical, grid
    public var id: String { rawValue }
    public var title: String {
        switch self { case .horizontal: return "横向排列"; case .vertical: return "纵向排列"; case .grid: return "网格排列" }
    }
    public func arrange(_ layouts: [DisplayLayout], main: String) -> [DisplayLayout] {
        let active = layouts.filter(\.enabled).sorted {
            if ($0.uuid == main) != ($1.uuid == main) { return $0.uuid == main }
            return $0.uuid < $1.uuid
        }
        var placed: [String: (Int, Int)] = [:]
        var x = 0, y = 0, rowHeight = 0
        for (index, item) in active.enumerated() {
            let width = item.rotation % 180 == 0 ? item.width : item.height
            let height = item.rotation % 180 == 0 ? item.height : item.width
            if self == .grid && index > 0 && index % 2 == 0 {
                x = 0; y += rowHeight; rowHeight = 0
            }
            placed[item.uuid] = (x, y)
            switch self {
            case .horizontal: x += width
            case .vertical: y += height
            case .grid: x += width; rowHeight = max(rowHeight, height)
            }
        }
        return layouts.map { item in
            var copy = item
            if let point = placed[item.uuid] { copy.x = point.0; copy.y = point.1 }
            return copy
        }
    }
}
