import Foundation

public struct EditorSession: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var selectedDocumentID: UUID?
    public var documents: [EditorDocument]

    public init(
        version: Int = Self.currentVersion,
        selectedDocumentID: UUID?,
        documents: [EditorDocument]
    ) {
        self.version = version
        self.selectedDocumentID = selectedDocumentID
        self.documents = documents
    }
}

public enum SessionPersistenceError: Error {
    case unsupportedVersion(Int)
}

public protocol SessionPersisting {
    func loadSession() throws -> EditorSession?
    func saveSession(_ session: EditorSession) throws
}

public final class LocalSessionStore: SessionPersisting {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = LocalSessionStore.defaultFileURL()) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadSession() throws -> EditorSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let session = try decoder.decode(EditorSession.self, from: data)

        guard session.version == EditorSession.currentVersion else {
            throw SessionPersistenceError.unsupportedVersion(session.version)
        }

        return session
    }

    public func saveSession(_ session: EditorSession) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return supportDirectory
            .appendingPathComponent("Ohbee Editor", isDirectory: true)
            .appendingPathComponent("session.json")
    }
}
