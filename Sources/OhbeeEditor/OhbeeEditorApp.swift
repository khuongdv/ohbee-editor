import SwiftUI
import AppKit
import OhbeeEditorCore

@main
struct OhbeeEditorApp: App {
    @NSApplicationDelegateAdaptor(OhbeeEditorAppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()
    @State private var isSearchVisible = false
    @State private var isAboutVisible = false
    @State private var isHelpVisible = false
    @State private var isCompareVisible = false
    @State private var isSafeShareReviewVisible = false
    @State private var isCommandPaletteVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ohbee.lineNumbers") private var showLineNumbers = true
    @AppStorage("ohbee.fontSize") private var fontSize: Double = 13

    var body: some Scene {
        Window("Ohbee Editor", id: "main") {
            ContentView(
                store: store,
                isSearchVisible: $isSearchVisible,
                isSafeShareReviewVisible: $isSafeShareReviewVisible,
                isCommandPaletteVisible: $isCommandPaletteVisible
            )
                .frame(minWidth: 760, minHeight: 520)
                .navigationTitle(store.windowTitle)
                .sheet(isPresented: $isAboutVisible) {
                    AboutOhbeeView()
                }
                .sheet(isPresented: $isHelpVisible) {
                    OhbeeHelpView()
                }
                .sheet(isPresented: $isCompareVisible) {
                    CompareTabsSheet(
                        documents: store.documents,
                        isPresented: $isCompareVisible,
                        onCompare: { baseID, changedID in
                            store.openDiffTab(baseID: baseID, changedID: changedID)
                        }
                    )
                }
                .onOpenURL { url in
                    openExternalFiles([url])
                }
                .onAppear {
                    appDelegate.openFilesHandler = { urls in
                        openExternalFiles(urls)
                    }
                    appDelegate.flushPendingOpenFiles()
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        store.flushPendingSessionSave()
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ohbee Editor") {
                    isAboutVisible = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    store.createScratchDocument()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!store.canCreateScratchDocument)
            }

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    closeSelectedTabWithWarning()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Reopen Closed File") {
                    store.reopenLastClosedFile()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!store.canReopenClosedFile)

                Button("Close Other Tabs") {
                    if let selectedDocumentID = store.selectedDocumentID {
                        closeOtherTabsWithWarning(keeping: selectedDocumentID)
                    }
                }
                .disabled(store.documents.count <= 1)

                Button("Close Tabs to the Right") {
                    if let selectedDocumentID = store.selectedDocumentID {
                        closeTabsToRightWithWarning(of: selectedDocumentID)
                    }
                }

                Button("Close All Tabs") {
                    closeAllTabsWithWarning()
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Save All") {
                    saveAll()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .importExport) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!store.canCreateScratchDocument)

