import Foundation

public struct DisplayMode: Equatable, Sendable, Identifiable {
    public var id: Int
    public var width: Int
    public var height: Int
    public var hertz: Int?
    public var scaling: Bool
    public var isCurrent: Bool
    public var label: String {
        "\(width) × \(height)" + (hertz.map { " · \($0) Hz" } ?? "") + (scaling ? " · HiDPI" : "")
    }
}

public struct DisplayLayout: Codable, Equatable, Sendable {
    public var uuid = ""
    public var width = 0
    public var height = 0
    public var hertz: Int?
    public var depth = 8
    public var scaling = false
    public var x = 0
    public var y = 0
    public var rotation = 0
    public var enabled = false
    public init() {}
    public var isValid: Bool {
        UUID(uuidString: uuid) != nil && (!enabled || (width > 0 && height > 0))
    }
    public var argument: String {
        guard enabled else { return "id:\(uuid) enabled:false" }
        let hz = hertz.map { " hz:\($0)" } ?? ""
        return "id:\(uuid) res:\(width)x\(height)\(hz) color_depth:\(depth) enabled:true scaling:\(scaling ? "on" : "off") origin:(\(x),\(y)) degree:\(rotation)"
    }
}

/// Parses displayplacer's documented text output; never evaluates shell commands.
public struct DisplaySnapshot: Sendable {
    public var layouts: [DisplayLayout] = []
    public var modes: [String: [DisplayMode]] = [:]
    public var arguments: [String] = []
    public init(_ output: String) {
        var current: DisplayLayout?
        func flush() {
            if let value = current, value.isValid { layouts.append(value) }
        }
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("displayplacer ") {
                arguments = Self.quotedArguments(String(line.dropFirst("displayplacer ".count))) ?? []
                continue
            }
            if line.hasPrefix("Persistent screen id:") {
                flush()
                current = DisplayLayout()
                current?.uuid = Self.value(line)
                continue
            }
            guard var record = current else { continue }
            let value = Self.value(line)
            if line.hasPrefix("Resolution:") {
                let wh = value.split(separator: "x")
                if wh.count == 2 { record.width = Int(wh[0]) ?? 0; record.height = Int(wh[1]) ?? 0 }
            } else if line.hasPrefix("Hertz:") {
                record.hertz = Int(value)
            } else if line.hasPrefix("Color Depth:") {
                record.depth = Int(value) ?? 8
            } else if line.hasPrefix("Scaling:") {
                record.scaling = value == "on"
            } else if line.hasPrefix("Origin:") {
                let origin = value.split(separator: " ").first ?? ""
                let xy = origin.trimmingCharacters(in: CharacterSet(charactersIn: "()")).split(separator: ",")
                if xy.count == 2 { record.x = Int(xy[0]) ?? 0; record.y = Int(xy[1]) ?? 0 }
            } else if line.hasPrefix("Rotation:") {
                record.rotation = Int(value.split(separator: " ").first ?? "0") ?? 0
            } else if line.hasPrefix("Enabled:") {
                record.enabled = value == "true"
            } else if line.hasPrefix("mode "), let mode = Self.parseMode(line) {
                modes[record.uuid, default: []].append(mode)
            }
            current = record
        }
        flush()
    }
    private static func value(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    private static func parseMode(_ line: String) -> DisplayMode? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3, parts[1].hasSuffix(":"), let number = Int(parts[1].dropLast()) else { return nil }
        var fields: [String: String] = [:]
        for part in parts.dropFirst(2) {
            let kv = part.split(separator: ":", maxSplits: 1)
            if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
        }
        let wh = fields["res", default: ""].split(separator: "x")
        guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]), w > 0, h > 0 else { return nil }
        return DisplayMode(id: number, width: w, height: h, hertz: fields["hz"].flatMap(Int.init),
                           scaling: fields["scaling"] == "on", isCurrent: line.contains("<-- current mode"))
    }
    public static func quotedArguments(_ text: String) -> [String]? {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String] = []
        while !remaining.isEmpty {
            guard remaining.removeFirst() == "\"", let end = remaining.firstIndex(of: "\"") else { return nil }
            let arg = String(remaining[..<end])
            guard arg.hasPrefix("id:"), !arg.contains("\n") else { return nil }
            args.append(arg)
            remaining = remaining[remaining.index(after: end)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return args.isEmpty ? nil : args
    }
    public static func referencedIDs(_ arguments: [String]) -> Set<String> {
        Set(arguments.flatMap { arg -> [String] in
            guard let first = arg.split(whereSeparator: \.isWhitespace).first, first.hasPrefix("id:") else { return [] }
            return first.dropFirst(3).split(separator: "+").map(String.init)
        })
    }
    public static func canRestore(_ arguments: [String], connectedIDs: Set<String>) -> Bool {
        let ids = referencedIDs(arguments)
        return !arguments.isEmpty && !ids.isEmpty && ids == connectedIDs
            && ids.allSatisfy { UUID(uuidString: $0) != nil }
            && arguments.contains { $0.split(whereSeparator: \.isWhitespace).contains("enabled:true") }
    }
    public static func movingMain(to uuid: String, in layouts: [DisplayLayout]) -> [DisplayLayout]? {
        guard let target = layouts.first(where: { $0.uuid == uuid && $0.enabled }) else { return nil }
        return layouts.map { item in
            var result = item
            result.x -= target.x
            result.y -= target.y
            return result
        }
    }
}
