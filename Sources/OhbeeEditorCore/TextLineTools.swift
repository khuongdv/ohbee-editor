import Foundation

enum TextLineTools {
    enum LineEnding: String {
        case lf = "\n"
        case crlf = "\r\n"
        case cr = "\r"
    }

    static func splitLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    static func preferredLineEnding(in text: String) -> LineEnding {
        let crlfCount = text.components(separatedBy: "\r\n").count - 1
        let withoutCRLF = text.replacingOccurrences(of: "\r\n", with: "")
        let lfCount = withoutCRLF.components(separatedBy: "\n").count - 1
        let crCount = withoutCRLF.components(separatedBy: "\r").count - 1

        if crlfCount >= lfCount && crlfCount >= crCount && crlfCount > 0 {
            return .crlf
        }

        if crCount > lfCount {
            return .cr
        }

        return .lf
    }

    static func hasTerminalLineEnding(_ text: String) -> Bool {
        text.hasSuffix("\n") || text.hasSuffix("\r")
    }

    static func joinLinesPreservingTerminalLineEnding(_ lines: [String], originalText: String) -> String {
        let lineEnding = preferredLineEnding(in: originalText).rawValue
        let joined = lines.joined(separator: lineEnding)
        guard !joined.isEmpty, hasTerminalLineEnding(originalText) else {
            return joined
        }

        return joined + lineEnding
    }
}
