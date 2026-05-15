import AppKit
import OhbeeEditorCore

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineMap: LineMap?
    private var cursorLine: Int = 1

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.textView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textStorageEdited(_:)),
                       name: NSTextStorage.didProcessEditingNotification,
                       object: textView.textStorage)
        nc.addObserver(self, selector: #selector(scrolled),
                       name: NSView.boundsDidChangeNotification,
                       object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(scrolled),
                       name: NSView.frameDidChangeNotification,
                       object: textView)
        nc.addObserver(self, selector: #selector(selectionChanged),
                       name: NSTextView.didChangeSelectionNotification,
                       object: textView)
        rebuildLineMap()
        ruleThickness = gutterWidth(for: lineMap?.lineCount ?? 1)
    }

    required init(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var isFlipped: Bool { true }

    func syncCursorLine() {
        guard let textView, let lineMap else { return }
        let loc = textView.selectedRange().location
        let length = (textView.string as NSString).length
        if loc >= length {
            // lineStarts already includes the virtual entry at `length` for each trailing
            // newline, so lineCount is the correct 1-based line number for the extra fragment.
            cursorLine = lineMap.lineCount
        } else {
            cursorLine = lineMap.lineAndColumn(for: loc).line + 1
        }
        needsDisplay = true
    }

    @objc private func selectionChanged() {
        syncCursorLine()
    }

    @objc private func textStorageEdited(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters) else { return }
        rebuildLineMap()
        updateRuleThicknessIfNeeded()
        needsDisplay = true
    }

    @objc private func scrolled() { needsDisplay = true }

    private func rebuildLineMap() {
        guard let textView else { lineMap = nil; return }
        lineMap = LineMap(string: textView.string as NSString)
    }

    private func updateRuleThicknessIfNeeded() {
        let newWidth = gutterWidth(for: lineMap?.lineCount ?? 1)
        guard abs(ruleThickness - newWidth) > 0.5 else { return }
        ruleThickness = newWidth
        scrollView?.tile()
    }

    private func gutterWidth(for lineCount: Int) -> CGFloat {
        let digits = max(1, String(lineCount).count)
        let fontSize = max(NSFont.systemFontSize - 2, 10)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return max(36, CGFloat(digits) * charWidth + 14)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let scrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 0.5, y: 0, width: 0.5, height: bounds.height).fill()

        let fontSize = max(NSFont.systemFontSize - 2, 10)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.quaternaryLabelColor
        ]
        let activeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ]

        let visibleRect = scrollView.documentVisibleRect
        let inset = textView.textContainerInset

        if layoutManager.numberOfGlyphs == 0 {
            let s = "1" as NSString
            let a = activeAttrs
            let sz = s.size(withAttributes: a)
            let lh = font.boundingRectForFont.height
            let y = inset.height - visibleRect.minY + (lh - sz.height) / 2
            s.draw(at: NSPoint(x: bounds.width - sz.width - 7, y: y), withAttributes: a)
            return
        }

        let totalGlyphs = layoutManager.numberOfGlyphs
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location < totalGlyphs else { return }

        let safeLen = min(glyphRange.length, totalGlyphs - glyphRange.location)
        guard safeLen > 0 else { return }
        let safeRange = NSRange(location: glyphRange.location, length: safeLen)

        let firstCharIdx = layoutManager.characterIndexForGlyph(at: safeRange.location)
        let startLine = (lineMap?.lineAndColumn(for: firstCharIdx).line ?? 0) + 1

        var lineNum = startLine
        var lastLineStart = -1
        let ns = textView.string as NSString

        layoutManager.enumerateLineFragments(forGlyphRange: safeRange) { [self] lineRect, _, _, gRange, _ in
            let charIdx = layoutManager.characterIndexForGlyph(at: gRange.location)
            let safeCharIdx = charIdx < ns.length ? charIdx : max(ns.length - 1, 0)
            let lineStart = ns.lineRange(for: NSRange(location: safeCharIdx, length: 0)).location
            guard lineStart != lastLineStart else { return }
            lastLineStart = lineStart

            let y = lineRect.minY + inset.height - visibleRect.minY
            let s = "\(lineNum)" as NSString
            let a = lineNum == cursorLine ? activeAttrs : attrs
            let sz = s.size(withAttributes: a)
            s.draw(at: NSPoint(x: bounds.width - sz.width - 7, y: y + (lineRect.height - sz.height) / 2), withAttributes: a)
            lineNum += 1
        }

        // When text ends with a newline, the cursor sits on an extra line fragment
        // that enumerateLineFragments doesn't visit — draw its line number explicitly.
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            let extraRect = layoutManager.extraLineFragmentRect
            let y = extraRect.minY + inset.height - visibleRect.minY
            if y < bounds.height && y + extraRect.height > 0 {
                let s = "\(lineNum)" as NSString
                let a = lineNum == cursorLine ? activeAttrs : attrs
                let sz = s.size(withAttributes: a)
                s.draw(at: NSPoint(x: bounds.width - sz.width - 7, y: y + (extraRect.height - sz.height) / 2), withAttributes: a)
            }
        }
    }
}
