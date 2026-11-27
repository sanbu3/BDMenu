import Foundation
import IOKit.hid
import Observation
import IOKit.ps

/// Feature report 1 uses a report ID followed by a little-endian angle in degrees.
/// Reference: samhenrigold/LidAngleSensor (Apache-2.0); no helper process or root access.
@MainActor @Observable
final class HardwareMonitor {
    private(set) var lidAngle: Double?
    private(set) var gpuUsage: Double?
    private(set) var lidClosed: Bool?
    private(set) var onBattery = false
    private(set) var sampledAt: Date?
    @ObservationIgnored var onSample: (() -> Void)?
    @ObservationIgnored private var angleTimer: Timer?
    @ObservationIgnored private var angleDemand = false
    @ObservationIgnored var onAngle: ((Double?) -> Void)?
    @ObservationIgnored private var device: IOHIDDevice?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0

    var angleLabel: String { lidAngle.map { String(format: "%.0f°", $0) } ?? "不可用" }
    var gpuLabel: String { gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—" }

    func start() {
        guard timer == nil else { return }
        sampleSystem()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSystem() }
        }
        timer?.tolerance = 0.3
        configureAngleTimer()
    }
    func setAngleDemand(_ enabled: Bool) {
        angleDemand = enabled
        configureAngleTimer()
    }
    private func configureAngleTimer() {
        guard timer != nil, angleDemand else {
            angleTimer?.invalidate(); angleTimer = nil
            if let device { IOHIDDeviceClose(device, 0) }
            device = nil; lidAngle = nil
            return
        }
        guard angleTimer == nil else { return }
        connect(); sample()
        angleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        angleTimer?.tolerance = 0.05
    }
    func stop() {
        timer?.invalidate(); timer = nil
        angleTimer?.invalidate(); angleTimer = nil
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        lidAngle = nil; gpuUsage = nil; sampledAt = nil; lidClosed = nil
    }
    private func sampleSystem() {
        gpuUsage = Self.readGPU()
        sampledAt = Date()
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if root != 0 {
            lidClosed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            IOObjectRelease(root)
        } else { lidClosed = nil }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            onBattery = (source as String) == kIOPSBatteryPowerValue
        }
        onSample?()
    }

    private func connect() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05ac,
            kIOHIDProductIDKey: 0x8104, kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8a] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return }
        let candidate = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
        IOHIDManagerClose(manager, 0)
        if let candidate, IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess {
            device = candidate
        }
    }

    private func sample() {
        if device == nil, ticks % 20 == 0 { connect() }
        ticks &+= 1
        var angle: Double?
        if let device {
            var bytes = [UInt8](repeating: 0, count: 8)
            var length = bytes.count
            if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length) == kIOReturnSuccess,
               length >= 3, bytes[0] == 1 {
                let value = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
                if (0...180).contains(value) { angle = value }
            } else {
                IOHIDDeviceClose(device, 0)
                self.device = nil
            }
        }
        lidAngle = angle
        onAngle?(angle)
    }

    private static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var usages: [Double] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let usage = stats["Device Utilization %"] as? NSNumber,
               usage.doubleValue.isFinite, (0...100).contains(usage.doubleValue) {
                usages.append(usage.doubleValue)
            }
        }
        return usages.max()
    }
}
