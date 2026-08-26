import Foundation

public enum RegexSearchError: Error, LocalizedError {
    case patternTooLong
    case patternNotSupported
    case inputTooLarge
    case matchingTimedOut

    public var errorDescription: String? {
        switch self {
        case .patternTooLong:
            return "Regex pattern is too long (max 1000 characters)."
        case .patternNotSupported:
            return "Regex uses a high-risk construct. Nested quantifiers such as (a+)+ and pattern backreferences are not supported."
        case .inputTooLarge:
            return "Regex search is limited to 300,000 UTF-16 characters."
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
    public var errorMessage: String?

    public init(matchCount: Int, currentMatchIndex: Int?, hasInvalidRegex: Bool = false, errorMessage: String? = nil) {
        self.matchCount = matchCount
        self.currentMatchIndex = currentMatchIndex
        self.hasInvalidRegex = hasInvalidRegex
        self.errorMessage = errorMessage
    }

    public var displayText: String {
        if let errorMessage {
            return errorMessage
        }
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

public struct SearchEvaluation: Equatable {
    public let summary: SearchSummary
    public let ranges: [NSRange]
}

public enum SearchReplaceEngine {
    private enum RegexMatchOutcome {
        case matches([NSTextCheckingResult])
        case inputTooLarge
        case timedOut
    }
    /// The single entry point for search results. `EditorStore` caches what this returns and
    /// every consumer (match count, navigation, highlighting) reads that cache.
    public static func evaluate(in text: String, options: SearchOptions, currentMatchIndex: Int?) -> SearchEvaluation {
        guard !options.query.isEmpty else {
            return SearchEvaluation(summary: SearchSummary(matchCount: 0, currentMatchIndex: nil), ranges: [])
        }
        if options.usesRegex {
            do {
                let regex = try regularExpression(for: options)
                let fullRange = NSRange(location: 0, length: (text as NSString).length)
                switch regexMatchOutcome(regex: regex, in: text, range: fullRange) {
                case .inputTooLarge:
                    return SearchEvaluation(
                        summary: SearchSummary(matchCount: 0, currentMatchIndex: nil, errorMessage: RegexSearchError.inputTooLarge.localizedDescription),
                        ranges: []
                    )
                case .timedOut:
                    return SearchEvaluation(
                        summary: SearchSummary(matchCount: 0, currentMatchIndex: nil, errorMessage: RegexSearchError.matchingTimedOut.localizedDescription),
                        ranges: []
                    )
                case let .matches(matches):
                    let ranges = matches.map(\.range)
                    let index = ranges.isEmpty ? nil : min(max(currentMatchIndex ?? 0, 0), ranges.count - 1)
                    return SearchEvaluation(
                        summary: SearchSummary(matchCount: ranges.count, currentMatchIndex: index),
                        ranges: ranges
                    )
                }
            } catch {
                return SearchEvaluation(
                    summary: SearchSummary(matchCount: 0, currentMatchIndex: nil, hasInvalidRegex: true, errorMessage: error.localizedDescription),
                    ranges: []
                )
            }
        }
        let ranges = ranges(in: text, options: options)
        let index = ranges.isEmpty ? nil : min(max(currentMatchIndex ?? 0, 0), ranges.count - 1)
        return SearchEvaluation(
            summary: SearchSummary(matchCount: ranges.count, currentMatchIndex: index),
            ranges: ranges
        )
    }

    public static func replacementText(forMatchedText source: String, options: SearchOptions) -> String {
        replacementText(source: source, options: options)
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

        if options.usesRegex {
            do {
                let regex = try regularExpression(for: options)
                let range = NSRange(location: 0, length: (text as NSString).length)
                let results: [NSTextCheckingResult]
                switch regexMatchOutcome(regex: regex, in: text, range: range) {
                    case .inputTooLarge:
                        return .failure(message: RegexSearchError.inputTooLarge.localizedDescription)
                    case .timedOut:
                        return .failure(message: RegexSearchError.matchingTimedOut.localizedDescription)
                    case let .matches(matches):
                        results = matches
                }
                var replaced = text as NSString
                for match in results.reversed() {
                        let replacement = regex.replacementString(
                            for: match,
                            in: text,
                            offset: 0,
                            template: options.replacement
                        )
                        replaced = replaced.replacingCharacters(in: match.range, with: replacement) as NSString
                }
                return .success(text: replaced as String, replacementCount: results.count)
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

        if options.usesRegex {
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

        if options.isWholeWord {
            return literalRanges(
                in: source,
                query: options.query,
                range: boundedRange,
                isCaseSensitive: options.isCaseSensitive
            ).filter { isWholeWordRange($0, in: source) }
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

    private static func literalRanges(
        in source: NSString,
        query: String,
        range: NSRange,
        isCaseSensitive: Bool
    ) -> [NSRange] {
        var results: [NSRange] = []
        var searchRange = range
        let compareOptions: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        while searchRange.length > 0 {
            let found = source.range(of: query, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            results.append(found)
            let next = NSMaxRange(found)
            guard next < NSMaxRange(range) else { break }
            searchRange = NSRange(location: next, length: NSMaxRange(range) - next)
        }
        return results
    }

    private static func isWholeWordRange(_ range: NSRange, in source: NSString) -> Bool {
        let beforeIsWord = range.location > 0 && isWordCodeUnit(source.character(at: range.location - 1))
        let end = NSMaxRange(range)
        let afterIsWord = end < source.length && isWordCodeUnit(source.character(at: end))
        return !beforeIsWord && !afterIsWord
    }

    private static func isWordCodeUnit(_ value: unichar) -> Bool {
        guard value != 95 else { return true }
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    /// Maximum allowed length for a user-supplied regex pattern to mitigate
    /// catastrophic backtracking (ReDoS). Patterns exceeding this are rejected.
    private static let maxRegexPatternLength = 1000
    private static let maxRegexInputLength = 300_000

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
        if options.usesRegex, containsHighRiskRegexConstruct(in: options.query) {
            throw RegexSearchError.patternNotSupported
        }

        return try NSRegularExpression(pattern: pattern, options: regexOptions)
    }

    /// Rejects only the constructs that actually amplify backtracking: a quantified group whose
    /// own content is quantified (`(a+)+`) and pattern backreferences. Plain groups,
    /// non-capturing groups, lookarounds, and single quantifiers stay usable, because the input
    /// cap and the match deadline already bound worst-case matching time.
    private static func containsHighRiskRegexConstruct(in pattern: String) -> Bool {
        if pattern.range(of: #"(?<!\\)\\[1-9]"#, options: .regularExpression) != nil {
            return true
        }

        return containsNestedQuantifiedGroup(in: pattern)
    }

    private static func containsNestedQuantifiedGroup(in pattern: String) -> Bool {
        let characters = Array(pattern)
        var groupContainsQuantifier: [Bool] = []
        var isInCharacterClass = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\" {
                index += 2
                continue
            }

            if isInCharacterClass {
                if character == "]" {
                    isInCharacterClass = false
                }
                index += 1
                continue
            }

            switch character {
            case "[":
                isInCharacterClass = true
            case "(":
                groupContainsQuantifier.append(false)
                if let contentIndex = groupContentIndex(characters, openParenthesisIndex: index) {
                    index = contentIndex
                    continue
                }
            case ")":
                let contentWasQuantified = groupContainsQuantifier.popLast() ?? false
                let isGroupQuantified = isUnboundedQuantifier(characters, at: index + 1)
                if contentWasQuantified, isGroupQuantified {
                    return true
                }
                // An unbounded quantifier anywhere inside this group counts for the enclosing
                // group too, so `((a+))+` is caught even though the inner group is bare.
                if contentWasQuantified || isGroupQuantified {
                    markQuantifier(in: &groupContainsQuantifier)
                }
            case "*", "+":
                markQuantifier(in: &groupContainsQuantifier)
            case "{":
                if isUnboundedRepetition(characters, openBraceIndex: index) {
                    markQuantifier(in: &groupContainsQuantifier)
                }
            default:
                break
            }

            index += 1
        }

        return false
    }

    /// Skips group-prefix syntax such as `(?:`, `(?i)`, `(?=`, `(?!`, `(?<=`, `(?<!`, `(?<name>`
    /// so the `?` in a prefix is never mistaken for a quantifier.
    private static func groupContentIndex(_ characters: [Character], openParenthesisIndex: Int) -> Int? {
        let prefixIndex = openParenthesisIndex + 1
        guard prefixIndex < characters.count, characters[prefixIndex] == "?" else {
            return nil
        }

        var index = prefixIndex + 1
        while index < characters.count {
            switch characters[index] {
            case ":", ")":
                return index
            case "=", "!", ">":
                return index + 1
            default:
                index += 1
            }
        }

        return index
    }

    /// Only quantifiers without a finite upper bound can grow the match space without limit.
    /// `{1,3}` and `{3}` are bounded, which keeps common log patterns such as
    /// `([0-9]{1,3}\.){3}[0-9]{1,3}` usable.
    private static func isUnboundedQuantifier(_ characters: [Character], at index: Int) -> Bool {
        guard index < characters.count else { return false }
        switch characters[index] {
        case "*", "+":
            return true
        case "{":
            return isUnboundedRepetition(characters, openBraceIndex: index)
        default:
            return false
        }
    }

    /// `{n,}` has no upper bound. `{n}` and `{n,m}` do. A malformed brace is treated as
    /// unbounded so the safe answer wins.
    private static func isUnboundedRepetition(_ characters: [Character], openBraceIndex: Int) -> Bool {
        var index = openBraceIndex + 1
        var body = ""
        while index < characters.count, characters[index] != "}" {
            body.append(characters[index])
            index += 1
        }

        guard index < characters.count else { return true }
        guard let commaIndex = body.firstIndex(of: ",") else {
            return body.isEmpty || Int(body) == nil
        }

        let upperBound = body[body.index(after: commaIndex)...]
        return upperBound.isEmpty
    }

    private static func markQuantifier(in groupContainsQuantifier: inout [Bool]) {
        guard !groupContainsQuantifier.isEmpty else { return }
        groupContainsQuantifier[groupContainsQuantifier.count - 1] = true
    }

    /// Enumerates with ICU progress callbacks so pathological backtracking can be stopped
    /// without leaving an uninterruptible background worker behind.
    private static func regexMatchOutcome(
        regex: NSRegularExpression,
        in text: String,
        range: NSRange
    ) -> RegexMatchOutcome {
        guard range.length <= maxRegexInputLength else { return .inputTooLarge }
        let deadline = Date().addingTimeInterval(0.1)
        var results: [NSTextCheckingResult] = []
        var timedOut = false
        regex.enumerateMatches(
            in: text,
            options: [.reportProgress],
            range: range
        ) { result, flags, stop in
            if flags.contains(.progress), Date() >= deadline {
                timedOut = true
                stop.pointee = true
                return
            }
            if let result {
                results.append(result)
            }
        }
        return timedOut ? .timedOut : .matches(results)
    }

    static func timedMatches(
        regex: NSRegularExpression,
        in text: String,
        range: NSRange
    ) -> [NSTextCheckingResult]? {
        guard case let .matches(results) = regexMatchOutcome(regex: regex, in: text, range: range) else {
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
