import Foundation
import SwiftUI

public enum StatusMessageTone {
    case neutral
    case success
    case warning
}

public final class EditorStore: ObservableObject {
    public static let maxDocumentCount = 50
    private static let recentFilesKey = "ohbee.recentFiles"
    private static let maxRecentFiles = 10

    @Published public private(set) var documents: [EditorDocument]
    @Published public var selectedDocumentID: EditorDocument.ID?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var statusMessageTone: StatusMessageTone = .neutral
    @Published public var searchOptions = SearchOptions()
    @Published public private(set) var currentMatchIndex: Int?
    @Published public private(set) var recentFiles: [URL]

    private let sessionStore: SessionPersisting
    private let fileIO: EditorFileIO

    public init(
        documents: [EditorDocument]? = nil,
        selectedDocumentID: EditorDocument.ID? = nil,
        sessionStore: SessionPersisting = LocalSessionStore(),
        fileIO: EditorFileIO = EditorFileIO()
    ) {
        self.sessionStore = sessionStore
        self.fileIO = fileIO

        let paths = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) ?? []
        self.recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }

        let restoredSession = Self.restoreSession(using: sessionStore)
        let requestedDocuments = documents ?? restoredSession?.documents
        let initialDocuments = (requestedDocuments?.isEmpty == false)
            ? requestedDocuments!
            : [EditorDocument.scratch(index: 1)]

        self.documents = initialDocuments
        self.selectedDocumentID = selectedDocumentID
            ?? restoredSession?.selectedDocumentID
            ?? initialDocuments[0].id

        if self.selectedDocument == nil {
            self.selectedDocumentID = initialDocuments[0].id
        }

        // Restore text for file-backed documents whose text was not persisted in the session.
        // Deferred so init completes before async work begins.
        DispatchQueue.main.async { [weak self] in
            self?.reloadFileBackedDocumentsIfNeeded()
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
        refreshCurrentMatch()
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

        let closedTitle = documents[index].title
        documents.remove(at: index)

        if documents.isEmpty {
            let document = EditorDocument.scratch(index: 1)
            documents = [document]
            selectedDocumentID = document.id
        } else if selectedDocumentID == id {
            let nextIndex = min(index, documents.count - 1)
            selectedDocumentID = documents[nextIndex].id
        }

        refreshCurrentMatch()
        setStatus("Closed \(closedTitle).")
        saveSession()
    }

    public func closeOtherDocuments(keeping id: EditorDocument.ID) {
        guard let document = documents.first(where: { $0.id == id }) else {
            return
        }

        let closedCount = max(documents.count - 1, 0)
        documents = [document]
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

        documents.removeSubrange((index + 1)..<documents.count)
        selectedDocumentID = id
        refreshCurrentMatch()
        setStatus(closedCount == 1 ? "Closed 1 tab to the right." : "Closed \(closedCount) tabs to the right.")
        saveSession()
    }

    public func closeAllDocuments() {
        let closedCount = documents.count
        let document = EditorDocument.scratch(index: 1)
        documents = [document]
        selectedDocumentID = document.id
        currentMatchIndex = nil
        setStatus(closedCount == 1 ? "Closed 1 tab." : "Closed \(closedCount) tabs.")
        saveSession()
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
        document.updatedAt = Date()
        documents[index] = document
        refreshCurrentMatch()
        saveSession()
    }

    /// Opens a file asynchronously. A placeholder tab appears immediately while the
    /// file is read on a background thread, then the text is delivered on the main thread.
    /// Image files (png/jpg/jpeg/webp/bmp/svg) skip text loading and are shown in ImageViewerView.
    public func openDocument(from fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            removeRecentFile(fileURL)
            setStatus("File no longer exists and has been removed from recents: \(fileURL.lastPathComponent)", tone: .warning)
            return
        }

        if let existing = documents.first(where: { $0.fileURL == fileURL }) {
            selectedDocumentID = existing.id
            currentMatchIndex = nil
            setStatus("Switched to \(existing.title).")
            return
        }

        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        let isImageFile = EditorDocument.imageExtensions.contains(fileURL.pathExtension.lowercased())
        let isReadOnly = !FileManager.default.isWritableFile(atPath: fileURL.path)

        var isLargeFile = false
        if !isImageFile {
            let fileSize = EditorFileIO.byteCount(of: fileURL) ?? 0
            let category = LargeFilePolicy.classify(byteCount: fileSize)

            if category == .tooLarge {
                setStatus(
                    "\(fileURL.lastPathComponent) exceeds \(LargeFilePolicy.maximumByteLimit / 1_048_576) MB. " +
                    "Ohbee Editor is not designed for files this large.",
                    tone: .warning
                )
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
            isLargeFile: isLargeFile,
            isReadOnly: isReadOnly
        )

        documents.append(placeholder)
        selectedDocumentID = placeholder.id
        currentMatchIndex = nil

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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let text = try EditorFileIO().readText(from: fileURL)
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let idx = self.documents.firstIndex(where: { $0.id == docID }) else { return }
                    self.documents[idx].text = text
                    self.documents[idx].updatedAt = Date()
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
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.documents.removeAll { $0.id == docID }
                    if self.selectedDocumentID == docID {
                        self.selectedDocumentID = self.documents.last?.id
                    }
                    self.setStatus("Could not open file: \(error.localizedDescription)", tone: .warning)
                }
            }
        }
    }

    public func clearRecentFiles() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: Self.recentFilesKey)
    }

    private func removeRecentFile(_ url: URL) {
        let updated = recentFiles.filter { $0 != url }
        recentFiles = updated
        UserDefaults.standard.set(updated.map(\.path), forKey: Self.recentFilesKey)
    }

    private func addRecentFile(_ url: URL) {
        var updated = recentFiles.filter { $0 != url }
        updated.insert(url, at: 0)
        if updated.count > Self.maxRecentFiles {
            updated = Array(updated.prefix(Self.maxRecentFiles))
        }
        recentFiles = updated
        UserDefaults.standard.set(updated.map(\.path), forKey: Self.recentFilesKey)
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

        do {
            try fileIO.save(documents[index], to: fileURL)

            var document = documents[index]
            document.fileURL = fileURL
            document.title = fileURL.lastPathComponent
            document.isScratch = false
            document.isDirty = false
            document.isReadOnly = false
            document.updatedAt = Date()
            documents[index] = document
            setStatus("Saved \(document.title).")
            saveSession()
            return true
        } catch {
            setStatus("Could not save file: \(error.localizedDescription)", tone: .warning)
            return false
        }
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
            saveSession()
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

    public var searchSummary: SearchSummary {
        guard !(selectedDocument?.isLargeFile == true) else {
            return SearchSummary(matchCount: 0, currentMatchIndex: nil)
        }
        return SearchReplaceEngine.summary(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
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
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
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
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
    }

    public func setCaseSensitiveSearchEnabled(_ enabled: Bool) {
        searchOptions.isCaseSensitive = enabled
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
    }

    public func setWholeWordSearchEnabled(_ enabled: Bool) {
        searchOptions.isWholeWord = enabled
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
    }

    public func selectNextMatch() {
        guard !(selectedDocument?.isLargeFile == true) else { return }
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
    }

    public func selectPreviousMatch() {
        guard !(selectedDocument?.isLargeFile == true) else { return }
        currentMatchIndex = SearchReplaceEngine.previousMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
    }

    public func replaceCurrentMatch() {
        guard !(selectedDocument?.isLargeFile == true) else {
            setStatus("Replace is not available for large files.", tone: .warning)
            return
        }
        guard let index = selectedDocumentIndex else {
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
        guard !(selectedDocument?.isLargeFile == true) else {
            currentMatchIndex = nil
            return
        }
        currentMatchIndex = SearchReplaceEngine.summary(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        ).currentMatchIndex
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
        saveSession()
    }

    private func setStatus(_ message: String, tone: StatusMessageTone = .neutral) {
        statusMessage = message
        statusMessageTone = tone
    }

    private func saveSession() {
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

    /// Returns a copy of the document with text stripped where it is safe to omit from the session.
    /// Clean file-backed documents store no text; the file on disk is the source of truth.
    /// Scratch and dirty file-backed documents store text up to LargeFilePolicy.sessionTextCap.
    private func sessionDocumentRecord(from document: EditorDocument) -> EditorDocument {
        var record = document
        record.text = LargeFilePolicy.sessionText(for: document)
        if record.text.isEmpty && document.isDirty && document.fileURL != nil {
            // Dirty text was too large to persist; restore will load the last saved file.
            record.isDirty = false
        }
        return record
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

    /// After session restore, file-backed documents whose text was not persisted
    /// have text == "". Reload them from disk asynchronously.
    private func reloadFileBackedDocumentsIfNeeded() {
        for doc in documents {
            guard let fileURL = doc.fileURL, !doc.isDirty, doc.text.isEmpty else { continue }
            guard !doc.isImageFile else { continue }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let docID = doc.id
            let fileSize = EditorFileIO.byteCount(of: fileURL) ?? 0
            let isLargeFile = LargeFilePolicy.classify(byteCount: fileSize) != .normal
            let isReadOnly = !FileManager.default.isWritableFile(atPath: fileURL.path)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let text = try? EditorFileIO().readText(from: fileURL) else { return }
                DispatchQueue.main.async {
                    guard let self,
                          let idx = self.documents.firstIndex(where: { $0.id == docID }) else { return }
                    self.documents[idx].text = text
                    self.documents[idx].isLargeFile = isLargeFile
                    self.documents[idx].isReadOnly = isReadOnly
                }
            }
        }
    }
}
