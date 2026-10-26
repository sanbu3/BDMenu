import AppKit
import SwiftUI

@MainActor
final class DisplayIdentification {
    private var panels: [NSPanel] = []
    private var hideTask: Task<Void, Never>?

    func show(displays: [DisplayManager.DisplayInfo], guiding id: CGDirectDisplayID? = nil) {
        stop()
        for (index, display) in displays.filter(\.enabled).enumerated() {
            guard id == nil || id == display.id,
                  let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id }) else { continue }
            let guide = id != nil
            let size = NSSize(width: guide ? 380 : 300, height: guide ? 110 : 140)
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = guide ? "BDMenu Dock 呼出引导" : "BDMenu 屏幕识别"
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: IdentificationView(number: index + 1, name: display.name, guide: guide).frame(width: size.width, height: size.height))
            host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = host
            panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                y: guide ? screen.visibleFrame.minY + 40 : screen.frame.midY - size.height / 2,
                width: size.width, height: size.height), display: true)
            panels.append(panel); panel.orderFrontRegardless()
        }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(id == nil ? 3 : 6)) } catch { return }
            self?.stop()
        }
    }
    func stop() { hideTask?.cancel(); hideTask = nil; panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
}

private struct IdentificationView: View {
    let number: Int
    let name: String
    let guide: Bool
    var body: some View {
        VStack(spacing: 8) {
            if guide {
                Label("在这块屏幕呼出 Dock", systemImage: "dock.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                Text("沿这块屏幕露出的底边，继续向下移动鼠标。")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                Text("\(number)").font(.system(size: 42, weight: .semibold, design: .rounded)).foregroundStyle(.blue)
                Text(name).font(.system(size: 17, weight: .medium)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
