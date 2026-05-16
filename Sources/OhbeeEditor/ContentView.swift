import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OhbeeEditorCore

struct ContentView: View {
    @ObservedObject var store: EditorStore
    @Binding var isSearchVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDocInfo = false
    @State private var showWordFrequency = false
    @State private var wordFrequencySnapshot: [WordFrequencyEntry] = []
    @State private var showCompare = false
    @State private var draggingDocumentID: EditorDocument.ID?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if isSearchVisible {
                searchBar
                Divider()
            }
            editorArea
            statusBar
        }
        .onAppear {
            activateAppWindow()
        }
        .onChange(of: isSearchVisible) { visible in
            if visible {
                searchFieldFocused = true
            }
        }
        .background(
            TabKeyboardShortcutView {
                closeSelectedTabWithWarning()
            }
        )
        .background(WindowTitleUpdater(title: store.windowTitle))
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            OhbeeLogoImage(size: 24)
                .help("Ohbee Editor")

            ForEach(store.documents) { document in
                TabItemView(
                    document: document,
                    isSelected: store.selectedDocumentID == document.id,
                    tooltip: document.fileURL?.path ?? document.title,
                    action: { store.selectDocument(document.id) },
                    closeAction: { closeTabWithWarning(document.id) }
                )
                .onDrag {
                    draggingDocumentID = document.id
                    return NSItemProvider(object: document.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text], delegate: TabDropDelegate(
                    documentID: document.id,
                    store: store,
                    draggingDocumentID: $draggingDocumentID
                ))
                .contextMenu {
                    Button("Close This Tab") {
                        closeTabWithWarning(document.id)
                    }

                    Button("Close Other Tabs") {
                        closeOtherTabsWithWarning(keeping: document.id)
                    }
                    .disabled(store.documents.count <= 1)

                    Button("Close Tabs to the Right") {
                        closeTabsToRightWithWarning(of: document.id)
                    }
                    .disabled(!hasTabsToRight(of: document.id))

                    Divider()

                    Button("Close All Tabs") {
                        closeAllTabsWithWarning()
                    }
                }
            }

            NewNoteButton(
                isEnabled: store.canCreateScratchDocument,
                action: store.createScratchDocument
            )
            .disabled(!store.canCreateScratchDocument)
            .help(store.canCreateScratchDocument ? "New Note" : "Maximum \(EditorStore.maxDocumentCount) tabs")

            if !store.canCreateScratchDocument {
                Text("Max \(EditorStore.maxDocumentCount) tabs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isSearchVisible.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Find and Replace")
            }
            .buttonStyle(.borderless)
            .help("Find and Replace")

            Button {
                openFile()
            } label: {
                Image(systemName: "folder")
                    .accessibilityLabel("Open File")
            }
            .buttonStyle(.borderless)
            .help("Open File")

            Button {
                save()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .accessibilityLabel("Save")
            }
            .buttonStyle(.borderless)
            .help("Save")

            Button {
                saveAs()
            } label: {
                Image(systemName: "square.and.arrow.down.on.square")
                    .accessibilityLabel("Save As")
            }
            .buttonStyle(.borderless)
            .help("Save As")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Find", text: Binding(
                get: { store.searchOptions.query },
                set: { query in
                    store.updateSearchQuery(query)
                    selectCurrentSearchMatch()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .focused($searchFieldFocused)

            Text(store.searchSummary.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Button {
                store.selectPreviousMatch()
                selectCurrentSearchMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .accessibilityLabel("Previous Match")
            }
            .buttonStyle(.borderless)
            .disabled(store.searchSummary.matchCount == 0)

            Button {
                store.selectNextMatch()
                selectCurrentSearchMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .accessibilityLabel("Next Match")
            }
            .buttonStyle(.borderless)
            .disabled(store.searchSummary.matchCount == 0)

            Divider()
                .frame(height: 18)

            TextField("Replace", text: Binding(
                get: { store.searchOptions.replacement },
                set: store.updateReplacement
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)

            Button("Replace") {
                EditorTextOperationCenter.shared.replaceCurrentSearchMatch(store: store)
            }
            .controlSize(.small)
            .disabled(store.searchSummary.matchCount == 0)

            Button("All") {
                EditorTextOperationCenter.shared.replaceAllSearchMatches(store: store)
            }
            .controlSize(.small)
            .disabled(store.searchSummary.matchCount == 0)

            Toggle("Regex", isOn: Binding(
                get: { store.searchOptions.usesRegex },
                set: { enabled in
                    store.setRegexSearchEnabled(enabled)
                    selectCurrentSearchMatch()
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Toggle("Case", isOn: Binding(
                get: { store.searchOptions.isCaseSensitive },
                set: { enabled in
                    store.setCaseSensitiveSearchEnabled(enabled)
                    selectCurrentSearchMatch()
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Spacer()

            Button {
                isSearchVisible = false
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel("Close Find and Replace")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var editorArea: some View {
        if let document = store.selectedDocument {
            ScratchEditorView(
                document: document,
                text: store.textBinding(for: document.id),
                onFileDrop: { urls in
                    for url in urls {
                        store.openDocument(from: url)
                    }
                }
            )
        } else {
            Text("No Document")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Menu("Lines") {
                transformButton("Trim Whitespace", BasicTextTransforms.trimWhitespace)
                transformButton("Trim Trailing Spaces", BasicTextTransforms.trimTrailingWhitespace)
                transformButton("Remove Empty Lines", BasicTextTransforms.removeEmptyLines)
                transformButton("Remove Duplicate Lines", BasicTextTransforms.removeDuplicateLines)
                transformButton("Sort Lines", BasicTextTransforms.sortLines)
                transformButton("Join Lines", BasicTextTransforms.joinLines)
            }
            .controlSize(.small)
            .font(.caption)

            Menu("Case") {
                transformButton("lowercase", BasicTextTransforms.lowercase)
                transformButton("UPPERCASE", BasicTextTransforms.uppercase)
                transformButton("Title Case", BasicTextTransforms.titleCase)
                transformButton("snake_case", BasicTextTransforms.snakeCase)
                transformButton("kebab-case", BasicTextTransforms.kebabCase)
                transformButton("camelCase", BasicTextTransforms.camelCase)
            }
            .controlSize(.small)
            .font(.caption)

            Menu("Cleanup") {
                transformButton("Clean AI Output", BasicTextTransforms.cleanAIOutput)
            }
            .controlSize(.small)
            .font(.caption)

            Menu("JSON") {
                transformButton("Format JSON", JSONTools.format)
                transformButton("Minify JSON", JSONTools.minify)
                Button("Validate JSON") {
                    EditorTextOperationCenter.shared.inspectText(named: "Validate JSON", store: store) { text in
                        switch JSONTools.validate(text) {
                        case let .success(_, summary):
                            return (summary, .success)
                        case let .failure(message):
                            return (message, .warning)
                        }
                    }
                }
            }
            .controlSize(.small)
            .font(.caption)
            .disabled(!store.selectedDocumentSupportsJSONTools)

            Menu("XML") {
                transformButton("Format XML", XMLTools.format)
                transformButton("Minify XML", XMLTools.minify)
            }
            .controlSize(.small)
            .font(.caption)
            .disabled(!store.selectedDocumentSupportsXMLTools)

            Menu("URL") {
                transformButton("URL Encode", URLTools.encode)
                transformButton("URL Decode", URLTools.decode)
                transformButton("Remove Tracking Parameters", URLTools.removeTrackingParameters)
            }
            .controlSize(.small)
            .font(.caption)

            Menu("Hash") {
                Button("SHA-256") {
                    EditorTextOperationCenter.shared.inspectText(named: "SHA-256", store: store) { text in
                        if let hash = ChecksumTools.sha256(of: text) {
                            return (hash, .neutral)
                        }
                        return ("Cannot compute SHA-256.", .warning)
                    }
                }
                Button("MD5") {
                    EditorTextOperationCenter.shared.inspectText(named: "MD5", store: store) { text in
                        if let hash = ChecksumTools.md5(of: text) {
                            return (hash, .neutral)
                        }
                        return ("Cannot compute MD5.", .warning)
                    }
                }
            }
            .controlSize(.small)
            .font(.caption)

            Menu("Safe Share") {
                Button("Detect Sensitive Text") {
                    EditorTextOperationCenter.shared.inspectText(named: "Safe Share", store: store) { text in
                        let message = SafeShare.detectionSummary(in: text)
                        let tone: StatusMessageTone = message.hasPrefix("Potential sensitive text found")
                            ? .warning
                            : .success
                        return (message, tone)
                    }
                }
                transformButton("Mask Detected Patterns", SafeShare.maskDetectedPatterns)
            }
            .controlSize(.small)
            .font(.caption)

            if let statusMessage = store.statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            Button {
                wordFrequencySnapshot = WordFrequencyTools.topWords(in: store.selectedDocument?.text ?? "")
                showWordFrequency.toggle()
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Word Frequency")
            }
            .buttonStyle(.borderless)
            .help("Word Frequency")
            .popover(isPresented: $showWordFrequency, arrowEdge: .top) {
                WordFrequencyView(entries: wordFrequencySnapshot)
            }

            Button {
                showCompare = true
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Compare Tabs")
            }
            .buttonStyle(.borderless)
            .help("Compare Tabs")
            .disabled(store.documents.count < 2)
            .sheet(isPresented: $showCompare) {
                CompareTabsSheet(
                    documents: store.documents,
                    isPresented: $showCompare,
                    onCompare: { baseID, changedID in
                        store.openDiffTab(baseID: baseID, changedID: changedID)
                    }
                )
            }

            Button {
                showDocInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Document Info")
            }
            .buttonStyle(.borderless)
            .help("Document Info")
            .popover(isPresented: $showDocInfo, arrowEdge: .top) {
                DocumentInfoView(document: store.selectedDocument, text: store.selectedDocument?.text ?? "")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var statusColor: Color {
        switch store.statusMessageTone {
        case .neutral:
            return .secondary
        case .success:
            return colorScheme == .dark
                ? Color(red: 0.25, green: 0.78, blue: 0.38)
                : Color(red: 0.0, green: 0.42, blue: 0.12)
        case .warning:
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.58, blue: 0.22)
                : Color(red: 0.72, green: 0.32, blue: 0.0)
        }
    }

    @ViewBuilder
    private func transformButton(
        _ title: String,
        _ transform: @escaping (String) -> TextTransformResult
    ) -> some View {
        Button(title) {
            EditorTextOperationCenter.shared.applyTransform(named: title, store: store, transform: transform)
        }
    }

    private func selectCurrentSearchMatch() {
        DispatchQueue.main.async {
            EditorTextOperationCenter.shared.selectCurrentSearchMatch(store: store)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                store.openDocument(from: url)
            }
        }
    }

    private func save() {
        if !store.saveSelectedDocument() {
            saveAs()
        }
    }

    private func saveAs() {
        guard let document = store.selectedDocument else {
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.title

        if panel.runModal() == .OK, let fileURL = panel.url {
            _ = store.saveSelectedDocument(to: fileURL)
        }
    }

    private func hasTabsToRight(of id: EditorDocument.ID) -> Bool {
        guard let index = store.documents.firstIndex(where: { $0.id == id }) else {
            return false
        }

        return index < store.documents.count - 1
    }

    private func closeSelectedTabWithWarning() {
        guard let selectedDocumentID = store.selectedDocumentID else {
            return
        }

        closeTabWithWarning(selectedDocumentID)
    }

    private func closeTabWithWarning(_ id: EditorDocument.ID) {
        guard let document = store.documents.first(where: { $0.id == id }) else {
            return
        }

        guard UnsavedTabWarning.confirmClosing([document]) else {
            return
        }

        store.closeDocument(id)
    }

    private func closeOtherTabsWithWarning(keeping id: EditorDocument.ID) {
        let closingDocuments = store.documents.filter { $0.id != id }
        guard UnsavedTabWarning.confirmClosing(closingDocuments) else {
            return
        }

        store.closeOtherDocuments(keeping: id)
    }

    private func closeTabsToRightWithWarning(of id: EditorDocument.ID) {
        guard let index = store.documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        let closingDocuments = Array(store.documents.suffix(from: index + 1))
        guard UnsavedTabWarning.confirmClosing(closingDocuments) else {
            return
        }

        store.closeDocumentsToRight(of: id)
    }

    private func closeAllTabsWithWarning() {
        guard UnsavedTabWarning.confirmClosing(store.documents) else {
            return
        }

        store.closeAllDocuments()
    }
}

private struct ScratchEditorView: View {
    let document: EditorDocument
    @Binding var text: String
    let onFileDrop: ([URL]) -> Void
    @AppStorage("ohbee.lineNumbers") private var showLineNumbers = true
    @AppStorage("ohbee.fontSize") private var fontSize: Double = 13

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title)
                    .font(.headline)

                if document.isScratch {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(document.effectiveLanguage.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HighlightedTextEditor(
                text: $text,
                language: document.effectiveLanguage,
                documentID: document.id,
                showLineNumbers: showLineNumbers,
                isLargeFile: document.isLargeFile,
                fontSize: CGFloat(fontSize),
                onFileDrop: onFileDrop
            )
                .background(Color(nsColor: .textBackgroundColor))
                .id(document.id)
                .onAppear {
                    activateAppWindow()
                }
        }
    }
}

private func activateAppWindow() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

private struct NewNoteButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("New Note")
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var background: some View {
        if isEnabled && isHovering {
            Color(nsColor: .controlAccentColor)
                .opacity(0.18)
        } else {
            Color.clear
        }
    }
}

private struct TabKeyboardShortcutView: NSViewRepresentable {
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClose = onClose
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onClose: () -> Void
        private var monitor: Any?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Self.isCloseTabShortcut(event) else {
                    return event
                }

                self?.onClose()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitor = nil
        }

        private static func isCloseTabShortcut(_ event: NSEvent) -> Bool {
            guard event.charactersIgnoringModifiers?.lowercased() == "w" else {
                return false
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCloseModifier = flags.contains(.command) || flags.contains(.control)
            let hasExtraModifier = flags.contains(.option) || flags.contains(.shift)

            return hasCloseModifier && !hasExtraModifier
        }
    }
}

private struct TabItemView: View {
    let document: EditorDocument
    let isSelected: Bool
    let tooltip: String
    let action: () -> Void
    let closeAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(document.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.leading, 9)
                    .padding(.trailing, 3)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            Button(action: closeAction) {
                ZStack {
                    if document.isDirty {
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .help(tooltip)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(tabBackground)
        }
        .onHover { isHovering = $0 }
    }

    private var tabBackground: Color {
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.15)
        } else if isHovering {
            return Color.primary.opacity(0.07)
        }
        return .clear
    }
}

private struct DocumentInfoView: View {
    let document: EditorDocument?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Document Info")
                .font(.headline)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Lines").foregroundStyle(.secondary)
                    Text(lineCount.formatted()).monospacedDigit()
                }
                GridRow {
                    Text("Words").foregroundStyle(.secondary)
                    Text(wordCount.formatted()).monospacedDigit()
                }
                GridRow {
                    Text("Characters").foregroundStyle(.secondary)
                    Text(charCount.formatted()).monospacedDigit()
                }
                GridRow {
                    Text("No whitespace").foregroundStyle(.secondary)
                    Text(charNoWhitespace.formatted()).monospacedDigit()
                }
                GridRow { Color.clear.gridCellUnsizedAxes(.vertical).frame(height: 2) }
                GridRow {
                    Text("Language").foregroundStyle(.secondary)
                    Text(language)
                }
                if let size = fileSize {
                    GridRow {
                        Text("File size").foregroundStyle(.secondary)
                        Text(size)
                    }
                }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(minWidth: 220)
    }

    private var lineCount: Int {
        text.isEmpty ? 1 : text.components(separatedBy: "\n").count
    }

    private var wordCount: Int {
        text.split { $0.isWhitespace }.count
    }

    private var charCount: Int { text.count }

    private var charNoWhitespace: Int {
        text.filter { !$0.isWhitespace }.count
    }

    private var language: String {
        document?.effectiveLanguage.displayName ?? "Plain Text"
    }

    private var fileSize: String? {
        guard let url = document?.fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNum = attrs[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeNum.int64Value, countStyle: .file)
    }
}

private struct TabDropDelegate: DropDelegate {
    let documentID: EditorDocument.ID
    let store: EditorStore
    @Binding var draggingDocumentID: EditorDocument.ID?

    func dropEntered(info: DropInfo) {
        guard let fromID = draggingDocumentID, fromID != documentID,
              let fromIdx = store.documents.firstIndex(where: { $0.id == fromID }),
              let toIdx = store.documents.firstIndex(where: { $0.id == documentID })
        else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveDocument(
                from: IndexSet(integer: fromIdx),
                to: toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingDocumentID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingDocumentID != nil && draggingDocumentID != documentID
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}
