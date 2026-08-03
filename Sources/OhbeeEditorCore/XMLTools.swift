import Foundation

public enum XMLTools {
    private static func rejectsEntityDeclarations(_ text: String) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            let suffix = text[index...]
            if suffix.hasPrefix("<!--") {
                index = suffix.range(of: "-->")?.upperBound ?? text.endIndex
                continue
            }
            if suffix.hasPrefix("<![CDATA[") {
                index = suffix.range(of: "]]>")?.upperBound ?? text.endIndex
                continue
            }
            let declarationPrefix = String(suffix.prefix(10)).uppercased()
            if declarationPrefix.hasPrefix("<!DOCTYPE") || declarationPrefix.hasPrefix("<!ENTITY") {
                return true
            }
            index = text.index(after: index)
        }
        return false
    }

    public static func format(_ text: String) -> TextTransformResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Enter XML to format.")
        }
        guard !rejectsEntityDeclarations(text) else {
            return .failure(message: "XML document type and entity declarations are not supported.")
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
        guard !rejectsEntityDeclarations(text) else {
            return .failure(message: "XML document type and entity declarations are not supported.")
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
