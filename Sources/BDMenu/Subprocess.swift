import Foundation
import DisplayCore
import os

enum Subprocess {
    private static let queue = DispatchQueue(label: "com.local.BDMenu.commands", qos: .userInitiated)
    private static let logger = Logger(subsystem: "com.local.BDMenu", category: "Commands")
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 4) async -> CommandResult {
        let path = Bundle.main.url(forResource: tool, withExtension: nil)?.path ?? ""
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = CommandRunner.run(path, arguments, timeout: timeout)
                if !result.succeeded {
                    logger.error("\(tool, privacy: .public) failed (\(result.status), timeout=\(result.timedOut)): \(result.error, privacy: .public)")
                }
                continuation.resume(returning: result)
            }
        }
    }
}
