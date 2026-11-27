import Foundation
import DisplayCore
import os

enum Subprocess {
    private static let queue = DispatchQueue(label: "com.local.BDMenu.commands", qos: .userInitiated)
    private static let logger = Logger(subsystem: "com.local.BDMenu", category: "Commands")
    private static let registry = CommandRegistry()
    static func cancelDisplayWrites() { registry.cancelAll() }
    static func waitForPendingCommands() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 4) async -> CommandResult {
        let path = Bundle.main.url(forResource: tool, withExtension: nil)?.path ?? ""
        let cancellation = CommandCancellation()
        let id = UUID()
        let displayWrite = tool == "displayplacer" && arguments != ["list"]
        if displayWrite { registry.insert(id, cancellation) }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                queue.async {
                    defer { if displayWrite { registry.remove(id) } }
                    let result = CommandRunner.run(path, arguments, timeout: timeout, cancellationCheck: { cancellation.isCancelled })
                    if !result.succeeded, result.status != -999 {
                        logger.error("\(tool, privacy: .public) failed (\(result.status), timeout=\(result.timedOut)): \(result.error, privacy: .public)")
                    }
                    continuation.resume(returning: result)
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
}

/// The only cross-queue mutable state is a lock-protected cancellation bit/map.
private final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
private final class CommandRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [UUID: CommandCancellation] = [:]
    func insert(_ id: UUID, _ value: CommandCancellation) { lock.lock(); commands[id] = value; lock.unlock() }
    func remove(_ id: UUID) { lock.lock(); commands.removeValue(forKey: id); lock.unlock() }
    func cancelAll() {
        lock.lock(); let pending = Array(commands.values); lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
