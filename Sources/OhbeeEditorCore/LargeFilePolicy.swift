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
    public static let maximumImageByteLimit = 100 * 1_048_576
    public static let maximumSVGByteLimit = 10 * 1_048_576

    public static func maximumImageByteLimit(forExtension fileExtension: String) -> Int {
        fileExtension.lowercased() == "svg" ? maximumSVGByteLimit : maximumImageByteLimit
    }

    public static func maximumImageByteLimit(for fileURL: URL) -> Int {
        if fileURL.pathExtension.lowercased() == "svg" || EditorFileIO.isLikelySVG(at: fileURL) {
            return maximumSVGByteLimit
        }
        return maximumImageByteLimit
    }

    /// Maximum UTF-8 bytes of document text stored inline in the session JSON.
    /// Larger scratch and dirty file-backed buffers are stored as local sidecar files.
    public static let sessionTextCap = normalByteLimit

    public static func classify(byteCount: Int) -> FileSizeCategory {
        if byteCount <= normalByteLimit  { return .normal }
        if byteCount <= warningByteLimit { return .large }
        if byteCount <= maximumByteLimit { return .veryLarge }
        return .tooLarge
    }

    /// Returns the text that should be preserved for a given document.
    /// Clean file-backed documents store no text (re-read from disk on restore).
    /// Dirty or scratch documents preserve their full text; LocalSessionStore decides
    /// whether to keep that text inline or spill it to a local sidecar file.
    public static func sessionText(for document: EditorDocument) -> String {
        if document.fileURL != nil {
            if !document.isDirty {
                return ""
            }
            return document.text
        }
        return document.text
    }

}
