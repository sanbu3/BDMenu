import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct CommandResult: Sendable {
    public var output: String
    public var error: String
    public var status: Int32
    public var timedOut: Bool
    public var succeeded: Bool { status == 0 && !timedOut }
}

public enum CommandRunner {
    /// Run on a worker queue. File-backed output avoids pipe-buffer deadlocks.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 4) -> CommandResult {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BDMenu-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: folder) }
            let stdoutURL = folder.appendingPathComponent("stdout")
            let stderrURL = folder.appendingPathComponent("stderr")
            _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer { try? stdout.close(); try? stderr.close() }
            let process = Process()
            let finished = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            let timedOut = finished.wait(timeout: .now() + max(0.05, timeout)) == .timedOut
            if timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            func read(_ url: URL) -> String {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 2 * 1024 * 1024)) ?? Data()
                return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return CommandResult(output: read(stdoutURL), error: read(stderrURL),
                                 status: process.terminationStatus, timedOut: timedOut)
        } catch {
            return CommandResult(output: "", error: error.localizedDescription, status: -1, timedOut: false)
        }
    }
}