                Menu("Open Recent") {
                    if store.recentFiles.isEmpty {
                        Button("No Recent Files") {}
                            .disabled(true)
                    } else {
                        ForEach(store.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                store.openDocument(from: url)
                            }
                            .help(url.path)
                            .disabled(!store.recentFileExists(url))
                        }
                        Divider()
                        Button("Remove Missing Recent Files") {
                            store.removeMissingRecentFiles()
                        }
                        Divider()
                        Button("Clear Recent Files") {
                            store.clearRecentFiles()
                        }
                    }
                }
            }

            CommandGroup(after: .textEditing) {
                Button("Find") {
                    isSearchVisible = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace") {
                    isSearchVisible = true
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("Command Palette...") {
                    isCommandPaletteVisible = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Compare Tabs…") {
                    isCompareVisible = true
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.documents.count < 2)

                Divider()

                Button("Vertical Selection…") {
                    let alert = NSAlert()
                    alert.messageText = "Vertical Selection"
                    alert.informativeText = "Hold Option and drag to select a rectangular block of text.\n\nPress Escape or click elsewhere to exit vertical selection mode."
                    alert.alertStyle = .informational
                    alert.icon = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }

            CommandGroup(after: .toolbar) {
                Menu("Language") {
                    Picker("Language", selection: languageSelection) {
                        ForEach(EditorLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Toggle("Show Line Numbers", isOn: $showLineNumbers)

                Divider()

                Button("Increase Font Size") {
                    fontSize = min(fontSize + 1.0, 36.0)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    fontSize = max(fontSize - 1.0, 10.0)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    fontSize = 13.0
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Ohbee Editor Help") {
                    isHelpVisible = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Text Tools") {
                Button("Trim Whitespace") { apply("Trim Whitespace", BasicTextTransforms.trimWhitespace) }
                Button("Trim Trailing Spaces") { apply("Trim Trailing Spaces", BasicTextTransforms.trimTrailingWhitespace) }
                Button("Remove Empty Lines") { apply("Remove Empty Lines", BasicTextTransforms.removeEmptyLines) }
                Button("Remove Duplicate Lines") { apply("Remove Duplicate Lines", BasicTextTransforms.removeDuplicateLines) }
                Button("Sort Lines") { apply("Sort Lines", BasicTextTransforms.sortLines) }
                Button("Join Lines") { apply("Join Lines", BasicTextTransforms.joinLines) }

                Divider()

                Button("lowercase") { apply("lowercase", BasicTextTransforms.lowercase) }
                Button("UPPERCASE") { apply("UPPERCASE", BasicTextTransforms.uppercase) }
                Button("Title Case") { apply("Title Case", BasicTextTransforms.titleCase) }
                Button("snake_case") { apply("snake_case", BasicTextTransforms.snakeCase) }
                Button("kebab-case") { apply("kebab-case", BasicTextTransforms.kebabCase) }
                Button("camelCase") { apply("camelCase", BasicTextTransforms.camelCase) }

                Divider()

                Button("Clean AI Output") { apply("Clean AI Output", BasicTextTransforms.cleanAIOutput) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .help("Strips surrounding Markdown code fences, collapses excess blank lines, trims trailing spaces, and normalizes line endings. One tap to clean up text copied from ChatGPT, Claude, or similar tools.")

                Divider()

                Button("Format JSON") { apply("Format JSON", JSONTools.format) }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .disabled(!store.selectedDocumentSupportsJSONTools)
                Button("Minify JSON") { apply("Minify JSON", JSONTools.minify) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(!store.selectedDocumentSupportsJSONTools)
                Button("Validate JSON") { validateJSON() }
                    .disabled(!store.selectedDocumentSupportsJSONTools)

                Divider()

                Button("Format XML") { apply("Format XML", XMLTools.format) }
                    .disabled(!store.selectedDocumentSupportsXMLTools)
                Button("Minify XML") { apply("Minify XML", XMLTools.minify) }
                    .disabled(!store.selectedDocumentSupportsXMLTools)

                Divider()

                Button("Extract URLs") { apply("Extract URLs", LogCleanupTools.extractURLs) }
                Button("Extract IPv4 Addresses") { apply("Extract IPv4 Addresses", LogCleanupTools.extractIPv4Addresses) }
                Button("Remove Timestamp Prefixes") { apply("Remove Timestamp Prefixes", LogCleanupTools.removeTimestampPrefixes) }

                Divider()

                Button("Word Frequency") { wordFrequency() }

                Divider()

                Button("URL Encode") { apply("URL Encode", URLTools.encode) }
                Button("URL Decode") { apply("URL Decode", URLTools.decode) }
                Button("Remove Tracking Parameters") { apply("Remove Tracking Parameters", URLTools.removeTrackingParameters) }

                Divider()

                Button("Review Safe Share…") {
                    isSafeShareReviewVisible = true
                }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Detect Sensitive Text") { detectSensitiveText() }
                Button("Mask Detected Patterns") { apply("Mask Detected Patterns", SafeShare.maskDetectedPatterns) }

                Divider()

                Button("SHA-256 Checksum") { computeChecksum("SHA-256", ChecksumTools.sha256(of:)) }
                Button("MD5 Checksum") { computeChecksum("MD5", ChecksumTools.md5(of:)) }

                Divider()

                Button("Duplicate Line") { duplicateLineInActiveEditor() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }

    private func apply(_ name: String, _ transform: @escaping (String) -> TextTransformResult) {
        EditorTextOperationCenter.shared.applyTransform(named: name, store: store, transform: transform)
    }

    private func openExternalFiles(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !fileURLs.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            for url in fileURLs {
                store.openDocument(from: url)
            }
            activateAppWindow()
        }
    }

    private var languageSelection: Binding<EditorLanguage> {
        Binding(
            get: { store.selectedLanguage },
            set: { store.setSelectedLanguage($0) }
        )
    }

    private func validateJSON() {
        EditorTextOperationCenter.shared.inspectText(named: "Validate JSON", store: store) { text in
            switch JSONTools.validate(text) {
            case let .success(_, summary):
                return (summary, .success)
            case let .failure(message):
                return (message, .warning)
            }
        }
    }

    private func computeChecksum(_ name: String, _ fn: (String) -> String?) {
        EditorTextOperationCenter.shared.inspectText(named: name, store: store) { text in
            if let hash = fn(text) {
                return (hash, .neutral)
            }
            return ("Cannot compute \(name).", .warning)
        }
    }

    private func duplicateLineInActiveEditor() {
        EditorTextOperationCenter.shared.duplicateLineInActiveEditor()
    }

    private func wordFrequency() {
        EditorTextOperationCenter.shared.inspectText(named: "Word Frequency", store: store) { text in
            let entries = WordFrequencyTools.topWords(in: text, limit: 5)
            if entries.isEmpty {
                return ("No words found.", .neutral)
            }
            let preview = entries.map { "\($0.word)×\($0.count)" }.joined(separator: ", ")
            return ("Top words: \(preview)", .neutral)
        }
    }

    private func detectSensitiveText() {
        EditorTextOperationCenter.shared.inspectText(named: "Safe Share", store: store) { text in
            let message = SafeShare.detectionSummary(in: text)
            let tone: StatusMessageTone = message.hasPrefix("Potential sensitive text found")
                ? .warning
                : .success
            return (message, tone)
        }
    }

    private func closeSelectedTabWithWarning() {
        guard let selectedDocumentID = store.selectedDocumentID else {
            return
        }

        guard let document = store.documents.first(where: { $0.id == selectedDocumentID }) else {
            return
        }

        switch UnsavedTabWarning.closeDecision(for: [document]) {
        case .closeWithoutSaving:
            store.closeDocument(selectedDocumentID)
        case .saveThenClose:
            if save() {
                store.closeDocument(selectedDocumentID)
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

    private func saveAll() {
        store.saveAllDocuments()
    }
}

final class OhbeeEditorAppDelegate: NSObject, NSApplicationDelegate {
    var openFilesHandler: (([URL]) -> Void)?
    private var pendingOpenFileURLs: [URL] = []

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        enqueueOpenFiles(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        enqueueOpenFiles([URL(fileURLWithPath: filename)])
        return true
    }

    func flushPendingOpenFiles() {
        guard !pendingOpenFileURLs.isEmpty else {
            return
        }

        let urls = pendingOpenFileURLs
        pendingOpenFileURLs = []
        openFilesHandler?(urls)
    }

    private func enqueueOpenFiles(_ urls: [URL]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if let openFilesHandler {
                openFilesHandler(urls)
            } else {
                pendingOpenFileURLs.append(contentsOf: urls)
            }
        }
    }
}
