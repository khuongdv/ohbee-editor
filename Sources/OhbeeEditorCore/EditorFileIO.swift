import Foundation

public struct EditorFileMetadata: Equatable {
    public let byteCount: Int64?
    public let creationDate: Date?
    public let author: String?

    public init(byteCount: Int64?, creationDate: Date?, author: String?) {
        self.byteCount = byteCount
        self.creationDate = creationDate
        self.author = author
    }
}

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
        guard let byteCount = metadata(for: fileURL)?.byteCount else { return nil }
        return Int(byteCount)
    }

    /// Returns local filesystem metadata for a file-backed document, or nil when the file is unavailable.
    public static func metadata(for fileURL: URL) -> EditorFileMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }

        let size = (attrs[.size] as? NSNumber)?.int64Value
        let created = attrs[.creationDate] as? Date
        let ownerName = (attrs[.ownerAccountName] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = ownerName.flatMap { $0.isEmpty ? nil : $0 }

        return EditorFileMetadata(
            byteCount: size,
            creationDate: created,
            author: author
        )
    }

    /// Detects SVG content independently of the filename so a renamed SVG cannot bypass
    /// the stricter vector-image size policy before AppKit parses it.
    public static func isLikelySVG(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return false }
        var prefix = String(decoding: data, as: UTF8.self)
        if prefix.hasPrefix("\u{feff}") { prefix.removeFirst() }
        let lowered = prefix.lowercased()
        return lowered.contains("<svg")
            || (lowered.contains("<?xml") && lowered.contains("svg"))
    }
}
