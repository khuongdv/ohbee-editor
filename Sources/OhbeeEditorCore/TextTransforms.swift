import Foundation

public enum TextTransformResult: Equatable {
    case success(text: String, summary: String)
    case failure(message: String)
}

public enum BasicTextTransforms {
    public static func trimWhitespace(_ text: String) -> TextTransformResult {
        let lines = splitLines(text)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let changedLineCount = zip(lines, trimmedLines).filter { $0 != $1 }.count

        return .success(
            text: trimmedLines.joined(separator: "\n"),
            summary: lineSummary("Trimmed whitespace", count: changedLineCount)
        )
    }

    public static func trimTrailingWhitespace(_ text: String) -> TextTransformResult {
        let lines = splitLines(text)
        let trimmedLines = lines.map { line in
            line.replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
        }

        let changedLineCount = zip(lines, trimmedLines).filter { $0 != $1 }.count
        let summary = changedLineCount == 1
            ? "Trimmed trailing whitespace on 1 line."
            : "Trimmed trailing whitespace on \(changedLineCount) lines."

        return .success(text: trimmedLines.joined(separator: "\n"), summary: summary)
    }

    public static func removeEmptyLines(_ text: String) -> TextTransformResult {
        let lines = splitLines(text)
        let keptLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let removedCount = lines.count - keptLines.count

        return .success(
            text: keptLines.joined(separator: "\n"),
            summary: lineSummary("Removed empty", count: removedCount)
        )
    }

    public static func removeDuplicateLines(_ text: String) -> TextTransformResult {
        var seen = Set<String>()
        let lines = splitLines(text)
        let keptLines = lines.filter { line in
            if seen.contains(line) {
                return false
            }

            seen.insert(line)
            return true
        }

        return .success(
            text: keptLines.joined(separator: "\n"),
            summary: lineSummary("Removed duplicate", count: lines.count - keptLines.count)
        )
    }

    public static func sortLines(_ text: String) -> TextTransformResult {
        let lines = splitLines(text)

        return .success(
            text: lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n"),
            summary: lineSummary("Sorted", count: lines.count)
        )
    }

    public static func joinLines(_ text: String) -> TextTransformResult {
        let lines = splitLines(text)
        let joined = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return .success(
            text: joined,
            summary: lineSummary("Joined", count: lines.count)
        )
    }

    public static func lowercase(_ text: String) -> TextTransformResult {
        .success(text: text.lowercased(), summary: "Converted text to lowercase.")
    }

    public static func uppercase(_ text: String) -> TextTransformResult {
        .success(text: text.uppercased(), summary: "Converted text to uppercase.")
    }

    public static func titleCase(_ text: String) -> TextTransformResult {
        .success(text: text.localizedCapitalized, summary: "Converted text to Title Case.")
    }

    public static func snakeCase(_ text: String) -> TextTransformResult {
        .success(text: words(in: text).map(\.lowercase).joined(separator: "_"), summary: "Converted text to snake_case.")
    }

    public static func kebabCase(_ text: String) -> TextTransformResult {
        .success(text: words(in: text).map(\.lowercase).joined(separator: "-"), summary: "Converted text to kebab-case.")
    }

    public static func camelCase(_ text: String) -> TextTransformResult {
        let tokens = words(in: text)
        guard let first = tokens.first else {
            return .success(text: "", summary: "Converted text to camelCase.")
        }

        let tail = tokens.dropFirst().map { $0.lowercase.capitalized }

        return .success(
            text: ([first.lowercase] + tail).joined(),
            summary: "Converted text to camelCase."
        )
    }

    public static func cleanAIOutput(_ text: String) -> TextTransformResult {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let withoutFence = removeSurroundingCodeFence(normalized)
        let trailingTrimmed = splitLines(withoutFence).map { line in
            line.replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
        }.joined(separator: "\n")
        let compactedBlankLines = trailingTrimmed.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return .success(
            text: compactedBlankLines.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: "Cleaned AI output."
        )
    }

    private static func splitLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func lineSummary(_ verb: String, count: Int) -> String {
        count == 1 ? "\(verb) 1 line." : "\(verb) \(count) lines."
    }

    private static func words(in text: String) -> [(original: String, lowercase: String)] {
        var result: [String] = []
        var current = ""

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result.map { (original: $0, lowercase: $0.lowercased()) }
    }

    private static func removeSurroundingCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = splitLines(trimmed)

        guard
            lines.count >= 2,
            lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true,
            lines.last?.trimmingCharacters(in: .whitespaces) == "```"
        else {
            return text
        }

        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}
