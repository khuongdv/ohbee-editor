import AppKit
import SwiftUI
import OhbeeEditorCore

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let language: EditorLanguage
    let documentID: EditorDocument.ID
    var showLineNumbers: Bool = true
    var onFileDrop: (([URL]) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = SmartIndentingTextView()
        textView.delegate = context.coordinator
        textView.languageProvider = { [weak coordinator = context.coordinator] in
            coordinator?.language ?? .plainText
        }
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.documentID = documentID
        context.coordinator.language = language
        context.coordinator.applyHighlighting(to: textView)
        EditorTextOperationCenter.shared.register(textView: textView, documentID: documentID)
        textView.onFileDrop = onFileDrop
        var rulerRef: LineNumberRulerView?
        if showLineNumbers {
            let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            rulerRef = ruler
        }
        let fileURLType = NSPasteboard.PasteboardType.fileURL
        if !textView.registeredDraggedTypes.contains(fileURLType) {
            textView.registerForDraggedTypes(textView.registeredDraggedTypes + [fileURLType])
        }

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            rulerRef?.syncCursorLine()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SmartIndentingTextView else {
            return
        }

        textView.onFileDrop = onFileDrop
        context.coordinator.text = $text
        let documentChanged = context.coordinator.documentID != documentID
        let languageChanged = context.coordinator.language != language
        context.coordinator.documentID = documentID
        context.coordinator.language = language
        EditorTextOperationCenter.shared.register(textView: textView, documentID: documentID)

        if showLineNumbers {
            if !(scrollView.verticalRulerView is LineNumberRulerView) {
                let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView)
                scrollView.verticalRulerView = ruler
                scrollView.hasVerticalRuler = true
            }
            scrollView.rulersVisible = true
            scrollView.verticalRulerView?.needsDisplay = true
        } else {
            scrollView.rulersVisible = false
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            let textLength = (text as NSString).length
            let validRanges = selectedRanges.filter { NSMaxRange($0.rangeValue) <= textLength }
            textView.selectedRanges = validRanges.isEmpty
                ? [NSValue(range: NSRange(location: 0, length: 0))]
                : validRanges
            context.coordinator.isApplyingExternalText = false
            context.coordinator.applyHighlighting(to: textView)
        } else if languageChanged {
            context.coordinator.applyHighlighting(to: textView)
        }

        if documentChanged {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NSTextView {
            EditorTextOperationCenter.shared.unregister(textView: textView)
        }

        coordinator.cancelScheduledHighlighting()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var language: EditorLanguage = .plainText
        var documentID: EditorDocument.ID?
        var isApplyingExternalText = false

        private let highlighter = SimpleSyntaxHighlighter()
        private var pendingHighlight: DispatchWorkItem?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
            scheduleHighlighting(to: textView)
        }

        func applyHighlighting(to textView: NSTextView) {
            pendingHighlight?.cancel()
            pendingHighlight = nil
            highlighter.apply(language: language, to: textView)
        }

        func scheduleHighlighting(to textView: NSTextView) {
            guard language != .plainText else {
                return
            }

            pendingHighlight?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else {
                    return
                }

                self.highlighter.apply(language: self.language, to: textView)
            }

            pendingHighlight = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func cancelScheduledHighlighting() {
            pendingHighlight?.cancel()
            pendingHighlight = nil
        }
    }
}

