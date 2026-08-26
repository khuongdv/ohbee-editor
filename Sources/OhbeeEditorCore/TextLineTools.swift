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

    /// Scalar comparison is required: `"\r\n"` is a single Swift `Character`, so
    /// `hasSuffix("\n")` is false for CRLF text and would drop its terminal line ending.
    static func hasTerminalLineEnding(_ text: String) -> Bool {
        guard let lastScalar = text.unicodeScalars.last else {
            return false
        }

        return lastScalar == "\n" || lastScalar == "\r"
    }

    /// Lines without the empty element that a terminal line ending produces. Transforms work
    /// on these so a trailing newline is never sorted, deduplicated, or counted as a line, and
    /// is restored by `joinLinesPreservingTerminalLineEnding`.
    static func contentLines(in text: String) -> [String] {
        var lines = splitLines(text)
        if hasTerminalLineEnding(text), lines.last == "" {
            lines.removeLast()
        }

        return lines
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
