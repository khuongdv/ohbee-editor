import Foundation
import OhbeeEditorCore

enum SelfTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfTestError.failed(message)
    }
}

final class NoopSessionStore: SessionPersisting {
    func loadSession() throws -> EditorSession? {
        nil
    }

    func saveSession(_ session: EditorSession) throws {}
}

final class CountingSessionStore: SessionPersisting {
    private(set) var saveCount = 0

    func loadSession() throws -> EditorSession? {
        nil
    }

    func saveSession(_ session: EditorSession) throws {
        saveCount += 1
    }
}

func testSaveAndLoadSession() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let store = LocalSessionStore(fileURL: fileURL)
    let document = EditorDocument.scratch(index: 1)
    let session = EditorSession(
        selectedDocumentID: document.id,
        documents: [document]
    )

    try store.saveSession(session)
    let loadedSession = try store.loadSession()
    try expect(loadedSession?.version == session.version, "Saved session version should load unchanged.")
    try expect(loadedSession?.selectedDocumentID == session.selectedDocumentID, "Selected document ID should load unchanged.")
    try expect(loadedSession?.documents.count == 1, "Saved document count should load unchanged.")
    try expect(loadedSession?.documents.first?.id == document.id, "Saved document ID should load unchanged.")
    try expect(loadedSession?.documents.first?.title == document.title, "Saved document title should load unchanged.")
}

func testMissingSessionReturnsNil() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let store = LocalSessionStore(fileURL: fileURL)

    let loadedSession = try store.loadSession()
    try expect(loadedSession == nil, "Missing session should return nil.")
}

func testLegacySessionMigration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let legacy = root.appendingPathComponent("legacy", isDirectory: true)
    let current = root.appendingPathComponent("current", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: legacy.appendingPathComponent("Session Text", isDirectory: true),
        withIntermediateDirectories: true
    )
    try "session".write(to: legacy.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
    try "scratch".write(
        to: legacy.appendingPathComponent("Session Text/note.txt"),
        atomically: true,
        encoding: .utf8
    )

    let didMigrate = try LocalSessionStore.migrateLegacyStoreIfNeeded(from: legacy, to: current)
    let migratedSession = try String(contentsOf: current.appendingPathComponent("session.json"), encoding: .utf8)
    let migratedSidecar = try String(contentsOf: current.appendingPathComponent("Session Text/note.txt"), encoding: .utf8)
    let didMigrateAgain = try LocalSessionStore.migrateLegacyStoreIfNeeded(from: legacy, to: current)
    try expect(
        didMigrate,
        "A legacy session should migrate when the container has no session."
    )
    try expect(
        migratedSession == "session",
        "Migration should copy the session manifest."
    )
    try expect(
        migratedSidecar == "scratch",
        "Migration should copy large scratch sidecars before the manifest."
    )
    try expect(
        !didMigrateAgain,
        "Migration should not overwrite an existing container session."
    )
}

func testTrimTrailingWhitespace() throws {
    let result = BasicTextTransforms.trimTrailingWhitespace("one  \ntwo\t\nthree")

    try expect(
        result == .success(
            text: "one\ntwo\nthree",
            summary: "Trimmed trailing whitespace on 2 lines."
        ),
        "Trailing whitespace transform should trim spaces and tabs."
    )
}

func testTrimTrailingWhitespaceHandlesEmptyInput() throws {
    let result = BasicTextTransforms.trimTrailingWhitespace("")

    try expect(
        result == .success(
            text: "",
            summary: "Trimmed trailing whitespace on 0 lines."
        ),
        "Trailing whitespace transform should handle empty input."
    )
}

func testLineTransforms() throws {
    try expect(
        BasicTextTransforms.removeEmptyLines("one\n\n  \ntwo") == .success(
            text: "one\ntwo",
            summary: "Removed empty 2 lines."
        ),
        "Remove empty lines should drop blank and whitespace-only lines."
    )

    try expect(
        BasicTextTransforms.removeDuplicateLines("b\na\nb") == .success(
            text: "b\na",
            summary: "Removed duplicate 1 line."
        ),
        "Remove duplicate lines should preserve first occurrences."
    )

    try expect(
        BasicTextTransforms.sortLines("b\na") == .success(
            text: "a\nb",
            summary: "Sorted 2 lines."
        ),
        "Sort lines should order lines ascending."
    )

    try expect(
        BasicTextTransforms.joinLines(" one \n\ntwo ") == .success(
            text: "one two",
            summary: "Joined 3 lines."
        ),
        "Join lines should trim and join non-empty lines."
    )
}

func testLineEndingPreservation() throws {
    try expect(
        BasicTextTransforms.trimTrailingWhitespace("one  \r\ntwo\t\r\n") == .success(
            text: "one\r\ntwo\r\n",
            summary: "Trimmed trailing whitespace on 2 lines."
        ),
        "Trailing whitespace transform should preserve dominant CRLF endings."
    )

    try expect(
        BasicTextTransforms.removeEmptyLines("one\r\n\r\ntwo") == .success(
            text: "one\r\ntwo",
            summary: "Removed empty 1 line."
        ),
        "Remove empty lines should preserve dominant CRLF endings."
    )
}

func testCaseTransforms() throws {
    try expect(
        BasicTextTransforms.snakeCase("Xin chao Ohbee") == .success(
            text: "xin_chao_ohbee",
            summary: "Converted text to snake_case."
        ),
        "snake_case should lowercase words and join with underscores."
    )

    try expect(
        BasicTextTransforms.kebabCase("Xin chao Ohbee") == .success(
            text: "xin-chao-ohbee",
            summary: "Converted text to kebab-case."
        ),
        "kebab-case should lowercase words and join with hyphens."
    )

    try expect(
        BasicTextTransforms.camelCase("Xin chao Ohbee") == .success(
            text: "xinChaoOhbee",
            summary: "Converted text to camelCase."
        ),
        "camelCase should lowercase the first word and capitalize following words."
    )
}

func testCleanAIOutput() throws {
    let input = "```swift\r\nlet x = 1   \r\n\r\n\r\nprint(x)\r\n```\n"
    let result = BasicTextTransforms.cleanAIOutput(input)

    try expect(
        result == .success(
            text: "let x = 1\n\nprint(x)",
            summary: "Cleaned AI output."
        ),
        "Clean AI output should remove surrounding fences, normalize line endings, trim trailing spaces, and compact blanks."
    )
}

func testSearchSummaryAndNavigation() throws {
    let options = SearchOptions(query: "xin", replacement: "hello", usesRegex: false, isCaseSensitive: false)
    let text = "Xin chao\nxin nua"

    let evaluation = SearchReplaceEngine.evaluate(in: text, options: options, currentMatchIndex: nil)
    try expect(
        evaluation.summary == SearchSummary(matchCount: 2, currentMatchIndex: 0),
        "Search evaluation should count case-insensitive matches."
    )
    try expect(
        evaluation.ranges == [NSRange(location: 0, length: 3), NSRange(location: 9, length: 3)],
        "Search evaluation should return the ranges consumers highlight."
    )

    let regexEvaluation = SearchReplaceEngine.evaluate(
        in: "id=100\nid=200\nid=300",
        options: SearchOptions(query: #"id=\d+"#, usesRegex: true, isCaseSensitive: true),
        currentMatchIndex: nil
    )
    try expect(
        regexEvaluation.ranges.count == 3,
        "Regex evaluation should return every match range."
    )

    // Navigation lives in EditorStore and walks the cached ranges; it is the only path the UI uses.
    var document = EditorDocument.scratch(index: 1)
    document.text = text
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )
    store.updateSearchQuery("xin")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try expect(store.searchSummary.currentMatchIndex == 0, "A new query should start at the first match.")
    store.selectNextMatch()
    try expect(store.searchSummary.currentMatchIndex == 1, "Next match should advance.")
    store.selectNextMatch()
    try expect(store.searchSummary.currentMatchIndex == 0, "Next match should wrap to the first match.")
    store.selectPreviousMatch()
    try expect(store.searchSummary.currentMatchIndex == 1, "Previous match should wrap backwards.")
}

func testSearchReplace() throws {
    let options = SearchOptions(query: "xin", replacement: "hello", usesRegex: false, isCaseSensitive: false)

    try expect(
        SearchReplaceEngine.replaceCurrent(in: "Xin chao xin", options: options, currentMatchIndex: 1) == .success(text: "Xin chao hello", replacementCount: 1),
        "Replace current should replace the selected match index."
    )

    try expect(
        SearchReplaceEngine.replaceAll(in: "Xin chao xin", options: options) == .success(text: "hello chao hello", replacementCount: 2),
        "Replace all should replace all literal matches."
    )

    try expect(
        SearchReplaceEngine.replaceAll(in: "Xin chao", options: SearchOptions(query: "", replacement: "hello")) == .failure(message: "Enter text to find."),
        "Replace all should reject an empty search query instead of changing text."
    )

    try expect(
        SearchReplaceEngine.replaceCurrent(in: "Xin chao", options: SearchOptions(query: "", replacement: "hello"), currentMatchIndex: nil) == .success(text: "Xin chao", replacementCount: 0),
        "Replace current should leave text unchanged for an empty search query."
    )
}

func testRegexReplace() throws {
    let options = SearchOptions(query: #"\d+"#, replacement: "#", usesRegex: true, isCaseSensitive: true)

    try expect(
        SearchReplaceEngine.replaceAll(in: "a1 b22", options: options) == .success(text: "a# b#", replacementCount: 2),
        "Regex replace all should use NSRegularExpression templates."
    )

    let captureOptions = SearchOptions(query: #"(\w+)=(\d+)"#, replacement: "$1:#$2", usesRegex: true, isCaseSensitive: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "id=42", options: captureOptions) == .success(text: "id:#42", replacementCount: 1),
        "Regex replace all should support capture templates."
    )
}

func testSearchReplaceEdgeCases() throws {
    let invalidRegex = SearchOptions(query: #"("#, replacement: "", usesRegex: true, isCaseSensitive: true)
    let invalidSummary = SearchReplaceEngine.evaluate(in: "abc", options: invalidRegex, currentMatchIndex: nil).summary
    try expect(
        invalidSummary.hasInvalidRegex && invalidSummary.errorMessage != nil,
        "Invalid regex search should report an invalid pattern."
    )
    try expect(
        SearchReplaceEngine.replaceAll(in: "abc", options: invalidRegex) == .failure(message: "Invalid regular expression."),
        "Invalid regex replace all should fail without mutating text."
    )
    try expect(
        SearchReplaceEngine.evaluate(in: "abc", options: invalidRegex, currentMatchIndex: nil).ranges.isEmpty,
        "Invalid regex match lookup should return no ranges."
    )

    let wholeWord = SearchOptions(query: "cat", replacement: "dog", usesRegex: false, isCaseSensitive: false, isWholeWord: true)
    try expect(
        SearchReplaceEngine.evaluate(in: "cat scatter cat-cat _cat cat1", options: wholeWord, currentMatchIndex: nil).ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 12, length: 3),
            NSRange(location: 16, length: 3)
        ],
        "Whole-word search should skip embedded word characters and match punctuation boundaries."
    )
    try expect(
        SearchReplaceEngine.replaceAll(in: "cat scatter cat-cat _cat cat1", options: wholeWord) == .success(text: "dog scatter dog-dog _cat cat1", replacementCount: 3),
        "Whole-word replace should only replace whole-word matches."
    )

    let caseSensitive = SearchOptions(query: "xin", replacement: "hello", usesRegex: false, isCaseSensitive: true)
    try expect(
        SearchReplaceEngine.evaluate(in: "Xin xin XIN", options: caseSensitive, currentMatchIndex: nil).summary == SearchSummary(matchCount: 1, currentMatchIndex: 0),
        "Case-sensitive search should only count exact-case matches."
    )
}

func testSearchCacheInvalidatesImmediately() throws {
    var document = EditorDocument.scratch(index: 1)
    document.text = "alpha beta alpha"
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )
    store.updateSearchQuery("alpha")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try expect(store.searchSummary.matchCount == 2, "Setup should publish alpha matches.")

    store.updateSearchQuery("beta")
    try expect(store.searchSummary.matchCount == 0, "Changing query should invalidate old matches synchronously.")
    try expect(store.currentSearchMatchRange == nil, "A stale range must not remain replaceable during debounce.")

    store.updateReplacement("replacement changed during evaluation")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try expect(store.searchSummary.matchCount == 1, "Replacement changes must not discard a valid search evaluation.")
}

