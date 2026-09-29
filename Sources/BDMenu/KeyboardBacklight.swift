import Darwin
import Foundation
import ObjectiveC.runtime

/// Runtime adapter for the system keyboard-brightness client. The framework is
/// private and therefore treated as optional on every launch.
final class KeyboardBacklightController {
    typealias IDsFunction = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    typealias BrightnessFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    typealias BooleanFunction = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    typealias SetBrightnessFunction = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let frameworkHandle: UnsafeMutableRawPointer
    private var client: NSObject?
    private let keyboardIDs: [UInt64]
    private let brightnessFunction: BrightnessFunction
    private let setBrightnessFunction: SetBrightnessFunction
    private let brightnessSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setBrightnessSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    init?() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        var keepHandle = false
        defer {
            if !keepHandle { dlclose(handle) }
        }

        guard let objectType = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let object = objectType.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtinSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard object.responds(to: idsSelector),
              object.responds(to: brightnessSelector),
              object.responds(to: setBrightnessSelector),
              object.responds(to: builtinSelector) else { return nil }

        let idsFunction = unsafeBitCast(object.method(for: idsSelector), to: IDsFunction.self)
        let isBuiltinFunction = unsafeBitCast(object.method(for: builtinSelector), to: BooleanFunction.self)
        guard let values = idsFunction(object, idsSelector)?.takeRetainedValue() as? [NSNumber] else { return nil }
        let builtins = values.map(\.uint64Value).filter {
            isBuiltinFunction(object, builtinSelector, $0)
        }
        guard !builtins.isEmpty else { return nil }

        frameworkHandle = handle
        client = object
        keyboardIDs = builtins
        brightnessFunction = unsafeBitCast(object.method(for: brightnessSelector), to: BrightnessFunction.self)
        setBrightnessFunction = unsafeBitCast(object.method(for: setBrightnessSelector), to: SetBrightnessFunction.self)
        keepHandle = true
    }

    deinit {
        client = nil
        dlclose(frameworkHandle)
    }

    func snapshot() -> [UInt64: Float] {
        guard let client else { return [:] }
        var result: [UInt64: Float] = [:]
        for id in keyboardIDs {
            let value = brightnessFunction(client, brightnessSelector, id)
            if value.isFinite, value >= 0, value <= 1 {
                result[id] = value
            }
        }
        return result
    }

    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let client, value.isFinite else { return false }
        let clamped = min(1, max(0, value))
        var succeeded = true
        for id in keyboardIDs {
            if !setBrightnessFunction(client, setBrightnessSelector, clamped, id) {
                succeeded = false
            }
        }
        return succeeded
    }

    @discardableResult
    func restore(_ snapshot: [UInt64: Float]) -> Bool {
        guard let client else { return false }
        let currentIDs = Set(keyboardIDs)
        let targets = snapshot.filter { currentIDs.contains($0.key) }
        guard !targets.isEmpty else { return false }
        var succeeded = true
        for (id, value) in targets {
            let clamped = min(1, max(0, value))
            if !setBrightnessFunction(client, setBrightnessSelector, clamped, id) {
                succeeded = false
            }
        }
        return succeeded
    }
}
