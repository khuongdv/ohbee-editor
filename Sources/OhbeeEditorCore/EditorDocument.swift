import Foundation

public struct EditorDocument: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String
    public var fileURL: URL?
    public var isScratch: Bool
    public var isDirty: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var language: EditorLanguage?
    public var sessionTextFileName: String?

    /// Set to true when the file on disk exceeds LargeFilePolicy.normalByteLimit.
    /// Not persisted in the session. Defaults to false on decode.
    public var isLargeFile: Bool = false

    /// Set to true when the file on disk is not writable. Not persisted. Defaults to false on decode.
    public var isReadOnly: Bool = false

    /// Set to true when a file-backed document's backing file no longer exists on disk.
    /// Clean file-backed text is never persisted (it is re-read from disk on restore), so a
    /// missing file means the content is unrecoverable. Not persisted. Defaults to false on decode.
    public var isMissingFile: Bool = false

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

    public var isImageFile: Bool {
        guard let ext = fileURL?.pathExtension.lowercased() else { return false }
        return Self.imageExtensions.contains(ext)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, fileURL, isScratch, isDirty, createdAt, updatedAt, language, sessionTextFileName
    }

    public init(
        id: UUID,
        title: String,
        text: String,
        fileURL: URL?,
        isScratch: Bool,
        isDirty: Bool,
        createdAt: Date,
        updatedAt: Date,
        language: EditorLanguage? = nil,
        sessionTextFileName: String? = nil,
        isLargeFile: Bool = false,
        isReadOnly: Bool = false,
        isMissingFile: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.fileURL = fileURL
        self.isScratch = isScratch
        self.isDirty = isDirty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.language = language
        self.sessionTextFileName = sessionTextFileName
        self.isLargeFile = isLargeFile
        self.isReadOnly = isReadOnly
        self.isMissingFile = isMissingFile
    }

    public var effectiveLanguage: EditorLanguage {
        language ?? EditorLanguage.inferred(from: fileURL)
    }

    public static func scratch(index: Int) -> EditorDocument {
        let now = Date()

        return EditorDocument(
            id: UUID(),
            title: "Note \(index)",
            text: "",
            fileURL: nil,
            isScratch: true,
            isDirty: false,
            createdAt: now,
            updatedAt: now
        )
    }

    // isLargeFile, isReadOnly, and isMissingFile are intentionally excluded: runtime classifications, not document identity.
    public static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.text == rhs.text &&
        lhs.fileURL == rhs.fileURL &&
        lhs.isScratch == rhs.isScratch &&
        lhs.isDirty == rhs.isDirty &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.language == rhs.language &&
        lhs.sessionTextFileName == rhs.sessionTextFileName
    }
}
