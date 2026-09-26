import Foundation

enum Subprocess {

    static var resourceDir: String {
        Bundle.main.resourcePath ?? Bundle.main.bundlePath + "/../Resources"
    }

    static var m1ddcBin: String { resourceDir + "/m1ddc" }
    static var displayplacerBin: String { resourceDir + "/displayplacer" }

    @discardableResult
    static func run(_ bin: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func m1ddc(_ args: [String]) -> String? {
        run(m1ddcBin, args)
    }

    static func displayplacer(_ args: [String]) -> String? {
        run(displayplacerBin, args)
    }

    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var cur = ""
        var inQuote = false
        for ch in s {
            if ch == "\"" {
                inQuote.toggle()
                continue
            }
            if ch == " " && !inQuote {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
                continue
            }
            cur.append(ch)
        }
        if !cur.isEmpty { tokens.append(cur) }
        return tokens
    }
}
