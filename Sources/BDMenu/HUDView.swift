import SwiftUI

struct HUDView: View {
    var value: Int = 50
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
            Text("\(value)%")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
    }
}
