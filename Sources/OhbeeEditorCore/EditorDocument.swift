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

    public init(
        id: UUID,
        title: String,
        text: String,
        fileURL: URL?,
        isScratch: Bool,
        isDirty: Bool,
        createdAt: Date,
        updatedAt: Date,
        language: EditorLanguage? = nil
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
}
