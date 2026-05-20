import Foundation

public enum URLTools {
    public static let trackingParameters: Set<String> = [
        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_term",
        "utm_content",
        "fbclid",
        "gclid",
        "msclkid"
    ]

    public static func encode(_ text: String) -> TextTransformResult {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: urlComponentAllowedCharacters) else {
            return .failure(message: "Could not URL encode text.")
        }

        return .success(text: encoded, summary: "URL encoded text.")
    }

    public static func decode(_ text: String) -> TextTransformResult {
        guard let decoded = text.removingPercentEncoding else {
            return .failure(message: "Could not URL decode text.")
        }

        return .success(text: decoded, summary: "URL decoded text.")
    }

    public static func removeTrackingParameters(_ text: String) -> TextTransformResult {
        var removedCount = 0
        let cleanedText = replaceURLMatches(in: text) { urlText in
            let cleaned = cleanURLString(urlText)
            removedCount += cleaned.removedCount
            return cleaned.text
        }

        let summary = removedCount == 1
            ? "Removed 1 tracking parameter."
            : "Removed \(removedCount) tracking parameters."

        return .success(text: cleanedText, summary: summary)
    }

    private static func cleanURLString(_ text: String) -> (text: String, removedCount: Int) {
        guard
            var components = URLComponents(string: text),
            let queryItems = components.queryItems,
            !queryItems.isEmpty
        else {
            return (text, 0)
        }

        let keptItems = queryItems.filter { item in
            !trackingParameters.contains(item.name.lowercased())
        }
        let removedCount = queryItems.count - keptItems.count
        guard removedCount > 0 else {
            return (text, 0)
        }

        components.queryItems = keptItems.isEmpty ? nil : keptItems
        return (components.string ?? text, removedCount)
    }

    private static func replaceURLMatches(in text: String, transform: (String) -> String) -> String {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else {
            return transform(text)
        }

        var result = text
        for match in matches.reversed() {
            let original = source.substring(with: match.range)
            let cleaned = transform(original)
            result = (result as NSString).replacingCharacters(in: match.range, with: cleaned)
        }

        return result
    }

    private static var urlComponentAllowedCharacters: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    }
}
