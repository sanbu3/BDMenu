import SwiftUI

struct HUDView: View {
    var value: Int = 50

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 24)).foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(value)").font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Text("亮度").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(.blue).frame(width: geometry.size.width * CGFloat(max(0, min(100, value))) / 100)
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 236, height: 76)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("屏幕亮度 \(value)%")
    }
}
