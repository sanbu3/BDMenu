import Foundation
import CoreGraphics
import os.log

enum PrivateAPI {

    static func load(_ paths: [String], _ symbol: String) -> UnsafeMutableRawPointer? {
        for p in paths {
            if let h = dlopen(p, RTLD_LAZY) {
                if let address = dlsym(h, symbol) { return address }
                dlclose(h)
            }
        }
        return nil
    }

    static let coreDisplayPaths = [
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
    ]
    static let skyLightPaths = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
    ]
    static let displayServicesPaths = [
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
    ]

    typealias CDInfoFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    static var cdInfo: CDInfoFn? = {
        guard let s = load(coreDisplayPaths, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(s, to: CDInfoFn.self)
    }()

    static func displayInfo(_ id: CGDirectDisplayID) -> [String: Any]? {
        cdInfo?(id)?.takeRetainedValue() as? [String: Any]
    }

    typealias CGSGetDisplayListFn = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    static var cgsList: CGSGetDisplayListFn? = {
        guard let s = load(skyLightPaths, "CGSGetDisplayList") else { return nil }
        return unsafeBitCast(s, to: CGSGetDisplayListFn.self)
    }()

    typealias CGSConfigureDisplayEnabledFn = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError
    static var cgsEnabled: CGSConfigureDisplayEnabledFn? = {
        guard let s = load(skyLightPaths, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(s, to: CGSConfigureDisplayEnabledFn.self)
    }()

    static func allDisplayIDs() -> [CGDirectDisplayID] {
        guard let fn = cgsList else {
            var ids = [CGDirectDisplayID](repeating: 0, count: 64)
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return [] }
            return Array(ids.prefix(Int(count)))
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard fn(64, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func setDisplayEnabled(id: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard let fn = cgsEnabled else {
            os_log("BDMenu: cgsEnabled symbol missing")
            return false
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
            os_log("BDMenu: CGBeginDisplayConfiguration failed")
            return false
        }
        let r = fn(cfg, id, enabled)
        guard r == .success else {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(cfg, .forSession)
        os_log("BDMenu: setDisplayEnabled id=%{public}d enabled=%{public}d -> %{public}d/%{public}d", id, enabled ? 1 : 0, r.rawValue, complete.rawValue)
        return r == .success && complete == .success
    }

    typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    static var dsGet: DSGetBrightnessFn? = {
        guard let s = load(displayServicesPaths, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(s, to: DSGetBrightnessFn.self)
    }()
    static var dsSet: DSSetBrightnessFn? = {
        guard let s = load(displayServicesPaths, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(s, to: DSSetBrightnessFn.self)
    }()

    static func getBrightness(_ id: CGDirectDisplayID) -> Double? {
        guard let fn = dsGet else { return nil }
        var v: Float = -1
        guard fn(id, &v) == 0, v >= 0 else { return nil }
        return Double(v)
    }

    static func setBrightness(_ id: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let fn = dsSet else { return false }
        guard value.isFinite else { return false }
        return fn(id, Float(min(1, max(0, value)))) == 0
    }
}
