import AppKit
import SwiftUI

/// A utility window whose entire visible surface belongs to the app.
final class BDMenuWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

enum WindowGeometry {
    static func resized(_ frame: CGRect, delta: CGSize, minimum: CGSize) -> CGRect {
        let width = max(minimum.width, frame.width + delta.width)
        let height = max(minimum.height, frame.height - delta.height)
        return CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
    }
}

struct WindowResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ResizeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class ResizeView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let frame = window.frame
            let start = NSEvent.mouseLocation
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .leftMouseUp { break }
                let current = NSEvent.mouseLocation
                window.setFrame(WindowGeometry.resized(frame,
                    delta: CGSize(width: current.x - start.x, height: current.y - start.y),
                    minimum: window.contentMinSize), display: true)
            }
        }
    }
}

struct WindowActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled().focused($focused)
        .background(Color.primary.opacity(hovered ? 0.12 : 0.055), in: Circle())
        .overlay(Circle().strokeBorder(focused ? Color.blue : Color.primary.opacity(0.10), lineWidth: focused ? 2 : 1))
        .onHover { hovered = $0 }
        .accessibilityLabel(label).help(label)
    }
}
