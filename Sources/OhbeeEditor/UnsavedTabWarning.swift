import AppKit
import OhbeeEditorCore

enum UnsavedTabWarning {
    enum CloseDecision {
        case closeWithoutSaving
        case saveThenClose
        case cancel
    }

    static func confirmClosing(_ documents: [EditorDocument]) -> Bool {
        closeDecision(for: documents) == .closeWithoutSaving
    }

    static func closeDecision(for documents: [EditorDocument]) -> CloseDecision {
        let dirtyDocuments = documents.filter(\.isDirty)
        guard !dirtyDocuments.isEmpty else {
            return .closeWithoutSaving
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = dirtyDocuments.count == 1
            ? "This tab has unsaved changes."
            : "\(dirtyDocuments.count) tabs have unsaved changes."
        alert.informativeText = informativeText(for: dirtyDocuments)
        if dirtyDocuments.count == 1 {
            alert.addButton(withTitle: "Save")
        }
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if dirtyDocuments.count == 1 {
            switch response {
            case .alertFirstButtonReturn:
                return .saveThenClose
            case .alertSecondButtonReturn:
                return .closeWithoutSaving
            default:
                return .cancel
            }
        }

        return response == .alertFirstButtonReturn ? .closeWithoutSaving : .cancel
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
