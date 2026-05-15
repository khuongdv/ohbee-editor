import Foundation
import SwiftUI

public enum StatusMessageTone {
    case neutral
    case success
    case warning
}

public final class EditorStore: ObservableObject {
    public static let maxDocumentCount = 50

    @Published public private(set) var documents: [EditorDocument]
    @Published public var selectedDocumentID: EditorDocument.ID?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var statusMessageTone: StatusMessageTone = .neutral
    @Published public var searchOptions = SearchOptions()
    @Published public private(set) var currentMatchIndex: Int?

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

    public func openDocument(from fileURL: URL) {
        guard canCreateScratchDocument else {
            setStatus("Maximum \(Self.maxDocumentCount) tabs reached.", tone: .warning)
            return
        }

        do {
            let document = try fileIO.openDocument(from: fileURL)
            documents.append(document)
            selectedDocumentID = document.id
            currentMatchIndex = nil
            setStatus("Opened \(document.title).")
            saveSession()
        } catch {
            setStatus("Could not open file: \(error.localizedDescription)", tone: .warning)
        }
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

        do {
            try fileIO.save(documents[index], to: fileURL)

            var document = documents[index]
            document.fileURL = fileURL
            document.title = fileURL.lastPathComponent
            document.isScratch = false
            document.isDirty = false
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
        SearchReplaceEngine.summary(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
    }

    public func updateSearchQuery(_ query: String) {
        searchOptions.query = query
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
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
    }

    public func setCaseSensitiveSearchEnabled(_ enabled: Bool) {
        searchOptions.isCaseSensitive = enabled
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: nil
        )
    }

    public func selectNextMatch() {
        currentMatchIndex = SearchReplaceEngine.nextMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
    }

    public func selectPreviousMatch() {
        currentMatchIndex = SearchReplaceEngine.previousMatchIndex(
            in: selectedDocument?.text ?? "",
            options: searchOptions,
            currentMatchIndex: currentMatchIndex
        )
    }

    public func replaceCurrentMatch() {
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
        let scratchDocuments = documents.filter(\.isScratch)
        let selectedScratchID = scratchDocuments.contains { $0.id == selectedDocumentID }
            ? selectedDocumentID
            : scratchDocuments.first?.id

        let session = EditorSession(
            selectedDocumentID: selectedScratchID,
            documents: scratchDocuments
        )

        do {
            try sessionStore.saveSession(session)
        } catch {
            setStatus("Could not save session: \(error.localizedDescription)", tone: .warning)
        }
    }

    private static func restoreSession(using sessionStore: SessionPersisting) -> EditorSession? {
        do {
            guard let session = try sessionStore.loadSession() else {
                return nil
            }

            let scratchDocuments = session.documents.filter(\.isScratch)
            guard !scratchDocuments.isEmpty else {
                return nil
            }

            return EditorSession(
                selectedDocumentID: session.selectedDocumentID,
                documents: scratchDocuments
            )
        } catch {
            return nil
        }
    }
}