private final class SmartIndentingTextView: NSTextView {
    var languageProvider: (() -> EditorLanguage)?
    var onFileDrop: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fileURLs(from: sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = fileURLs(from: sender), !urls.isEmpty {
            onFileDrop?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL]? {
        let pb = info.draggingPasteboard
        guard let objects = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !objects.isEmpty else {
            return nil
        }
        return objects
    }

    // MARK: - Column Selection

    private var columnAnchorPoint: NSPoint?
    private var isColumnSelecting = false
    private var columnRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            isColumnSelecting = true
            columnAnchorPoint = convert(event.locationInWindow, from: nil)
            refreshColumnRanges(from: columnAnchorPoint!, to: columnAnchorPoint!)
        } else {
            exitColumnMode()
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isColumnSelecting, let anchor = columnAnchorPoint else {
            super.mouseDragged(with: event)
            return
        }
        refreshColumnRanges(from: anchor, to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isColumnSelecting else {
            super.mouseUp(with: event)
            return
        }
        // Column selection stays active until a normal click or ESC
    }

    private func refreshColumnRanges(from anchor: NSPoint, to current: NSPoint) {
        let ns = string as NSString
        let lineMap = LineMap(string: ns)
        guard let anchorIdx = columnCharIndex(at: anchor),
              let currentIdx = columnCharIndex(at: current) else { return }
        let aLC = lineMap.lineAndColumn(for: anchorIdx)
        let cLC = lineMap.lineAndColumn(for: currentIdx)
        let sel = ColumnSelection(
            startLine: min(aLC.line, cLC.line),
            endLine: max(aLC.line, cLC.line),
            startCol: min(aLC.col, cLC.col),
            endCol: max(aLC.col, cLC.col)
        )
        columnRanges = sel.ranges(in: ns, lineMap: lineMap)
        selectedRanges = columnRanges.map { NSValue(range: $0) }
    }

    private func columnCharIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = NSPoint(x: point.x - textContainerInset.width,
                        y: point.y - textContainerInset.height)
        var fraction: CGFloat = 0
        let idx = lm.characterIndex(for: p, in: tc,
                                    fractionOfDistanceBetweenInsertionPoints: &fraction)
        // Convert character index to insertion point: if past the midpoint of a character,
        // advance by 1 so the character is included in the selection.
        return fraction >= 0.5 ? idx + 1 : idx
    }

    override func copy(_ sender: Any?) {
        guard isColumnSelecting, !columnRanges.isEmpty else {
            super.copy(sender)
            return
        }
        let text = copyColumnRanges(columnRanges, from: string as NSString)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard isColumnSelecting, !columnRanges.isEmpty else {
            super.cut(sender)
            return
        }
        copy(sender)
        deleteColumnRanges()
    }

    private enum KeyCode {
        static let backspace: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let escape: UInt16 = 53
    }

    override func keyDown(with event: NSEvent) {
        guard isColumnSelecting else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case KeyCode.backspace, KeyCode.forwardDelete:
            deleteColumnRanges()
        case KeyCode.escape:
            exitColumnMode()
        default:
            exitColumnMode()
            super.keyDown(with: event)
        }
    }

    private func deleteColumnRanges() {
        undoManager?.beginUndoGrouping()
        for range in columnRanges.sorted(by: { $0.location > $1.location }) {
            insertText("", replacementRange: range)
        }
        undoManager?.endUndoGrouping()
        exitColumnMode()
    }

    private func exitColumnMode() {
        guard isColumnSelecting else { return }
        isColumnSelecting = false
        columnAnchorPoint = nil
        let cursor = columnRanges.first.map { NSRange(location: $0.location, length: 0) }
            ?? NSRange(location: selectedRange().location, length: 0)
        columnRanges = []
        setSelectedRange(cursor)
    }

    // MARK: - Smart Indentation

    override func insertNewline(_ sender: Any?) {
        guard languageProvider?() != .plainText else {
            super.insertNewline(sender)
            return
        }

        let insertion = "\n" + leadingWhitespaceForCurrentLine()
        insertText(insertion, replacementRange: selectedRange())
    }

    private func leadingWhitespaceForCurrentLine() -> String {
        let source = string as NSString
        let cursorLocation = selectedRange().location
        let safeLocation = min(cursorLocation, source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        var index = lineRange.location
        var indentation = ""

        while index < safeLocation {
            let character = source.character(at: index)
            if character == 32 {
                indentation.append(" ")
            } else if character == 9 {
                indentation.append("\t")
            } else {
                break
            }

            index += 1
        }

        return indentation
    }
}

private final class SimpleSyntaxHighlighter {
    private let maxHighlightedCharacters = 300_000

    func apply(language: EditorLanguage, to textView: NSTextView) {
        guard let storage = textView.textStorage else {
            return
        }

        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let font = textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]

        storage.beginEditing()
        storage.setAttributes(defaultAttributes, range: fullRange)

        if text.count <= maxHighlightedCharacters {
            highlight(language: language, text: text, storage: storage)
        }

