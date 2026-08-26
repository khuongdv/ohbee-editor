import Foundation

public struct SafeShareFinding: Equatable {
    public let category: String
    public let range: NSRange
    public let text: String
    /// 1-based line of `range` in the reviewed text. Lets the review sheet tell two findings of
    /// the same category apart without showing any part of either value.
    public let line: Int
}

public struct SafeShareCategorySummary: Equatable, Identifiable {
    public var id: String { category }

    public let category: String
    public let count: Int
}

public struct SafeShareReview: Equatable {
    public let sourceText: String
    public let findings: [SafeShareFinding]
    public let maskedText: String

    public var hasFindings: Bool {
        !findings.isEmpty
    }

    public var categorySummaries: [SafeShareCategorySummary] {
        Dictionary(grouping: findings, by: \.category)
            .map { SafeShareCategorySummary(category: $0.key, count: $0.value.count) }
            .sorted { first, second in
                if first.count == second.count {
                    return first.category < second.category
                }

                return first.count > second.count
            }
    }

    public var copyableFindingsSummary: String {
        guard hasFindings else {
            return "No obvious sensitive patterns found."
        }

        let categories = categorySummaries
            .map { "\($0.count) \(displayName(for: $0))" }
            .joined(separator: ", ")
        return "Potential sensitive text found: \(categories)."
    }

    public func maskedText(includingFindingIndexes indexes: Set<Int>) -> String {
        let selectedFindings = findings.enumerated().compactMap { index, finding in
            indexes.contains(index) ? finding : nil
        }
        return SafeShare.maskedText(for: sourceText, findings: selectedFindings)
    }

    private func displayName(for summary: SafeShareCategorySummary) -> String {
        summary.count == 1 ? summary.category : "\(summary.category)s"
    }
}

public enum SafeShare {
    private struct Detector {
        let category: String
        let regex: NSRegularExpression
        /// Second-stage check for patterns that regex alone cannot keep conservative.
        let isPlausible: (String) -> Bool

        init(
            category: String,
            pattern: String,
            isPlausible: @escaping (String) -> Bool = { _ in true }
        ) {
            self.category = category
            self.isPlausible = isPlausible
            do {
                self.regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } catch {
                preconditionFailure("Invalid Safe Share regex for \(category): \(error)")
            }
        }
    }

