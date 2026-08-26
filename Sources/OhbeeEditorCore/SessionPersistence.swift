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

public enum SessionPersistenceError: Error, LocalizedError {
    case unsupportedVersion(Int)
    /// A session that could not be restored. `reason` keeps the underlying cause so an
    /// unsupported version is never reported as corruption.
    case loadFailure(reason: Error?, quarantinedPath: String?, recoveredTextPath: String?)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "This session was written by a newer version of Ohbee Editor (format \(version)) and was not opened."
        case let .loadFailure(reason, quarantinedPath, recoveredTextPath):
            var message = (reason as? LocalizedError)?.errorDescription
                ?? "The saved session could not be read."
            if let quarantinedPath {
                message += " The session file was kept at \(quarantinedPath)."
            }
            if let recoveredTextPath {
                message += " Unsaved note text was moved to \(recoveredTextPath)."
            }
            return message
        }
    }

    /// True when the failure is an unsupported format rather than damaged data.
    public var isUnsupportedVersion: Bool {
        switch self {
        case .unsupportedVersion:
            return true
        case let .loadFailure(reason, _, _):
            guard let reason = reason as? SessionPersistenceError else { return false }
            return reason.isUnsupportedVersion
        }
    }
}

public protocol SessionPersisting {
    func loadSession() throws -> EditorSession?
    func saveSession(_ session: EditorSession) throws

    /// Local, user-facing note about recovered or preserved session state, if any.
    var recoveryNotice: String? { get }
}

public extension SessionPersisting {
    var recoveryNotice: String? { nil }
}

