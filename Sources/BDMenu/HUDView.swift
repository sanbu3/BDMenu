import SwiftUI

/// Center against the physical screen, while keeping above a bottom Dock.
enum HUDLayout {
    static let size = CGSize(width: 280, height: 76)

    static func frame(screen: CGRect, visible: CGRect, scale: CGFloat = 1) -> CGRect {
        let scale = max(1, scale)
        let x = screen.midX - size.width / 2
        let y = min(max(screen.minY, visible.minY) + 32, screen.maxY - size.height)
        return CGRect(x: (x * scale).rounded() / scale, y: (y * scale).rounded() / scale,
                      width: size.width, height: size.height)
    }
}

struct HUDView: View {
    var value: Int = 50

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.blue)
                Text("亮度").font(.system(size: 15, weight: .medium))

            }
            .frame(maxWidth: .infinity, alignment: .center)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(.blue)
                        .frame(width: geometry.size.width * CGFloat(max(0, min(100, value))) / 100)
                }
            }
            .frame(width: 232, height: 6)
        }
        .frame(width: HUDLayout.size.width, height: HUDLayout.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("屏幕亮度已调整")
    }
}
