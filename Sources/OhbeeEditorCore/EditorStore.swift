import Foundation
import SwiftUI

public enum StatusMessageTone {
    case neutral
    case success
    case warning
}

public struct SaveAllResult: Equatable {
    public let savedCount: Int
    public let skippedScratchCount: Int
    public let skippedCleanCount: Int
    public let skippedReadOnlyCount: Int
    public let failedCount: Int
}

public final class EditorStore: ObservableObject {
    public static let maxDocumentCount = 50
    private static let recentFilesKey = "ohbee.recentFiles"
    private static let recentFileRecordsKey = "ohbee.recentFileRecords"
    private static let maxRecentFiles = 10
    private static let maxRecentlyClosedFiles = 10

    @Published public private(set) var documents: [EditorDocument]
    @Published public var selectedDocumentID: EditorDocument.ID?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var statusMessageTone: StatusMessageTone = .neutral
    @Published public var searchOptions = SearchOptions()
    @Published public private(set) var currentMatchIndex: Int?
    @Published public private(set) var recentFiles: [URL]
    @Published public private(set) var recentlyClosedFileURLs: [URL] = []
    @Published public private(set) var searchSummary = SearchSummary(matchCount: 0, currentMatchIndex: nil)

    private let sessionStore: SessionPersisting
    private let fileIO: EditorFileIO
    private let sessionSaveDebounceInterval: TimeInterval
    private var pendingSessionSave: DispatchWorkItem?
    private var activeSecurityScopedURLs = Set<URL>()
    private var inFlightFileAccessCounts: [URL: Int] = [:]
    private var recentFileBookmarks: [String: Data]
    private var cachedSearchRanges: [NSRange] = []
    private var searchEvaluationGeneration = 0
    private var pendingSearchEvaluation: DispatchWorkItem?

    private struct RecentFileRecord: Codable {
        let path: String
        let bookmark: Data?
    }

