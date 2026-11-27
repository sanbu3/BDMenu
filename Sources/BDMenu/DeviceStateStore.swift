import AppKit
import Observation
import DisplayCore

/// Shared, main-actor state. AX/AppKit consumers and hardware callbacks never race its revisions.
@MainActor @Observable
final class DeviceStateStore {
    let hardware = HardwareMonitor()
    private(set) var screens: [ScreenRegion] = []
    private(set) var topologyVersion = 0
    private(set) var topologyIsStable = false
    private(set) var isSleeping = false
    private(set) var frontmostBundleID = ""
    private(set) var frontmostPID: pid_t = 0
    private(set) var actionRevision = 0
    func cancelActions() { actionRevision += 1 }
    var isConfiguring = false
    var mirrored = false
    @ObservationIgnored var onTopologyStable: (() -> Void)?
    @ObservationIgnored var onTopologyWillChange: (() -> Void)?
    @ObservationIgnored var onApplicationChange: (() -> Void)?
    @ObservationIgnored var onSleepChange: ((Bool) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var stabilityTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var demands = Set<String>()

    var automaticActionsAllowed: Bool { started && !isSleeping && !isConfiguring && topologyIsStable && !mirrored }
    var mouseIsDown: Bool { NSEvent.pressedMouseButtons != 0 }
    var userIdleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }
    var frontmostIsFullscreen: Bool {
        guard let element = WindowAccessibility.focusedWindow(pid: frontmostPID) else { return false }
        return WindowAccessibility.bool(element, "AXFullScreen")
    }

    func start() {
        guard !started else { return }
        started = true
        updateApplication()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateApplication(); self?.onApplicationChange?() }
            })
        }
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isSleeping = sleeping
                    self.stabilityTask?.cancel()
                    self.topologyIsStable = false
                    if sleeping { self.hardware.stop() } else { self.hardware.start(); self.settle() }
                    self.onSleepChange?(sleeping)
                }
            })
        }
        hardware.start()
    }
    func stop() {
        started = false
        stabilityTask?.cancel(); stabilityTask = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        hardware.stop()
        topologyIsStable = false
    }
    func setAngleDemand(_ key: String, enabled: Bool) {
        if enabled { demands.insert(key) } else { demands.remove(key) }
        hardware.setAngleDemand(!demands.isEmpty)
    }
    private func updateApplication() {
        let app = NSWorkspace.shared.frontmostApplication
        frontmostBundleID = app?.bundleIdentifier ?? ""
        frontmostPID = app?.processIdentifier ?? 0
    }
    func invalidateTopology() {
        topologyVersion += 1
        topologyIsStable = false
        stabilityTask?.cancel()
        onTopologyWillChange?()
    }
    func update(displays: [DisplayManager.DisplayInfo], mirrored: Bool) {
        self.mirrored = mirrored
        // AX and CoreGraphics share top-left global coordinates. NSScreen uses a bottom-left origin.
        let primaryTop = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        })?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        let regions = displays.filter { $0.enabled && !$0.uuid.isEmpty }.map { display -> ScreenRegion in
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }
            let frame = CGDisplayBounds(display.id)
            let visible = screen.map { WindowPlacementPolicy.axRect($0.visibleFrame, primaryTop: primaryTop) } ?? frame
            return ScreenRegion(id: display.uuid, frame: frame, visibleFrame: visible)
        }.sorted { $0.id < $1.id }
        if regions != screens {
            invalidateTopology()
            screens = regions
        }
        if !topologyIsStable { settle() }
    }
    func configurationChanged(_ applying: Bool) {
        isConfiguring = applying
        if applying { invalidateTopology() } else { settle() }
    }
    private func settle() {
        stabilityTask?.cancel()
        guard started, !isSleeping, !isConfiguring else { return }
        let expected = topologyVersion
        stabilityTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, self.started, self.topologyVersion == expected,
                  !self.isConfiguring, !self.isSleeping else { return }
            self.topologyIsStable = true
            self.onTopologyStable?()
        }
    }
}
