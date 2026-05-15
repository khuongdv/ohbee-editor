import SwiftUI
import AppKit
import OhbeeEditorCore

@main
struct OhbeeEditorApp: App {
    @StateObject private var store = EditorStore()
    @State private var isSearchVisible = false
    @State private var isAboutVisible = false
    @State private var isHelpVisible = false
    @AppStorage("ohbee.lineNumbers") private var showLineNumbers = true

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, isSearchVisible: $isSearchVisible)
                .frame(minWidth: 760, minHeight: 520)
                .navigationTitle(store.windowTitle)
                .sheet(isPresented: $isAboutVisible) {
                    AboutOhbeeView()
                }
                .sheet(isPresented: $isHelpVisible) {
                    OhbeeHelpView()
                }
                .onOpenURL { url in
                    guard url.isFileURL else {
                        return
                    }

                    store.openDocument(from: url)
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

                Button("URL Encode") { apply("URL Encode", URLTools.encode) }
                Button("URL Decode") { apply("URL Decode", URLTools.decode) }
                Button("Remove Tracking Parameters") { apply("Remove Tracking Parameters", URLTools.removeTrackingParameters) }

                Divider()

                Button("Detect Sensitive Text") { detectSensitiveText() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Mask Detected Patterns") { apply("Mask Detected Patterns", SafeShare.maskDetectedPatterns) }
            }
        }
    }

    private func apply(_ name: String, _ transform: @escaping (String) -> TextTransformResult) {
        EditorTextOperationCenter.shared.applyTransform(named: name, store: store, transform: transform)
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

        guard UnsavedTabWarning.confirmClosing([document]) else {
            return
        }

        store.closeDocument(selectedDocumentID)
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
}
