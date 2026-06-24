import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OhbeeEditorCore

struct ContentView: View {
    @ObservedObject var store: EditorStore
    @Binding var isSearchVisible: Bool
    @Binding var isSafeShareReviewVisible: Bool
    @Binding var isCommandPaletteVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDocInfo = false
    @State private var showWordFrequency = false
    @State private var wordFrequencySnapshot: [WordFrequencyEntry] = []
    @State private var showCompare = false
    @State private var showReportIssue = false
    @State private var safeShareReview: SafeShareReview?
    @State private var draggingDocumentID: EditorDocument.ID?
    @State private var lineFilterRequest: LineFilterRequest?
    @State private var commandPaletteActions: [CommandPaletteAction] = []
    @State private var statusBarWidth: CGFloat = 0
    @FocusState private var searchFieldFocused: Bool

    // Status bar responsive breakpoints (measured width of the status bar).
    // Below each threshold, the matching group of controls is hidden because
    // every status bar action is also reachable from the menu bar.
    private let statusBarSecondaryButtonsMinWidth: CGFloat = 900
    private let statusBarExtraMenusMinWidth: CGFloat = 820

    // Word Frequency and Compare are the first to go when space is tight.
    private var showsStatusBarSecondaryButtons: Bool {
        statusBarWidth == 0 || statusBarWidth >= statusBarSecondaryButtonsMinWidth
    }

    // Log, XML, and Hash are niche menus hidden when the window gets narrow.
    private var showsStatusBarExtraMenus: Bool {
        statusBarWidth == 0 || statusBarWidth >= statusBarExtraMenusMinWidth
    }

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
        .overlay(alignment: .top) {
            if isCommandPaletteVisible {
                CommandPaletteView(
                    actions: commandPaletteActions,
                    isPresented: $isCommandPaletteVisible
                )
                .padding(.top, 56)
            }
        }
        .onAppear {
            activateAppWindow()
            rebuildCommandPaletteActions()
        }
        .onChange(of: isSearchVisible) { visible in
            if visible {
                searchFieldFocused = true
            }
        }
        .onChange(of: isSafeShareReviewVisible) { visible in
            if visible {
                prepareSafeShareReview()
            }
        }
        .sheet(isPresented: $isSafeShareReviewVisible) {
            SafeShareReviewView(
                review: safeShareReview ?? SafeShare.review(in: ""),
                onApplyMask: { maskedText in
                    if safeShareReview != nil {
                        EditorTextOperationCenter.shared.applyReviewedText(
                            maskedText,
                            named: "Safe Share Mask",
                            store: store
                        )
                    }
                    isSafeShareReviewVisible = false
                },
                onCancel: {
                    isSafeShareReviewVisible = false
                }
            )
        }
        .sheet(item: $lineFilterRequest) { request in
            LineFilterSheet(
                request: request,
                onApply: { query in
                    EditorTextOperationCenter.shared.applyTransform(
                        named: request.title,
                        store: store,
                        transform: request.mode.transform(query: query)
                    )
                }
            )
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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

                            if let fileURL = document.fileURL {
                                Button("Copy File Path") {
                                    copyToPasteboard(fileURL.path)
                                    store.reportOperationStatus("Copied file path.")
                                }

                                Button("Copy File Name") {
                                    copyToPasteboard(fileURL.lastPathComponent)
                                    store.reportOperationStatus("Copied file name.")
                                }

                                Divider()
                            }

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
                }
                .padding(.vertical, 1)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

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