func testEditingSearchMatchDoesNotRequestSelection() throws {
    var document = EditorDocument.scratch(index: 1)
    document.text = "LynkiD first\nLynkiD second"
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try expect(store.searchSummary.matchCount == 2, "Setup should publish both search matches.")
    let selectionRequest = store.searchSelectionRequest
    try expect(selectionRequest > 0, "Entering a query should request selection of its first match.")

    store.textBinding(for: document.id).wrappedValue = "M first\nLynkiD second"
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    try expect(store.searchSummary.matchCount == 1, "Editing a match should refresh the remaining search results.")
    try expect(
        store.searchSelectionRequest == selectionRequest,
        "Editing document text must not request selection of the next search result."
    )
}

func testClosingSelectedDocumentRequestsSearchSelection() throws {
    var first = EditorDocument.scratch(index: 1)
    first.text = "LynkiD first"
    var second = EditorDocument.scratch(index: 2)
    second.text = "before LynkiD after"
    let store = EditorStore(
        documents: [first, second],
        selectedDocumentID: first.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let selectionRequest = store.searchSelectionRequest

    store.closeDocument(first.id)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    try expect(store.selectedDocumentID == second.id, "Closing the selected document should select the remaining document.")
    try expect(store.currentSearchMatchRange == NSRange(location: 7, length: 6), "Search should reset to the first match in the newly selected document.")
    try expect(store.searchSelectionRequest == selectionRequest + 1, "Changing documents through Close should request match selection.")
}

func testClosingBackgroundDocumentDoesNotRequestSearchSelection() throws {
    var selected = EditorDocument.scratch(index: 1)
    selected.text = "LynkiD selected"
    var background = EditorDocument.scratch(index: 2)
    background.text = "LynkiD background"
    let store = EditorStore(
        documents: [selected, background],
        selectedDocumentID: selected.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let selectionRequest = store.searchSelectionRequest

    store.closeDocument(background.id)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    try expect(store.selectedDocumentID == selected.id, "Closing a background document should preserve the selected document.")
    try expect(store.searchSelectionRequest == selectionRequest, "Closing a background document must not move the editor selection.")
}

func testDiscardingSelectedDocumentRequestsSearchSelection() throws {
    let now = Date()
    let missing = EditorDocument(
        id: UUID(),
        title: "missing.txt",
        text: "LynkiD missing",
        fileURL: nil,
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now,
        isMissingFile: true
    )
    var remaining = EditorDocument.scratch(index: 1)
    remaining.text = "LynkiD remaining"
    let store = EditorStore(
        documents: [missing, remaining],
        selectedDocumentID: missing.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let selectionRequest = store.searchSelectionRequest

    store.discardMissingDocument(missing.id)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    try expect(store.selectedDocumentID == remaining.id, "Discarding the selected missing document should select the remaining document.")
    try expect(store.searchSelectionRequest == selectionRequest + 1, "Changing documents through Discard should request match selection.")
}

func testCloseAllClearsSearchState() throws {
    var document = EditorDocument.scratch(index: 1)
    document.text = "LynkiD"
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    try expect(store.searchSummary.matchCount == 1, "Setup should publish a search match.")

    store.closeAllDocuments()

    try expect(store.searchSummary.matchCount == 0, "Close All should synchronously clear stale search results.")
    try expect(store.currentSearchMatchRange == nil, "Close All should clear the stale current match range.")
}

func testReplaceCurrentRequestsSearchSelection() throws {
    var document = EditorDocument.scratch(index: 1)
    document.text = "LynkiD first LynkiD second"
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore(),
        sessionSaveDebounceInterval: 0
    )

    store.updateSearchQuery("LynkiD")
    store.updateReplacement("MyCompany")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let selectionRequest = store.searchSelectionRequest

    store.replaceCurrentMatch()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    try expect(store.selectedDocument?.text == "MyCompany first LynkiD second", "Replace should update the current match.")
    try expect(store.searchSummary.matchCount == 1, "Replace should refresh the remaining matches.")
    try expect(store.searchSelectionRequest == selectionRequest + 1, "Replace should select the next available match.")
}

func testReauthorizationPreservesDirtyBuffer() throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    try "disk text".write(to: fileURL, atomically: true, encoding: .utf8)
    let now = Date()
    let document = EditorDocument(
        id: UUID(),
        title: fileURL.lastPathComponent,
        text: "unsaved buffer",
        fileURL: fileURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now,
        requiresFileAuthorization: true
    )
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore()
    )
    store.reauthorizeDocument(document.id, with: fileURL)
    try expect(store.documents.first?.text == "unsaved buffer", "Reauthorization must not overwrite dirty session text from disk.")
    try expect(store.documents.first?.isDirty == true, "Reauthorization must preserve dirty state.")
}

func testReauthorizationRejectsDifferentFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let expectedURL = root.appendingPathComponent("expected.txt")
    let differentURL = root.appendingPathComponent("different.txt")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "other file".write(to: differentURL, atomically: true, encoding: .utf8)
    let now = Date()
    let document = EditorDocument(
        id: UUID(),
        title: expectedURL.lastPathComponent,
        text: "unsaved buffer",
        fileURL: expectedURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now,
        requiresFileAuthorization: true
    )
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore()
    )

    store.reauthorizeDocument(document.id, with: differentURL)

    try expect(store.documents.first?.fileURL == expectedURL, "Reauthorization must not relink a tab to a differently named file.")
    try expect(store.documents.first?.requiresFileAuthorization == true, "A rejected file must leave authorization unresolved.")
    try expect(store.statusMessage?.contains("expected.txt") == true, "The warning should identify the file that must be selected.")
}

func testRegexSafetyLimits() throws {
    let risky = SearchOptions(query: "(a+)+", replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: String(repeating: "a", count: 10_000), options: risky)
            == .failure(message: RegexSearchError.patternNotSupported.localizedDescription),
        "Nested quantifiers should be rejected before matching."
    )

    let oversized = String(repeating: "a", count: 300_001)
    let bounded = SearchOptions(query: "a+", replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: oversized, options: bounded)
            == .failure(message: RegexSearchError.inputTooLarge.localizedDescription),
        "Regex replace should report oversized input instead of running it."
    )
    try expect(
        SearchReplaceEngine.evaluate(in: oversized, options: bounded, currentMatchIndex: nil).summary.errorMessage
            == RegexSearchError.inputTooLarge.localizedDescription,
        "Regex search summary should distinguish oversized input from no matches."
    )

    let ambiguous = SearchOptions(
        query: "a*a*a*a*a*a*a*a*a*a*b",
        replacement: "x",
        usesRegex: true
    )
    let startedAt = Date()
    let ambiguousResult = SearchReplaceEngine.replaceAll(
        in: String(repeating: "a", count: 40_000),
        options: ambiguous
    )
    try expect(Date().timeIntervalSince(startedAt) < 1.0, "Ambiguous regex matching should be stopped promptly.")
    try expect(
        ambiguousResult == .failure(message: RegexSearchError.matchingTimedOut.localizedDescription),
        "A stopped regex should report timeout rather than oversized input or no matches."
    )
}

func testWholeWordLargeLiteralInput() throws {
    let text = String(repeating: "cat ", count: 100_000)
    let options = SearchOptions(query: "cat", replacement: "dog", isWholeWord: true)
    let evaluation = SearchReplaceEngine.evaluate(in: text, options: options, currentMatchIndex: nil)
    try expect(evaluation.summary.errorMessage == nil, "Whole-word literal search should not inherit the regex size limit.")
    try expect(evaluation.summary.matchCount == 100_000, "Whole-word literal search should handle large input.")
    let unicodeEvaluation = SearchReplaceEngine.evaluate(
        in: "😀cat😀 cafécat cat",
        options: options,
        currentMatchIndex: nil
    )
    try expect(unicodeEvaluation.summary.matchCount == 2, "Whole-word boundary checks should safely handle surrogate pairs.")
}

func testEditorStoreCachesSearchEvaluation() throws {
    var document = EditorDocument.scratch(index: 1)
    document.text = String(repeating: "alpha beta ", count: 2_000)
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: NoopSessionStore()
    )
    store.updateSearchQuery("beta")
    let deadline = Date().addingTimeInterval(2)
    while store.searchSummary.matchCount != 2_000, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    try expect(store.searchSummary.matchCount == 2_000, "EditorStore should publish the debounced search evaluation.")
    let first = store.searchSummary
    let startedAt = Date()
    for _ in 0..<1_000 { _ = store.searchSummary }
    try expect(store.searchSummary == first, "Repeated summary reads should return cached state.")
    try expect(Date().timeIntervalSince(startedAt) < 0.1, "Reading cached search state should not rerun matching.")
}

func testSearchReplaceLargeLiteralInputCompletes() throws {
    let text = String(repeating: "alpha beta gamma\n", count: 20_000)
    let options = SearchOptions(query: "beta", replacement: "BETA", isCaseSensitive: true)
    let start = Date()
    let result = SearchReplaceEngine.replaceAll(in: text, options: options)
    let elapsed = Date().timeIntervalSince(start)

    guard case let .success(replaced, replacementCount) = result else {
        throw SelfTestError.failed("Large literal replace should succeed.")
    }

    try expect(replacementCount == 20_000, "Large literal replace should replace every matching line.")
    try expect(!replaced.contains(" beta "), "Large literal replace should remove original literal matches.")
    try expect(elapsed < 2.0, "Large literal replace should finish within a practical smoke-test threshold.")
}

func testCloseTabBehaviors() throws {
    let first = EditorDocument.scratch(index: 1)
    let second = EditorDocument.scratch(index: 2)
    let third = EditorDocument.scratch(index: 3)
    let store = EditorStore(
        documents: [first, second, third],
        selectedDocumentID: second.id,
        sessionStore: NoopSessionStore()
    )

    store.closeDocumentsToRight(of: first.id)
    try expect(store.documents.map(\.id) == [first.id], "Close tabs to the right should keep the target and close later tabs.")
    try expect(store.selectedDocumentID == first.id, "Close tabs to the right should select the target tab.")

    store.closeAllDocuments()
    try expect(store.documents.count == 1, "Close all should leave one fresh note open.")
    try expect(store.selectedDocument != nil, "Close all should keep a selected document.")
}

func testCloseOtherTabsAndLanguage() throws {
    let first = EditorDocument.scratch(index: 1)
    let second = EditorDocument.scratch(index: 2)
    let store = EditorStore(
        documents: [first, second],
        selectedDocumentID: second.id,
        sessionStore: NoopSessionStore()
    )

    store.setSelectedLanguage(.json)
    try expect(store.selectedDocument?.language == .json, "Language selection should update the selected document.")

    store.closeOtherDocuments(keeping: second.id)
    try expect(store.documents.map(\.id) == [second.id], "Close other tabs should keep only the requested tab.")
    try expect(store.selectedDocumentID == second.id, "Close other tabs should keep the requested tab selected.")
}

func testRecentlyClosedFilesStack() throws {
    let now = Date()
    let fileDocuments = (0..<12).map { index in
        EditorDocument(
            id: UUID(),
            title: "file\(index).txt",
            text: "",
            fileURL: URL(fileURLWithPath: "/tmp/file\(index).txt"),
            isScratch: false,
            isDirty: false,
            createdAt: now,
            updatedAt: now
        )
    }
    let scratch = EditorDocument.scratch(index: 1)
    let store = EditorStore(
        documents: fileDocuments + [scratch],
        selectedDocumentID: scratch.id,
        sessionStore: NoopSessionStore()
    )

    for document in fileDocuments {
        store.closeDocument(document.id)
    }

    try expect(store.recentlyClosedFileURLs.count == 10, "Recently closed files should be capped at 10.")
    try expect(
        store.recentlyClosedFileURLs.first?.lastPathComponent == "file11.txt",
        "Most recently closed file should be first in the reopen stack."
    )
    try expect(
        !store.recentlyClosedFileURLs.contains(URL(fileURLWithPath: "/tmp/file0.txt")),
        "Old closed files should fall off the capped reopen stack."
    )
    try expect(store.documents.contains { $0.id == scratch.id }, "Unsaved scratch tabs should remain separate from the closed-file stack.")
}

