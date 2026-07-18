import Foundation

public enum RegexSearchError: Error, LocalizedError {
    case patternTooLong
    case matchingTimedOut

    public var errorDescription: String? {
        switch self {
        case .patternTooLong:
            return "Regex pattern is too long (max 1000 characters)."
        case .matchingTimedOut:
            return "Regex matching timed out. Simplify your pattern."
        }
    }
}

public struct SearchOptions: Equatable {
    public var query: String
    public var replacement: String
    public var usesRegex: Bool
    public var isCaseSensitive: Bool
    public var isWholeWord: Bool

    public init(
        query: String = "",
        replacement: String = "",
        usesRegex: Bool = false,
        isCaseSensitive: Bool = false,
        isWholeWord: Bool = false
    ) {
        self.query = query
        self.replacement = replacement
        self.usesRegex = usesRegex
        self.isCaseSensitive = isCaseSensitive
        self.isWholeWord = isWholeWord
    }
}

public struct SearchSummary: Equatable {
    public var matchCount: Int
    public var currentMatchIndex: Int?
    public var hasInvalidRegex: Bool

    public init(matchCount: Int, currentMatchIndex: Int?, hasInvalidRegex: Bool = false) {
        self.matchCount = matchCount
        self.currentMatchIndex = currentMatchIndex
        self.hasInvalidRegex = hasInvalidRegex
    }

    public var displayText: String {
        if hasInvalidRegex {
            return "Invalid pattern"
        }

        guard matchCount > 0, let currentMatchIndex else {
            return matchCount == 0 ? "No matches" : "\(matchCount) matches"
        }

        return "\(currentMatchIndex + 1) of \(matchCount)"
    }
}

public enum SearchReplaceResult: Equatable {
    case success(text: String, replacementCount: Int)
    case failure(message: String)
}

public enum SearchReplaceEngine {
    public static func matchRanges(in text: String, options: SearchOptions) -> [NSRange] {
        ranges(in: text, options: options)
    }

    public static func matchRanges(in text: String, options: SearchOptions, range: NSRange) -> [NSRange] {
        ranges(in: text, options: options, range: range)
    }

    public static func matchRange(
        in text: String,
        options: SearchOptions,
        matchIndex: Int
    ) -> NSRange? {
        let matches = ranges(in: text, options: options)
        guard matches.indices.contains(matchIndex) else {
            return nil
        }

        return matches[matchIndex]
    }

    public static func replacementText(forMatchedText source: String, options: SearchOptions) -> String {
        replacementText(source: source, options: options)
    }

    public static func summary(
        in text: String,
        options: SearchOptions,
        currentMatchIndex: Int?
    ) -> SearchSummary {
        if options.usesRegex, !options.query.isEmpty,
           (try? regularExpression(for: options)) == nil {
            return SearchSummary(matchCount: 0, currentMatchIndex: nil, hasInvalidRegex: true)
        }

        let matches = ranges(in: text, options: options)

        guard !matches.isEmpty else {
            return SearchSummary(matchCount: 0, currentMatchIndex: nil)
        }

        let index = min(max(currentMatchIndex ?? 0, 0), matches.count - 1)
        return SearchSummary(matchCount: matches.count, currentMatchIndex: index)
    }

    public static func nextMatchIndex(
        in text: String,
        options: SearchOptions,
        currentMatchIndex: Int?
    ) -> Int? {
        let count = ranges(in: text, options: options).count
        guard count > 0 else {
            return nil
        }

        return ((currentMatchIndex ?? -1) + 1) % count
    }

    public static func previousMatchIndex(
        in text: String,
        options: SearchOptions,
        currentMatchIndex: Int?
    ) -> Int? {
        let count = ranges(in: text, options: options).count
        guard count > 0 else {
            return nil
        }

        let current = currentMatchIndex ?? 0
        return (current - 1 + count) % count
    }

    public static func replaceCurrent(
        in text: String,
        options: SearchOptions,
        currentMatchIndex: Int?
    ) -> SearchReplaceResult {
        let matches = ranges(in: text, options: options)
        guard !matches.isEmpty else {
            return .success(text: text, replacementCount: 0)
        }

        let index = min(max(currentMatchIndex ?? 0, 0), matches.count - 1)
        let range = matches[index]
        let source = text as NSString
        let replacement = replacementText(
            source: source.substring(with: range),
            options: options
        )

        return .success(
            text: source.replacingCharacters(in: range, with: replacement),
            replacementCount: 1
        )
    }

