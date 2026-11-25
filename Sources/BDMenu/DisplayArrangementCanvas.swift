import SwiftUI
import DisplayCore

struct DisplayArrangementCanvas: View {
    @Binding var layouts: [DisplayLayout]
    @Binding var selected: String
    let main: String
    let names: [String: String]
    var changed: () -> Void
    @State private var dragging: String?
    @State private var translation = CGSize.zero

    private var active: [DisplayLayout] { layouts.filter(\.enabled) }
    private func size(_ layout: DisplayLayout) -> CGSize {
        CGSize(width: layout.rotation % 180 == 0 ? layout.width : layout.height,
               height: layout.rotation % 180 == 0 ? layout.height : layout.width)
    }
    private var bounds: CGRect {
        active.reduce(CGRect.null) { result, item in
            result.union(CGRect(origin: CGPoint(x: item.x, y: item.y), size: size(item)))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let area = bounds
            let scale = min((geometry.size.width - 60) / max(1, area.width), (geometry.size.height - 50) / max(1, area.height))
            let offsetX = (geometry.size.width - area.width * scale) / 2
            let offsetY = (geometry.size.height - area.height * scale) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18).fill(.primary.opacity(0.035))
                ForEach(active, id: \.uuid) { layout in
                    let screenSize = size(layout)
                    Button {
                        selected = layout.uuid
                    } label: {
                        VStack(spacing: 5) {
                            if main == layout.uuid { Capsule().fill(.white).frame(height: 4) }
                            Spacer(minLength: 0)
                            Text(names[layout.uuid] ?? "显示器").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\(layout.width) × \(layout.height)").font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(width: max(30, screenSize.width * scale), height: max(25, screenSize.height * scale))
                        .background(selected == layout.uuid ? BDMenuStyle.accent.opacity(0.45) : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected == layout.uuid ? BDMenuStyle.accent : Color.primary.opacity(0.25), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: (CGFloat(layout.x) - area.minX) * scale + offsetX + (dragging == layout.uuid ? translation.width : 0),
                            y: (CGFloat(layout.y) - area.minY) * scale + offsetY + (dragging == layout.uuid ? translation.height : 0))
                    .simultaneousGesture(DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            selected = layout.uuid; dragging = layout.uuid; translation = value.translation
                        }
                        .onEnded { value in
                            move(layout, dx: Int((value.translation.width / scale).rounded()),
                                 dy: Int((value.translation.height / scale).rounded()))
                            dragging = nil; translation = .zero; changed()
                        })
                    .accessibilityLabel("\(names[layout.uuid] ?? "显示器")，\(main == layout.uuid ? "主屏，" : "")横坐标 \(layout.x)，纵坐标 \(layout.y)")
                    .help("拖动排列；也可以选中后输入下方 X、Y 坐标")
                }
            }
        }
    }

    private func move(_ layout: DisplayLayout, dx: Int, dy: Int) {
        guard let index = layouts.firstIndex(where: { $0.uuid == layout.uuid }) else { return }
        var x = layout.x + dx, y = layout.y + dy
        let width = Int(size(layout).width), height = Int(size(layout).height)
        var edgesX: [Int] = [], edgesY: [Int] = []
        for other in active where other.uuid != layout.uuid {
            let otherWidth = Int(size(other).width), otherHeight = Int(size(other).height)
            edgesX += [other.x, other.x + otherWidth, other.x - width]
            edgesY += [other.y, other.y + otherHeight, other.y - height]
        }
        if let edge = edgesX.min(by: { abs($0 - x) < abs($1 - x) }), abs(edge - x) <= 80 { x = edge }
        if let edge = edgesY.min(by: { abs($0 - y) < abs($1 - y) }), abs(edge - y) <= 80 { y = edge }
        layouts[index].x = min(32000, max(-32000, x))
        layouts[index].y = min(32000, max(-32000, y))
    }
}