func testSaveAllDocuments() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let dirtyURL = directory.appendingPathComponent("dirty.txt")
    let cleanURL = directory.appendingPathComponent("clean.txt")
    let readOnlyURL = directory.appendingPathComponent("readonly.txt")
    try "old".write(to: dirtyURL, atomically: true, encoding: .utf8)
    try "clean".write(to: cleanURL, atomically: true, encoding: .utf8)
    try "readonly".write(to: readOnlyURL, atomically: true, encoding: .utf8)

    let now = Date()
    let dirtyFile = EditorDocument(
        id: UUID(),
        title: "dirty.txt",
        text: "new",
        fileURL: dirtyURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now
    )
    let cleanFile = EditorDocument(
        id: UUID(),
        title: "clean.txt",
        text: "clean",
        fileURL: cleanURL,
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )
    let readOnlyFile = EditorDocument(
        id: UUID(),
        title: "readonly.txt",
        text: "changed",
        fileURL: readOnlyURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now,
        isReadOnly: true
    )
    var scratch = EditorDocument.scratch(index: 1)
    scratch.text = "draft"
    scratch.isDirty = true

    let store = EditorStore(
        documents: [dirtyFile, cleanFile, readOnlyFile, scratch],
        selectedDocumentID: dirtyFile.id,
        sessionStore: NoopSessionStore()
    )

    let result = store.saveAllDocuments()
    try expect(result.savedCount == 1, "Save All should save dirty writable file-backed tabs.")
    try expect(result.skippedCleanCount == 1, "Save All should skip clean file-backed tabs.")
    try expect(result.skippedReadOnlyCount == 1, "Save All should skip read-only file-backed tabs.")
    try expect(result.skippedScratchCount == 1, "Save All should skip unsaved scratch tabs.")
    let savedText = try String(contentsOf: dirtyURL)
    try expect(savedText == "new", "Save All should write dirty file-backed text to disk.")
    try expect(store.documents.first { $0.id == dirtyFile.id }?.isDirty == false, "Saved files should be marked clean.")
    try expect(store.documents.first { $0.id == scratch.id }?.isDirty == true, "Unsaved scratch tabs should remain dirty.")
}

func testEditorFileMetadata() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("metadata.txt")
    try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

    let metadata = EditorFileIO.metadata(for: fileURL)
    try expect(metadata?.byteCount == 5, "File metadata should include byte count for an existing file.")
    try expect(metadata?.creationDate != nil, "File metadata should include creation date when the filesystem provides it.")
    try expect(metadata?.author?.isEmpty == false, "File metadata should include a local owner/author when available.")

    let missingURL = directory.appendingPathComponent("missing.txt")
    try expect(EditorFileIO.metadata(for: missingURL) == nil, "Missing files should not produce file metadata.")
}

func testLanguageInferenceAndOverride() throws {
    let jsonURL = URL(fileURLWithPath: "/tmp/sample.json")
    let dataURL = URL(fileURLWithPath: "/tmp/sample.data")
    let jsonDocument = EditorDocument(
        id: UUID(),
        title: "sample.json",
        text: "{}",
        fileURL: jsonURL,
        isScratch: false,
        isDirty: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    let dataDocument = EditorDocument(
        id: UUID(),
        title: "sample.data",
        text: "{}",
        fileURL: dataURL,
        isScratch: false,
        isDirty: false,
        createdAt: Date(),
        updatedAt: Date()
    )

    try expect(jsonDocument.effectiveLanguage == .json, ".json files should infer JSON language.")
    try expect(dataDocument.effectiveLanguage == .plainText, "Unknown extensions should infer Plain Text.")

    let store = EditorStore(
        documents: [dataDocument],
        selectedDocumentID: dataDocument.id,
        sessionStore: NoopSessionStore()
    )
    try expect(!store.selectedDocumentSupportsJSONTools, ".data should not enable JSON tools before override.")

    store.setSelectedLanguage(.json)
    try expect(store.selectedDocument?.language == .json, "Language override should be stored on the document.")
    try expect(store.selectedDocument?.effectiveLanguage == .json, "Language override should win over extension inference.")
    try expect(store.selectedDocumentSupportsJSONTools, "JSON override should enable JSON tools.")

    let jsonStore = EditorStore(
        documents: [jsonDocument],
        selectedDocumentID: jsonDocument.id,
        sessionStore: NoopSessionStore()
    )
    jsonStore.setSelectedLanguage(.plainText)
    try expect(jsonStore.selectedDocument?.effectiveLanguage == .plainText, "Language override should change the visible language indicator.")
    try expect(jsonStore.selectedDocumentSupportsJSONTools, ".json files should keep JSON tools enabled even if the visible language is overridden.")
}

func testWindowTitle() throws {
    let note = EditorDocument.scratch(index: 1)
    let uniqueFile = EditorDocument(
        id: UUID(),
        title: "mylocalfile.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/tmp/mylocalfile.txt"),
        isScratch: false,
        isDirty: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    let duplicateA = EditorDocument(
        id: UUID(),
        title: "same.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/Users/khuongdv/work/a/same.txt"),
        isScratch: false,
        isDirty: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    let duplicateB = EditorDocument(
        id: UUID(),
        title: "same.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/Users/khuongdv/work/b/same.txt"),
        isScratch: false,
        isDirty: false,
        createdAt: Date(),
        updatedAt: Date()
    )

    let noteStore = EditorStore(documents: [note], selectedDocumentID: note.id, sessionStore: NoopSessionStore())
    try expect(noteStore.windowTitle == "Ohbee Editor - Note 1", "Scratch note title should be shown in the window title.")

    let fileStore = EditorStore(documents: [uniqueFile], selectedDocumentID: uniqueFile.id, sessionStore: NoopSessionStore())
    try expect(fileStore.windowTitle == "Ohbee Editor - mylocalfile.txt", "Unique saved file should use the file name in the window title.")

    let duplicateStore = EditorStore(documents: [duplicateA, duplicateB], selectedDocumentID: duplicateB.id, sessionStore: NoopSessionStore())
    try expect(
        duplicateStore.windowTitle == "Ohbee Editor - /Users/khuongdv/work/b/same.txt",
        "Duplicate file names should use path in the window title."
    )
}

