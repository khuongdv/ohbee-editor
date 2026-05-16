import Foundation

public enum XMLTools {
    public static func format(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter XML to format.")
        }

        do {
            let doc = try XMLDocument(xmlString: text, options: [])
            let formatted = doc.xmlString(options: .nodePrettyPrint)
            return .success(text: formatted, summary: "Formatted XML.")
        } catch {
            return .failure(message: "Invalid XML: \(error.localizedDescription)")
        }
    }

    public static func minify(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter XML to minify.")
        }

        do {
            let doc = try XMLDocument(xmlString: text, options: [])
            let minified = doc.xmlString(options: [])
            return .success(text: minified, summary: "Minified XML.")
        } catch {
            return .failure(message: "Invalid XML: \(error.localizedDescription)")
        }
    }
}
