import Foundation

public enum EditorFileError: LocalizedError {
    case unreadableText

    public var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "The selected file could not be read as text."
        }
    }
}

public struct EditorFileIO {
    public init() {}

    public func openDocument(from fileURL: URL) throws -> EditorDocument {
        let text = try readText(from: fileURL)
        let now = Date()

        return EditorDocument(
            id: UUID(),
            title: fileURL.lastPathComponent,
            text: text,
            fileURL: fileURL,
            isScratch: false,
            isDirty: false,
            createdAt: now,
            updatedAt: now
        )
    }

    public func save(_ document: EditorDocument, to fileURL: URL) throws {
        try document.text.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func readText(from fileURL: URL) throws -> String {
        if let utf8Text = try? String(contentsOf: fileURL, encoding: .utf8) {
            return utf8Text
        }

        var detectedEncoding = String.Encoding.utf8
        if let text = try? String(contentsOf: fileURL, usedEncoding: &detectedEncoding) {
            return text
        }

        throw EditorFileError.unreadableText
    }
}
