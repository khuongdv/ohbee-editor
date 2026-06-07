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

    try expect(
        SearchReplaceEngine.summary(in: text, options: options, currentMatchIndex: nil) == SearchSummary(matchCount: 2, currentMatchIndex: 0),
        "Search summary should count case-insensitive matches."
    )
    try expect(
        SearchReplaceEngine.nextMatchIndex(in: text, options: options, currentMatchIndex: 0) == 1,
        "Next match should advance."
    )
    try expect(
        SearchReplaceEngine.previousMatchIndex(in: text, options: options, currentMatchIndex: 0) == 1,
        "Previous match should wrap."
    )

    let visibleOnlyRanges = SearchReplaceEngine.matchRanges(
        in: "xin before\nmiddle\nxin visible\nxin after",
        options: options,
        range: NSRange(location: 12, length: 17)
    )
    try expect(
        visibleOnlyRanges == [NSRange(location: 18, length: 3)],
        "Search range matching should only return matches inside the requested text range."
    )

    let regexRanges = SearchReplaceEngine.matchRanges(
        in: "id=100\nid=200\nid=300",
        options: SearchOptions(query: #"id=\d+"#, usesRegex: true, isCaseSensitive: true),
        range: NSRange(location: 7, length: 6)
    )
    try expect(
        regexRanges == [NSRange(location: 7, length: 6)],
        "Regex range matching should respect the requested text range."
    )
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
    try expect(
        SearchReplaceEngine.summary(in: "abc", options: invalidRegex, currentMatchIndex: nil) == SearchSummary(matchCount: 0, currentMatchIndex: nil, hasInvalidRegex: true),
        "Invalid regex search should report an invalid pattern."
    )
    try expect(
        SearchReplaceEngine.replaceAll(in: "abc", options: invalidRegex) == .failure(message: "Invalid regular expression."),
        "Invalid regex replace all should fail without mutating text."
    )
    try expect(
        SearchReplaceEngine.matchRanges(in: "abc", options: invalidRegex).isEmpty,
        "Invalid regex match lookup should return no ranges."
    )

    let wholeWord = SearchOptions(query: "cat", replacement: "dog", usesRegex: false, isCaseSensitive: false, isWholeWord: true)
    try expect(
        SearchReplaceEngine.matchRanges(in: "cat scatter cat-cat _cat cat1", options: wholeWord) == [
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
        SearchReplaceEngine.summary(in: "Xin xin XIN", options: caseSensitive, currentMatchIndex: nil) == SearchSummary(matchCount: 1, currentMatchIndex: 0),
        "Case-sensitive search should only count exact-case matches."
    )
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

func testShouldPreserveDirtyStateFileBacked() throws {
    let smallDirtyDoc = EditorDocument(
        id: UUID(), title: "file.txt", text: "small change",
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(LargeFilePolicy.shouldPreserveDirtyState(for: smallDirtyDoc), "Small dirty file-backed doc should preserve dirty state.")

    let bigText = String(repeating: "x", count: LargeFilePolicy.sessionTextCap + 1)
    let largeDirtyDoc = EditorDocument(
        id: UUID(), title: "file.txt", text: bigText,
        fileURL: URL(fileURLWithPath: "/tmp/file.txt"),
        isScratch: false, isDirty: true,
        createdAt: Date(), updatedAt: Date()
    )
    try expect(LargeFilePolicy.shouldPreserveDirtyState(for: largeDirtyDoc), "Large dirty file-backed doc should preserve dirty state through sidecar persistence.")
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

let tests: [(String, () throws -> Void)] = [
    ("file size policy classification", testFileSizePolicyClassification),
    ("session text: clean file-backed omits text", testSessionTextForCleanFileBacked),
    ("session text: dirty file-backed within cap persists", testSessionTextForDirtyFileBackedWithinCap),
    ("session text: dirty file-backed over cap preserves text", testSessionTextForDirtyFileBackedOverCap),
    ("session text: scratch within cap persists", testSessionTextForScratchWithinCap),
    ("session text: scratch over cap preserves text", testSessionTextForScratchOverCap),
    ("session dirty state preservation", testShouldPreserveDirtyStateFileBacked),
    ("session round-trip strips file-backed text", testFileSizeSessionRoundTrip),
    ("large session text sidecar round-trip", testLargeSessionTextSidecarRoundTrip),
    ("isLargeFile not persisted in session", testIsLargeFileNotPersistedInSession),
    ("save and load session", testSaveAndLoadSession),
    ("missing session returns nil", testMissingSessionReturnsNil),
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
    ("word frequency top words", testWordFrequencyTopWords),
    ("word frequency empty input", testWordFrequencyEmptyInput),
    ("word frequency ignores short tokens", testWordFrequencyIgnoresShortTokens),
    ("diff common lines", testDiffCommonLines),
    ("diff added lines", testDiffAddedLines),
    ("diff removed lines", testDiffRemovedLines),
    ("diff annotated text", testDiffAnnotatedText),
    ("diff empty base", testDiffEmptyBase),
    ("diff empty changed", testDiffEmptyChanged)
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