public final class LocalSessionStore: SessionPersisting {
    private let fileURL: URL
    private let sidecarDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Sidecar text files are only prunable once this process has proven it can read the
    /// manifest that references them. Pruning before that would delete unsaved note text
    /// that the app simply failed to load.
    private var canPruneSidecars = false
    public private(set) var recoveryNotice: String?

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
            // No manifest, so nothing maps to the remaining text files. Move them somewhere
            // pruning never looks instead of leaving them to be deleted on a later launch.
            if let recoveredDirectoryURL = preserveOrphanSidecars() {
                recoveryNotice = "Unreferenced note text was moved to \(recoveredDirectoryURL.path)."
            }
            canPruneSidecars = true
            return nil
        }

        var loadFailure: Error?
        do {
            let data = try Data(contentsOf: fileURL)
            var session = try decoder.decode(EditorSession.self, from: data)

            if session.version != EditorSession.currentVersion {
                // Reported as its own case: a manifest from a newer build is readable but not
                // understood, which is a different problem from corruption.
                loadFailure = SessionPersistenceError.unsupportedVersion(session.version)
            } else {
                hydrateSidecarText(in: &session)
                canPruneSidecars = true
                return session
            }
        } catch {
            loadFailure = error
        }

        // The manifest is the only map to the sidecar text. Keep both: quarantine the manifest
        // instead of overwriting it, and move the unreachable text out of the prunable
        // directory so no later launch can delete what the user typed.
        canPruneSidecars = false
        let quarantinedURL = quarantineUnreadableSession()
        let recoveredDirectoryURL = preserveOrphanSidecars()
        let failure = SessionPersistenceError.loadFailure(
            reason: loadFailure,
            quarantinedPath: quarantinedURL?.path,
            recoveredTextPath: recoveredDirectoryURL?.path
        )
        recoveryNotice = failure.errorDescription
        throw failure
    }

    /// Moves an unreadable manifest aside so the next save cannot overwrite it and the user
    /// can still inspect or repair it locally.
    private func quarantineUnreadableSession() -> URL? {
        let quarantinedURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("session.corrupt-\(Self.recoveryStamp()).json", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: quarantinedURL.path) else {
            return quarantinedURL
        }

        do {
            try FileManager.default.moveItem(at: fileURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            return nil
        }
    }

    /// Moves note text that no readable manifest references into a sibling directory that
    /// `cleanupUnusedSidecars` never scans. Returns the directory when text was preserved.
    private func preserveOrphanSidecars() -> URL? {
        guard !sidecarFileNames().isEmpty else {
            return nil
        }

        let recoveredURL = sidecarDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("Recovered Note Text \(Self.recoveryStamp())", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: recoveredURL.path) else {
            return recoveredURL
        }

        do {
            try FileManager.default.moveItem(at: sidecarDirectoryURL, to: recoveredURL)
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.restrictedDirectoryPermissions],
                ofItemAtPath: recoveredURL.path
            )
            return recoveredURL
        } catch {
            // Preserving failed, so keep pruning disabled and leave the text where it is.
            return nil
        }
    }

    private static func recoveryStamp() -> String {
        quarantineTimestampFormatter.string(from: Date())
    }

    private static let quarantineTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Only the `<uuid>.txt` files this store writes count as session text. Filesystem noise
    /// such as `.DS_Store` must not be mistaken for note text.
    private func sidecarFileNames() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sidecarDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".txt") }
    }

    /// Owner-only file permissions (rw-------) to protect potentially sensitive session content.
    private static let restrictedFilePermissions: Int16 = 0o600
    /// Owner-only directory permissions (rwx------).
    private static let restrictedDirectoryPermissions: Int16 = 0o700

    public func saveSession(_ session: EditorSession) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        // Restrict the session directory so other local users cannot browse it
        try? FileManager.default.setAttributes(
            [.posixPermissions: Self.restrictedDirectoryPermissions],
            ofItemAtPath: directoryURL.path
        )

        let sessionToWrite = try sessionExternalizingLargeText(session)
        let data = try encoder.encode(sessionToWrite)
        try data.write(to: fileURL, options: [.atomic])
        // Restrict the session file to owner-only read/write
        try? FileManager.default.setAttributes(
            [.posixPermissions: Self.restrictedFilePermissions],
            ofItemAtPath: fileURL.path
        )
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
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.restrictedDirectoryPermissions],
                ofItemAtPath: sidecarDirectoryURL.path
            )

            let fileName = "\(sessionToWrite.documents[index].id.uuidString).txt"
            let textURL = sidecarDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try sessionToWrite.documents[index].text.write(
                to: textURL,
                atomically: true,
                encoding: .utf8
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.restrictedFilePermissions],
                ofItemAtPath: textURL.path
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

            // The name is persisted state, not a path. Bind it to the document UUID so a
            // tampered session cannot escape the private sidecar directory.
            guard fileName == "\(session.documents[index].id.uuidString).txt" else {
                session.documents[index].sessionTextFileName = nil
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
        // Never prune text this process could not account for (see loadSession).
        guard canPruneSidecars else {
            return
        }

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

        let currentURL = supportDirectory
            .appendingPathComponent("Ohbee Editor", isDirectory: true)
            .appendingPathComponent("session.json")
        migrateLegacyStoreIfNeeded(to: currentURL)
        return currentURL
    }

    /// Moves the pre-sandbox Application Support state into the app container on first launch.
    /// The narrowly scoped temporary entitlement in Support/Entitlements.plist permits reading
    /// this one legacy directory; it can be removed after the supported migration window.
    private static func migrateLegacyStoreIfNeeded(to currentFileURL: URL) {
        let currentDirectory = currentFileURL.deletingLastPathComponent()
        _ = try? migrateLegacyStoreIfNeeded(from: legacyStoreDirectory(), to: currentDirectory)
    }

    /// The pre-sandbox state directory, resolved against the real account home.
    public static func legacyStoreDirectory() -> URL {
        URL(fileURLWithPath: realHomeDirectoryPath(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Ohbee Editor", isDirectory: true)
    }

    /// `FileManager.homeDirectoryForCurrentUser` returns the sandbox container once App Sandbox
    /// is enabled, so it cannot address pre-sandbox state. Prefer the POSIX account home and
    /// fall back to stripping the container suffix when the account lookup is unavailable.
    public static func realHomeDirectoryPath(
        sandboxHomePath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        posixHomePath: String? = LocalSessionStore.posixHomeDirectoryPath()
    ) -> String {
        if let posixHomePath, !posixHomePath.isEmpty {
            return posixHomePath
        }

        return homePathStrippingContainerSuffix(sandboxHomePath)
    }

    /// `/Users/me/Library/Containers/<bundle-id>/Data` -> `/Users/me`
    public static func homePathStrippingContainerSuffix(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard
            let containersIndex = components.firstIndex(of: "Containers"),
            containersIndex >= 1,
            components[containersIndex - 1] == "Library"
        else {
            return path
        }

        return NSString.path(withComponents: Array(components.prefix(containersIndex - 1)))
    }

    public static func posixHomeDirectoryPath() -> String? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return nil
        }

        let path = String(cString: directory)
        return path.isEmpty ? nil : path
    }

    @discardableResult
    public static func migrateLegacyStoreIfNeeded(from legacyDirectory: URL, to currentDirectory: URL) throws -> Bool {
        let manager = FileManager.default
        let legacySession = legacyDirectory.appendingPathComponent("session.json")
        let currentSession = currentDirectory.appendingPathComponent("session.json")
        guard legacyDirectory.standardizedFileURL != currentDirectory.standardizedFileURL,
              !manager.fileExists(atPath: currentSession.path),
              manager.fileExists(atPath: legacySession.path) else { return false }

        try manager.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        let legacySidecars = legacyDirectory.appendingPathComponent("Session Text", isDirectory: true)
        let currentSidecars = currentDirectory.appendingPathComponent("Session Text", isDirectory: true)
        if manager.fileExists(atPath: legacySidecars.path), !manager.fileExists(atPath: currentSidecars.path) {
            try manager.copyItem(at: legacySidecars, to: currentSidecars)
        }
        // Copy the manifest last; its presence is the migration completion marker.
        try manager.copyItem(at: legacySession, to: currentSession)
        return true
    }
}