    private static let detectors: [Detector] = [
        Detector(category: "Bearer token", pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"#),
        Detector(category: "JWT-like token", pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#),
        Detector(category: "Email", pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#),
        // Dots and colons are excluded so timestamps, IP addresses, decimals, and version
        // strings can never match; the shape check below rejects bare digit runs and dates.
        Detector(
            category: "Phone number",
            pattern: #"(?<![\w.:+-])(?:\+?\d[\d ()-]{6,16}\d)(?![\w-])(?!\.\d)(?!:\d)"#,
            isPlausible: isPlausiblePhoneNumber
        ),
        Detector(category: ".env secret", pattern: #"(?im)^\s*[A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY)[A-Z0-9_]*\s*=\s*["']?[^"'\s#]{6,}"#),
        Detector(category: "API key", pattern: #"(?i)\b(?:api[_-]?key|secret|token|password)\b\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{12,}"#),
        Detector(category: "JSON secret", pattern: #"(?i)"(?:api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token|secret|client[_-]?secret|password|private[_-]?key)"\s*:\s*"[^"\s]{12,}""#),
        Detector(category: "API key", pattern: #"\b(?:sk|pk|ghp|gho|github_pat)[-_][A-Za-z0-9_=-]{16,}\b"#),
        Detector(category: "Token URL parameter", pattern: #"(?i)([?&](?:access_token|auth_token|token|api_key|apikey|key|secret|password)=)[^&#\s]{6,}"#)
    ]

    public static func detect(in text: String) -> [SafeShareFinding] {
        let sorted = detectors
            .flatMap { detector in
                findings(for: detector, in: text)
            }
            .sorted { first, second in
                if first.range.location == second.range.location {
                    return first.range.length > second.range.length
                }

                return first.range.location < second.range.location
            }

        return assigningLineNumbers(to: sorted, in: text)
    }

    /// Single forward scan: findings are already sorted by location, so line numbers cost one
    /// pass over the text instead of one pass per finding.
    private static func assigningLineNumbers(
        to findings: [SafeShareFinding],
        in text: String
    ) -> [SafeShareFinding] {
        guard !findings.isEmpty else {
            return findings
        }

        let source = text as NSString
        let newline: unichar = 10
        let carriageReturn: unichar = 13
        var line = 1
        var scanIndex = 0

        return findings.map { finding in
            while scanIndex < finding.range.location, scanIndex < source.length {
                let character = source.character(at: scanIndex)
                if character == newline {
                    line += 1
                } else if character == carriageReturn {
                    // Count CRLF once.
                    let nextIndex = scanIndex + 1
                    if nextIndex >= source.length || source.character(at: nextIndex) != newline {
                        line += 1
                    }
                }
                scanIndex += 1
            }

            return SafeShareFinding(
                category: finding.category,
                range: finding.range,
                text: finding.text,
                line: line
            )
        }
    }

    public static func maskDetectedPatterns(_ text: String) -> TextTransformResult {
        let findings = nonOverlappingFindings(in: text)
        guard !findings.isEmpty else {
            return .success(text: text, summary: "No potential sensitive text found.")
        }

        let masked = maskedText(for: text, findings: findings)

        let summary = findings.count == 1
            ? "Masked 1 potential sensitive item."
            : "Masked \(findings.count) potential sensitive items."
        return .success(text: masked, summary: summary)
    }

    public static func detectionSummary(in text: String) -> String {
        let findings = nonOverlappingFindings(in: text)
        guard !findings.isEmpty else {
            return "No obvious sensitive patterns found."
        }

        let categories = Set(findings.map(\.category)).sorted().joined(separator: ", ")
        return "Potential sensitive text found: \(findings.count) item(s). \(categories)."
    }

    public static func review(in text: String) -> SafeShareReview {
        let findings = nonOverlappingFindings(in: text)
        return SafeShareReview(
            sourceText: text,
            findings: findings,
            maskedText: maskedText(for: text, findings: findings)
        )
    }

    /// Review rows describe where the finding is without echoing any part of the value, and
    /// without leaking its exact length.
    public static func maskedSnippet(for finding: SafeShareFinding) -> String {
        "line \(finding.line) -> \(Self.redactionPlaceholder)"
    }

    private static func findings(for detector: Detector, in text: String) -> [SafeShareFinding] {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        return detector.regex.matches(in: text, range: range).compactMap { match in
            let matchedText = source.substring(with: match.range)
            guard detector.isPlausible(matchedText) else {
                return nil
            }

            return SafeShareFinding(
                category: detector.category,
                range: match.range,
                text: matchedText,
                line: 0
            )
        }
    }

    /// Conservative phone-number shape check. Ohbee Editor is used on logs, so a false
    /// positive here would redact real data; false negatives are the safer failure.
    static func isPlausiblePhoneNumber(_ text: String) -> Bool {
        let digitCount = text.filter(\.isNumber).count
        guard (8...15).contains(digitCount) else {
            return false
        }

        // yyyy-mm-dd / dd-mm-yyyy and their space-separated forms are dates, not numbers.
        let datePatterns = [#"^\d{4}[ -]\d{1,2}[ -]\d{1,2}$"#, #"^\d{1,2}[ -]\d{1,2}[ -]\d{4}$"#]
        for pattern in datePatterns where text.range(of: pattern, options: .regularExpression) != nil {
            return false
        }

        let hasInternationalPrefix = text.hasPrefix("+")
        let groups = text
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)

        // A bare digit run is an order, ticket, or record number far more often than a phone.
        guard hasInternationalPrefix || groups.count > 1 else {
            return false
        }

        // Long chains of groups, or groups wider than a dialable segment, are numeric lists.
        let maximumGroupCount = hasInternationalPrefix ? 4 : 3
        guard groups.count <= maximumGroupCount else {
            return false
        }

        guard groups.count > 1 else {
            return true
        }

        return groups.dropFirst().allSatisfy { $0.count <= 4 }
    }

    private static func nonOverlappingFindings(in text: String) -> [SafeShareFinding] {
        var result: [SafeShareFinding] = []
        for finding in detect(in: text) {
            guard !result.contains(where: { NSIntersectionRange($0.range, finding.range).length > 0 }) else {
                continue
            }

            result.append(finding)
        }

        return result
    }

    public static func maskedText(for text: String, findings: [SafeShareFinding]) -> String {
        var masked = text
        for finding in findings.reversed() {
            masked = (masked as NSString).replacingCharacters(
                in: finding.range,
                with: Self.redactionPlaceholder
            )
        }

        return masked
    }

    /// Fixed-width redaction. Keeping a prefix or suffix of a token narrows the search space
    /// for whoever receives the text, and the original length is itself a hint, so neither is
    /// preserved.
    public static let redactionPlaceholder = "***REDACTED***"
}
