import Foundation

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
    public static func matchRange(
        in text: String,
        options: SearchOptions,
        matchIndex: Int
    ) -> NSRange? {
        let matches = matchRanges(in: text, options: options)
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

        let matches = matchRanges(in: text, options: options)

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
        let count = matchRanges(in: text, options: options).count
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
        let count = matchRanges(in: text, options: options).count
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
        let matches = matchRanges(in: text, options: options)
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
                    let count = regex.numberOfMatches(in: text, range: range)
                    let replaced = regex.stringByReplacingMatches(
                        in: text,
                        range: range,
                        withTemplate: options.replacement
                    )
                    return .success(text: replaced, replacementCount: count)
                } else {
                    // Whole-word plain: literal replacement, no backreference expansion
                    let matches = regex.matches(in: text, range: range).map(\.range)
                    var result = text as NSString
                    for r in matches.reversed() {
                        result = result.replacingCharacters(in: r, with: options.replacement) as NSString
                    }
                    return .success(text: result as String, replacementCount: matches.count)
                }
            } catch {
                return .failure(message: "Invalid regular expression.")
            }
        }

        let matches = matchRanges(in: text, options: options)
        guard !matches.isEmpty else {
            return .success(text: text, replacementCount: 0)
        }

        var result = text as NSString
        for range in matches.reversed() {
            result = result.replacingCharacters(in: range, with: options.replacement) as NSString
        }

        return .success(text: result as String, replacementCount: matches.count)
    }

    private static func matchRanges(in text: String, options: SearchOptions) -> [NSRange] {
        guard !options.query.isEmpty else {
            return []
        }

        if options.usesRegex || options.isWholeWord {
            do {
                let regex = try regularExpression(for: options)
                let range = NSRange(location: 0, length: (text as NSString).length)
                return regex.matches(in: text, range: range).map(\.range)
            } catch {
                return []
            }
        }

        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        var ranges: [NSRange] = []
        var searchRange = range
        let compareOptions: NSString.CompareOptions = options.isCaseSensitive ? [] : [.caseInsensitive]

        while searchRange.length > 0 {
            let foundRange = source.range(of: options.query, options: compareOptions, range: searchRange)
            guard foundRange.location != NSNotFound else {
                break
            }

            ranges.append(foundRange)
            let nextLocation = foundRange.location + max(foundRange.length, 1)
            searchRange = NSRange(
                location: nextLocation,
                length: source.length - nextLocation
            )
        }

        return ranges
    }

    private static func regularExpression(for options: SearchOptions) throws -> NSRegularExpression {
        let regexOptions: NSRegularExpression.Options = options.isCaseSensitive ? [] : [.caseInsensitive]
        let basePattern = options.usesRegex
            ? options.query
            : NSRegularExpression.escapedPattern(for: options.query)
        let pattern = options.isWholeWord
            ? #"(?<!\w)(?:"# + basePattern + #")(?!\w)"#
            : basePattern
        return try NSRegularExpression(pattern: pattern, options: regexOptions)
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
