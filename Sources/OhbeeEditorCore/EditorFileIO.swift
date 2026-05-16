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
        let fileSize = Self.byteCount(of: fileURL) ?? 0
        let isLargeFile = LargeFilePolicy.classify(byteCount: fileSize) != .normal

        return EditorDocument(
            id: UUID(),
            title: fileURL.lastPathComponent,
            text: text,
            fileURL: fileURL,
            isScratch: false,
            isDirty: false,
            createdAt: now,
            updatedAt: now,
            isLargeFile: isLargeFile
        )
    }

    public func save(_ document: EditorDocument, to fileURL: URL) throws {
        try document.text.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    public func readText(from fileURL: URL) throws -> String {
        if let utf8Text = try? String(contentsOf: fileURL, encoding: .utf8) {
            return utf8Text
        }

        var detectedEncoding = String.Encoding.utf8
        if let text = try? String(contentsOf: fileURL, usedEncoding: &detectedEncoding) {
            return text
        }

        throw EditorFileError.unreadableText
    }

    /// Returns the file size in bytes, or nil if the file attributes cannot be read.
    public static func byteCount(of fileURL: URL) -> Int? {
        (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}
