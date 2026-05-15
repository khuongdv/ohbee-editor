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
}

func testRegexReplace() throws {
    let options = SearchOptions(query: #"\d+"#, replacement: "#", usesRegex: true, isCaseSensitive: true)

    try expect(
        SearchReplaceEngine.replaceAll(in: "a1 b22", options: options) == .success(text: "a# b#", replacementCount: 2),
        "Regex replace all should use NSRegularExpression templates."
    )
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

    try expect(
        SafeShare.detect(in: "Meet me at 10:30 for lunch. Nothing secret here.").isEmpty,
        "Safe Share should avoid obvious normal-text false positives."
    )

    try expect(
        SafeShare.detect(in: #"{"APIKey": "short"}"#).isEmpty,
        "Safe Share should avoid short JSON API-key-looking placeholders."
    )
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

let tests: [(String, () throws -> Void)] = [
    ("save and load session", testSaveAndLoadSession),
    ("missing session returns nil", testMissingSessionReturnsNil),
    ("trim trailing whitespace", testTrimTrailingWhitespace),
    ("trim trailing whitespace handles empty input", testTrimTrailingWhitespaceHandlesEmptyInput),
    ("line transforms", testLineTransforms),
    ("case transforms", testCaseTransforms),
    ("clean AI output", testCleanAIOutput),
    ("search summary and navigation", testSearchSummaryAndNavigation),
    ("search replace", testSearchReplace),
    ("regex replace", testRegexReplace),
    ("close tab behaviors", testCloseTabBehaviors),
    ("close other tabs and language", testCloseOtherTabsAndLanguage),
    ("language inference and override", testLanguageInferenceAndOverride),
    ("window title", testWindowTitle),
    ("JSON tools", testJSONTools),
    ("URL tools", testURLTools),
    ("Safe Share", testSafeShare),
    ("SQL basic keywords", testSQLBasicKeywords),
    ("SQL case-insensitive keywords", testSQLCaseInsensitiveKeywords),
    ("SQL data types", testSQLDataTypes),
    ("SQL functions", testSQLFunctions),
    ("SQL strings and quoted identifiers", testSQLStringsAndQuotedIdentifiers),
    ("SQL comments", testSQLComments),
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
    ("column selection: copy rectangle with empty line", testCopyColumnRangesWithEmptyLine)
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
