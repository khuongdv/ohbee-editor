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

    /// Set to true when the file on disk exceeds LargeFilePolicy.normalByteLimit.
    /// Not persisted in the session. Defaults to false on decode.
    public var isLargeFile: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, title, text, fileURL, isScratch, isDirty, createdAt, updatedAt, language
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
        isLargeFile: Bool = false
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
        self.isLargeFile = isLargeFile
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

    // isLargeFile is intentionally excluded: it is a runtime classification, not document identity.
    public static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.text == rhs.text &&
        lhs.fileURL == rhs.fileURL &&
        lhs.isScratch == rhs.isScratch &&
        lhs.isDirty == rhs.isDirty &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.language == rhs.language
    }
}
