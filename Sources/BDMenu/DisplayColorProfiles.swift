import Foundation
import CoreGraphics
import ColorSync

struct DisplayColorProfile: Identifiable, Equatable {
    var id: String
    var title: String
}

enum DisplayColorProfiles {
    static func current(_ display: CGDirectDisplayID) -> String? {
        guard let profile = ColorSyncProfileCreateWithDisplayID(display)?.takeRetainedValue(),
              let url = ColorSyncProfileGetURL(profile, nil)?.takeUnretainedValue() else { return nil }
        return (url as URL).path
    }

    static func options(_ display: CGDirectDisplayID) -> [DisplayColorProfile] {
        var paths = Set<String>()
        if let current = current(display) { paths.insert(current) }
        let roots = ["/System/Library/ColorSync/Profiles", "/Library/ColorSync/Profiles",
                     NSHomeDirectory() + "/Library/ColorSync/Profiles"]
        for root in roots {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files where ["icc", "icm"].contains(url.pathExtension.lowercased()) {
                paths.insert(url.path)
            }
        }
        let profiles = paths.sorted().compactMap { path -> DisplayColorProfile? in
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url), data.count >= 128,
                  String(data: data[16..<20], encoding: .ascii) == "RGB ",
                  ["mntr", "spac"].contains(String(data: data[12..<16], encoding: .ascii) ?? ""),
                  let profile = ColorSyncProfileCreateWithURL(url as CFURL, nil)?.takeRetainedValue() else { return nil }
            let title = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
            return DisplayColorProfile(id: path, title: title ?? url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return [DisplayColorProfile(id: "", title: "显示器出厂默认")] + profiles
    }

    static func set(_ path: String, display: CGDirectDisplayID) -> Bool {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return false }
        if !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path),
                  ColorSyncProfileCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) != nil else { return false }
        }
        let value: Any = path.isEmpty ? kCFNull! as Any : URL(fileURLWithPath: path) as CFURL
        let info = [kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String: value] as CFDictionary
        guard ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid, info) else { return false }
        return path.isEmpty || current(display) == path
    }
}
