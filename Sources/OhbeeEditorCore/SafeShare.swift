import Foundation

public struct SafeShareFinding: Equatable {
    public let category: String
    public let range: NSRange
    public let text: String
}

public enum SafeShare {
    private struct Detector {
        let category: String
        let pattern: String
    }

    private static let detectors: [Detector] = [
        Detector(category: "Bearer token", pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"#),
        Detector(category: "JWT-like token", pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#),
        Detector(category: "Email", pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#),
        Detector(category: "Phone number", pattern: #"(?<!\w)(?:\+?\d[\d .()-]{7,}\d)(?!\w)"#),
        Detector(category: ".env secret", pattern: #"(?im)^\s*[A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY)[A-Z0-9_]*\s*=\s*["']?[^"'\s#]{6,}"#),
        Detector(category: "API key", pattern: #"(?i)\b(?:api[_-]?key|secret|token|password)\b\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{12,}"#),
        Detector(category: "JSON secret", pattern: #"(?i)"(?:api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token|secret|client[_-]?secret|password|private[_-]?key)"\s*:\s*"[^"\s]{12,}""#),
        Detector(category: "API key", pattern: #"\b(?:sk|pk|ghp|gho|github_pat)[-_][A-Za-z0-9_=-]{16,}\b"#),
        Detector(category: "Token URL parameter", pattern: #"(?i)([?&](?:access_token|auth_token|token|api_key|apikey|key|secret|password)=)[^&#\s]{6,}"#)
    ]

    public static func detect(in text: String) -> [SafeShareFinding] {
        detectors.flatMap { detector in
            findings(for: detector, in: text)
        }
        .sorted { first, second in
            if first.range.location == second.range.location {
                return first.range.length > second.range.length
            }

            return first.range.location < second.range.location
        }
    }

    public static func maskDetectedPatterns(_ text: String) -> TextTransformResult {
        let findings = nonOverlappingFindings(in: text)
        guard !findings.isEmpty else {
            return .success(text: text, summary: "No potential sensitive text found.")
        }

        let source = text as NSString
        var masked = text
        for finding in findings.reversed() {
            let replacement = mask(for: source.substring(with: finding.range))
            masked = (masked as NSString).replacingCharacters(in: finding.range, with: replacement)
        }

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

    private static func findings(for detector: Detector, in text: String) -> [SafeShareFinding] {
        do {
            let regex = try NSRegularExpression(pattern: detector.pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: (text as NSString).length)
            return regex.matches(in: text, range: range).map { match in
                SafeShareFinding(
                    category: detector.category,
                    range: match.range,
                    text: (text as NSString).substring(with: match.range)
                )
            }
        } catch {
            return []
        }
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

    private static func mask(for text: String) -> String {
        guard text.count > 8 else {
            return String(repeating: "*", count: max(text.count, 4))
        }

        let prefix = text.prefix(4)
        let suffix = text.suffix(4)
        return "\(prefix)***\(suffix)"
    }
}
