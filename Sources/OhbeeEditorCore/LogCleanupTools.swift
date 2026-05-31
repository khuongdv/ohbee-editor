import Foundation

public enum LogCleanupTools {
    public static func keepLines(containing query: String, caseSensitive: Bool = false) -> (String) -> TextTransformResult {
        { text in
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty else {
                return .failure(message: "Enter text to keep lines by.")
            }

            let lines = effectiveLines(in: text)
            let kept = lines.filter { lineContains($0, query: normalizedQuery, caseSensitive: caseSensitive) }

            return .success(
                text: TextLineTools.joinLinesPreservingTerminalLineEnding(kept, originalText: text),
                summary: lineSummary("Kept", count: kept.count)
            )
        }
    }

    public static func removeLines(containing query: String, caseSensitive: Bool = false) -> (String) -> TextTransformResult {
        { text in
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty else {
                return .failure(message: "Enter text to remove lines by.")
            }

            let lines = effectiveLines(in: text)
            let kept = lines.filter { !lineContains($0, query: normalizedQuery, caseSensitive: caseSensitive) }
            let removedCount = lines.count - kept.count

            return .success(
                text: TextLineTools.joinLinesPreservingTerminalLineEnding(kept, originalText: text),
                summary: lineSummary("Removed", count: removedCount)
            )
        }
    }

    public static func extractURLs(_ text: String) -> TextTransformResult {
        extractedResult(
            URLTools.extractURLStrings(in: text),
            emptyMessage: "No URLs found.",
            summaryName: "URL"
        )
    }

    public static func extractIPv4Addresses(_ text: String) -> TextTransformResult {
        let candidates = matches(in: text, pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#)
        let addresses = candidates.filter { candidate in
            candidate.split(separator: ".").allSatisfy { part in
                guard let value = Int(part) else { return false }
                return value >= 0 && value <= 255
            }
        }

        return extractedResult(addresses, emptyMessage: "No IPv4 addresses found.", summaryName: "IPv4 address")
    }

    public static func removeTimestampPrefixes(_ text: String) -> TextTransformResult {
        let lines = effectiveLines(in: text)

        let cleaned = lines.map { line in
            timestampPrefixRegexes.reduce(line) { current, regex in
                let source = current as NSString
                let range = NSRange(location: 0, length: source.length)
                return regex.stringByReplacingMatches(in: current, options: [], range: range, withTemplate: "")
            }
        }
        let changedCount = zip(lines, cleaned).filter { $0 != $1 }.count

        return .success(
            text: TextLineTools.joinLinesPreservingTerminalLineEnding(cleaned, originalText: text),
            summary: lineSummary("Removed timestamp prefix from", count: changedCount)
        )
    }

    private static func extractedResult(
        _ values: [String],
        emptyMessage: String,
        summaryName: String
    ) -> TextTransformResult {
        guard !values.isEmpty else {
            return .failure(message: emptyMessage)
        }

        let uniqueValues = stableUnique(values)
        let summary = uniqueValues.count == 1
            ? "Extracted 1 \(summaryName)."
            : "Extracted \(uniqueValues.count) \(summaryName)s."

        return .success(text: uniqueValues.joined(separator: "\n"), summary: summary)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }

        return result
    }

    private static func lineContains(_ line: String, query: String, caseSensitive: Bool) -> Bool {
        line.range(
            of: query,
            options: caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private static func effectiveLines(in text: String) -> [String] {
        var lines = TextLineTools.splitLines(text)
        if TextLineTools.hasTerminalLineEnding(text), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func lineSummary(_ verb: String, count: Int) -> String {
        count == 1 ? "\(verb) 1 line." : "\(verb) \(count) lines."
    }

    private static let timestampPrefixRegexes: [NSRegularExpression] = [
        #"^\s*\[\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\]\s*"#,
        #"^\s*\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s*"#,
        #"^\s*\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s+"#
    ].map { pattern in
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid timestamp prefix regex: \(error.localizedDescription)")
        }
    }
}