        storage.endEditing()
        textView.typingAttributes = defaultAttributes
    }

    private func highlight(language: EditorLanguage, text: String, storage: NSTextStorage) {
        switch language {
        case .plainText:
            return
        case .json:
            highlightJSON(text: text, storage: storage)
        case .html:
            highlightHTML(text: text, storage: storage)
        case .xml:
            highlightXML(text: text, storage: storage)
        case .sql:
            highlightSQL(text: text, storage: storage)
        case .css:
            highlightCSS(text: text, storage: storage)
        case .yaml:
            highlightYAML(text: text, storage: storage)
        case .markdown:
            highlightMarkdown(text: text, storage: storage)
        case .java:
            highlightJava(text: text, storage: storage)
        case .javascript, .cSharp, .cPlusPlus, .swift, .python, .shell:
            highlightCode(definition: codeDefinition(for: language), text: text, storage: storage)
        }
    }

    private func highlightJSON(text: String, storage: NSTextStorage) {
        add(pattern: #""(?:\\.|[^"\\])*""#, color: .systemBlue, text: text, storage: storage)
        add(pattern: #"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: .systemGreen, text: text, storage: storage)
        addBold(pattern: #"\b(?:true|false|null)\b"#, color: .systemBlue, text: text, storage: storage)
        add(pattern: #""(?:\\.|[^"\\])*"(?=\s*:)"#, color: .systemRed, text: text, storage: storage)
    }

    private func highlightHTML(text: String, storage: NSTextStorage) {
        let commentRanges = highlightMarkupBase(text: text, storage: storage)
        let scriptStyleRanges = addAndReturnRanges(
            pattern: #"(?is)<(script|style)\b[^>]*>[\s\S]*?</\1>"#,
            color: .systemOrange,
            text: text,
            storage: storage,
            excludedRanges: commentRanges
        )
        let protectedRanges = commentRanges + scriptStyleRanges
        highlightMarkupTokens(text: text, storage: storage, protectedRanges: protectedRanges)
        add(pattern: #"&[A-Za-z0-9#]+;"#, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func highlightXML(text: String, storage: NSTextStorage) {
        let commentRanges = highlightMarkupBase(text: text, storage: storage)
        let protectedRanges = commentRanges
            + addAndReturnRanges(pattern: #"<!\[CDATA\[[\s\S]*?\]\]>"#, color: .secondaryLabelColor, text: text, storage: storage, excludedRanges: commentRanges)
        highlightMarkupTokens(text: text, storage: storage, protectedRanges: protectedRanges)
        add(pattern: #"&[A-Za-z0-9#]+;"#, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func highlightMarkupBase(text: String, storage: NSTextStorage) -> [NSRange] {
        addAndReturnRanges(pattern: #"<!--[\s\S]*?-->"#, color: .secondaryLabelColor, text: text, storage: storage)
            + addAndReturnRanges(pattern: #"<!(?:DOCTYPE|doctype)\b[^>]*>"#, color: .secondaryLabelColor, text: text, storage: storage)
            + addAndReturnRanges(pattern: #"<\?[\s\S]*?\?>"#, color: .secondaryLabelColor, text: text, storage: storage)
    }

    private func highlightMarkupTokens(text: String, storage: NSTextStorage, protectedRanges: [NSRange]) {
        let stringRanges = addAndReturnRanges(
            pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
            color: .systemGreen,
            text: text,
            storage: storage,
            excludedRanges: protectedRanges
        )
        let excludedRanges = protectedRanges + stringRanges

        add(pattern: #"</?[A-Za-z_:][A-Za-z0-9:._-]*"#, color: .systemBlue, text: text, storage: storage, excludedRanges: excludedRanges)
        add(pattern: #"/?>"#, color: .systemBlue, text: text, storage: storage, excludedRanges: excludedRanges)
        add(pattern: #"\s[A-Za-z_:][A-Za-z0-9:._-]*(?=\s*=)"#, color: .systemPurple, text: text, storage: storage, excludedRanges: excludedRanges)
        add(pattern: #"(?<=\=)\s*(?:true|false|null|\d+(?:\.\d+)?)\b"#, color: .systemOrange, text: text, storage: storage, excludedRanges: excludedRanges)
    }

    private func highlightSQL(text: String, storage: NSTextStorage) {
        for token in SQLSyntaxTokenizer.tokens(in: text) {
            storage.addAttribute(.foregroundColor, value: sqlColor(for: token.kind), range: token.range)
        }
    }

    private func sqlColor(for kind: SQLTokenKind) -> NSColor {
        switch kind {
        case .keyword:
            return .systemBlue
        case .function:
            return .systemTeal
        case .type:
            return .systemPurple
        case .string:
            return .systemGreen
        case .number:
            return .systemOrange
        case .comment:
            return .secondaryLabelColor
        case .operatorToken, .punctuation:
            return .secondaryLabelColor
        case .identifier:
            return .systemPurple
        }
    }

    private func highlightCSS(text: String, storage: NSTextStorage) {
        let commentRanges = addAndReturnRanges(
            pattern: #"/\*[\s\S]*?\*/"#,
            color: .secondaryLabelColor,
            text: text,
            storage: storage
        )
        let stringRanges = addAndReturnRanges(
            pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
            color: .systemGreen,
            text: text,
            storage: storage,
            excludedRanges: commentRanges
        )
        let protectedRanges = commentRanges + stringRanges

        add(pattern: #"@[A-Za-z-]+\b"#, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?:^|[{};,]\s*)(?:[.#]?[A-Za-z_][A-Za-z0-9_-]*|[A-Za-z_][A-Za-z0-9_-]*\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_-]*:[A-Za-z-]+)(?=[^{]*\{)"#, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"#[A-Fa-f0-9]{3,8}\b"#, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"[A-Za-z-]+(?=\s*:)"#, color: .systemBlue, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?<=:\s)[^;{}\n]+(?=;|\})"#, color: .systemOrange, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?<![\w.])-?\b\d+(?:\.\d+)?(?:px|em|rem|vh|vw|%|s|ms|deg|fr)?\b"#, color: .systemOrange, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func highlightYAML(text: String, storage: NSTextStorage) {
        let commentRanges = addAndReturnRanges(pattern: #"#.*$"#, color: .secondaryLabelColor, text: text, storage: storage, options: [.anchorsMatchLines])
        let stringRanges = addAndReturnRanges(
            pattern: #""(?:\\.|[^"\\])*"|'(?:''|[^'])*'"#,
            color: .systemGreen,
            text: text,
            storage: storage,
            excludedRanges: commentRanges
        )
        let protectedRanges = commentRanges + stringRanges

        add(pattern: #"(?m)^\s*[-?]?\s*[A-Za-z0-9_.-]+\s*:"#, color: .systemBlue, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?m)^\s*---|\.\.\.\s*$"#, color: .secondaryLabelColor, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?<![\w.])(?:true|false|null|yes|no|on|off)\b"#, color: .systemTeal, text: text, storage: storage, options: [.caseInsensitive], excludedRanges: protectedRanges)
        add(pattern: #"(?<![\w.])-?\b\d+(?:\.\d+)?\b"#, color: .systemOrange, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?m)^\s*-\s"#, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"[&*][A-Za-z0-9_-]+\b|![A-Za-z0-9!/_-]+\b"#, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func highlightMarkdown(text: String, storage: NSTextStorage) {
        let fencedCodeRanges = addAndReturnRanges(pattern: #"(?ms)^```[\s\S]*?^```"#, color: .secondaryLabelColor, text: text, storage: storage)
        let inlineCodeRanges = addAndReturnRanges(pattern: #"`[^`\n]+`"#, color: .systemPurple, text: text, storage: storage, excludedRanges: fencedCodeRanges)
        let protectedRanges = fencedCodeRanges + inlineCodeRanges

        addBold(pattern: #"(?m)^\s{0,3}#{1,6}\s.*$"#, color: .systemBlue, text: text, storage: storage, options: [.anchorsMatchLines], excludedRanges: protectedRanges)
        add(pattern: #"(?m)^\s{0,3}(?:[-*+]|\d+\.)\s+"#, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?m)^\s{0,3}>\s?.*$"#, color: .secondaryLabelColor, text: text, storage: storage, options: [.anchorsMatchLines], excludedRanges: protectedRanges)
        add(pattern: #"\[[^\]\n]+\]\([^) \n]+(?:\s+"[^"]*")?\)"#, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"https?://[^\s)]+|mailto:[^\s)]+"#, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?<!\*)\*\*[^*\n]+\*\*(?!\*)|__[^_\n]+__"#, color: .systemBlue, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: #"(?<!\*)\*[^*\n]+\*(?!\*)|_[^_\n]+_"#, color: .systemGreen, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func highlightJava(text: String, storage: NSTextStorage) {
        let commentRanges = addAndReturnRanges(
            pattern: #"/\*[\s\S]*?\*/"#,
            color: .secondaryLabelColor,
            text: text,
            storage: storage
        ) + addAndReturnRanges(
            pattern: #"//.*$"#,
            color: .secondaryLabelColor,
            text: text,
            storage: storage,
            options: [.anchorsMatchLines]
        )

        let stringRanges = addAndReturnRanges(
            pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'"#,
            color: .systemGreen,
            text: text,
            storage: storage,
            excludedRanges: commentRanges
        )
        let protectedRanges = commentRanges + stringRanges

        add(
            pattern: #"@\b(?:Override|Deprecated|SuppressWarnings|FunctionalInterface)\b"#,
            color: .systemTeal,
            text: text,
            storage: storage,
            excludedRanges: protectedRanges
        )
        addKeywordPattern(
            javaKeywords,
            color: .systemBlue,
            text: text,
            storage: storage,
            excludedRanges: protectedRanges
        )
        addKeywordPattern(
            javaBuiltinTypes,
            color: .systemPurple,
            text: text,
            storage: storage,
            excludedRanges: protectedRanges
        )
        add(
            pattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?[fFdDlL]?)(?![\w.])"#,
            color: .systemOrange,
            text: text,
            storage: storage,
            excludedRanges: protectedRanges
        )
    }

    private var javaKeywords: [String] {
        [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
            "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float",
            "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native",
            "new", "package", "private", "protected", "public", "return", "short", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void",
            "volatile", "while", "var", "record", "sealed", "permits", "non-sealed", "yield", "true",
            "false", "null"
        ]
    }

    private var javaBuiltinTypes: [String] {
        [
            "String", "Object", "Integer", "Long", "Double", "Float", "Boolean", "Character", "Byte",
            "Short", "System", "Math", "List", "ArrayList", "Map", "HashMap", "Set", "HashSet",
            "Optional", "Date", "LocalDate", "LocalDateTime", "BigDecimal", "BigInteger", "Exception",
            "RuntimeException"
        ]
    }

    private struct CodeHighlightDefinition {
        let keywords: [String]
        let builtins: [String]
        let annotations: [String]
        let lineCommentPattern: String?
        let blockCommentPattern: String?
        let stringPattern: String
        let numberPattern: String
    }

    private func highlightCode(definition: CodeHighlightDefinition, text: String, storage: NSTextStorage) {
        var commentRanges: [NSRange] = []
        if let blockCommentPattern = definition.blockCommentPattern {
            commentRanges += addAndReturnRanges(
                pattern: blockCommentPattern,
                color: .secondaryLabelColor,
                text: text,
                storage: storage
            )
        }
        if let lineCommentPattern = definition.lineCommentPattern {
            commentRanges += addAndReturnRanges(
                pattern: lineCommentPattern,
                color: .secondaryLabelColor,
                text: text,
                storage: storage,
                options: [.anchorsMatchLines]
            )
        }

        let stringRanges = addAndReturnRanges(
            pattern: definition.stringPattern,
            color: .systemGreen,
            text: text,
            storage: storage,
            excludedRanges: commentRanges
        )
        let protectedRanges = commentRanges + stringRanges

        addKeywordPattern(definition.keywords, color: .systemBlue, text: text, storage: storage, excludedRanges: protectedRanges)
        addKeywordPattern(definition.builtins, color: .systemPurple, text: text, storage: storage, excludedRanges: protectedRanges)
        addKeywordPattern(definition.annotations, color: .systemTeal, text: text, storage: storage, excludedRanges: protectedRanges)
        add(pattern: definition.numberPattern, color: .systemOrange, text: text, storage: storage, excludedRanges: protectedRanges)
    }

    private func codeDefinition(for language: EditorLanguage) -> CodeHighlightDefinition {
        switch language {
        case .javascript:
            return CodeHighlightDefinition(
                keywords: [
                    "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
                    "default", "delete", "do", "else", "export", "extends", "finally", "for", "from",
                    "function", "if", "import", "in", "instanceof", "let", "new", "of", "return", "static",
                    "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with",
                    "yield", "true", "false", "null", "undefined"
                ],
                builtins: [
                    "Array", "Object", "String", "Number", "Boolean", "BigInt", "Symbol", "Date", "Math",
                    "JSON", "Promise", "Map", "Set", "WeakMap", "WeakSet", "Error", "RegExp", "console",
                    "window", "document", "localStorage", "fetch", "URL", "Intl"
                ],
                annotations: [],
                lineCommentPattern: #"//.*$"#,
                blockCommentPattern: #"/\*[\s\S]*?\*/"#,
                stringPattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#,
                numberPattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?n?)(?![\w.])"#
            )
        case .cSharp:
            return CodeHighlightDefinition(
                keywords: [
                    "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked",
                    "class", "const", "continue", "decimal", "default", "delegate", "do", "double", "else",
                    "enum", "event", "explicit", "extern", "false", "finally", "fixed", "float", "for",
                    "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal", "is", "lock",
                    "long", "namespace", "new", "null", "object", "operator", "out", "override", "params",
                    "private", "protected", "public", "readonly", "record", "ref", "return", "sbyte",
                    "sealed", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch",
                    "this", "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe",
                    "ushort", "using", "var", "virtual", "void", "volatile", "while", "async", "await",
                    "yield"
                ],
                builtins: [
                    "String", "Object", "Int32", "Int64", "Double", "Single", "Boolean", "Char", "Byte",
                    "Decimal", "DateTime", "Guid", "Console", "Math", "List", "Dictionary", "HashSet",
                    "IEnumerable", "Task", "Exception", "ArgumentException", "InvalidOperationException"
                ],
                annotations: [],
                lineCommentPattern: #"//.*$"#,
                blockCommentPattern: #"/\*[\s\S]*?\*/"#,
                stringPattern: #"@?"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'"#,
                numberPattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?[fFdDmMlLuU]?)(?![\w.])"#
            )
        case .cPlusPlus:
            return CodeHighlightDefinition(
                keywords: [
                    "alignas", "alignof", "and", "asm", "auto", "bitand", "bitor", "bool", "break", "case",
                    "catch", "char", "char8_t", "char16_t", "char32_t", "class", "compl", "concept",
                    "const", "consteval", "constexpr", "constinit", "const_cast", "continue", "co_await",
                    "co_return", "co_yield", "decltype", "default", "delete", "do", "double", "dynamic_cast",
                    "else", "enum", "explicit", "export", "extern", "false", "float", "for", "friend",
                    "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept",
                    "not", "nullptr", "operator", "or", "private", "protected", "public", "register",
                    "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static",
                    "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local",
                    "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using",
                    "virtual", "void", "volatile", "wchar_t", "while"
                ],
                builtins: [
                    "std", "string", "wstring", "vector", "map", "unordered_map", "set", "unordered_set",
                    "optional", "variant", "tuple", "array", "unique_ptr", "shared_ptr", "weak_ptr",
                    "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t",
                    "int32_t", "int64_t", "cout", "cin", "cerr", "endl", "exception", "runtime_error"
                ],
                annotations: [],
                lineCommentPattern: #"//.*$"#,
                blockCommentPattern: #"/\*[\s\S]*?\*/"#,
                stringPattern: #"R"\([^)]*\)[^"]*"|u8?"(?:\\.|[^"\\])*"|U"(?:\\.|[^"\\])*"|L"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
                numberPattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?[fFlLuU]*)(?![\w.])"#
            )
        case .swift:
            return CodeHighlightDefinition(
                keywords: [
                    "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer",
                    "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
                    "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is",
                    "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "return",
                    "rethrows", "self", "Self", "static", "struct", "subscript", "super", "switch",
                    "throw", "throws", "true", "try", "typealias", "var", "where", "while", "async", "await"
                ],
                builtins: [
                    "String", "Int", "Double", "Float", "Bool", "Character", "Array", "Dictionary", "Set",
                    "Optional", "Result", "URL", "Date", "UUID", "Data", "Error", "Any", "AnyObject",
                    "Never", "Void", "Task", "MainActor"
                ],
                annotations: [
                    "@available", "@discardableResult", "@escaping", "@MainActor", "@Published", "@State",
                    "@Binding", "@ObservedObject", "@StateObject", "@Environment", "@ViewBuilder"
                ],
                lineCommentPattern: #"//.*$"#,
                blockCommentPattern: #"/\*[\s\S]*?\*/"#,
                stringPattern: ##"#{0,3}"""[\s\S]*?"""#{0,3}|#{0,3}"(?:\\.|[^"\\])*"#{0,3}|'(?:\\.|[^'\\])*'"##,
                numberPattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?)(?![\w.])"#
            )
        case .python:
            return CodeHighlightDefinition(
                keywords: [
                    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
                    "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
                    "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
                    "return", "try", "while", "with", "yield", "match", "case"
                ],
                builtins: [
                    "str", "int", "float", "bool", "list", "dict", "set", "tuple", "object", "Exception",
                    "ValueError", "TypeError", "RuntimeError", "print", "len", "range", "enumerate", "zip",
                    "map", "filter", "sum", "min", "max", "open", "super", "self", "dataclass", "Path"
                ],
                annotations: [
                    "@staticmethod", "@classmethod", "@property", "@dataclass", "@abstractmethod", "@pytest"
                ],
                lineCommentPattern: #"#.*$"#,
                blockCommentPattern: nil,
                stringPattern: #"(?i)(?:r|u|b|f|fr|rf)?"""[\s\S]*?"""|(?:r|u|b|f|fr|rf)?'''[\s\S]*?'''|(?:r|u|b|f|fr|rf)?"(?:\\.|[^"\\])*"|(?:r|u|b|f|fr|rf)?'(?:\\.|[^'\\])*'"#,
                numberPattern: #"(?<![\w.])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?j?)(?![\w.])"#
            )
        case .shell:
            return CodeHighlightDefinition(
                keywords: [
                    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case",
                    "esac", "function", "select", "in", "time", "coproc", "return", "break", "continue",
                    "true", "false"
                ],
                builtins: [
                    "echo", "printf", "read", "cd", "pwd", "export", "unset", "local", "declare", "typeset",
                    "source", "alias", "unalias", "test", "eval", "exec", "trap", "shift", "getopts",
                    "set", "exit", "mkdir", "rm", "cp", "mv", "grep", "sed", "awk", "find", "xargs"
                ],
                annotations: [],
                lineCommentPattern: #"#.*$"#,
                blockCommentPattern: nil,
                stringPattern: #""(?:\\.|[^"\\])*"|'[^']*'|`[^`]*`"#,
                numberPattern: #"(?<![\w.])\d+(?![\w.])"#
            )
        default:
            return CodeHighlightDefinition(
                keywords: [],
                builtins: [],
                annotations: [],
                lineCommentPattern: nil,
                blockCommentPattern: nil,
                stringPattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
                numberPattern: #"(?!)"#
            )
        }
    }

    private func addKeywordPattern(
        _ keywords: [String],
        color: NSColor,
        text: String,
        storage: NSTextStorage,
        excludedRanges: [NSRange] = []
    ) {
        guard !keywords.isEmpty else {
            return
        }

        let escaped = keywords
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        add(
            pattern: "(?<![A-Za-z0-9_-])(?:\(escaped))(?![A-Za-z0-9_-])",
            color: color,
            text: text,
            storage: storage,
            excludedRanges: excludedRanges
        )
    }

    private func add(
        pattern: String,
        color: NSColor,
        text: String,
        storage: NSTextStorage,
        options: NSRegularExpression.Options = [],
        excludedRanges: [NSRange] = []
    ) {
        _ = addAndReturnRanges(
            pattern: pattern,
            color: color,
            text: text,
            storage: storage,
            options: options,
            excludedRanges: excludedRanges
        )
    }

    private func addAndReturnRanges(
        pattern: String,
        color: NSColor,
        text: String,
        storage: NSTextStorage,
        options: NSRegularExpression.Options = [],
        excludedRanges: [NSRange] = []
    ) -> [NSRange] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(location: 0, length: (text as NSString).length)
            var appliedRanges: [NSRange] = []
            for match in regex.matches(in: text, range: range) {
                guard !overlaps(match.range, excludedRanges) else {
                    continue
                }

                storage.addAttribute(.foregroundColor, value: color, range: match.range)
                appliedRanges.append(match.range)
            }

            return appliedRanges
        } catch {
            return []
        }
    }

    private func addBold(
        pattern: String,
        color: NSColor,
        text: String,
        storage: NSTextStorage,
        options: NSRegularExpression.Options = [],
        excludedRanges: [NSRange] = []
    ) {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(location: 0, length: (text as NSString).length)
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
            for match in regex.matches(in: text, range: range) {
                guard !overlaps(match.range, excludedRanges) else {
                    continue
                }

                storage.addAttributes([
                    .foregroundColor: color,
                    .font: font
                ], range: match.range)
            }
        } catch {}
    }

    private func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