            Toggle("Word", isOn: Binding(
                get: { store.searchOptions.isWholeWord },
                set: { enabled in
                    store.setWholeWordSearchEnabled(enabled)
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
            if document.isImageFile {
                ImageViewerView(document: document)
                    .id(document.id)
            } else {
                ScratchEditorView(
                    document: document,
                    text: store.textBinding(for: document.id),
                    searchOptions: store.searchOptions,
                    currentSearchMatchIndex: store.currentMatchIndex,
                    onSaveAs: saveAs,
                    onFileDrop: { urls in
                        for url in urls {
                            store.openDocument(from: url)
                        }
                    }
                )
            }
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
                transformButton("Sort Lines A→Z", BasicTextTransforms.sortLines)
                transformButton("Sort Lines Z→A", BasicTextTransforms.sortLinesDescending)
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
                transformButton("PascalCase", BasicTextTransforms.pascalCase)
            }
            .controlSize(.small)
            .font(.caption)

            Menu("Cleanup") {
                transformButton("Clean AI Output", BasicTextTransforms.cleanAIOutput)
            }
            .controlSize(.small)
            .font(.caption)

            if showsStatusBarExtraMenus {
                Menu("Log") {
                    Button("Keep Lines Containing…") {
                        presentLineFilter(.keep)
                    }
                    Button("Remove Lines Containing…") {
                        presentLineFilter(.remove)
                    }
                    Divider()
                    transformButton("Extract URLs", LogCleanupTools.extractURLs)
                    transformButton("Extract IPv4 Addresses", LogCleanupTools.extractIPv4Addresses)
                    transformButton("Remove Timestamp Prefixes", LogCleanupTools.removeTimestampPrefixes)
                }
                .controlSize(.small)
                .font(.caption)
            }

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

            if showsStatusBarExtraMenus {
                Menu("XML") {
                    transformButton("Format XML", XMLTools.format)
                    transformButton("Minify XML", XMLTools.minify)
                }
                .controlSize(.small)
                .font(.caption)
                .disabled(!store.selectedDocumentSupportsXMLTools)
            }

            Menu("URL") {
                transformButton("URL Encode", URLTools.encode)
                transformButton("URL Decode", URLTools.decode)
                transformButton("Remove Tracking Parameters", URLTools.removeTrackingParameters)
            }
            .controlSize(.small)
            .font(.caption)

            if showsStatusBarExtraMenus {
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
            }

            Menu("Safe Share") {
                Button("Review Safe Share…") {
                    presentSafeShareReview()
                }
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

            if showsStatusBarSecondaryButtons {
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

            Button {
                showReportIssue = true
            } label: {
                Image(systemName: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Report Issue")
            }
            .buttonStyle(.borderless)
            .help("Report Issue")
            .confirmationDialog(
                "Report an Issue",
                isPresented: $showReportIssue,
                titleVisibility: .visible
            ) {
                Button("Email hi@ohbee.link") {
                    openReportEmail()
                }
                Button("Open a Pull Request on GitHub") {
                    openReportGitHub()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Help us improve Ohbee Editor. Choose how you'd like to report the issue.")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { statusBarWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { newWidth in
                        statusBarWidth = newWidth
                    }
            }
        )
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

    private func openReportEmail() {
        let subject = "Ohbee Editor Issue Report"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:hi@ohbee.link?subject=\(encodedSubject)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openReportGitHub() {
        if let url = URL(string: "https://github.com/ohbee-labs/ohbee-editor") {
            NSWorkspace.shared.open(url)
        }
    }

    private func rebuildCommandPaletteActions() {
        commandPaletteActions = [
            CommandPaletteAction(title: "New Note", subtitle: "Create a fresh scratch tab", keywords: "scratch tab") {
                store.createScratchDocument()
            },
            CommandPaletteAction(title: "Find and Replace", subtitle: "Show current-tab search controls", keywords: "search replace") {
                isSearchVisible = true
            },
            CommandPaletteAction(title: "Review Safe Share", subtitle: "Review likely sensitive text before sharing", keywords: "mask redact secret token") {
                presentSafeShareReview()
            },
            CommandPaletteAction(title: "Clean AI Output", subtitle: "Remove fences, excess blanks, trailing spaces", keywords: "markdown fence cleanup") {
                applyPaletteTransform("Clean AI Output", BasicTextTransforms.cleanAIOutput)
            },
            CommandPaletteAction(title: "Format JSON", subtitle: "Pretty-print valid JSON", keywords: "json pretty") {
                applyPaletteTransform("Format JSON", JSONTools.format)
            },
            CommandPaletteAction(title: "Minify JSON", subtitle: "Compact valid JSON", keywords: "json compact") {
                applyPaletteTransform("Minify JSON", JSONTools.minify)
            },
            CommandPaletteAction(title: "Remove Tracking Parameters", subtitle: "Strip common tracking query params from URLs", keywords: "url utm fbclid gclid") {
                applyPaletteTransform("Remove Tracking Parameters", URLTools.removeTrackingParameters)
            },
            CommandPaletteAction(title: "Keep Lines Containing", subtitle: "Filter log lines by text", keywords: "log grep include") {
                presentLineFilter(.keep)
            },
            CommandPaletteAction(title: "Remove Lines Containing", subtitle: "Drop log lines by text", keywords: "log exclude filter") {
                presentLineFilter(.remove)
            },
            CommandPaletteAction(title: "Extract URLs", subtitle: "Keep unique URLs from messy text", keywords: "log links") {
                applyPaletteTransform("Extract URLs", LogCleanupTools.extractURLs)
            },
            CommandPaletteAction(title: "Extract IPv4 Addresses", subtitle: "Keep unique IPv4 addresses", keywords: "log ip address") {
                applyPaletteTransform("Extract IPv4 Addresses", LogCleanupTools.extractIPv4Addresses)
            },
            CommandPaletteAction(title: "Remove Timestamp Prefixes", subtitle: "Strip common log timestamp prefixes", keywords: "log date time") {
                applyPaletteTransform("Remove Timestamp Prefixes", LogCleanupTools.removeTimestampPrefixes)
            },
            CommandPaletteAction(title: "Mask Detected Patterns", subtitle: "Mask likely secrets, emails, tokens, and phone numbers", keywords: "safe share redact") {
                applyPaletteTransform("Mask Detected Patterns", SafeShare.maskDetectedPatterns)
            },
            CommandPaletteAction(title: "Trim Trailing Spaces", subtitle: "Remove spaces and tabs at line ends", keywords: "whitespace cleanup") {
                applyPaletteTransform("Trim Trailing Spaces", BasicTextTransforms.trimTrailingWhitespace)
            },
            CommandPaletteAction(title: "Sort Lines A-Z", subtitle: "Sort selected or full text", keywords: "lines ascending") {
                applyPaletteTransform("Sort Lines A-Z", BasicTextTransforms.sortLines)
            },
            CommandPaletteAction(title: "Remove Duplicate Lines", subtitle: "Keep first occurrence of each line", keywords: "unique lines") {
                applyPaletteTransform("Remove Duplicate Lines", BasicTextTransforms.removeDuplicateLines)
            }
        ]
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

    private func applyPaletteTransform(
        _ title: String,
        _ transform: @escaping (String) -> TextTransformResult
    ) {
        EditorTextOperationCenter.shared.applyTransform(named: title, store: store, transform: transform)
    }

    private func presentLineFilter(_ mode: LineFilterMode) {
        let selected = EditorTextOperationCenter.shared.selectedText(store: store)
        let initialQuery: String
        if let selected, !selected.contains("\n"), !selected.contains("\r"), selected.count <= 80 {
            initialQuery = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            initialQuery = ""
        }
        lineFilterRequest = LineFilterRequest(mode: mode, initialQuery: initialQuery)
    }

    private func presentSafeShareReview() {
        isSafeShareReviewVisible = true
    }

    private func prepareSafeShareReview() {
        let text = EditorTextOperationCenter.shared.operationText(store: store)
        safeShareReview = SafeShare.review(in: text)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    @discardableResult
    private func save() -> Bool {
        if store.saveSelectedDocument() {
            return true
        }

        return saveAs()
    }

    @discardableResult
    private func saveAs() -> Bool {
        guard let document = store.selectedDocument else {
            return false
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.title

        if panel.runModal() == .OK, let fileURL = panel.url {
            return store.saveSelectedDocument(to: fileURL)
        }

        return false
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

        switch UnsavedTabWarning.closeDecision(for: [document]) {
        case .closeWithoutSaving:
            store.closeDocument(id)
        case .saveThenClose:
            store.selectDocument(id)
            if save() {
                store.closeDocument(id)
            }
        case .cancel:
            return
        }
    }

    private func closeOtherTabsWithWarning(keeping id: EditorDocument.ID) {
        let closingDocuments = store.documents.filter { $0.id != id }
        closeDocumentsWithWarning(closingDocuments) {
            store.closeOtherDocuments(keeping: id)
        }
    }

    private func closeTabsToRightWithWarning(of id: EditorDocument.ID) {
        guard let index = store.documents.firstIndex(where: { $0.id == id }) else {
            return
        }

        let closingDocuments = Array(store.documents.suffix(from: index + 1))
        closeDocumentsWithWarning(closingDocuments) {
            store.closeDocumentsToRight(of: id)
        }
    }

    private func closeAllTabsWithWarning() {
        closeDocumentsWithWarning(store.documents) {
            store.closeAllDocuments()
        }
    }

    private func closeDocumentsWithWarning(_ documents: [EditorDocument], close: () -> Void) {
        switch UnsavedTabWarning.closeDecision(for: documents) {
        case .closeWithoutSaving:
            close()
        case .saveThenClose:
            guard
                let dirtyDocument = documents.first(where: \.isDirty),
                documents.filter(\.isDirty).count == 1
            else {
                return
            }

            store.selectDocument(dirtyDocument.id)
            if save() {
                close()
            }
        case .cancel:
            return
        }
    }
}

private struct ScratchEditorView: View {
    let document: EditorDocument
    @Binding var text: String
    let searchOptions: SearchOptions
    let currentSearchMatchIndex: Int?
    let onSaveAs: () -> Bool
    let onFileDrop: ([URL]) -> Void
    @AppStorage("ohbee.lineNumbers") private var showLineNumbers = true
    @AppStorage("ohbee.wordWrap") private var wordWrap = true
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

                if document.isReadOnly {
                    Label("Read-only", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("This file cannot be overwritten. Use Save As to write a copy.")

                    Button("Save As") {
                        _ = onSaveAs()
                    }
                    .controlSize(.small)
                    .help("Save this read-only file as a writable copy")
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
                wordWrap: wordWrap,
                isLargeFile: document.isLargeFile,
                isReadOnly: document.isReadOnly,
                fontSize: CGFloat(fontSize),
                searchOptions: searchOptions,
                currentSearchMatchIndex: currentSearchMatchIndex,
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

func activateAppWindow() {
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
                HStack(spacing: 3) {
                    Text(document.title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .medium : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                    if document.isReadOnly {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(isSelected ? 0.8 : 0.5))
                    }
                }
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
        let meta = document?.fileURL.flatMap { EditorFileIO.metadata(for: $0) }
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
                if let byteCount = meta?.byteCount {
                    GridRow {
                        Text("File size").foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                    }
                }
                if let createdAt = meta?.creationDate {
                    GridRow {
                        Text("Created").foregroundStyle(.secondary)
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let author = meta?.author {
                    GridRow {
                        Text("Author").foregroundStyle(.secondary)
                        Text(author)
                    }
                }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(minWidth: 260)
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
}

private struct CommandPaletteAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: String
    let perform: () -> Void

    init(title: String, subtitle: String, keywords: String = "", perform: @escaping () -> Void) {
        self.id = title
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.perform = perform
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let haystack = "\(title) \(subtitle) \(keywords)"
        return haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private struct CommandPaletteView: View {
    let actions: [CommandPaletteAction]
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredActions: [CommandPaletteAction] {
        actions.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)

                TextField("Command", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit(runFirstAction)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Close Command Palette")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if filteredActions.isEmpty {
                Text("No commands")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredActions.prefix(10)) { action in
                        Button {
                            run(action)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "return")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                    Text(action.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if action.id != filteredActions.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 18, y: 8)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func runFirstAction() {
        guard let action = filteredActions.first else {
            return
        }

        run(action)
    }

    private func run(_ action: CommandPaletteAction) {
        isPresented = false
        action.perform()
    }
}

private enum LineFilterMode {
    case keep
    case remove

    var title: String {
        switch self {
        case .keep:
            return "Keep Lines Containing"
        case .remove:
            return "Remove Lines Containing"
        }
    }

    var prompt: String {
        switch self {
        case .keep:
            return "Keep lines containing"
        case .remove:
            return "Remove lines containing"
        }
    }

    func transform(query: String) -> (String) -> TextTransformResult {
        switch self {
        case .keep:
            return LogCleanupTools.keepLines(containing: query)
        case .remove:
            return LogCleanupTools.removeLines(containing: query)
        }
    }
}

private struct LineFilterRequest: Identifiable {
    let id = UUID()
    let mode: LineFilterMode
    let initialQuery: String

    var title: String { mode.title }
}

private struct LineFilterSheet: View {
    let request: LineFilterRequest
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @FocusState private var isFocused: Bool

    init(request: LineFilterRequest, onApply: @escaping (String) -> Void) {
        self.request = request
        self.onApply = onApply
        _query = State(initialValue: request.initialQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title)
                .font(.headline)

            TextField(request.mode.prompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(apply)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Apply") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            isFocused = true
        }
    }

    private func apply() {
        onApply(query)
        dismiss()
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
