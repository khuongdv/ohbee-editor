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
    private let sidecarDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = LocalSessionStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.sidecarDirectoryURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Session Text", isDirectory: true)

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
        var session = try decoder.decode(EditorSession.self, from: data)

        guard session.version == EditorSession.currentVersion else {
            throw SessionPersistenceError.unsupportedVersion(session.version)
        }

        hydrateSidecarText(in: &session)
        return session
    }

    public func saveSession(_ session: EditorSession) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let sessionToWrite = try sessionExternalizingLargeText(session)
        let data = try encoder.encode(sessionToWrite)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func sessionExternalizingLargeText(_ session: EditorSession) throws -> EditorSession {
        var sessionToWrite = session
        var activeSidecars = Set<String>()

        for index in sessionToWrite.documents.indices {
            sessionToWrite.documents[index].sessionTextFileName = nil
            guard shouldExternalizeText(sessionToWrite.documents[index]) else {
                continue
            }

            try FileManager.default.createDirectory(
                at: sidecarDirectoryURL,
                withIntermediateDirectories: true
            )

            let fileName = "\(sessionToWrite.documents[index].id.uuidString).txt"
            let textURL = sidecarDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try sessionToWrite.documents[index].text.write(
                to: textURL,
                atomically: true,
                encoding: .utf8
            )
            sessionToWrite.documents[index].text = ""
            sessionToWrite.documents[index].sessionTextFileName = fileName
            activeSidecars.insert(fileName)
        }

        cleanupUnusedSidecars(keeping: activeSidecars)
        return sessionToWrite
    }

    private func shouldExternalizeText(_ document: EditorDocument) -> Bool {
        guard document.text.utf8.count > LargeFilePolicy.sessionTextCap else {
            return false
        }

        return document.fileURL == nil || document.isDirty
    }

    private func hydrateSidecarText(in session: inout EditorSession) {
        for index in session.documents.indices {
            guard let fileName = session.documents[index].sessionTextFileName else {
                continue
            }

            let textURL = sidecarDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            guard let text = try? String(contentsOf: textURL, encoding: .utf8) else {
                continue
            }

            session.documents[index].text = text
            session.documents[index].sessionTextFileName = nil
        }
    }

    private func cleanupUnusedSidecars(keeping activeSidecars: Set<String>) {
        guard
            let sidecars = try? FileManager.default.contentsOfDirectory(
                at: sidecarDirectoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for sidecar in sidecars where !activeSidecars.contains(sidecar.lastPathComponent) {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return supportDirectory
            .appendingPathComponent("Ohbee Editor", isDirectory: true)
            .appendingPathComponent("session.json")
    }
}
