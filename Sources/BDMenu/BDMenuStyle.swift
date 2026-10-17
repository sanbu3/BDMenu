import AppKit
import SwiftUI

enum BDMenuStyle {
    static let body = Font.system(size: 15)
    static let detail = Font.system(size: 13)
    static let section = Font.system(size: 16, weight: .semibold)
    static let title = Font.system(size: 25, weight: .semibold)
    static let accent = Color.blue
}

struct BDMenuBackground: View {
    var windowSurface = false
    var body: some View {
        ZStack {
            if windowSurface { WindowMaterial() }
            else { Rectangle().fill(.ultraThinMaterial) }
            RadialGradient(colors: [BDMenuStyle.accent.opacity(0.09), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 650)
        }
        .accessibilityHidden(true)
    }
}

/// Use a behind-window material for a transparent custom window. SwiftUI's
/// within-window material alone can wash out dark text contrast over a light desktop.
private struct WindowMaterial: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

struct BDMenuSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 20) {
            configuration.label
                .font(BDMenuStyle.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture { if enabled { configuration.isOn.toggle() } }
                .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .scaleEffect(1.25)
                .frame(width: 58, height: 36)
        }
        .frame(minHeight: 52)
    }
}

/// The inner native Button owns keyboard activation. Its focus outline is drawn
/// on the same capsule as the click target, rather than on a rectangular label.
struct BDMenuCapsuleButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct CapsuleButton: View {
        let configuration: PrimitiveButtonStyleConfiguration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @FocusState private var focused: Bool
        @State private var hovered = false

        var body: some View {
            Button(action: configuration.trigger) {
                configuration.label
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .padding(.horizontal, compact ? 13 : 18)
                    .frame(minHeight: compact ? 34 : 42)
                    .foregroundStyle(prominent ? Color.white : Color.primary)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focused)
            .background {
                Capsule().fill(prominent ? BDMenuStyle.accent : Color.primary.opacity(hovered ? 0.10 : 0.055))
            }
            .overlay {
                Capsule().strokeBorder(focused ? BDMenuStyle.accent : Color.primary.opacity(prominent ? 0 : 0.10),
                                       lineWidth: focused ? 2 : 1)
            }
            .onHover { hovered = $0 }
            .opacity(enabled ? 1 : 0.42)
        }
    }
}

struct BDMenuCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct StatusPill: View {
    let title: String
    var color: Color = .blue

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.10), in: Capsule())
            .fixedSize()
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(BDMenuStyle.accent)
                .frame(width: 44, height: 44)
                .background(BDMenuStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(BDMenuStyle.section)
                Text(subtitle).font(BDMenuStyle.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ErrorNotice: View {
    @Environment(DisplayManager.self) private var dm
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(BDMenuStyle.detail).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { dm.lastError = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(BDMenuCapsuleButtonStyle(compact: true))
                .accessibilityLabel("关闭提示")
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