func testJSONTools() throws {
    let formatted = JSONTools.format(#"{"b":2,"a":1}"#)
    guard case let .success(formattedText, _) = formatted else {
        throw SelfTestError.failed("Valid JSON should format.")
    }
    try expect(formattedText.contains(#""a" : 1"#), "Formatted JSON should contain sorted key a.")
    try expect(formattedText.contains(#""b" : 2"#), "Formatted JSON should contain sorted key b.")

    try expect(
        JSONTools.minify("{\n  \"a\" : 1\n}") == .success(text: #"{"a":1}"#, summary: "Minified JSON."),
        "Minify JSON should remove insignificant whitespace."
    )

    guard case let .failure(message) = JSONTools.validate("{") else {
        throw SelfTestError.failed("Invalid JSON should fail validation.")
    }
    try expect(message.hasPrefix("Invalid JSON:"), "Invalid JSON should report a parse error.")
}

func testURLTools() throws {
    try expect(
        URLTools.encode("a b&c=d?") == .success(text: "a%20b%26c%3Dd%3F", summary: "URL encoded text."),
        "URL encode should encode arbitrary text as a URL component."
    )

    try expect(
        URLTools.decode("xin%20chao") == .success(text: "xin chao", summary: "URL decoded text."),
        "URL decode should decode percent escapes."
    )

    try expect(
        URLTools.removeTrackingParameters("https://ohbee.link/?utm_source=x&keep=1&fbclid=y") == .success(
            text: "https://ohbee.link/?keep=1",
            summary: "Removed 2 tracking parameters."
        ),
        "Tracking cleanup should remove only known tracking parameters."
    )

    try expect(
        URLTools.removeTrackingParameters("Share this: https://ohbee.link/page?utm_source=x&keep=1 and keep reading.") == .success(
            text: "Share this: https://ohbee.link/page?keep=1 and keep reading.",
            summary: "Removed 1 tracking parameter."
        ),
        "Tracking cleanup should clean embedded URLs in prose."
    )

    try expect(
        URLTools.removeTrackingParameters("See https://ohbee.link/path?utm_source=x).") == .success(
            text: "See https://ohbee.link/path).",
            summary: "Removed 1 tracking parameter."
        ),
        "Tracking cleanup should preserve trailing prose punctuation outside the URL."
    )

    try expect(
        URLTools.removeTrackingParameters("https://example.com/path?utm_source=news&keep=1&gclid=abc#section") == .success(
            text: "https://example.com/path?keep=1#section",
            summary: "Removed 2 tracking parameters."
        ),
        "Tracking cleanup should preserve unknown query parameters and URL fragments."
    )
}

func testLogCleanupTools() throws {
    let log = """
    2026-06-01 10:00:00 INFO started
    2026-06-01 10:00:01 ERROR failed for https://example.com/a?b=1
    10:00:02 warn client 192.168.1.20 retried
    10:00:03 ERROR duplicate https://example.com/a?b=1 from 999.1.1.1
    """

    try expect(
        LogCleanupTools.keepLines(containing: "error")(log) == .success(
            text: "2026-06-01 10:00:01 ERROR failed for https://example.com/a?b=1\n10:00:03 ERROR duplicate https://example.com/a?b=1 from 999.1.1.1",
            summary: "Kept 2 lines."
        ),
        "Keep lines containing should filter lines case-insensitively."
    )

    try expect(
        LogCleanupTools.removeLines(containing: "ERROR")(log) == .success(
            text: "2026-06-01 10:00:00 INFO started\n10:00:02 warn client 192.168.1.20 retried",
            summary: "Removed 2 lines."
        ),
        "Remove lines containing should drop matching lines."
    )

    try expect(
        LogCleanupTools.extractURLs(log) == .success(
            text: "https://example.com/a?b=1",
            summary: "Extracted 1 URL."
        ),
        "Extract URLs should return stable unique URLs."
    )

    try expect(
        LogCleanupTools.extractIPv4Addresses(log) == .success(
            text: "192.168.1.20",
            summary: "Extracted 1 IPv4 address."
        ),
        "Extract IPv4 should reject invalid octets."
    )

    try expect(
        LogCleanupTools.removeTimestampPrefixes("[2026-06-01 10:00:00Z] hello\n10:00:01 world") == .success(
            text: "hello\nworld",
            summary: "Removed timestamp prefix from 2 lines."
        ),
        "Remove timestamp prefixes should handle bracketed date-times and time-only prefixes."
    )

    try expect(
        LogCleanupTools.keepLines(containing: "ERROR")("INFO ok\nERROR bad\n") == .success(
            text: "ERROR bad\n",
            summary: "Kept 1 line."
        ),
        "Keep lines containing should preserve a trailing POSIX newline."
    )

    try expect(
        LogCleanupTools.removeLines(containing: "INFO")("INFO ok\nERROR bad\n") == .success(
            text: "ERROR bad\n",
            summary: "Removed 1 line."
        ),
        "Remove lines containing should preserve a trailing POSIX newline."
    )

    try expect(
        LogCleanupTools.extractURLs("Read https://example.com/wiki/Go_(lang)") == .success(
            text: "https://example.com/wiki/Go_(lang)",
            summary: "Extracted 1 URL."
        ),
        "Extract URLs should keep balanced trailing parentheses inside URLs."
    )
}

func testSafeShare() throws {
    let text = """
    Email me at dev@example.com
    API_KEY=abc123456789secret
    https://ohbee.link/?token=abcdef123456&keep=1
    {"APIKey": "9L00152353252AFc2-014ACHA"}
    """
    let findings = SafeShare.detect(in: text)
    try expect(findings.contains { $0.category == "Email" }, "Safe Share should detect emails.")
    try expect(findings.contains { $0.category == ".env secret" }, "Safe Share should detect .env style secrets.")
    try expect(findings.contains { $0.category == "Token URL parameter" }, "Safe Share should detect token-like URL parameters.")
    try expect(findings.contains { $0.category == "JSON secret" }, "Safe Share should detect JSON-style secret key/value pairs.")

    guard case let .success(masked, summary) = SafeShare.maskDetectedPatterns(text) else {
        throw SelfTestError.failed("Safe Share masking should succeed.")
    }
    try expect(summary.hasPrefix("Masked"), "Safe Share masking should report masked findings.")
    try expect(!masked.contains("dev@example.com"), "Safe Share masking should hide detected email text.")
    try expect(!masked.contains("abc123456789secret"), "Safe Share masking should hide detected secret values.")
    try expect(!masked.contains("9L00152353252AFc2-014ACHA"), "Safe Share masking should hide detected JSON secret values.")

    let review = SafeShare.review(in: text)
    try expect(review.sourceText == text, "Safe Share review should preserve the original source text.")
    try expect(review.hasFindings, "Safe Share review should report findings when sensitive-looking text exists.")
    try expect(review.categorySummaries.contains { $0.category == "Email" && $0.count == 1 }, "Safe Share review should summarize email findings.")
    try expect(review.categorySummaries.contains { $0.category == "JSON secret" && $0.count == 1 }, "Safe Share review should summarize JSON secret findings.")
    try expect(
        review.copyableFindingsSummary.contains("Email"),
        "Safe Share review should expose a copyable summary without secret values."
    )
    try expect(
        !review.copyableFindingsSummary.contains("dev@example.com"),
        "Safe Share review summary should not include sensitive values."
    )
    try expect(review.maskedText == masked, "Safe Share review masked preview should match the masking transform.")
    try expect(!review.maskedText.contains("dev@example.com"), "Safe Share review preview should hide detected email text.")

    if let emailIndex = review.findings.firstIndex(where: { $0.category == "Email" }) {
        let selectedMasked = review.maskedText(includingFindingIndexes: Set([emailIndex]))
        try expect(!selectedMasked.contains("dev@example.com"), "Selected Safe Share masking should mask selected findings.")
        try expect(selectedMasked.contains("abc123456789secret"), "Selected Safe Share masking should leave unselected findings alone.")
    } else {
        throw SelfTestError.failed("Safe Share review should include an email finding for selected masking.")
    }

    if let emailFinding = review.findings.first(where: { $0.category == "Email" }) {
        let snippet = SafeShare.maskedSnippet(for: emailFinding)
        try expect(snippet.contains("***"), "Safe Share review snippets should show masked text.")
        try expect(!snippet.contains("dev@example.com"), "Safe Share review snippets should not expose full sensitive values.")
        try expect(!snippet.contains("dev@"), "Safe Share review snippets should not expose sensitive prefixes.")
        try expect(!snippet.contains(".com"), "Safe Share review snippets should not expose sensitive suffixes.")
    } else {
        throw SelfTestError.failed("Safe Share review should include an email finding.")
    }

    try expect(
        SafeShare.detect(in: "Meet me at 10:30 for lunch. Nothing secret here.").isEmpty,
        "Safe Share should avoid obvious normal-text false positives."
    )

    try expect(
        SafeShare.detect(in: #"{"APIKey": "short"}"#).isEmpty,
        "Safe Share should avoid short JSON API-key-looking placeholders."
    )

    try expect(
        SafeShare.detect(in: "Order ID 12345678 and invoice total 123.45 are ordinary support text.").isEmpty,
        "Safe Share should avoid obvious support-text numeric false positives."
    )

    let emptyReview = SafeShare.review(in: "Meet me at 10:30 for lunch. Nothing secret here.")
    try expect(!emptyReview.hasFindings, "Safe Share review should handle no-finding text.")
    try expect(emptyReview.maskedText == emptyReview.sourceText, "Safe Share review should leave no-finding text unchanged.")
}

func testDebouncedSessionSaveFlushesOnce() throws {
    let document = EditorDocument.scratch(index: 1)
    let sessionStore = CountingSessionStore()
    let store = EditorStore(
        documents: [document],
        selectedDocumentID: document.id,
        sessionStore: sessionStore,
        sessionSaveDebounceInterval: 60
    )

    let binding = store.textBinding(for: document.id)
    binding.wrappedValue = "one"
    binding.wrappedValue = "two"
    binding.wrappedValue = "three"

    try expect(sessionStore.saveCount == 0, "Text edits should schedule session save instead of writing immediately.")
    store.flushPendingSessionSave()
    try expect(sessionStore.saveCount == 1, "Flushing pending session save should write one coalesced session.")
}

func sqlTokens(_ text: String, kind: SQLTokenKind? = nil) -> [SQLSyntaxToken] {
    let tokens = SQLSyntaxTokenizer.tokens(in: text)
    guard let kind else {
        return tokens
    }

    return tokens.filter { $0.kind == kind }
}

func expectSQLToken(_ text: String, _ tokenText: String, _ kind: SQLTokenKind, _ message: String) throws {
    try expect(
        sqlTokens(text, kind: kind).contains { $0.text.uppercased() == tokenText.uppercased() },
        message
    )
}

func testSQLBasicKeywords() throws {
    let text = "SELECT * FROM users WHERE active = true;"
    try expectSQLToken(text, "SELECT", .keyword, "SQL should highlight SELECT as keyword.")
    try expectSQLToken(text, "FROM", .keyword, "SQL should highlight FROM as keyword.")
    try expectSQLToken(text, "WHERE", .keyword, "SQL should highlight WHERE as keyword.")
    try expectSQLToken(text, "true", .keyword, "SQL should highlight true as keyword/literal.")
}

func testSQLCaseInsensitiveKeywords() throws {
    let text = "select * from users;\nSelect * From users;"
    let keywordTexts = sqlTokens(text, kind: .keyword).map { $0.text.uppercased() }
    try expect(keywordTexts.filter { $0 == "SELECT" }.count == 2, "SQL keywords should be case-insensitive for SELECT.")
    try expect(keywordTexts.filter { $0 == "FROM" }.count == 2, "SQL keywords should be case-insensitive for FROM.")
}

func testSQLDataTypes() throws {
    let text = "CREATE TABLE users (id UUID PRIMARY KEY, name VARCHAR(255), age INT);"
    try expectSQLToken(text, "CREATE", .keyword, "SQL should highlight CREATE as keyword.")
    try expectSQLToken(text, "TABLE", .keyword, "SQL should highlight TABLE as keyword.")
    try expectSQLToken(text, "PRIMARY", .keyword, "SQL should highlight PRIMARY as keyword.")
    try expectSQLToken(text, "KEY", .keyword, "SQL should highlight KEY as keyword.")
    try expectSQLToken(text, "UUID", .type, "SQL should highlight UUID as type.")
    try expectSQLToken(text, "VARCHAR", .type, "SQL should highlight VARCHAR as type.")
    try expectSQLToken(text, "INT", .type, "SQL should highlight INT as type.")
    try expectSQLToken(text, "255", .number, "SQL should highlight numeric type arguments.")
}

func testSQLFunctions() throws {
    let text = "SELECT COUNT(*), COALESCE(name, 'Unknown') FROM users WHERE created_at >= CURRENT_DATE;"
    try expectSQLToken(text, "COUNT", .function, "SQL should highlight COUNT as function.")
    try expectSQLToken(text, "COALESCE", .function, "SQL should highlight COALESCE as function.")
    try expectSQLToken(text, "CURRENT_DATE", .function, "SQL should highlight CURRENT_DATE as function.")
    try expectSQLToken(text, "'Unknown'", .string, "SQL should highlight single-quoted strings.")
}

func testSQLStringsAndQuotedIdentifiers() throws {
    let text = #"SELECT 'hello', 'It''s fine', "user", "order" FROM "table";"#
    try expectSQLToken(text, "'hello'", .string, "SQL should highlight simple single-quoted strings.")
    try expectSQLToken(text, "'It''s fine'", .string, "SQL should highlight escaped single-quoted strings.")
    try expectSQLToken(text, #""user""#, .identifier, "SQL should highlight quoted identifiers.")
    try expectSQLToken(text, #""order""#, .identifier, "SQL should highlight quoted identifiers that contain keyword-like text.")
    try expectSQLToken(text, #""table""#, .identifier, "SQL should highlight quoted table identifiers.")
    try expect(!sqlTokens(text, kind: .keyword).contains { $0.text == "order" || $0.text == "table" }, "SQL should not highlight keywords inside quoted identifiers.")
}

func testSQLComments() throws {
    let text = """
    -- SELECT should not highlight here
    SELECT * FROM users;

    /* FROM should not highlight here */
    SELECT * FROM users;
    """
    try expect(sqlTokens(text, kind: .comment).count == 2, "SQL should highlight line and block comments.")
    try expect(sqlTokens(text, kind: .keyword).filter { $0.text.uppercased() == "SELECT" }.count == 2, "SQL should not highlight SELECT inside comments.")
    try expect(sqlTokens(text, kind: .keyword).filter { $0.text.uppercased() == "FROM" }.count == 2, "SQL should not highlight FROM inside comments.")
}

func testSQLLineCommentsRespectNonUnixLineEndings() throws {
    let carriageReturnText = "-- SELECT should not highlight here\rselect * from XSource where Code = 'XXX';"
    let windowsText = "-- SELECT should not highlight here\r\ninsert into XSource values ('XXX');"

    try expectSQLToken(carriageReturnText, "select", .keyword, "SQL line comments should end at carriage returns.")
    try expectSQLToken(carriageReturnText, "from", .keyword, "SQL should resume highlighting after carriage-return line comments.")
    try expectSQLToken(carriageReturnText, "'XXX'", .string, "SQL strings should highlight after carriage-return line comments.")

    try expectSQLToken(windowsText, "insert", .keyword, "SQL line comments should end before Windows newlines.")
    try expectSQLToken(windowsText, "into", .keyword, "SQL should resume highlighting after Windows line comments.")
    try expectSQLToken(windowsText, "'XXX'", .string, "SQL strings should highlight after Windows line comments.")
}

func testSQLNumbersAndOperators() throws {
    let text = "SELECT 0, 123, 12.34, -5, 1_000 FROM users WHERE age >= 18 AND status <> 'disabled';"
    for number in ["0", "123", "12.34", "-5", "1_000", "18"] {
        try expectSQLToken(text, number, .number, "SQL should highlight number \(number).")
    }
    try expectSQLToken(text, ">=", .operatorToken, "SQL should highlight >= as operator.")
    try expectSQLToken(text, "<>", .operatorToken, "SQL should highlight <> as operator.")
    try expectSQLToken(text, "'disabled'", .string, "SQL should highlight strings near operators.")
}

func testSQLPlainTextModeProducesNoTokens() throws {
    let text = "SELECT * FROM users WHERE active = true;"
    try expect(SQLSyntaxTokenizer.tokens(in: text, language: .plainText).isEmpty, "Plain Text mode should not produce SQL highlight tokens.")
}

// MARK: - ColumnSelection tests

func testLineMapSingleLine() throws {
    let ns = "hello" as NSString
    let lm = LineMap(string: ns)
    try expect(lm.lineCount == 1, "Single-line string should have 1 line.")
    try expect(lm.lineStart(0) == 0, "Line 0 should start at 0.")
    try expect(lm.lineContentLength(0) == 5, "Line 0 content length should be 5.")
}

func testLineMapMultiLine() throws {
    let ns = "hello\nworld\nfoo" as NSString
    let lm = LineMap(string: ns)
    try expect(lm.lineCount == 3, "Three lines should be detected.")
    try expect(lm.lineStart(0) == 0, "Line 0 starts at 0.")
    try expect(lm.lineStart(1) == 6, "Line 1 starts at 6.")
    try expect(lm.lineStart(2) == 12, "Line 2 starts at 12.")
    try expect(lm.lineContentLength(0) == 5, "Line 0 content length is 5 (hello).")
    try expect(lm.lineContentLength(1) == 5, "Line 1 content length is 5 (world).")
    try expect(lm.lineContentLength(2) == 3, "Line 2 content length is 3 (foo).")
}

func testLineMapTrailingNewline() throws {
    let ns = "hello\n" as NSString
    let lm = LineMap(string: ns)
    try expect(lm.lineCount == 2, "Trailing newline should produce 2 lines.")
    try expect(lm.lineStart(1) == 6, "Empty last line starts at 6.")
    try expect(lm.lineContentLength(1) == 0, "Empty last line has 0 content length.")
}

func testLineMapEmptyString() throws {
    let ns = "" as NSString
    let lm = LineMap(string: ns)
    try expect(lm.lineCount == 1, "Empty string should have 1 (empty) line.")
    try expect(lm.lineStart(0) == 0, "Line 0 of empty string starts at 0.")
    try expect(lm.lineContentLength(0) == 0, "Empty string line content length is 0.")
}

func testLineAndColumn() throws {
    let ns = "hello\nworld" as NSString
    let lm = LineMap(string: ns)
    let (l0, c0) = lm.lineAndColumn(for: 0)
    try expect(l0 == 0 && c0 == 0, "charIdx 0 → line 0, col 0.")
    let (l4, c4) = lm.lineAndColumn(for: 4)
    try expect(l4 == 0 && c4 == 4, "charIdx 4 → line 0, col 4.")
    let (l6, c6) = lm.lineAndColumn(for: 6)
    try expect(l6 == 1 && c6 == 0, "charIdx 6 → line 1, col 0 (first char of 'world').")
    let (l9, c9) = lm.lineAndColumn(for: 9)
    try expect(l9 == 1 && c9 == 3, "charIdx 9 → line 1, col 3 ('ld' start).")
}

func testColumnSelectionRanges() throws {
    // "abc\ndef\nghi"  indices: a=0 b=1 c=2 \n=3 d=4 e=5 f=6 \n=7 g=8 h=9 i=10
    let ns = "abc\ndef\nghi" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 2, startCol: 1, endCol: 3)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    try expect(ranges.count == 3, "Rectangle across 3 lines should produce 3 ranges.")
    try expect(ranges[0] == NSRange(location: 1, length: 2), "Line 0: 'bc' at NSRange(1,2).")
    try expect(ranges[1] == NSRange(location: 5, length: 2), "Line 1: 'ef' at NSRange(5,2).")
    try expect(ranges[2] == NSRange(location: 9, length: 2), "Line 2: 'hi' at NSRange(9,2).")
}

func testColumnSelectionShortLine() throws {
    // "ab\ndefgh\nx"  — line 0 is short, col 3-5 should clamp
    // a=0 b=1 \n=2  d=3 e=4 f=5 g=6 h=7 \n=8  x=9
    let ns = "ab\ndefgh\nx" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 2, startCol: 3, endCol: 5)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    try expect(ranges.count == 3, "3 lines in rectangle.")
    try expect(ranges[0] == NSRange(location: 2, length: 0), "Short line 0: empty range at content end.")
    try expect(ranges[1] == NSRange(location: 6, length: 2), "Line 1: 'gh' at NSRange(6,2).")
    try expect(ranges[2] == NSRange(location: 10, length: 0), "Short line 2 ('x'): clamp both cols to 1.")
}

func testColumnSelectionEmptyLine() throws {
    // "abc\n\nghi"  — line 1 is empty
    // a=0 b=1 c=2 \n=3  \n=4  g=5 h=6 i=7
    let ns = "abc\n\nghi" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 2, startCol: 1, endCol: 3)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    try expect(ranges[1] == NSRange(location: 4, length: 0), "Empty line 1: empty range at its start.")
}

func testColumnSelectionSingleLine() throws {
    let ns = "hello world" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 0, startCol: 6, endCol: 11)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    try expect(ranges.count == 1, "Single-line selection produces 1 range.")
    try expect(ranges[0] == NSRange(location: 6, length: 5), "Single-line: 'world' at NSRange(6,5).")
}

func testCopyColumnRanges() throws {
    let ns = "abc\ndef\nghi" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 2, startCol: 1, endCol: 3)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    let copied = copyColumnRanges(ranges, from: ns)
    try expect(copied == "bc\nef\nhi", "Copy rectangle should join extracted text with newlines.")
}

func testCopyColumnRangesWithEmptyLine() throws {
    let ns = "abc\n\nghi" as NSString
    let lm = LineMap(string: ns)
    let sel = ColumnSelection(startLine: 0, endLine: 2, startCol: 1, endCol: 3)
    let ranges = sel.ranges(in: ns, lineMap: lm)
    let copied = copyColumnRanges(ranges, from: ns)
    try expect(copied == "bc\n\nhi", "Empty line in rectangle should produce empty segment in copy.")
}

// MARK: - Large file policy tests

func testFileSizePolicyClassification() throws {
    try expect(LargeFilePolicy.classify(byteCount: 0) == .normal, "0 bytes should be normal.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.normalByteLimit) == .normal, "Exactly at normalByteLimit should be normal.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.normalByteLimit + 1) == .large, "1 byte over normalByteLimit should be large.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.warningByteLimit) == .large, "Exactly at warningByteLimit should be large.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.warningByteLimit + 1) == .veryLarge, "1 byte over warningByteLimit should be veryLarge.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.maximumByteLimit) == .veryLarge, "Exactly at maximumByteLimit should be veryLarge.")
    try expect(LargeFilePolicy.classify(byteCount: LargeFilePolicy.maximumByteLimit + 1) == .tooLarge, "1 byte over maximumByteLimit should be tooLarge.")
}

func testSessionTextForCleanFileBacked() throws {
    let doc = EditorDocument(
        id: UUID(), title: "file.txt", text: "hello world",
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: false,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(LargeFilePolicy.sessionText(for: doc) == "", "Clean file-backed document should not persist text in session.")
}

func testSessionTextForDirtyFileBackedWithinCap() throws {
    let doc = EditorDocument(
        id: UUID(), title: "file.txt", text: "unsaved change",
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(LargeFilePolicy.sessionText(for: doc) == "unsaved change", "Dirty file-backed doc within cap should persist text.")
}

func testSessionTextForDirtyFileBackedOverCap() throws {
    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    let doc = EditorDocument(
        id: UUID(), title: "file.txt", text: bigText,
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(LargeFilePolicy.sessionText(for: doc) == bigText, "Dirty file-backed doc over cap should preserve text for sidecar persistence.")
}

func testSessionTextForScratchWithinCap() throws {
    let doc = EditorDocument.scratch(index: 1)
    var mutable = doc
    mutable.text = "my notes"
    try expect(LargeFilePolicy.sessionText(for: mutable) == "my notes", "Scratch doc within cap should persist text.")
}

func testSessionTextForScratchOverCap() throws {
    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    var doc = EditorDocument.scratch(index: 1)
    doc.text = bigText
    try expect(LargeFilePolicy.sessionText(for: doc) == bigText, "Scratch doc over cap should preserve text for sidecar persistence.")
}

func testDirtyFileBackedTextIsPreservedForSession() throws {
    let smallDirtyDoc = EditorDocument(
        id: UUID(), title: "file.txt", text: "small change",
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(
        LargeFilePolicy.sessionText(for: smallDirtyDoc) == "small change",
        "A dirty file-backed doc should keep its unsaved text in the session."
    )

    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    let largeDirtyDoc = EditorDocument(
        id: UUID(), title: "file.txt", text: bigText,
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(
        LargeFilePolicy.sessionText(for: largeDirtyDoc) == bigText,
        "A large dirty file-backed doc should preserve text for sidecar persistence."
    )

    var cleanDoc = smallDirtyDoc
    cleanDoc.isDirty = false
    try expect(
        LargeFilePolicy.sessionText(for: cleanDoc).isEmpty,
        "A clean file-backed doc is re-read from disk, so the session should store no text."
    )
}

func testFileSizeSessionRoundTrip() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let store = LocalSessionStore(fileURL: fileURL)

    let fileBackedDoc = EditorDocument(
        id: UUID(), title: "sample.txt", text: "content from disk",
        fileURL: URL(fileURLWithPath: "/tmp/sample.txt"),
        isScratch: false, isDirty: false,
        createdAt: Date(), updatedAt: Date()
    )
    let scratchDoc = EditorDocument.scratch(index: 1)
    var mutableScratch = scratchDoc
    mutableScratch.text = "scratch notes"

    // Simulate what EditorStore.saveSession does: strip text for clean file-backed docs.
    var fileRecord = fileBackedDoc
    fileRecord.text = LargeFilePolicy.sessionText(for: fileBackedDoc)

    let session = EditorSession(
        selectedDocumentID: fileBackedDoc.id,
        documents: [fileRecord, mutableScratch]
    )
    try store.saveSession(session)
    let loaded = try store.loadSession()

    try expect(loaded?.documents.first?.text == "", "Saved session should not contain text for clean file-backed document.")
    try expect(loaded?.documents.last?.text == "scratch notes", "Saved session should preserve scratch document text.")
}

func testLargeSessionTextSidecarRoundTrip() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fileURL = directoryURL.appendingPathComponent("session.json")
    let store = LocalSessionStore(fileURL: fileURL)

    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    var scratchDoc = EditorDocument.scratch(index: 1)
    scratchDoc.text = bigText
    scratchDoc.isDirty = true

    let session = EditorSession(
        selectedDocumentID: scratchDoc.id,
        documents: [scratchDoc]
    )

    try store.saveSession(session)
    let sessionData = try Data(contentsOf: fileURL)
    try expect(sessionData.count < LargeFilePolicy.sessionTextCap, "Large scratch text should be kept out of the session JSON.")

    let loaded = try store.loadSession()
    try expect(loaded?.documents.first?.text == bigText, "Large scratch text should restore from local sidecar storage.")
    try expect(loaded?.documents.first?.sessionTextFileName == nil, "Loaded documents should expose hydrated text, not sidecar internals.")

    try? FileManager.default.removeItem(at: directoryURL)
}

// MARK: - XML tools tests

func testXMLFormat() throws {
    let xml = "<root><child>text</child></root>"
    guard case let .success(formatted, summary) = XMLTools.format(xml) else {
        throw SelfTestError.failed("Valid XML should format successfully.")
    }
    try expect(summary == "Formatted XML.", "XML format summary should be 'Formatted XML.'")
    try expect(formatted.contains("<child>text</child>"), "Formatted XML should contain child element.")
}

func testXMLMinify() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
        <child>text</child>
    </root>
    """
    guard case let .success(minified, summary) = XMLTools.minify(xml) else {
        throw SelfTestError.failed("Valid XML should minify successfully.")
    }
    try expect(summary == "Minified XML.", "XML minify summary should be 'Minified XML.'")
    try expect(!minified.contains("\n    "), "Minified XML should not contain indentation whitespace.")
}

func testXMLInvalidReportsError() throws {
    guard case let .failure(message) = XMLTools.format("<unclosed>") else {
        throw SelfTestError.failed("Invalid XML should fail.")
    }
    try expect(message.hasPrefix("Invalid XML:"), "Invalid XML error should start with 'Invalid XML:'.")
}

func testXMLEmptyInput() throws {
    guard case .failure = XMLTools.format("   ") else {
        throw SelfTestError.failed("Empty XML input should fail.")
    }
}

func testXMLRejectsEntities() throws {
    let externalEntity = #"<!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><root>&xxe;</root>"#
    guard case let .failure(message) = XMLTools.format(externalEntity) else {
        throw SelfTestError.failed("XML external entity declarations should be rejected.")
    }
    try expect(message.contains("entity declarations"), "XML entity rejection should explain the restriction.")

    let expansion = #"<!DOCTYPE root [<!ENTITY a "123"><!ENTITY b "&a;&a;">]><root>&b;</root>"#
    guard case .failure = XMLTools.minify(expansion) else {
        throw SelfTestError.failed("XML internal entity expansion should be rejected.")
    }

    let harmless = #"<root><!-- Example: <!DOCTYPE html> --><![CDATA[<!ENTITY example>]]></root>"#
    guard case .success = XMLTools.format(harmless) else {
        throw SelfTestError.failed("DOCTYPE/entity text inside comments and CDATA should remain valid.")
    }
}

func testImageFileSizeLimits() throws {
    try expect(
        LargeFilePolicy.maximumImageByteLimit(forExtension: "svg") == 10 * 1_048_576,
        "SVG files should have a conservative 10 MB limit."
    )
    try expect(
        LargeFilePolicy.maximumImageByteLimit(forExtension: "PNG") == 100 * 1_048_576,
        "Raster images should use the general 100 MB image limit."
    )

    let disguisedSVG = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: disguisedSVG) }
    try #"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>"#
        .write(to: disguisedSVG, atomically: true, encoding: .utf8)
    try expect(EditorFileIO.isLikelySVG(at: disguisedSVG), "SVG content should be detected despite a raster extension.")
    try expect(
        LargeFilePolicy.maximumImageByteLimit(for: disguisedSVG) == LargeFilePolicy.maximumSVGByteLimit,
        "Disguised SVG content should receive the stricter vector-image limit."
    )
}

// MARK: - Word frequency tests

func testWordFrequencyTopWords() throws {
    let text = "apple banana apple cherry apple banana"
    let entries = WordFrequencyTools.topWords(in: text, limit: 3)
    try expect(entries.count == 3, "Should return top 3 words.")
    try expect(entries[0].word == "apple" && entries[0].count == 3, "Most frequent word should be 'apple' with count 3.")
    try expect(entries[1].word == "banana" && entries[1].count == 2, "Second word should be 'banana' with count 2.")
}

func testWordFrequencyEmptyInput() throws {
    let entries = WordFrequencyTools.topWords(in: "")
    try expect(entries.isEmpty, "Empty input should produce no entries.")
}

func testWordFrequencyIgnoresShortTokens() throws {
    let text = "a b c go to the store"
    let entries = WordFrequencyTools.topWords(in: text)
    let words = entries.map(\.word)
    try expect(!words.contains("a"), "Single-char tokens should be ignored.")
    try expect(!words.contains("b"), "Single-char tokens should be ignored.")
    try expect(words.contains("go"), "2-char word 'go' should appear.")
    try expect(words.contains("to"), "2-char word 'to' should appear.")
    try expect(words.contains("the"), "3-char word 'the' should appear.")
    try expect(words.contains("store"), "5-char word 'store' should appear.")
}

// MARK: - Diff tools tests

func testDiffCommonLines() throws {
    let base = ["line1", "line2", "line3"]
    let changed = ["line1", "line2", "line3"]
    let lines = DiffTools.diff(base: base, changed: changed)
    try expect(lines.allSatisfy { $0.kind == .common }, "Identical inputs should produce all common lines.")
    try expect(lines.count == 3, "Should have 3 common lines.")
}

func testDiffAddedLines() throws {
    let base = ["line1", "line3"]
    let changed = ["line1", "line2", "line3"]
    let lines = DiffTools.diff(base: base, changed: changed)
    let added = lines.filter { $0.kind == .added }
    try expect(added.count == 1, "Should detect 1 added line.")
    try expect(added[0].text == "line2", "Added line should be 'line2'.")
}

func testDiffRemovedLines() throws {
    let base = ["line1", "line2", "line3"]
    let changed = ["line1", "line3"]
    let lines = DiffTools.diff(base: base, changed: changed)
    let removed = lines.filter { $0.kind == .removed }
    try expect(removed.count == 1, "Should detect 1 removed line.")
    try expect(removed[0].text == "line2", "Removed line should be 'line2'.")
}

func testDiffAnnotatedText() throws {
    let base = "hello\nworld"
    let changed = "hello\nSwift"
    let annotated = DiffTools.annotatedText(baseTitle: "A", changedTitle: "B", base: base, changed: changed)
    try expect(annotated.contains("--- A"), "Annotated text should have base header.")
    try expect(annotated.contains("+++ B"), "Annotated text should have changed header.")
    try expect(annotated.contains("- world"), "Annotated text should mark removed line.")
    try expect(annotated.contains("+ Swift"), "Annotated text should mark added line.")
    try expect(annotated.contains("  hello"), "Annotated text should mark common line.")
}

func testDiffEmptyBase() throws {
    let lines = DiffTools.diff(base: [], changed: ["new"])
    try expect(lines.count == 1 && lines[0].kind == .added, "All lines should be added when base is empty.")
}

// MARK: - Regressions for the sandbox, session-recovery, privacy, and transform fixes

func testLegacyStoreDirectoryUsesRealHome() throws {
    let containerHome = "/Users/tester/Library/Containers/link.ohbee.editor/Data"

    try expect(
        LocalSessionStore.homePathStrippingContainerSuffix(containerHome) == "/Users/tester",
        "A sandbox container home should resolve back to the account home."
    )
    try expect(
        LocalSessionStore.homePathStrippingContainerSuffix("/Users/tester") == "/Users/tester",
        "A non-container home should be returned unchanged."
    )
    try expect(
        LocalSessionStore.realHomeDirectoryPath(sandboxHomePath: containerHome, posixHomePath: "/Users/tester")
            == "/Users/tester",
        "The POSIX account home should win over the container home."
    )
    try expect(
        LocalSessionStore.realHomeDirectoryPath(sandboxHomePath: containerHome, posixHomePath: nil)
            == "/Users/tester",
        "Without a POSIX home, the container suffix should still be stripped."
    )

    let legacyDirectory = LocalSessionStore.legacyStoreDirectory().path
    try expect(
        !legacyDirectory.contains("/Library/Containers/"),
        "The pre-sandbox store directory must never point inside the sandbox container."
    )
    try expect(
        legacyDirectory.hasSuffix("/Library/Application Support/Ohbee Editor"),
        "The pre-sandbox store directory should be the Application Support folder."
    )
}

func testUnsupportedSessionVersionIsReportedAsSuch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("session.json")
    try #"{"version": 99, "documents": []}"#.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = LocalSessionStore(fileURL: fileURL)
    var caught: SessionPersistenceError?
    do {
        _ = try store.loadSession()
    } catch let error as SessionPersistenceError {
        caught = error
    }

    guard let caught else {
        throw SelfTestError.failed("A newer session format should report a failure.")
    }
    try expect(
        caught.isUnsupportedVersion,
        "A newer session format should be reported as unsupported, not as corruption."
    )
    try expect(
        store.recoveryNotice?.contains("newer version") == true,
        "The notice should explain that the session came from a newer build: \(store.recoveryNotice ?? "nil")"
    )
}

func testFailedLoadMovesOrphanTextOutOfPruneScope() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sidecarDirectory = directory.appendingPathComponent("Session Text", isDirectory: true)
    try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("session.json")
    try "{ not json".write(to: fileURL, atomically: true, encoding: .utf8)
    try "unsaved note text".write(
        to: sidecarDirectory.appendingPathComponent("\(UUID().uuidString).txt"),
        atomically: true,
        encoding: .utf8
    )

    let firstLaunch = LocalSessionStore(fileURL: fileURL)
    _ = try? firstLaunch.loadSession()
    let replacement = EditorDocument.scratch(index: 1)
    try firstLaunch.saveSession(EditorSession(selectedDocumentID: replacement.id, documents: [replacement]))

    let recoveredDirectories = try FileManager.default
        .contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasPrefix("Recovered Note Text ") }
    try expect(recoveredDirectories.count == 1, "Orphan note text should be moved to a recovery folder.")

    let recoveredURL = directory.appendingPathComponent(recoveredDirectories[0], isDirectory: true)
    let recoveredFiles = try FileManager.default.contentsOfDirectory(atPath: recoveredURL.path)
    try expect(recoveredFiles.count == 1, "The recovery folder should hold the preserved text file.")
    try expect(
        firstLaunch.recoveryNotice?.contains("Recovered Note Text") == true,
        "The notice should point at the recovery folder."
    )

    // Later healthy launches must not be able to delete the preserved text.
    let secondLaunch = LocalSessionStore(fileURL: fileURL)
    _ = try secondLaunch.loadSession()
    let note = EditorDocument.scratch(index: 2)
    try secondLaunch.saveSession(EditorSession(selectedDocumentID: note.id, documents: [note]))
    let thirdLaunch = LocalSessionStore(fileURL: fileURL)
    _ = try thirdLaunch.loadSession()
    try thirdLaunch.saveSession(EditorSession(selectedDocumentID: note.id, documents: [note]))

    try expect(
        FileManager.default.fileExists(atPath: recoveredURL.appendingPathComponent(recoveredFiles[0]).path),
        "Preserved note text must survive every later launch, not just the one that recovered it."
    )
}

func testHiddenFilesDoNotBlockSidecarPruning() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sidecarDirectory = directory.appendingPathComponent("Session Text", isDirectory: true)
    try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data().write(to: sidecarDirectory.appendingPathComponent(".DS_Store"))

    let store = LocalSessionStore(fileURL: directory.appendingPathComponent("session.json"))
    let loaded = try store.loadSession()

    try expect(loaded == nil, "A missing manifest should still return nil.")
    try expect(
        store.recoveryNotice == nil,
        "Filesystem noise must not be reported as preserved note text: \(store.recoveryNotice ?? "nil")"
    )
    try expect(
        FileManager.default.fileExists(atPath: sidecarDirectory.path),
        "A directory holding only hidden files should be left alone, not moved."
    )
}

func testReadableSessionStillPrunesUnusedSidecars() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fileURL = directory.appendingPathComponent("session.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = LocalSessionStore(fileURL: fileURL)
    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    var note = EditorDocument.scratch(index: 1)
    note.text = bigText
    note.isDirty = true

    try store.saveSession(EditorSession(selectedDocumentID: note.id, documents: [note]))
    let sidecarURL = directory
        .appendingPathComponent("Session Text", isDirectory: true)
        .appendingPathComponent("\(note.id.uuidString).txt")
    try expect(
        FileManager.default.fileExists(atPath: sidecarURL.path),
        "A large note should spill to a sidecar file."
    )

    // A successful load proves the manifest is readable, so stale sidecars may be pruned.
    _ = try store.loadSession()
    let replacement = EditorDocument.scratch(index: 2)
    try store.saveSession(EditorSession(selectedDocumentID: replacement.id, documents: [replacement]))

    try expect(
        !FileManager.default.fileExists(atPath: sidecarURL.path),
        "Sidecars that the current session no longer references should be pruned after a successful load."
    )
    try expect(store.recoveryNotice == nil, "A healthy session should not produce a recovery notice.")
}

func testCorruptSessionIsQuarantined() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("session.json")
    try "{ not json".write(to: fileURL, atomically: true, encoding: .utf8)

    let store = LocalSessionStore(fileURL: fileURL)
    var didThrow = false
    do {
        _ = try store.loadSession()
    } catch {
        didThrow = true
    }

    try expect(didThrow, "An unreadable session should report a failure instead of returning nil.")
    try expect(
        !FileManager.default.fileExists(atPath: fileURL.path),
        "The unreadable manifest should be moved aside, not left to be overwritten."
    )
    let quarantined = try FileManager.default
        .contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasPrefix("session.corrupt-") }
    try expect(quarantined.count == 1, "The unreadable manifest should be kept as a quarantined copy.")
    try expect(store.recoveryNotice != nil, "A load failure should produce a user-facing notice.")
}

func testCorruptSessionKeepsSidecarText() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sidecarDirectory = directory.appendingPathComponent("Session Text", isDirectory: true)
    try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("session.json")
    try "{ not json".write(to: fileURL, atomically: true, encoding: .utf8)
    let sidecarURL = sidecarDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    try "unsaved note text".write(to: sidecarURL, atomically: true, encoding: .utf8)

    let store = LocalSessionStore(fileURL: fileURL)
    _ = try? store.loadSession()

    // Saving a fresh session must not delete text this process could not account for.
    let replacement = EditorDocument.scratch(index: 1)
    try store.saveSession(EditorSession(selectedDocumentID: replacement.id, documents: [replacement]))

    // The text may have been moved out of the prunable directory; what matters is that its
    // content still exists somewhere under the session directory.
    let preservedTexts = FileManager.default
        .enumerator(at: directory, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "txt" }
        .compactMap { try? String(contentsOf: $0, encoding: .utf8) } ?? []

    try expect(
        preservedTexts.contains("unsaved note text"),
        "Unsaved note text must survive a session load failure, found: \(preservedTexts)"
    )
    try expect(
        !FileManager.default.fileExists(atPath: sidecarURL.path),
        "Preserved text should be moved out of the directory that pruning scans."
    )
}

func testCorruptSessionWarnsThroughStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("session.json")
    try "{ not json".write(to: fileURL, atomically: true, encoding: .utf8)

    let sessionStore = LocalSessionStore(fileURL: fileURL)
    let outcome = EditorStore.restoreSession(using: sessionStore)

    try expect(outcome.session == nil, "An unreadable session should not restore documents.")
    try expect(outcome.warning != nil, "An unreadable session should surface a warning to the user.")
}

func testSafeShareMaskHidesPrefixAndSuffix() throws {
    let text = "key sk_live_51H8xQpKq9ZabCdEfGhIjKl and mail john.doe@company.com"

    guard case let .success(masked, _) = SafeShare.maskDetectedPatterns(text) else {
        throw SelfTestError.failed("Safe Share masking should succeed.")
    }

    try expect(!masked.contains("sk_live"), "Masking must not keep a secret prefix.")
    try expect(!masked.contains("IjKl"), "Masking must not keep a secret suffix.")
    try expect(!masked.contains("john"), "Masking must not keep an email prefix.")
    try expect(!masked.contains(".com"), "Masking must not keep an email suffix.")
    try expect(
        masked.contains(SafeShare.redactionPlaceholder),
        "Masked output should use the fixed redaction placeholder."
    )
}

func testSafeSharePhoneFalsePositives() throws {
    let logText = """
    2026-05-15 12:30:45 INFO request from 192.168.100.201
    build version 1.2.3.4567 finished
    order 1234567890 shipped
    ids 10 20 30 40 50
    invoice total 123.45
    date 2026-05-15 recorded
    """

    let phoneFindings = SafeShare.detect(in: logText).filter { $0.category == "Phone number" }
    try expect(
        phoneFindings.isEmpty,
        "Timestamps, IP addresses, version strings, bare IDs, and dates must not be treated as phone numbers: \(phoneFindings.map(\.text))"
    )

    guard case let .success(masked, _) = SafeShare.maskDetectedPatterns(logText) else {
        throw SelfTestError.failed("Masking log text should succeed.")
    }
    try expect(
        masked.contains("2026-05-15 12:30:45") && masked.contains("192.168.100.201"),
        "Apply Mask must leave ordinary log data untouched."
    )
}

func testSafeSharePhoneTruePositives() throws {
    let samples = ["+1 (415) 555-2671", "0912 345 678", "415-555-2671", "+14155552671"]

    for sample in samples {
        let findings = SafeShare.detect(in: "call \(sample) today").filter { $0.category == "Phone number" }
        try expect(!findings.isEmpty, "Safe Share should still detect \(sample) as a phone number.")
    }
}

func testLineTransformsPreserveTerminalNewline() throws {
    try expect(
        BasicTextTransforms.sortLines("banana\napple\ncherry\n") == .success(
            text: "apple\nbanana\ncherry\n",
            summary: "Sorted 3 lines."
        ),
        "Sorting must not move a terminal newline to the top of the document."
    )

    try expect(
        BasicTextTransforms.sortLinesDescending("apple\nbanana\n") == .success(
            text: "banana\napple\n",
            summary: "Sorted descending 2 lines."
        ),
        "Descending sort should preserve the terminal newline."
    )

    try expect(
        BasicTextTransforms.trimWhitespace("  one  \n  two  \n") == .success(
            text: "one\ntwo\n",
            summary: "Trimmed whitespace 2 lines."
        ),
        "Trimming should preserve the terminal newline without adding a blank line."
    )

    try expect(
        BasicTextTransforms.removeDuplicateLines("a\nb\na\n") == .success(
            text: "a\nb\n",
            summary: "Removed duplicate 1 line."
        ),
        "Deduplication should not count or drop the terminal newline."
    )

    try expect(
        BasicTextTransforms.removeEmptyLines("one\n\ntwo\n") == .success(
            text: "one\ntwo\n",
            summary: "Removed empty 1 line."
        ),
        "Removing empty lines should preserve the terminal newline."
    )

    try expect(
        BasicTextTransforms.sortLines("b\r\na\r\n") == .success(
            text: "a\r\nb\r\n",
            summary: "Sorted 2 lines."
        ),
        "Sorting should preserve dominant CRLF endings including the terminal one."
    )

    try expect(
        BasicTextTransforms.sortLines("b\ra\r") == .success(
            text: "a\rb\r",
            summary: "Sorted 2 lines."
        ),
        "Sorting should preserve dominant CR endings including the terminal one."
    )

    // Documented edge: when a transform empties the document there is no line left to terminate,
    // so the result is empty rather than a lone newline.
    try expect(
        BasicTextTransforms.trimWhitespace(" \n") == .success(
            text: "",
            summary: "Trimmed whitespace 1 line."
        ),
        "Trimming a document down to nothing should produce empty text, not a stray newline."
    )
    try expect(
        BasicTextTransforms.removeEmptyLines("\n\n") == .success(
            text: "",
            summary: "Removed empty 2 lines."
        ),
        "Removing every line should produce empty text."
    )
}

func testRegexAllowsOrdinaryConstructs() throws {
    let nonCapturing = SearchOptions(query: #"(?:cat|dog)s?"#, replacement: "pet", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "cats and dogs", options: nonCapturing)
            == .success(text: "pet and pet", replacementCount: 2),
        "Non-capturing groups should be usable in regex mode."
    )

    let quantifiedGroup = SearchOptions(query: #"(ab)+"#, replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "abab cd", options: quantifiedGroup)
            == .success(text: "x cd", replacementCount: 1),
        "A quantified plain group is ordinary regex and should be allowed."
    )

    let lookahead = SearchOptions(query: #"\d+(?=px)"#, replacement: "N", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "12px 34em", options: lookahead)
            == .success(text: "Npx 34em", replacementCount: 1),
        "Lookaheads should be allowed."
    )

    let lookbehind = SearchOptions(query: #"(?<=id=)\d+"#, replacement: "N", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "id=42", options: lookbehind)
            == .success(text: "id=N", replacementCount: 1),
        "Lookbehinds should be allowed."
    )

    let backreference = SearchOptions(query: #"(\w)\1"#, replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "aa bb", options: backreference)
            == .failure(message: RegexSearchError.patternNotSupported.localizedDescription),
        "Pattern backreferences should stay rejected."
    )

    let nestedNonCapturing = SearchOptions(query: #"(?:a+)+"#, replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "aaaa", options: nestedNonCapturing)
            == .failure(message: RegexSearchError.patternNotSupported.localizedDescription),
        "Nested quantifiers should stay rejected even inside non-capturing groups."
    )
}

func testRegexRejectsNestedQuantifiersThroughExtraGroups() throws {
    let doubleWrapped = SearchOptions(query: "((a+))+", replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "aaaa", options: doubleWrapped)
            == .failure(message: RegexSearchError.patternNotSupported.localizedDescription),
        "A nested quantifier wrapped in an extra group should still be rejected."
    )

    let openEndedInner = SearchOptions(query: "(a{2,})+", replacement: "x", usesRegex: true)
    try expect(
        SearchReplaceEngine.replaceAll(in: "aaaa", options: openEndedInner)
            == .failure(message: RegexSearchError.patternNotSupported.localizedDescription),
        "An open-ended inner repetition inside a quantified group should be rejected."
    )
}

func testRegexAllowsBoundedRepetition() throws {
    let ipPattern = SearchOptions(
        query: #"([0-9]{1,3}\.){3}[0-9]{1,3}"#,
        replacement: "IP",
        usesRegex: true
    )
    try expect(
        SearchReplaceEngine.replaceAll(in: "from 192.168.100.201 ok", options: ipPattern)
            == .success(text: "from IP ok", replacementCount: 1),
        "Bounded repetition such as an IPv4 pattern must stay usable for log inspection."
    )

    let datePattern = SearchOptions(query: #"(\d{4}-\d{2}-\d{2} ){2}"#, replacement: "D", usesRegex: true)
    guard case let .success(_, count) = SearchReplaceEngine.replaceAll(
        in: "2026-05-15 2026-05-16 done",
        options: datePattern
    ) else {
        throw SelfTestError.failed("A bounded date-group pattern should not be refused.")
    }
    try expect(count == 1, "Bounded date grouping should match once.")
}

func testAmbiguousRegexIsStoppedByDeadline() throws {
    // Alternation ambiguity is not modelled by the construct scan on purpose; the match
    // deadline is the defence. This pins that the defence still fires.
    let ambiguous = SearchOptions(query: "(a|a)+$", replacement: "x", usesRegex: true)
    let startedAt = Date()
    let result = SearchReplaceEngine.replaceAll(in: String(repeating: "a", count: 40), options: ambiguous)
    let elapsed = Date().timeIntervalSince(startedAt)

    try expect(elapsed < 1.0, "Ambiguous alternation must be stopped promptly, took \(elapsed)s.")
    if case let .failure(message) = result {
        try expect(
            message == RegexSearchError.matchingTimedOut.localizedDescription,
            "An ambiguous pattern that is allowed through should report a timeout, got: \(message)"
        )
    }
}

func testSafeShareFindingsCarryLineNumbers() throws {
    let text = """
    first dev@example.com
    second line
    third ops@example.com
    """

    let emails = SafeShare.detect(in: text).filter { $0.category == "Email" }
    try expect(emails.count == 2, "Both emails should be detected.")
    try expect(emails[0].line == 1, "The first email should be reported on line 1.")
    try expect(emails[1].line == 3, "The second email should be reported on line 3.")

    let snippets = emails.map(SafeShare.maskedSnippet(for:))
    try expect(
        snippets[0] != snippets[1],
        "Review rows for two findings of the same category must be distinguishable."
    )
    try expect(
        snippets.allSatisfy { !$0.contains("example.com") && !$0.contains("dev") },
        "Snippets must not echo any part of the value."
    )
}

func testSafeShareRejectsWideNumericColumns() throws {
    let findings = SafeShare.detect(in: "counts 1234 5678 91011 done")
        .filter { $0.category == "Phone number" }
    try expect(
        findings.isEmpty,
        "Numeric columns with segments wider than a dialable group must not match: \(findings.map(\.text))"
    )
}

func testSaveAsClearsAuthorizationRequirement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let originalURL = directory.appendingPathComponent("original.txt")
    try "on disk".write(to: originalURL, atomically: true, encoding: .utf8)

    let now = Date()
    let unauthorized = EditorDocument(
        id: UUID(),
        title: "original.txt",
        text: "buffered edit",
        fileURL: originalURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now,
        requiresFileAuthorization: true
    )
    let store = EditorStore(
        documents: [unauthorized],
        selectedDocumentID: unauthorized.id,
        sessionStore: NoopSessionStore()
    )

    // Saving back to the unauthorized path is refused, same rule as Save All.
    try expect(
        store.saveSelectedDocument() == false,
        "Saving to a path whose access was revoked should be refused."
    )
    let untouched = try String(contentsOf: originalURL, encoding: .utf8)
    try expect(untouched == "on disk", "The original file must not be overwritten.")

    // Save As to a user-picked path succeeds and resolves the authorization state.
    let rescueURL = directory.appendingPathComponent("rescued.txt")
    try expect(store.saveSelectedDocument(to: rescueURL), "Save As should rescue the buffer.")
    try expect(
        store.documents.first?.requiresFileAuthorization == false,
        "A successful save must clear the authorization requirement so Save All stops skipping the tab."
    )

    store.textBinding(for: unauthorized.id).wrappedValue = "edited again"
    let result = store.saveAllDocuments()
    try expect(result.savedCount == 1, "Save All should write the rescued tab.")
    try expect(result.skippedUnauthorizedCount == 0, "The rescued tab must not be skipped any more.")
}

func testSaveAllSkipsUnauthorizedDocuments() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("locked.txt")
    try "on disk".write(to: fileURL, atomically: true, encoding: .utf8)

    let now = Date()
    let unauthorized = EditorDocument(
        id: UUID(),
        title: "locked.txt",
        text: "buffered edit",
        fileURL: fileURL,
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now,
        requiresFileAuthorization: true
    )

    let store = EditorStore(
        documents: [unauthorized],
        selectedDocumentID: unauthorized.id,
        sessionStore: NoopSessionStore()
    )

    let result = store.saveAllDocuments()
    try expect(result.savedCount == 0, "Save All must not write a tab whose file access was revoked.")
    try expect(result.skippedUnauthorizedCount == 1, "Save All should report tabs that need reauthorization.")
    let onDiskText = try String(contentsOf: fileURL, encoding: .utf8)
    try expect(
        onDiskText == "on disk",
        "The file on disk must stay untouched when access is unresolved."
    )
    try expect(
        store.documents.first?.isDirty == true,
        "A skipped tab must keep its unsaved buffer."
    )
}

func testDiffEmptyChanged() throws {
    let lines = DiffTools.diff(base: ["old"], changed: [])
    try expect(lines.count == 1 && lines[0].kind == .removed, "All lines should be removed when changed is empty.")
}

func testIsLargeFileNotPersistedInSession() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let store = LocalSessionStore(fileURL: fileURL)

    var doc = EditorDocument.scratch(index: 1)
    doc.isLargeFile = true

    let session = EditorSession(selectedDocumentID: doc.id, documents: [doc])
    try store.saveSession(session)
    let loaded = try store.loadSession()

    try expect(loaded?.documents.first?.isLargeFile == false, "isLargeFile should not be persisted; it must default to false on decode.")
}

func testMissingBackingFileDetectedOnInit() throws {
    let now = Date()
    let missing = EditorDocument(
        id: UUID(),
        title: "gone.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/tmp/ohbee-missing-\(UUID().uuidString).txt"),
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )
    let scratch = EditorDocument.scratch(index: 1)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let presentURL = directory.appendingPathComponent("present.txt")
    try "hello".write(to: presentURL, atomically: true, encoding: .utf8)
    let present = EditorDocument(
        id: UUID(),
        title: "present.txt",
        text: "",
        fileURL: presentURL,
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )

    let store = EditorStore(
        documents: [missing, scratch, present],
        selectedDocumentID: missing.id,
        sessionStore: NoopSessionStore()
    )

    try expect(
        store.documents.first { $0.id == missing.id }?.isMissingFile == true,
        "A clean file-backed tab whose file is gone should be flagged as missing."
    )
    try expect(
        store.documents.first { $0.id == scratch.id }?.isMissingFile == false,
        "Scratch tabs should never be flagged as missing."
    )
    try expect(
        store.documents.first { $0.id == present.id }?.isMissingFile == false,
        "A file-backed tab whose file still exists should not be flagged as missing."
    )
}

func testDirtyFileBackedNotFlaggedWhenFileMissing() throws {
    let now = Date()
    let dirty = EditorDocument(
        id: UUID(),
        title: "draft.txt",
        text: "unsaved work",
        fileURL: URL(fileURLWithPath: "/tmp/ohbee-missing-\(UUID().uuidString).txt"),
        isScratch: false,
        isDirty: true,
        createdAt: now,
        updatedAt: now
    )

    let store = EditorStore(
        documents: [dirty],
        selectedDocumentID: dirty.id,
        sessionStore: NoopSessionStore()
    )

    try expect(
        store.documents.first?.isMissingFile == false,
        "A dirty file-backed tab keeps its in-session content and must not be flagged as missing."
    )
}

func testDiscardMissingDocument() throws {
    let now = Date()
    let missing = EditorDocument(
        id: UUID(),
        title: "gone.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/tmp/ohbee-missing-\(UUID().uuidString).txt"),
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )
    let scratch = EditorDocument.scratch(index: 1)
    let store = EditorStore(
        documents: [missing, scratch],
        selectedDocumentID: missing.id,
        sessionStore: NoopSessionStore()
    )
    try expect(store.documents.first { $0.id == missing.id }?.isMissingFile == true, "Setup: missing tab should be flagged.")

    store.discardMissingDocument(missing.id)
    try expect(!store.documents.contains { $0.id == missing.id }, "Discarding a missing tab should remove it.")
    try expect(store.selectedDocumentID == scratch.id, "Discarding the selected missing tab should select a remaining tab.")
    if let missingURL = missing.fileURL {
        try expect(
            !store.recentlyClosedFileURLs.contains(missingURL),
            "A missing file should not be recorded as recently closed because it cannot be reopened."
        )
    }

    let onlyMissing = EditorDocument(
        id: UUID(),
        title: "gone2.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/tmp/ohbee-missing-\(UUID().uuidString).txt"),
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )
    let soloStore = EditorStore(
        documents: [onlyMissing],
        selectedDocumentID: onlyMissing.id,
        sessionStore: NoopSessionStore()
    )
    soloStore.discardMissingDocument(onlyMissing.id)
    try expect(soloStore.documents.count == 1, "Discarding the last tab should leave one fresh note.")
    try expect(soloStore.documents.first?.isScratch == true, "The replacement tab should be a scratch note.")
    try expect(soloStore.selectedDocument != nil, "There should always be a selected document.")
}

func testEditingMissingDocumentClearsFlag() throws {
    let now = Date()
    let missing = EditorDocument(
        id: UUID(),
        title: "gone.txt",
        text: "",
        fileURL: URL(fileURLWithPath: "/tmp/ohbee-missing-\(UUID().uuidString).txt"),
        isScratch: false,
        isDirty: false,
        createdAt: now,
        updatedAt: now
    )
    let store = EditorStore(
        documents: [missing],
        selectedDocumentID: missing.id,
        sessionStore: NoopSessionStore()
    )
    try expect(store.documents.first?.isMissingFile == true, "Setup: missing tab should be flagged.")

    store.textBinding(for: missing.id).wrappedValue = "typed content"
    try expect(store.documents.first?.isMissingFile == false, "Editing a missing-file tab should clear the missing flag.")
    try expect(store.documents.first?.isDirty == true, "Editing should mark the tab dirty so it follows the unsaved-changes flow.")
}

let tests: [(String, () throws -> Void)] = [
    ("file size policy classification", testFileSizePolicyClassification),
    ("session text: clean file-backed omits text", testSessionTextForCleanFileBacked),
    ("session text: dirty file-backed within cap persists", testSessionTextForDirtyFileBackedWithinCap),
    ("session text: dirty file-backed over cap preserves text", testSessionTextForDirtyFileBackedOverCap),
    ("session text: scratch within cap persists", testSessionTextForScratchWithinCap),
    ("session text: scratch over cap preserves text", testSessionTextForScratchOverCap),
    ("session dirty state preservation", testDirtyFileBackedTextIsPreservedForSession),
    ("session round-trip strips file-backed text", testFileSizeSessionRoundTrip),
    ("large session text sidecar round-trip", testLargeSessionTextSidecarRoundTrip),
    ("isLargeFile not persisted in session", testIsLargeFileNotPersistedInSession),
    ("missing backing file detected on init", testMissingBackingFileDetectedOnInit),
    ("dirty file-backed not flagged when file missing", testDirtyFileBackedNotFlaggedWhenFileMissing),
    ("discard missing document", testDiscardMissingDocument),
    ("editing missing document clears flag", testEditingMissingDocumentClearsFlag),
    ("save and load session", testSaveAndLoadSession),
    ("missing session returns nil", testMissingSessionReturnsNil),
    ("legacy session migration", testLegacySessionMigration),
    ("trim trailing whitespace", testTrimTrailingWhitespace),
    ("trim trailing whitespace handles empty input", testTrimTrailingWhitespaceHandlesEmptyInput),
    ("line transforms", testLineTransforms),
    ("line ending preservation", testLineEndingPreservation),
    ("case transforms", testCaseTransforms),
    ("clean AI output", testCleanAIOutput),
    ("search summary and navigation", testSearchSummaryAndNavigation),
    ("search replace", testSearchReplace),
    ("regex replace", testRegexReplace),
    ("search replace edge cases", testSearchReplaceEdgeCases),
    ("search cache invalidates immediately", testSearchCacheInvalidatesImmediately),
    ("editing search match preserves selection", testEditingSearchMatchDoesNotRequestSelection),
    ("closing selected document selects search match", testClosingSelectedDocumentRequestsSearchSelection),
    ("closing background document preserves selection", testClosingBackgroundDocumentDoesNotRequestSearchSelection),
    ("discarding selected document selects search match", testDiscardingSelectedDocumentRequestsSearchSelection),
    ("close all clears search state", testCloseAllClearsSearchState),
    ("replace current selects remaining match", testReplaceCurrentRequestsSearchSelection),
    ("reauthorization preserves dirty buffer", testReauthorizationPreservesDirtyBuffer),
    ("reauthorization rejects different file", testReauthorizationRejectsDifferentFile),
    ("regex safety limits", testRegexSafetyLimits),
    ("whole-word large literal input", testWholeWordLargeLiteralInput),
    ("editor store caches search evaluation", testEditorStoreCachesSearchEvaluation),
    ("search replace large literal input", testSearchReplaceLargeLiteralInputCompletes),
    ("close tab behaviors", testCloseTabBehaviors),
    ("close other tabs and language", testCloseOtherTabsAndLanguage),
    ("recently closed files stack", testRecentlyClosedFilesStack),
    ("save all documents", testSaveAllDocuments),
    ("editor file metadata", testEditorFileMetadata),
    ("language inference and override", testLanguageInferenceAndOverride),
    ("window title", testWindowTitle),
    ("JSON tools", testJSONTools),
    ("URL tools", testURLTools),
    ("log cleanup tools", testLogCleanupTools),
    ("Safe Share", testSafeShare),
    ("debounced session save flushes once", testDebouncedSessionSaveFlushesOnce),
    ("SQL basic keywords", testSQLBasicKeywords),
    ("SQL case-insensitive keywords", testSQLCaseInsensitiveKeywords),
    ("SQL data types", testSQLDataTypes),
    ("SQL functions", testSQLFunctions),
    ("SQL strings and quoted identifiers", testSQLStringsAndQuotedIdentifiers),
    ("SQL comments", testSQLComments),
    ("SQL line comments non-Unix line endings", testSQLLineCommentsRespectNonUnixLineEndings),
    ("SQL numbers and operators", testSQLNumbersAndOperators),
    ("SQL Plain Text mode", testSQLPlainTextModeProducesNoTokens),
    ("column selection: line map single line", testLineMapSingleLine),
    ("column selection: line map multi-line", testLineMapMultiLine),
    ("column selection: line map trailing newline", testLineMapTrailingNewline),
    ("column selection: line map empty string", testLineMapEmptyString),
    ("column selection: line and column lookup", testLineAndColumn),
    ("column selection: rectangle ranges", testColumnSelectionRanges),
    ("column selection: short line clamping", testColumnSelectionShortLine),
    ("column selection: empty line in rectangle", testColumnSelectionEmptyLine),
    ("column selection: single line", testColumnSelectionSingleLine),
    ("column selection: copy rectangle", testCopyColumnRanges),
    ("column selection: copy rectangle with empty line", testCopyColumnRangesWithEmptyLine),
    ("XML format valid", testXMLFormat),
    ("XML minify valid", testXMLMinify),
    ("XML invalid reports error", testXMLInvalidReportsError),
    ("XML empty input fails", testXMLEmptyInput),
    ("XML entities rejected", testXMLRejectsEntities),
    ("image file size limits", testImageFileSizeLimits),
    ("word frequency top words", testWordFrequencyTopWords),
    ("word frequency empty input", testWordFrequencyEmptyInput),
    ("word frequency ignores short tokens", testWordFrequencyIgnoresShortTokens),
    ("diff common lines", testDiffCommonLines),
    ("diff added lines", testDiffAddedLines),
    ("diff removed lines", testDiffRemovedLines),
    ("diff annotated text", testDiffAnnotatedText),
    ("diff empty base", testDiffEmptyBase),
    ("diff empty changed", testDiffEmptyChanged),
    ("legacy store directory resolves real home", testLegacyStoreDirectoryUsesRealHome),
    ("readable session still prunes sidecars", testReadableSessionStillPrunesUnusedSidecars),
    ("unsupported session version reported", testUnsupportedSessionVersionIsReportedAsSuch),
    ("failed load moves orphan text out of prune scope", testFailedLoadMovesOrphanTextOutOfPruneScope),
    ("hidden files do not block pruning", testHiddenFilesDoNotBlockSidecarPruning),
    ("corrupt session is quarantined", testCorruptSessionIsQuarantined),
    ("corrupt session keeps sidecar text", testCorruptSessionKeepsSidecarText),
    ("corrupt session warns through store", testCorruptSessionWarnsThroughStore),
    ("safe share mask hides prefix and suffix", testSafeShareMaskHidesPrefixAndSuffix),
    ("safe share phone false positives", testSafeSharePhoneFalsePositives),
    ("safe share phone true positives", testSafeSharePhoneTruePositives),
    ("line transforms preserve terminal newline", testLineTransformsPreserveTerminalNewline),
    ("regex allows ordinary constructs", testRegexAllowsOrdinaryConstructs),
    ("regex rejects nested quantifiers through extra groups", testRegexRejectsNestedQuantifiersThroughExtraGroups),
    ("regex allows bounded repetition", testRegexAllowsBoundedRepetition),
    ("ambiguous regex stopped by deadline", testAmbiguousRegexIsStoppedByDeadline),
    ("safe share findings carry line numbers", testSafeShareFindingsCarryLineNumbers),
    ("safe share rejects wide numeric columns", testSafeShareRejectsWideNumericColumns),
    ("save as clears authorization requirement", testSaveAsClearsAuthorizationRequirement),
    ("save all skips unauthorized tabs", testSaveAllSkipsUnauthorizedDocuments)
]

do {
    for (name, test) in tests {
        try test()
        print("PASS: \(name)")
    }

    print("All self tests passed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