    public init(
        documents: [EditorDocument]? = nil,
        selectedDocumentID: EditorDocument.ID? = nil,
        sessionStore: SessionPersisting = LocalSessionStore(),
        fileIO: EditorFileIO = EditorFileIO(),
        sessionSaveDebounceInterval: TimeInterval = 0.5
    ) {
        self.sessionStore = sessionStore
        self.fileIO = fileIO
        self.sessionSaveDebounceInterval = sessionSaveDebounceInterval

        let records = Self.loadRecentFileRecords()
        let legacyPaths = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) ?? []
        let paths = records.isEmpty ? legacyPaths : records.map(\.path)
        self.recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }
        self.recentFileBookmarks = Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                record.bookmark.map { (Self.urlKey(URL(fileURLWithPath: record.path)), $0) }
            }
        )

        let restoredSession = Self.restoreSession(using: sessionStore)
        let requestedDocuments = documents ?? restoredSession?.documents
        let initialDocuments: [EditorDocument]
        if let requestedDocuments, !requestedDocuments.isEmpty {
            initialDocuments = requestedDocuments
        } else {
            initialDocuments = [EditorDocument.scratch(index: 1)]
        }

        self.documents = initialDocuments
        self.selectedDocumentID = selectedDocumentID
            ?? restoredSession?.selectedDocumentID
            ?? initialDocuments[0].id

        if self.selectedDocument == nil {
            self.selectedDocumentID = initialDocuments[0].id
        }

        // Resolve persistent user grants before touching restored file URLs in a sandbox.
        restoreSecurityScopedAccess()
        // Flag file-backed tabs whose backing file no longer exists. Synchronous and cheap
        // (a stat per document) so missing tabs render marked immediately, with no flash.
        markMissingBackingFiles()

        // Restore text for file-backed documents whose text was not persisted in the session.
        // Deferred so init completes before async work begins.
        DispatchQueue.main.async { [weak self] in
            self?.reloadFileBackedDocumentsIfNeeded()
            self?.scheduleSearchEvaluation(resetCurrentIndex: true)
        }
    }

    deinit {
        flushPendingSessionSave()
        for url in activeSecurityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public var selectedDocument: EditorDocument? {
        guard let selectedDocumentID else {
            return documents.first
        }

        return documents.first { $0.id == selectedDocumentID }
    }

    public var canCreateScratchDocument: Bool {
        documents.count < Self.maxDocumentCount
    }

    public var selectedLanguage: EditorLanguage {
        selectedDocument?.effectiveLanguage ?? .plainText
    }

    public var selectedDocumentSupportsJSONTools: Bool {
        guard let selectedDocument else {
            return false
        }

        return selectedDocument.language == .json
            || EditorLanguage.inferred(from: selectedDocument.fileURL) == .json
    }

    public var selectedDocumentSupportsXMLTools: Bool {
        guard let selectedDocument else {
            return false
        }

        return selectedDocument.language == .xml
            || EditorLanguage.inferred(from: selectedDocument.fileURL) == .xml
    }

    public var windowTitle: String {
        let documentTitle = selectedDocument.map(displayTitleForWindow) ?? "Untitled"
        return "Ohbee Editor - \(documentTitle)"
    }

    public var canReopenClosedFile: Bool {
        !recentlyClosedFileURLs.isEmpty && documents.count < Self.maxDocumentCount
    }

    public func createScratchDocument() {
        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        let nextIndex = documents.filter(\.isScratch).count + 1
        let document = EditorDocument.scratch(index: nextIndex)

        documents.append(document)
        selectedDocumentID = document.id
        currentMatchIndex = nil
        scheduleSearchEvaluation(resetCurrentIndex: true)
        setStatus("Created \(document.title).")
        saveSession()
    }

    public func openDiffTab(baseID: EditorDocument.ID, changedID: EditorDocument.ID) {
        guard let base = documents.first(where: { $0.id == baseID }),
              let changed = documents.first(where: { $0.id == changedID }) else {
            setStatus("Could not find documents to compare.", tone: .warning)
            return
        }

        guard !base.isLargeFile && !changed.isLargeFile else {
            setStatus("Cannot diff large files.", tone: .warning)
            return
        }

        let baseLineCount = base.text.components(separatedBy: "\n").count
        let changedLineCount = changed.text.components(separatedBy: "\n").count
        guard baseLineCount * changedLineCount <= DiffTools.maxDiffCells else {
            setStatus(
                "Documents too large to diff (\(baseLineCount) × \(changedLineCount) lines).",
                tone: .warning
            )
            return
        }

        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        let diffText = DiffTools.annotatedText(
            baseTitle: base.title,
            changedTitle: changed.title,
            base: base.text,
            changed: changed.text
        )

        let nextIndex = documents.filter(\.isScratch).count + 1
        var doc = EditorDocument.scratch(index: nextIndex)
        doc.title = "Diff: \(base.title) → \(changed.title)"
        doc.text = diffText
        documents.append(doc)
        selectedDocumentID = doc.id
        scheduleSearchEvaluation(resetCurrentIndex: true)
        saveSession()
        setStatus("Diff opened in new tab.")
    }

    public func moveDocument(from source: IndexSet, to destination: Int) {
        documents.move(fromOffsets: source, toOffset: destination)
        saveSession()
    }

    public func selectDocument(_ id: EditorDocument.ID) {
        guard documents.contains(where: { $0.id == id }) else {
            return
        }

        selectedDocumentID = id
        scheduleSearchEvaluation(resetCurrentIndex: true)
        saveSession()
    }

    public func closeSelectedDocument() {
        guard let selectedDocumentID else {
            return
        }

        closeDocument(selectedDocumentID)
    }

    public func closeDocument(_ id: EditorDocument.ID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        let document = documents[index]
        let closedTitle = document.title
        recordClosedFileIfNeeded(document)
        documents.remove(at: index)

        if documents.isEmpty {
            let document = EditorDocument.scratch(index: 1)
            documents = [document]
            selectedDocumentID = document.id
        } else if selectedDocumentID == id {
            let nextIndex = min(index, documents.count - 1)
            selectedDocumentID = documents[nextIndex].id
        }
        reconcileSecurityScopedAccess()

        refreshCurrentMatch()
        setStatus("Closed \(closedTitle).")
        saveSession()
    }

    /// Removes a tab whose backing file no longer exists. The original content was never
    /// persisted (clean file-backed text is re-read from disk), so there is nothing to keep
    /// and no copy is written anywhere. The file is not recorded as recently closed because
    /// it cannot be reopened.
    public func discardMissingDocument(_ id: EditorDocument.ID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removedTitle = documents[index].title
        documents.remove(at: index)

        if documents.isEmpty {
            let document = EditorDocument.scratch(index: 1)
            documents = [document]
            selectedDocumentID = document.id
        } else if selectedDocumentID == id {
            let nextIndex = min(index, documents.count - 1)
            selectedDocumentID = documents[nextIndex].id
        }
        reconcileSecurityScopedAccess()

        refreshCurrentMatch()
        setStatus("Removed \(removedTitle): original file was deleted.", tone: .warning)
        saveSession()
    }

    public func closeOtherDocuments(keeping id: EditorDocument.ID) {
        guard let document = documents.first(where: { $0.id == id }) else {
            return
        }

        recordClosedFilesIfNeeded(documents.filter { $0.id != id })
        let closedCount = max(documents.count - 1, 0)
        documents = [document]
        reconcileSecurityScopedAccess()
        selectedDocumentID = document.id
        refreshCurrentMatch()
        setStatus(closedCount == 1 ? "Closed 1 other tab." : "Closed \(closedCount) other tabs.")
        saveSession()
    }

    public func closeDocumentsToRight(of id: EditorDocument.ID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        let closedCount = documents.count - index - 1
        guard closedCount > 0 else {
            setStatus("No tabs to the right.")
            return
        }

        recordClosedFilesIfNeeded(Array(documents.suffix(from: index + 1)))
        documents.removeSubrange((index + 1)..<documents.count)
        reconcileSecurityScopedAccess()
        selectedDocumentID = id
        refreshCurrentMatch()
        setStatus(closedCount == 1 ? "Closed 1 tab to the right." : "Closed \(closedCount) tabs to the right.")
        saveSession()
    }

    public func closeAllDocuments() {
        let closedCount = documents.count
        recordClosedFilesIfNeeded(documents)
        let document = EditorDocument.scratch(index: 1)
        documents = [document]
        reconcileSecurityScopedAccess()
        selectedDocumentID = document.id
        currentMatchIndex = nil
        setStatus(closedCount == 1 ? "Closed 1 tab." : "Closed \(closedCount) tabs.")
        saveSession()
    }

    public func reopenLastClosedFile() {
        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        while let fileURL = recentlyClosedFileURLs.first {
            recentlyClosedFileURLs.removeFirst()

            guard recentFileExists(fileURL) else {
                continue
            }

            openDocument(from: fileURL)
            return
        }

        setStatus("No recently closed files to reopen.", tone: .warning)
    }

    public func setSelectedLanguage(_ language: EditorLanguage) {
        guard let index = selectedDocumentIndex else {
            return
        }

        var document = documents[index]
        document.language = language
        document.updatedAt = Date()
        documents[index] = document
        setStatus("Language: \(language.displayName).")
        saveSession()
    }

    public func textBinding(for id: EditorDocument.ID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.documents.first { $0.id == id }?.text ?? ""
            },
            set: { [weak self] newText in
                self?.updateDocumentText(id, text: newText)
            }
        )
    }

    private func updateDocumentText(_ id: EditorDocument.ID, text: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard documents[index].text != text else {
            return
        }

        var document = documents[index]
        document.text = text
        document.isDirty = true
        // The user has typed real content into this buffer. Even if the backing file was
        // deleted, this tab now holds content worth keeping, so it follows the normal
        // unsaved-changes flow instead of the missing-file removal flow.
        document.isMissingFile = false
        document.updatedAt = Date()
        documents[index] = document
        refreshCurrentMatch()
        scheduleSessionSave()
    }

    /// Opens a file asynchronously. A placeholder tab appears immediately while the
    /// file is read on a background thread, then the text is delivered on the main thread.
    /// Image files (png/jpg/jpeg/webp/bmp/svg) skip text loading and are shown in ImageViewerView.
    public func openDocument(from requestedURL: URL) {
        let fileURL = resolvedRecentFileURL(for: requestedURL) ?? requestedURL
        if let existing = documents.first(where: { $0.fileURL == fileURL }) {
            selectedDocumentID = existing.id
            currentMatchIndex = nil
            scheduleSearchEvaluation(resetCurrentIndex: true)
            setStatus("Switched to \(existing.title).")
            return
        }

        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        retainSecurityScopedAccess(for: fileURL)

        let isImageFile = EditorDocument.imageExtensions.contains(fileURL.pathExtension.lowercased())
        let isReadOnly = !FileManager.default.isWritableFile(atPath: fileURL.path)
        let fileSize = EditorFileIO.byteCount(of: fileURL) ?? 0

        var isLargeFile = false
        if isImageFile {
            let limit = LargeFilePolicy.maximumImageByteLimit(for: fileURL)
            guard fileSize <= limit else {
                setStatus(
                    "\(fileURL.lastPathComponent) exceeds the \(limit / 1_048_576) MB image safety limit.",
                    tone: .warning
                )
                reconcileSecurityScopedAccess()
                return
            }
        } else {
            let category = LargeFilePolicy.classify(byteCount: fileSize)

            if category == .tooLarge {
                setStatus(
                    "\(fileURL.lastPathComponent) exceeds \(LargeFilePolicy.maximumByteLimit / 1_048_576) MB. " +
                    "Ohbee Editor is not designed for files this large.",
                    tone: .warning
                )
                reconcileSecurityScopedAccess()
                return
            }

            isLargeFile = category != .normal
        }

        let now = Date()
        let placeholder = EditorDocument(
            id: UUID(),
            title: fileURL.lastPathComponent,
            text: "",
            fileURL: fileURL,
            isScratch: false,
            isDirty: false,
            createdAt: now,
            updatedAt: now,
            securityScopedBookmark: try? fileURL.bookmarkData(options: .withSecurityScope),
            isLargeFile: isLargeFile,
            isReadOnly: isReadOnly
        )

        documents.append(placeholder)
        selectedDocumentID = placeholder.id
        currentMatchIndex = nil
        scheduleSearchEvaluation(resetCurrentIndex: true)

        if isImageFile {
            setStatus("Opened \(fileURL.lastPathComponent).")
            addRecentFile(fileURL)
            saveSession()
            return
        }

        if isLargeFile {
            setStatus(
                "Opening large file: \(fileURL.lastPathComponent). " +
                "Syntax highlighting and line numbers will be disabled.",
                tone: .warning
            )
        } else {
            setStatus("Opening \(fileURL.lastPathComponent)...")
        }

        let docID = placeholder.id
        beginFileOperation(at: fileURL)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try EditorFileIO().readText(from: fileURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.endFileOperation(at: fileURL) }
                switch result {
                case let .success(text):
                    guard let idx = self.documents.firstIndex(where: { $0.id == docID }) else { return }
                    self.documents[idx].text = text
                    self.documents[idx].updatedAt = Date()
                    self.scheduleSearchEvaluation(resetCurrentIndex: true)
                    if isLargeFile {
                        self.setStatus(
                            "Opened \(fileURL.lastPathComponent). " +
                            "Large-file mode: syntax highlighting and line numbers are disabled.",
                            tone: .warning
                        )
                    } else {
                        self.setStatus("Opened \(fileURL.lastPathComponent).")
                    }
                    self.saveSession()
                    self.addRecentFile(fileURL)
                case let .failure(error):
                    self.documents.removeAll { $0.id == docID }
                    self.reconcileSecurityScopedAccess()
                    if self.selectedDocumentID == docID {
                        self.selectedDocumentID = self.documents.last?.id
                    }
                    // If the file no longer exists, clean it from recents
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        self.removeRecentFile(fileURL)
                    }
                    self.setStatus("Could not open file: \(error.localizedDescription)", tone: .warning)
                }
            }
        }
    }

    public func reauthorizeDocument(_ id: EditorDocument.ID, with selectedURL: URL) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let expectedFileName = documents[index].fileURL?.lastPathComponent ?? documents[index].title
        guard selectedURL.lastPathComponent == expectedFileName else {
            setStatus(
                "Select \(expectedFileName) to restore access. Use Save As to write this buffer to a different file.",
                tone: .warning
            )
            return
        }
        retainSecurityScopedAccess(for: selectedURL)
        guard FileManager.default.fileExists(atPath: selectedURL.path) else {
            reconcileSecurityScopedAccess()
            setStatus("Could not access the selected file.", tone: .warning)
            return
        }

        documents[index].fileURL = selectedURL
        documents[index].title = selectedURL.lastPathComponent
        documents[index].securityScopedBookmark = try? selectedURL.bookmarkData(options: .withSecurityScope)
        documents[index].requiresFileAuthorization = false
        documents[index].isMissingFile = false
        addRecentFile(selectedURL)
        saveSession()
        if documents[index].isDirty {
            setStatus("Access restored for \(selectedURL.lastPathComponent); unsaved edits were preserved.")
        } else {
            reloadDocumentTextIfNeeded(id: id)
        }
    }

    public func clearRecentFiles() {
        recentFiles = []
        recentFileBookmarks = [:]
        UserDefaults.standard.removeObject(forKey: Self.recentFilesKey)
        UserDefaults.standard.removeObject(forKey: Self.recentFileRecordsKey)
    }

    public func removeMissingRecentFiles() {
        let originalCount = recentFiles.count
        let existing = recentFiles.filter(recentFileExists)
        recentFiles = existing
        persistRecentFiles()

        let removedCount = originalCount - existing.count
        if removedCount == 0 {
            setStatus("No missing recent files.")
        } else {
            setStatus(removedCount == 1
                ? "Removed 1 missing recent file."
                : "Removed \(removedCount) missing recent files.")
        }
    }

    public func recentFileExists(_ url: URL) -> Bool {
        let resolved = resolvedRecentFileURL(for: url, migratePath: false) ?? url
        let wasActive = activeSecurityScopedURLs.contains(resolved.standardizedFileURL)
        if !wasActive { retainSecurityScopedAccess(for: resolved) }
        let exists = FileManager.default.fileExists(atPath: resolved.path)
        if !wasActive { stopSecurityScopedAccess(for: resolved) }
        return exists
    }

    private func removeRecentFile(_ url: URL) {
        let updated = recentFiles.filter { $0 != url }
        recentFiles = updated
        recentFileBookmarks.removeValue(forKey: Self.urlKey(url))
        persistRecentFiles()
    }

    private func addRecentFile(_ url: URL) {
        var updated = recentFiles.filter { $0 != url }
        updated.insert(url, at: 0)
        if updated.count > Self.maxRecentFiles {
            updated = Array(updated.prefix(Self.maxRecentFiles))
        }
        recentFiles = updated
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            recentFileBookmarks[Self.urlKey(url)] = bookmark
        }
        persistRecentFiles()
    }

    public func saveSelectedDocument() -> Bool {
        guard let document = selectedDocument else {
            return false
        }

        guard let fileURL = document.fileURL else {
            return false
        }

        return saveSelectedDocument(to: fileURL)
    }

    public func saveSelectedDocument(to fileURL: URL) -> Bool {
        guard let index = selectedDocumentIndex else {
            return false
        }

        // Block overwriting the original read-only file; Save As to a new path is always allowed.
        if documents[index].isReadOnly, fileURL == documents[index].fileURL {
            setStatus("Cannot save: \(documents[index].title) is read-only.", tone: .warning)
            return false
        }

        retainSecurityScopedAccess(for: fileURL)
        do {
            try fileIO.save(documents[index], to: fileURL)

            var document = documents[index]
            document.fileURL = fileURL
            document.securityScopedBookmark = try? fileURL.bookmarkData(options: .withSecurityScope)
            document.title = fileURL.lastPathComponent
            document.isScratch = false
            document.isDirty = false
            document.isReadOnly = false
            document.updatedAt = Date()
            documents[index] = document
            reconcileSecurityScopedAccess()
            addRecentFile(fileURL)
            setStatus("Saved \(document.title).")
            saveSession()
            return true
        } catch {
            reconcileSecurityScopedAccess()
            setStatus("Could not save file: \(error.localizedDescription)", tone: .warning)
            return false
        }
    }

    @discardableResult
    public func saveAllDocuments() -> SaveAllResult {
        var savedCount = 0
        var skippedScratchCount = 0
        var skippedCleanCount = 0
        var skippedReadOnlyCount = 0
        var failedCount = 0

        for index in documents.indices {
            guard documents[index].isDirty else {
                skippedCleanCount += 1
                continue
            }

            guard let fileURL = documents[index].fileURL else {
                skippedScratchCount += 1
                continue
            }

            guard !documents[index].isReadOnly else {
                skippedReadOnlyCount += 1
                continue
            }

            do {
                try fileIO.save(documents[index], to: fileURL)
                documents[index].isDirty = false
                documents[index].updatedAt = Date()
                savedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if savedCount > 0 {
            saveSession()
        }

        let result = SaveAllResult(
            savedCount: savedCount,
            skippedScratchCount: skippedScratchCount,
            skippedCleanCount: skippedCleanCount,
            skippedReadOnlyCount: skippedReadOnlyCount,
            failedCount: failedCount
        )
        setStatus(saveAllStatus(for: result), tone: result.failedCount > 0 ? .warning : .neutral)
        return result
    }

    public func applyTransform(
        named name: String,
        transform: (String) -> TextTransformResult
    ) {
        guard let index = selectedDocumentIndex else {
            return
        }

        guard !documents[index].isImageFile else { return }
        guard !documents[index].isReadOnly else { return }

        // SwiftUI.TextEditor on the current macOS target does not expose a stable
        // selection binding, so Phase 4 applies transforms to the full document.
        let originalText = documents[index].text

        switch transform(originalText) {
        case let .success(text, summary):
            guard text != originalText else {
                setStatus("\(name): no changes.")
                return
            }

            var document = documents[index]
            document.text = text
            document.isDirty = true
            document.updatedAt = Date()
            documents[index] = document
            refreshCurrentMatch()
            setStatus(summary)
            scheduleSessionSave()
        case let .failure(message):
            setStatus("\(name): \(message)", tone: .warning)
        }
    }

    public func inspectSelectedText(named name: String, inspector: (String) -> (message: String, tone: StatusMessageTone)) {
        guard let selectedDocument else {
            return
        }

        let result = inspector(selectedDocument.text)
        setStatus("\(name): \(result.message)", tone: result.tone)
    }

    public func reportOperationStatus(_ message: String, tone: StatusMessageTone = .neutral) {
        setStatus(message, tone: tone)
    }

    public func beginFileAccessOperation(at url: URL) {
        beginFileOperation(at: url)
    }

    public func endFileAccessOperation(at url: URL) {
        endFileOperation(at: url)
    }

    public var currentSearchMatchRange: NSRange? {
        guard let currentMatchIndex, cachedSearchRanges.indices.contains(currentMatchIndex) else { return nil }
        return cachedSearchRanges[currentMatchIndex]
    }

    /// Cached ranges from the latest generation-checked evaluation. The editor consumes
    /// these for highlighting so regex matching is never repeated during SwiftUI updates.
    public var searchMatchRanges: [NSRange] {
        cachedSearchRanges
    }

    public func updateSearchQuery(_ query: String) {
        searchOptions.query = query
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            if !query.isEmpty {
                setStatus("Search is not available for large files.", tone: .warning)
            }
            return
        }
        scheduleSearchEvaluation(resetCurrentIndex: true)
    }

    public func updateReplacement(_ replacement: String) {
        searchOptions.replacement = replacement
    }

    public func setRegexSearchEnabled(_ enabled: Bool) {
        searchOptions.usesRegex = enabled
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        scheduleSearchEvaluation(resetCurrentIndex: true)
    }

    public func setCaseSensitiveSearchEnabled(_ enabled: Bool) {
        searchOptions.isCaseSensitive = enabled
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        scheduleSearchEvaluation(resetCurrentIndex: true)
    }

    public func setWholeWordSearchEnabled(_ enabled: Bool) {
        searchOptions.isWholeWord = enabled
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        scheduleSearchEvaluation(resetCurrentIndex: true)
    }

    public func selectNextMatch() {
        guard !(selectedDocument?.isLargeFile == true) else { return }
        guard !cachedSearchRanges.isEmpty else { currentMatchIndex = nil; return }
        currentMatchIndex = ((currentMatchIndex ?? -1) + 1) % cachedSearchRanges.count
        updateCachedSearchSummaryIndex()
    }

    public func selectPreviousMatch() {
        guard !(selectedDocument?.isLargeFile == true) else { return }
        guard !cachedSearchRanges.isEmpty else { currentMatchIndex = nil; return }
        currentMatchIndex = ((currentMatchIndex ?? 0) - 1 + cachedSearchRanges.count) % cachedSearchRanges.count
        updateCachedSearchSummaryIndex()
    }

    public func replaceCurrentMatch() {
        guard !(selectedDocument?.isLargeFile == true) else {
            setStatus("Replace is not available for large files.", tone: .warning)
            return
        }
        guard let index = selectedDocumentIndex else {
            return
        }
        guard currentSearchMatchRange != nil else {
            setStatus("Search results are updating.", tone: .warning)
            return
        }

        switch SearchReplaceEngine.replaceCurrent(
            in: documents[index].text,
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        ) {
        case let .success(text, replacementCount):
            applySearchReplacement(text: text, replacementCount: replacementCount)
        case let .failure(message):
            setStatus(message, tone: .warning)
        }
    }

    public func replaceAllMatches() {
        guard !(selectedDocument?.isLargeFile == true) else {
            setStatus("Replace is not available for large files.", tone: .warning)
            return
        }
        guard let index = selectedDocumentIndex else {
            return
        }

        switch SearchReplaceEngine.replaceAll(
            in: documents[index].text,
            options: searchOptions
        ) {
        case let .success(text, replacementCount):
            applySearchReplacement(text: text, replacementCount: replacementCount)
        case let .failure(message):
            setStatus(message, tone: .warning)
        }
    }

    private var selectedDocumentIndex: Int? {
        guard let selectedDocumentID else {
            return documents.indices.first
        }

        return documents.firstIndex { $0.id == selectedDocumentID }
    }

    private func displayTitleForWindow(_ document: EditorDocument) -> String {
        guard let fileURL = document.fileURL else {
            return document.title
        }

        let matchingNameCount = documents.filter { otherDocument in
            otherDocument.fileURL?.lastPathComponent == fileURL.lastPathComponent
        }.count

        guard matchingNameCount > 1 else {
            return fileURL.lastPathComponent
        }

        return compactPath(for: fileURL)
    }

    private func recordClosedFilesIfNeeded(_ documents: [EditorDocument]) {
        for document in documents.reversed() {
            recordClosedFileIfNeeded(document)
        }
    }

    private func recordClosedFileIfNeeded(_ document: EditorDocument) {
        guard let fileURL = document.fileURL else {
            return
        }

        var updated = recentlyClosedFileURLs.filter { $0 != fileURL }
        updated.insert(fileURL, at: 0)
        if updated.count > Self.maxRecentlyClosedFiles {
            updated = Array(updated.prefix(Self.maxRecentlyClosedFiles))
        }
        recentlyClosedFileURLs = updated
    }

    private func saveAllStatus(for result: SaveAllResult) -> String {
        if result.savedCount == 0 && result.failedCount == 0 {
            if result.skippedScratchCount > 0 {
                return "No file-backed changes to save. Unsaved notes need Save As."
            }
            if result.skippedReadOnlyCount > 0 {
                return "No writable file-backed changes to save."
            }
            return "No file-backed changes to save."
        }

        var parts: [String] = []
        if result.savedCount > 0 {
            parts.append(result.savedCount == 1 ? "Saved 1 file" : "Saved \(result.savedCount) files")
        }
        if result.skippedScratchCount > 0 {
            parts.append(result.skippedScratchCount == 1 ? "skipped 1 unsaved note" : "skipped \(result.skippedScratchCount) unsaved notes")
        }
        if result.skippedReadOnlyCount > 0 {
            parts.append(result.skippedReadOnlyCount == 1 ? "skipped 1 read-only file" : "skipped \(result.skippedReadOnlyCount) read-only files")
        }
        if result.failedCount > 0 {
            parts.append(result.failedCount == 1 ? "failed 1 file" : "failed \(result.failedCount) files")
        }

        return parts.joined(separator: ", ") + "."
    }

    private func compactPath(for fileURL: URL) -> String {
        let path = fileURL.standardizedFileURL.path
        guard path.count > 72 else {
            return path
        }

        let components = fileURL.standardizedFileURL.pathComponents
        guard components.count >= 4 else {
            return path
        }

        let start = NSString.path(withComponents: Array(components.prefix(3)))
        let parent = components.dropLast().last ?? ""
        let fileName = components.last ?? fileURL.lastPathComponent

        return "\(start)/.../\(parent)/\(fileName)"
    }

    private func refreshCurrentMatch() {
        scheduleSearchEvaluation(resetCurrentIndex: false)
    }

    private func scheduleSearchEvaluation(resetCurrentIndex: Bool) {
        pendingSearchEvaluation?.cancel()
        searchEvaluationGeneration += 1
        let generation = searchEvaluationGeneration
        let previousIndex = currentMatchIndex
        // Results are valid only for the exact document text and search criteria that
        // produced them. Invalidate synchronously before the debounced evaluation starts.
        cachedSearchRanges = []
        currentMatchIndex = nil
        searchSummary = SearchSummary(matchCount: 0, currentMatchIndex: nil)
        guard let document = selectedDocument, !document.isLargeFile, !searchOptions.query.isEmpty else {
            return
        }

        let documentID = document.id
        let text = document.text
        let options = searchOptions
        let requestedIndex = resetCurrentIndex ? nil : previousIndex
        let workItem = DispatchWorkItem { [weak self] in
            let evaluation = SearchReplaceEngine.evaluate(
                in: text,
                options: options,
                currentMatchIndex: requestedIndex
            )
            DispatchQueue.main.async {
                guard let self,
                      generation == self.searchEvaluationGeneration,
                      self.selectedDocumentID == documentID,
                      Self.hasSameSearchCriteria(self.searchOptions, options) else { return }
                self.cachedSearchRanges = evaluation.ranges
                self.currentMatchIndex = evaluation.summary.currentMatchIndex
                self.searchSummary = evaluation.summary
            }
        }
        pendingSearchEvaluation = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func updateCachedSearchSummaryIndex() {
        searchSummary = SearchSummary(
            matchCount: cachedSearchRanges.count,
            currentMatchIndex: currentMatchIndex,
            hasInvalidRegex: searchSummary.hasInvalidRegex,
            errorMessage: searchSummary.errorMessage
        )
    }

    private static func hasSameSearchCriteria(_ lhs: SearchOptions, _ rhs: SearchOptions) -> Bool {
        lhs.query == rhs.query
            && lhs.usesRegex == rhs.usesRegex
            && lhs.isCaseSensitive == rhs.isCaseSensitive
            && lhs.isWholeWord == rhs.isWholeWord
    }

    private func applySearchReplacement(text: String, replacementCount: Int) {
        guard let index = selectedDocumentIndex else {
            return
        }

        guard replacementCount > 0, documents[index].text != text else {
            setStatus("No matches replaced.")
            return
        }

        var document = documents[index]
        document.text = text
        document.isDirty = true
        document.updatedAt = Date()
        documents[index] = document
        refreshCurrentMatch()
        setStatus(replacementCount == 1
            ? "Replaced 1 match."
            : "Replaced \(replacementCount) matches.")
        scheduleSessionSave()
    }

    public func flushPendingSessionSave() {
        guard pendingSessionSave != nil else {
            return
        }

        pendingSessionSave?.cancel()
        pendingSessionSave = nil
        saveSession()
    }

    private func setStatus(_ message: String, tone: StatusMessageTone = .neutral) {
        statusMessage = message
        statusMessageTone = tone
    }

    private func saveSession() {
        pendingSessionSave?.cancel()
        pendingSessionSave = nil

        let docsToSave = documents.map { sessionDocumentRecord(from: $0) }
        let session = EditorSession(
            selectedDocumentID: selectedDocumentID,
            documents: docsToSave
        )

        do {
            try sessionStore.saveSession(session)
        } catch {
            setStatus("Could not save session: \(error.localizedDescription)", tone: .warning)
        }
    }

    private func scheduleSessionSave() {
        pendingSessionSave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingSessionSave = nil
            self?.saveSession()
        }
        pendingSessionSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionSaveDebounceInterval, execute: workItem)
    }

    /// Returns a copy of the document with text stripped where it is safe to omit from the session.
    /// Clean file-backed documents store no text; the file on disk is the source of truth.
    /// Scratch and dirty file-backed documents preserve their text. LocalSessionStore keeps
    /// large buffers in local sidecar files so the session JSON stays lightweight.
    private func sessionDocumentRecord(from document: EditorDocument) -> EditorDocument {
        var record = document
        record.text = LargeFilePolicy.sessionText(for: document)
        record.sessionTextFileName = nil
        return record
    }

    private func retainSecurityScopedAccess(for url: URL) {
        let standardized = url.standardizedFileURL
        guard !activeSecurityScopedURLs.contains(standardized) else { return }
        if standardized.startAccessingSecurityScopedResource() {
            activeSecurityScopedURLs.insert(standardized)
        }
    }

    private func stopSecurityScopedAccess(for url: URL) {
        let standardized = url.standardizedFileURL
        guard activeSecurityScopedURLs.remove(standardized) != nil else { return }
        standardized.stopAccessingSecurityScopedResource()
    }

    private func reconcileSecurityScopedAccess() {
        let documentURLs = Set(documents.compactMap { $0.fileURL?.standardizedFileURL })
        let operationURLs = Set(inFlightFileAccessCounts.compactMap { $0.value > 0 ? $0.key : nil })
        let required = documentURLs.union(operationURLs)
        for url in Array(activeSecurityScopedURLs) where !required.contains(url) {
            stopSecurityScopedAccess(for: url)
        }
    }

    private func restoreSecurityScopedAccess() {
        for index in documents.indices {
            guard documents[index].fileURL != nil else { continue }
            guard let bookmark = documents[index].securityScopedBookmark else {
                if Self.isRunningInAppSandbox {
                    documents[index].requiresFileAuthorization = true
                }
                continue
            }
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                documents[index].requiresFileAuthorization = Self.isRunningInAppSandbox
                continue
            }
            documents[index].fileURL = resolvedURL
            retainSecurityScopedAccess(for: resolvedURL)
            documents[index].requiresFileAuthorization = false
            if isStale {
                documents[index].securityScopedBookmark = try? resolvedURL.bookmarkData(options: .withSecurityScope)
            }
        }
    }

    private func beginFileOperation(at url: URL) {
        let standardized = url.standardizedFileURL
        retainSecurityScopedAccess(for: standardized)
        inFlightFileAccessCounts[standardized, default: 0] += 1
    }

    private func endFileOperation(at url: URL) {
        let standardized = url.standardizedFileURL
        let remaining = max((inFlightFileAccessCounts[standardized] ?? 1) - 1, 0)
        if remaining == 0 {
            inFlightFileAccessCounts.removeValue(forKey: standardized)
        } else {
            inFlightFileAccessCounts[standardized] = remaining
        }
        reconcileSecurityScopedAccess()
    }

    private func resolvedRecentFileURL(for url: URL, migratePath: Bool = true) -> URL? {
        guard let bookmark = recentFileBookmarks[Self.urlKey(url)] else { return nil }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        let oldKey = Self.urlKey(url)
        let newKey = Self.urlKey(resolved)
        let refreshed: Data?
        if isStale {
            let didStart = resolved.startAccessingSecurityScopedResource()
            defer { if didStart { resolved.stopAccessingSecurityScopedResource() } }
            refreshed = try? resolved.bookmarkData(options: .withSecurityScope)
        } else {
            refreshed = bookmark
        }
        if migratePath, oldKey != newKey {
            guard let refreshed else { return resolved }
            recentFiles.removeAll { Self.urlKey($0) == oldKey || Self.urlKey($0) == newKey }
            recentFiles.insert(resolved, at: 0)
            recentFileBookmarks.removeValue(forKey: oldKey)
            recentFileBookmarks[newKey] = refreshed
            persistRecentFiles()
        } else if isStale, let refreshed {
            recentFileBookmarks[oldKey] = refreshed
            persistRecentFiles()
        }
        return resolved
    }

    private func persistRecentFiles() {
        let records = recentFiles.map { url in
            RecentFileRecord(path: url.path, bookmark: recentFileBookmarks[Self.urlKey(url)])
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.recentFileRecordsKey)
        }
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: Self.recentFilesKey)
    }

    private static func loadRecentFileRecords() -> [RecentFileRecord] {
        guard let data = UserDefaults.standard.data(forKey: recentFileRecordsKey) else { return [] }
        return (try? JSONDecoder().decode([RecentFileRecord].self, from: data)) ?? []
    }

    private static func urlKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static var isRunningInAppSandbox: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static func restoreSession(using sessionStore: SessionPersisting) -> EditorSession? {
        do {
            guard let session = try sessionStore.loadSession(),
                  !session.documents.isEmpty else {
                return nil
            }

            return session
        } catch {
            return nil
        }
    }

    /// Flags file-backed documents whose backing file no longer exists on disk.
    /// Only clean, empty-text documents are flagged: their content was never persisted
    /// (clean file-backed text is re-read from disk), so a deleted file means the content
    /// is unrecoverable. Dirty documents keep their in-session content and are never flagged.
    private func markMissingBackingFiles() {
        for index in documents.indices {
            let document = documents[index]
            guard let fileURL = document.fileURL, !document.isDirty, document.text.isEmpty else {
                continue
            }
            guard !document.requiresFileAuthorization else { continue }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                documents[index].isMissingFile = true
            }
        }
    }

    /// After session restore, file-backed documents whose text was not persisted
    /// have text == "". Reload them from disk asynchronously.
    private func reloadFileBackedDocumentsIfNeeded() {
        for doc in documents {
            guard let fileURL = doc.fileURL, !doc.isDirty, doc.text.isEmpty, !doc.requiresFileAuthorization else { continue }
            guard !doc.isImageFile else { continue }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let docID = doc.id
            let fileSize = EditorFileIO.byteCount(of: fileURL) ?? 0
            let isLargeFile = LargeFilePolicy.classify(byteCount: fileSize) != .normal
            let isReadOnly = !FileManager.default.isWritableFile(atPath: fileURL.path)

            beginFileOperation(at: fileURL)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let text = try? EditorFileIO().readText(from: fileURL)
                DispatchQueue.main.async {
                    guard let self else { return }
                    defer { self.endFileOperation(at: fileURL) }
                    guard let text,
                          let idx = self.documents.firstIndex(where: { $0.id == docID }) else { return }
                    self.documents[idx].text = text
                    self.documents[idx].isLargeFile = isLargeFile
                    self.documents[idx].isReadOnly = isReadOnly
                }
            }
        }
    }

    private func reloadDocumentTextIfNeeded(id: EditorDocument.ID) {
        guard let document = documents.first(where: { $0.id == id }),
              let fileURL = document.fileURL,
              !document.isImageFile else { return }
        beginFileOperation(at: fileURL)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try EditorFileIO().readText(from: fileURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.endFileOperation(at: fileURL) }
                guard let index = self.documents.firstIndex(where: { $0.id == id }) else { return }
                switch result {
                case let .success(text):
                    self.documents[index].text = text
                    self.documents[index].updatedAt = Date()
                    self.scheduleSearchEvaluation(resetCurrentIndex: true)
                    self.setStatus("Access restored for \(fileURL.lastPathComponent).")
                case let .failure(error):
                    self.documents[index].requiresFileAuthorization = true
                    self.setStatus("Could not read file: \(error.localizedDescription)", tone: .warning)
                }
            }
        }
    }
}
