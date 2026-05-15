import Foundation

public enum JSONTools {
    private enum ParseResult {
        case success(Any)
        case failure(String)
    }

    public static func format(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter JSON to format.")
        }

        switch parse(text) {
        case let .success(object):
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
                )
                let formatted = String(decoding: data, as: UTF8.self)
                return .success(text: formatted, summary: "Formatted JSON.")
            } catch {
                return .failure(message: "Could not format JSON.")
            }
        case let .failure(message):
            return .failure(message: message)
        }
    }

    public static func minify(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter JSON to minify.")
        }

        switch parse(text) {
        case let .success(object):
            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
                let minified = String(decoding: data, as: UTF8.self)
                return .success(text: minified, summary: "Minified JSON.")
            } catch {
                return .failure(message: "Could not minify JSON.")
            }
        case let .failure(message):
            return .failure(message: message)
        }
    }

    public static func validate(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter JSON to validate.")
        }

        switch parse(text) {
        case .success:
            return .success(text: text, summary: "Valid JSON.")
        case let .failure(message):
            return .failure(message: message)
        }
    }

    private static func parse(_ text: String) -> ParseResult {
        guard let data = text.data(using: .utf8) else {
            return .failure("JSON must be valid UTF-8 text.")
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return .success(object)
        } catch {
            return .failure("Invalid JSON: \(error.localizedDescription)")
        }
    }
}
