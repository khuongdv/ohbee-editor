import AppKit
import OhbeeEditorCore

/// Alert shown when the user opens a tab whose backing file was deleted while the app was closed.
/// The original content was never persisted (clean file-backed text is re-read from disk), so the
/// only sensible action is to remove the tab. No copy of the content is offered or written anywhere.
enum MissingFileWarning {
    /// Returns true when the user confirms removing the missing-file tab.
    static func confirmRemoval(_ document: EditorDocument) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Original file was deleted"
        alert.informativeText = "\"\(document.title)\" no longer exists on disk. "
            + "This tab's content was not saved, so it can't be restored. Remove this tab?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
