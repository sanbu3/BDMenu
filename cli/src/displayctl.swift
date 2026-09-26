import Foundation
import CoreGraphics

func loadSymbol(_ paths: [String], _ symbol: String) -> UnsafeMutableRawPointer? {
    for p in paths {
        if let h = dlopen(p, RTLD_LAZY) {
            return dlsym(h, symbol)
        }
    }
    return nil
}

let coreDisplayPaths = [
    "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
    "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
]
let displayServicesPaths = [
    "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
]

typealias DSGet = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DSSet = @convention(c) (CGDirectDisplayID, Float) -> Int32
typealias CDGet = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Void
typealias CDSet = @convention(c) (CGDirectDisplayID, Double) -> Void
typealias CDInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?

func brightnessGet(_ id: CGDirectDisplayID) -> Double? {
    if let sym = loadSymbol(displayServicesPaths, "DisplayServicesGetBrightness") {
        let fn = unsafeBitCast(sym, to: DSGet.self)
        var v: Float = -1
        if fn(id, &v) == 0, v >= 0 { return Double(v) }
    }
    if let sym = loadSymbol(coreDisplayPaths, "CoreDisplay_Display_GetUserBrightness") {
        let fn = unsafeBitCast(sym, to: CDGet.self)
        var v: Double = -1
        fn(id, &v)
        if v >= 0 { return v }
    }
    return nil
}

func brightnessSet(_ id: CGDirectDisplayID, _ value: Double) -> Bool {
    if let sym = loadSymbol(displayServicesPaths, "DisplayServicesSetBrightness") {
        let fn = unsafeBitCast(sym, to: DSSet.self)
        if fn(id, Float(value)) == 0 { return true }
    }
    if let sym = loadSymbol(coreDisplayPaths, "CoreDisplay_Display_SetUserBrightness") {
        let fn = unsafeBitCast(sym, to: CDSet.self)
        fn(id, value)
        return true
    }
    return false
}

func displayInfo(_ id: CGDirectDisplayID) -> [String: Any]? {
    guard let sym = loadSymbol(coreDisplayPaths, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
    let fn = unsafeBitCast(sym, to: CDInfo.self)
    return fn(id)?.takeRetainedValue() as? [String: Any]
}

func displayName(_ info: [String: Any]) -> String {
    if let names = info["DisplayProductName"] as? [String: String] {
        if let n = names["en_US"] ?? names["en"] ?? names.first?.value, !n.isEmpty { return n }
    }
    if let n = info["DisplayName"] as? String, !n.isEmpty { return n }
    return "Unknown"
}

func displayUUID(_ info: [String: Any]) -> String {
    (info["kCGDisplayUUID"] as? String) ?? ""
}

struct DisplayRow {
    var id: CGDirectDisplayID
    var builtin: Bool
    var uuid: String
    var name: String
    var brightness: Double?
}

func onlineDisplays() -> [DisplayRow] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(32, &ids, &count)
    var rows: [DisplayRow] = []
    for i in 0..<Int(count) {
        let id = ids[i]
        let info = displayInfo(id) ?? [:]
        rows.append(DisplayRow(
            id: id,
            builtin: CGDisplayIsBuiltin(id) != 0,
            uuid: displayUUID(info),
            name: displayName(info),
            brightness: brightnessGet(id)
        ))
    }
    return rows
}

func printList() {
    for r in onlineDisplays() {
        let b = r.brightness.map { String(format: "%.1f", $0 * 100) } ?? "-"
        print("\(r.id)\t\(r.builtin ? 1 : 0)\t\(r.uuid)\t\(r.name)\t\(b)")
    }
}

let args = CommandLine.arguments
if args.count < 2 || args[1] == "list" {
    printList()
} else if args[1] == "get" {
    guard args.count >= 3, let id = UInt32(args[2]) else { exit(2) }
    if let b = brightnessGet(id) {
        print(String(format: "%.1f", b * 100))
    } else {
        FileHandle.standardError.write(Data("cannot read brightness of display \(id)\n".utf8))
        exit(1)
    }
} else if args[1] == "set" {
    guard args.count >= 4, let id = UInt32(args[2]), let v = Double(args[3]), (0...100).contains(v) else { exit(2) }
    if brightnessSet(id, v / 100.0) {
        print("ok")
    } else {
        FileHandle.standardError.write(Data("cannot set brightness of display \(id)\n".utf8))
        exit(1)
    }
} else {
    print("usage: displayctl [list|get <id>|set <id> <0-100>]")
    exit(2)
}
