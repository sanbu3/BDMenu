import Foundation

public struct DisplayConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var arguments: [String]
    public var layouts: [DisplayLayout]
    public var profiles: [String: String]
    public var updated: Date
    public init(name: String, snapshot: DisplaySnapshot, profiles: [String: String]) {
        id = UUID(); self.name = name; arguments = snapshot.arguments
        layouts = snapshot.layouts; self.profiles = profiles; updated = Date()
    }
    public var screenIDs: Set<String> { Set(layouts.map(\.uuid)) }
    public func isSupported(by snapshot: DisplaySnapshot) -> Bool {
        layouts.filter(\.enabled).allSatisfy { layout in
            // A disabled known panel has no mode list until it has been woken.
            if snapshot.layouts.contains(where: { $0.uuid == layout.uuid && !$0.enabled }),
               snapshot.modes[layout.uuid] == nil { return true }
            return snapshot.modes[layout.uuid]?.contains { mode in
                mode.width == layout.width && mode.height == layout.height
                    && mode.scaling == layout.scaling && mode.hertz == layout.hertz
            } == true
        }
    }
    public func hasSameLayout(as snapshot: DisplaySnapshot) -> Bool {
        Set(snapshot.layouts.map(\.uuid)) == screenIDs && layouts.allSatisfy { wanted in
            snapshot.layouts.contains { value in
                value.uuid == wanted.uuid && value.enabled == wanted.enabled
                    && (!wanted.enabled || (value.width == wanted.width && value.height == wanted.height
                        && value.hertz == wanted.hertz && value.scaling == wanted.scaling
                        && value.x == wanted.x && value.y == wanted.y && value.rotation == wanted.rotation))
            }
        }
    }
    public func matches(_ connected: Set<String>) -> Bool {
        !connected.isEmpty && screenIDs == connected
            && DisplaySnapshot.canRestore(arguments, connectedIDs: connected)
    }
}