    public static func replaceAll(in text: String, options: SearchOptions) -> SearchReplaceResult {
        guard !options.query.isEmpty else {
            return .failure(message: "Enter text to find.")
        }

        if options.usesRegex || options.isWholeWord {
            do {
                let regex = try regularExpression(for: options)
                let range = NSRange(location: 0, length: (text as NSString).length)
                if options.usesRegex {
                    guard let results = timedMatches(regex: regex, in: text, range: range) else {
                        return .failure(message: "Regex matching timed out. Simplify your pattern.")
                    }
                    let count = results.count
                    // Use stringByReplacingMatches only after confirming matching completes in time
                    let replaced = regex.stringByReplacingMatches(
                        in: text,
                        range: range,
                        withTemplate: options.replacement
                    )
                    return .success(text: replaced, replacementCount: count)
                } else {
                    // Whole-word plain: literal replacement, no backreference expansion
                    guard let results = timedMatches(regex: regex, in: text, range: range) else {
                        return .failure(message: "Regex matching timed out. Simplify your pattern.")
                    }
                    let matchRanges = results.map(\.range)
                    var result = text as NSString
                    for r in matchRanges.reversed() {
                        result = result.replacingCharacters(in: r, with: options.replacement) as NSString
                    }
                    return .success(text: result as String, replacementCount: matchRanges.count)
                }
            } catch let error as RegexSearchError {
                return .failure(message: error.localizedDescription)
            } catch {
                return .failure(message: "Invalid regular expression.")
            }
        }

        let matches = ranges(in: text, options: options)
        guard !matches.isEmpty else {
            return .success(text: text, replacementCount: 0)
        }

        var result = text as NSString
        for range in matches.reversed() {
            result = result.replacingCharacters(in: range, with: options.replacement) as NSString
        }

        return .success(text: result as String, replacementCount: matches.count)
    }

    private static func ranges(in text: String, options: SearchOptions) -> [NSRange] {
        let source = text as NSString
        return ranges(in: text, options: options, range: NSRange(location: 0, length: source.length))
    }

    private static func ranges(in text: String, options: SearchOptions, range: NSRange) -> [NSRange] {
        guard !options.query.isEmpty else {
            return []
        }

        let source = text as NSString
        let boundedRange = NSIntersectionRange(
            range,
            NSRange(location: 0, length: source.length)
        )
        guard boundedRange.length > 0 else {
            return []
        }

        if options.usesRegex || options.isWholeWord {
            do {
                let regex = try regularExpression(for: options)
                guard let results = timedMatches(regex: regex, in: text, range: boundedRange) else {
                    return []  // timed out — treat as no matches
                }
                return results.map(\.range)
            } catch {
                return []
            }
        }

        var ranges: [NSRange] = []
        var searchRange = boundedRange
        let compareOptions: NSString.CompareOptions = options.isCaseSensitive ? [] : [.caseInsensitive]

        while searchRange.length > 0 {
            let foundRange = source.range(of: options.query, options: compareOptions, range: searchRange)
            guard foundRange.location != NSNotFound else {
                break
            }

            ranges.append(foundRange)
            let nextLocation = foundRange.location + max(foundRange.length, 1)
            let boundedEnd = NSMaxRange(boundedRange)
            guard nextLocation < boundedEnd else {
                break
            }
            searchRange = NSRange(
                location: nextLocation,
                length: boundedEnd - nextLocation
            )
        }

        return ranges
    }

    /// Maximum allowed length for a user-supplied regex pattern to mitigate
    /// catastrophic backtracking (ReDoS). Patterns exceeding this are rejected.
    private static let maxRegexPatternLength = 1000

    /// Time limit for a single regex matching pass (seconds). If matching exceeds
    /// this duration, the operation is abandoned and treated as zero matches.
    static let regexMatchingTimeoutSeconds: TimeInterval = 2.0

    private static func regularExpression(for options: SearchOptions) throws -> NSRegularExpression {
        let regexOptions: NSRegularExpression.Options = options.isCaseSensitive ? [] : [.caseInsensitive]
        let basePattern = options.usesRegex
            ? options.query
            : NSRegularExpression.escapedPattern(for: options.query)
        let pattern = options.isWholeWord
            ? #"(?<!\w)(?:"# + basePattern + #")(?!\w)"#
            : basePattern

        guard pattern.count <= maxRegexPatternLength else {
            throw RegexSearchError.patternTooLong
        }

        return try NSRegularExpression(pattern: pattern, options: regexOptions)
    }

    /// Performs regex matching with a timeout to prevent ReDoS from freezing the UI.
    ///
    /// NOTE: `workItem.cancel()` only sets the cancelled flag — it does not forcibly
    /// terminate the regex engine. `NSRegularExpression` does not expose a cancellation
    /// API. The background thread will continue until matching completes naturally.
    /// The purpose of this timeout is to **unblock the caller** so the UI remains
    /// responsive; the orphaned background work will finish on its own and the result
    /// is discarded. On a single-user desktop app this is acceptable — one runaway
    /// GCD task is not a security concern, only a temporary CPU cost.
    static func timedMatches(
        regex: NSRegularExpression,
        in text: String,
        range: NSRange
    ) -> [NSTextCheckingResult]? {
        var results: [NSTextCheckingResult]?
        let semaphore = DispatchSemaphore(value: 0)

        let workItem = DispatchWorkItem {
            results = regex.matches(in: text, range: range)
            semaphore.signal()
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        let outcome = semaphore.wait(timeout: .now() + regexMatchingTimeoutSeconds)

        if outcome == .timedOut {
            workItem.cancel()
            return nil
        }

        return results
    }

    private static func replacementText(source: String, options: SearchOptions) -> String {
        guard options.usesRegex else {
            return options.replacement
        }

        do {
            let regex = try regularExpression(for: options)
            let range = NSRange(location: 0, length: (source as NSString).length)
            return regex.stringByReplacingMatches(
                in: source,
                range: range,
                withTemplate: options.replacement
            )
        } catch {
            return options.replacement
        }
    }
}
