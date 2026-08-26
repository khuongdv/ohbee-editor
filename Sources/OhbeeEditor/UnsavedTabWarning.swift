import AppKit
import OhbeeEditorCore

enum UnsavedTabWarning {
    enum CloseDecision {
        case closeWithoutSaving
        case saveThenClose
        case saveAllThenClose
        case cancel
    }

    static func closeDecision(for documents: [EditorDocument]) -> CloseDecision {
        let dirtyDocuments = documents.filter(\.isDirty)
        guard !dirtyDocuments.isEmpty else {
            return .closeWithoutSaving
        }

        let isSingleDocument = dirtyDocuments.count == 1
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isSingleDocument
            ? "This tab has unsaved changes."
            : "\(dirtyDocuments.count) tabs have unsaved changes."
        alert.informativeText = informativeText(for: dirtyDocuments)
        // Closing several dirty tabs must not force a discard-or-cancel choice; saving them
        // is the whole point of the warning.
        alert.addButton(withTitle: isSingleDocument ? "Save" : "Save All")
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return isSingleDocument ? .saveThenClose : .saveAllThenClose
        case .alertSecondButtonReturn:
            return .closeWithoutSaving
        default:
            return .cancel
        }
    }

    private static func informativeText(for documents: [EditorDocument]) -> String {
        if documents.count == 1, let document = documents.first {
            return "Closing \"\(document.title)\" will discard changes that have not been saved to a file."
        }

        let titles = documents
            .prefix(5)
            .map { "\"\($0.title)\"" }
            .joined(separator: ", ")
        let remainingCount = documents.count - min(documents.count, 5)

        if remainingCount > 0 {
            return "Closing \(titles), and \(remainingCount) more will discard changes that have not been saved to files."
        }

        return "Closing \(titles) will discard changes that have not been saved to files."
    }
}
