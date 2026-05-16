import Foundation

/// File size classification used to apply safety guardrails throughout the editor.
public enum FileSizeCategory: Equatable {
    case normal      // <= 10 MB: full feature support
    case large       // > 10 MB, <= 50 MB: large-file mode, highlighting/line numbers disabled
    case veryLarge   // > 50 MB, <= 100 MB: same as large, with a stronger opening warning
    case tooLarge    // > 100 MB: rejected; not supported
}

public enum LargeFilePolicy {
    public static let normalByteLimit  = 10 * 1_048_576    // 10 MB
    public static let warningByteLimit = 50 * 1_048_576    // 50 MB
    public static let maximumByteLimit = 100 * 1_048_576   // 100 MB

    /// Maximum UTF-8 bytes of document text persisted in the session file.
    /// Applies to scratch documents and dirty file-backed documents.
    public static let sessionTextCap = normalByteLimit

    public static func classify(byteCount: Int) -> FileSizeCategory {
        if byteCount <= normalByteLimit  { return .normal }
        if byteCount <= warningByteLimit { return .large }
        if byteCount <= maximumByteLimit { return .veryLarge }
        return .tooLarge
    }

    /// Returns the text that should be written to the session file for a given document.
    /// Clean file-backed documents store no text (re-read from disk on restore).
    /// Dirty or scratch documents store text up to sessionTextCap; larger content is dropped.
    public static func sessionText(for document: EditorDocument) -> String {
        if document.fileURL != nil {
            if !document.isDirty {
                return ""
            }
            return document.text.utf8.count <= sessionTextCap ? document.text : ""
        }
        return document.text.utf8.count <= sessionTextCap ? document.text : ""
    }

    /// Returns false when a dirty file-backed document's text was too large to persist,
    /// meaning the dirty flag should be cleared in the session record so the file is
    /// reloaded from disk (last saved version) on restore.
    public static func shouldPreserveDirtyState(for document: EditorDocument) -> Bool {
        guard document.fileURL != nil, document.isDirty else { return true }
        return document.text.utf8.count <= sessionTextCap
    }
}
