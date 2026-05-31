import AppKit
import OhbeeEditorCore

final class EditorTextOperationCenter {
    static let shared = EditorTextOperationCenter()

    private weak var textView: NSTextView?
    private var documentID: EditorDocument.ID?

    private init() {}

    func register(textView: NSTextView, documentID: EditorDocument.ID) {
        self.textView = textView
        self.documentID = documentID
    }

    func unregister(textView: NSTextView) {
        guard self.textView === textView else {
            return
        }

        self.textView = nil
        self.documentID = nil
    }

    func applyTransform(
        named name: String,
        store: EditorStore,
        transform: (String) -> TextTransformResult
    ) {
        guard
            let textView = activeTextView(for: store),
            let document = store.selectedDocument
        else {
            store.applyTransform(named: name, transform: transform)
            return
        }

        finalizeMarkedText(in: textView)
        let fullText = textView.string as NSString
        let targetRange = operationRange(in: textView, textLength: fullText.length)
        let originalText = fullText.substring(with: targetRange)

        switch transform(originalText) {
        case let .success(text, summary):
            guard text != originalText else {
                store.reportOperationStatus("\(name): no changes.")
                return
            }

            guard replaceText(in: textView, range: targetRange, with: text) else {
                store.reportOperationStatus("\(name): could not apply change.", tone: .warning)
                return
            }

            store.reportOperationStatus(summary)
            selectRangeAfterTransform(in: textView, originalDocument: document, replacement: text)
        case let .failure(message):
            store.reportOperationStatus("\(name): \(message)", tone: .warning)
        }
    }

    func inspectText(
        named name: String,
        store: EditorStore,
        inspector: (String) -> (message: String, tone: StatusMessageTone)
    ) {
        guard let textView = activeTextView(for: store) else {
            store.inspectSelectedText(named: name, inspector: inspector)
            return
        }

        finalizeMarkedText(in: textView)
        let source = textView.string as NSString
        let targetRange = operationRange(in: textView, textLength: source.length)
        let result = inspector(source.substring(with: targetRange))
        store.reportOperationStatus("\(name): \(result.message)", tone: result.tone)
    }

    func operationText(store: EditorStore) -> String {
        guard let textView = activeTextView(for: store) else {
            return store.selectedDocument?.text ?? ""
        }

        finalizeMarkedText(in: textView)
        let source = textView.string as NSString
        let targetRange = operationRange(in: textView, textLength: source.length)
        return source.substring(with: targetRange)
    }

    func selectedText(store: EditorStore) -> String? {
        guard let textView = activeTextView(for: store) else {
            return nil
        }

        finalizeMarkedText(in: textView)
        let source = textView.string as NSString
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0, NSMaxRange(selectedRange) <= source.length else {
            return nil
        }

        return source.substring(with: selectedRange)
    }

    func applyReviewedText(_ replacement: String, named name: String, store: EditorStore) {
        applyTransform(named: name, store: store) { _ in
            .success(text: replacement, summary: "Applied Safe Share mask.")
        }
    }

    func selectCurrentSearchMatch(store: EditorStore) {
        guard
            let textView = activeTextView(for: store),
            let currentMatchIndex = store.currentMatchIndex,
            let range = SearchReplaceEngine.matchRange(
                in: textView.string,
                options: store.searchOptions,
                matchIndex: currentMatchIndex
            )
        else {
            return
        }

        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    func replaceCurrentSearchMatch(store: EditorStore) {
        guard
            let textView = activeTextView(for: store),
            let currentMatchIndex = store.currentMatchIndex
        else {
            store.replaceCurrentMatch()
            return
        }

        finalizeMarkedText(in: textView)
        guard
            let range = SearchReplaceEngine.matchRange(
                in: textView.string,
                options: store.searchOptions,
                matchIndex: currentMatchIndex
            )
        else {
            store.replaceCurrentMatch()
            return
        }

        let source = (textView.string as NSString).substring(with: range)
        let replacement = SearchReplaceEngine.replacementText(forMatchedText: source, options: store.searchOptions)
        guard replaceText(in: textView, range: range, with: replacement) else {
            store.reportOperationStatus("Replace: could not apply change.", tone: .warning)
            return
        }

        store.reportOperationStatus("Replaced 1 match.")

        DispatchQueue.main.async {
            self.selectCurrentSearchMatch(store: store)
        }
    }

    func replaceAllSearchMatches(store: EditorStore) {
        guard let textView = activeTextView(for: store) else {
            store.replaceAllMatches()
            return
        }

        finalizeMarkedText(in: textView)
        switch SearchReplaceEngine.replaceAll(in: textView.string, options: store.searchOptions) {
        case let .success(text, replacementCount):
            guard replacementCount > 0, text != textView.string else {
                store.reportOperationStatus("No matches replaced.")
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard replaceText(in: textView, range: fullRange, with: text) else {
                store.reportOperationStatus("Replace All: could not apply change.", tone: .warning)
                return
            }

            store.reportOperationStatus(replacementCount == 1
                ? "Replaced 1 match."
                : "Replaced \(replacementCount) matches.")

            DispatchQueue.main.async {
                self.selectCurrentSearchMatch(store: store)
            }
        case let .failure(message):
            store.reportOperationStatus(message, tone: .warning)
        }
    }

    func duplicateLineInActiveEditor() {
        guard let textView = textView as? SmartIndentingTextView else { return }
        textView.triggerDuplicateLine()
    }

    private func activeTextView(for store: EditorStore) -> NSTextView? {
        guard
            let textView,
            documentID == store.selectedDocumentID
        else {
            return nil
        }

        return textView
    }

    private func operationRange(in textView: NSTextView, textLength: Int) -> NSRange {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else {
            return NSRange(location: 0, length: textLength)
        }

        guard selectedRange.location + selectedRange.length <= textLength else {
            return NSRange(location: 0, length: textLength)
        }

        return selectedRange
    }

    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String) -> Bool {
        guard textView.isEditable else {
            return false
        }

        finalizeMarkedText(in: textView)

        guard let textStorage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: replacement) else {
            return false
        }

        textView.breakUndoCoalescing()
        textView.undoManager?.beginUndoGrouping()
        textStorage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.undoManager?.endUndoGrouping()
        return true
    }

    private func finalizeMarkedText(in textView: NSTextView) {
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
    }

    private func selectRangeAfterTransform(
        in textView: NSTextView,
        originalDocument: EditorDocument,
        replacement: String
    ) {
        guard originalDocument.id == documentID else {
            return
        }

        let insertionLocation = textView.selectedRange().location
        let replacementLength = (replacement as NSString).length
        let selectionLocation = max(0, insertionLocation - replacementLength)
        let selection = NSRange(location: selectionLocation, length: replacementLength)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
    }
}
