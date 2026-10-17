import SwiftUI

enum BDMenuStyle {
    static let body = Font.system(size: 15)
    static let detail = Font.system(size: 13)
    static let section = Font.system(size: 15, weight: .semibold)
    static let title = Font.system(size: 21, weight: .semibold)
}

/// Keep the native switch's keyboard, disabled-state and accessibility behavior,
/// while giving its larger visual size enough space in the row.
struct BDMenuSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .font(BDMenuStyle.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .scaleEffect(1.2)
                .frame(width: 58, height: 36)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }
}

struct BDMenuCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background {
                Capsule().fill(.thinMaterial)
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.035))
            }
            .overlay {
                Capsule().strokeBorder(focused ? Color.accentColor : Color.primary.opacity(isEnabled ? 0.14 : 0.07),
                                       lineWidth: focused ? 2 : 1)
            }
            .contentShape(Capsule())
            .focusEffectDisabled()
            .focused($focused)
            .opacity(isEnabled ? 1 : 0.55)
    }
}

struct BDMenuCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
    }
}
