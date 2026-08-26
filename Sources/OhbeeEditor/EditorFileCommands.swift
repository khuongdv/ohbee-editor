import AppKit
import OhbeeEditorCore

/// The single implementation of file and tab-close commands. Both the menu bar
/// (`OhbeeEditorApp`) and the in-window controls (`ContentView`) route through this type so the
/// two surfaces cannot drift apart on save prompts, unsaved-change warnings, or panel behavior.
struct EditorFileCommands {
    let store: EditorStore

    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            store.openDocument(from: url)
        }
    }

    @discardableResult
    func save() -> Bool {
        if store.saveSelectedDocument() {
            return true
        }

        return saveAs()
    }

    @discardableResult
    func saveAs() -> Bool {
        guard let document = store.selectedDocument else {
            return false
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.title

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return false
        }

        return store.saveSelectedDocument(to: fileURL)
    }

    func saveAll() {
        store.saveAllDocuments()
    }

    func closeSelectedTab() {
        guard let selectedDocumentID = store.selectedDocumentID else {
            return
        }

        closeTab(selectedDocumentID)
    }

    func closeTab(_ id: EditorDocument.ID) {
        guard let document = store.documents.first(where: { $0.id == id }) else {
            return
        }

        if document.isMissingFile {
            store.discardMissingDocument(id)
            return
        }

        closeDocumentsWithWarning([document]) {
            store.closeDocument(id)
        }
    }

    func closeOtherTabs(keeping id: EditorDocument.ID) {
        let closingDocuments = store.documents.filter { $0.id != id }
        closeDocumentsWithWarning(closingDocuments) {
            store.closeOtherDocuments(keeping: id)
        }
    }

    func closeTabsToRight(of id: EditorDocument.ID) {
        guard let index = store.documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        let closingDocuments = Array(store.documents.suffix(from: index + 1))
        closeDocumentsWithWarning(closingDocuments) {
            store.closeDocumentsToRight(of: id)
        }
    }

    func closeAllTabs() {
        closeDocumentsWithWarning(store.documents) {
            store.closeAllDocuments()
        }
    }

    func hasTabsToRight(of id: EditorDocument.ID) -> Bool {
        guard let index = store.documents.firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index < store.documents.count - 1
    }

    private func closeDocumentsWithWarning(_ documents: [EditorDocument], close: () -> Void) {
        switch UnsavedTabWarning.closeDecision(for: documents) {
        case .closeWithoutSaving:
            close()
        case .saveThenClose, .saveAllThenClose:
            guard saveDirtyDocuments(in: documents) else {
                return
            }

            close()
        case .cancel:
            return
        }
    }

    /// Saves every dirty document that is about to close. Unsaved notes go through Save As so
    /// the user decides where new files land. A cancelled or failed save aborts the close, so a
    /// buffer is never discarded because part of the batch could not be written.
    private func saveDirtyDocuments(in documents: [EditorDocument]) -> Bool {
        let previousSelectionID = store.selectedDocumentID

        for document in documents where document.isDirty {
            store.selectDocument(document.id)
            guard save() else {
                if let previousSelectionID {
                    store.selectDocument(previousSelectionID)
                }
                store.reportOperationStatus(
                    "Close cancelled: \(document.title) was not saved.",
                    tone: .warning
                )
                return false
            }
        }

        return true
    }
}
