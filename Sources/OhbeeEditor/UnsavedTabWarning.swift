import AppKit
import OhbeeEditorCore

enum UnsavedTabWarning {
    static func confirmClosing(_ documents: [EditorDocument]) -> Bool {
        let dirtyDocuments = documents.filter(\.isDirty)
        guard !dirtyDocuments.isEmpty else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = dirtyDocuments.count == 1
            ? "This tab has unsaved changes."
            : "\(dirtyDocuments.count) tabs have unsaved changes."
        alert.informativeText = informativeText(for: dirtyDocuments)
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
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
