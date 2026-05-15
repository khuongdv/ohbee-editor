import Foundation

public enum SQLTokenKind: Equatable {
    case keyword
    case function
    case type
    case string
    case number
    case comment
    case operatorToken
    case identifier
    case punctuation
}

public struct SQLSyntaxToken: Equatable {
    public let kind: SQLTokenKind
    public let range: NSRange
    public let text: String
}

public enum SQLSyntaxTokenizer {
    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "DATABASE", "SCHEMA",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "UNIQUE", "CHECK", "DEFAULT",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", "USING",
        "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "DISTINCT",
        "UNION", "ALL", "EXCEPT", "INTERSECT",
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "AS", "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "ILIKE", "BETWEEN", "EXISTS",
        "TRUE", "FALSE",
        "WITH", "RECURSIVE",
        "RETURNING",
        "BEGIN", "COMMIT", "ROLLBACK",
        "GRANT", "REVOKE",
        "AUTO_INCREMENT", "UNSIGNED", "ENGINE", "CHARSET", "AUTOINCREMENT"
    ]

    private static let types: Set<String> = [
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT",
        "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
        "BOOLEAN", "BOOL",
        "CHAR", "VARCHAR", "TEXT", "UUID",
        "DATE", "TIME", "TIMESTAMP", "DATETIME",
        "JSON", "JSONB",
        "BLOB", "BYTEA",
        "SERIAL", "BIGSERIAL"
    ]

    private static let functions: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "NULLIF",
        "LOWER", "UPPER", "LENGTH", "SUBSTRING", "TRIM",
        "NOW", "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP",
        "DATE_TRUNC",
        "CAST", "CONVERT",
        "ROUND", "ABS",
        "ROW_NUMBER", "RANK", "DENSE_RANK",
        "JSON_EXTRACT", "JSON_VALUE"
    ]

    public static func tokens(in text: String, language: EditorLanguage = .sql) -> [SQLSyntaxToken] {
        guard language == .sql else {
            return []
        }

        var tokens: [SQLSyntaxToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }

            if text[index] == "-", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex, text[next] == "-" {
                let start = index
                index = text.index(after: next)
                while index < text.endIndex, text[index] != "\n" {
                    index = text.index(after: index)
                }
                tokens.append(token(.comment, from: start, to: index, in: text))
                continue
            }

            if text[index] == "/", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex, text[next] == "*" {
                let start = index
                index = text.index(after: next)
                while index < text.endIndex {
                    let nextIndex = text.index(after: index)
                    if text[index] == "*", nextIndex < text.endIndex, text[nextIndex] == "/" {
                        index = text.index(after: nextIndex)
                        break
                    }
                    index = nextIndex
                }
                tokens.append(token(.comment, from: start, to: index, in: text))
                continue
            }

            if text[index] == "'" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex {
                    let nextIndex = text.index(after: index)
                    if text[index] == "'" {
                        if nextIndex < text.endIndex, text[nextIndex] == "'" {
                            index = text.index(after: nextIndex)
                            continue
                        }
                        index = nextIndex
                        break
                    }
                    index = nextIndex
                }
                tokens.append(token(.string, from: start, to: index, in: text))
                continue
            }

            if text[index] == "\"" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex {
                    let nextIndex = text.index(after: index)
                    if text[index] == "\"" {
                        if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                            index = text.index(after: nextIndex)
                            continue
                        }
                        index = nextIndex
                        break
                    }
                    index = nextIndex
                }
                tokens.append(token(.identifier, from: start, to: index, in: text))
                continue
            }

            if text[index] == "$", let dollarStringEnd = dollarQuotedStringEnd(from: index, in: text) {
                let start = index
                index = dollarStringEnd
                tokens.append(token(.string, from: start, to: index, in: text))
                continue
            }

            if isNumberStart(at: index, in: text) {
                let start = index
                if text[index] == "-" {
                    index = text.index(after: index)
                }
                while index < text.endIndex, text[index].isNumber || text[index] == "_" {
                    index = text.index(after: index)
                }
                if index < text.endIndex, text[index] == "." {
                    let decimalStart = index
                    let afterDecimal = text.index(after: decimalStart)
                    if afterDecimal < text.endIndex, text[afterDecimal].isNumber {
                        index = afterDecimal
                        while index < text.endIndex, text[index].isNumber || text[index] == "_" {
                            index = text.index(after: index)
                        }
                    }
                }
                tokens.append(token(.number, from: start, to: index, in: text))
                continue
            }

            if let operatorEnd = operatorEnd(from: index, in: text) {
                let start = index
                index = operatorEnd
                tokens.append(token(.operatorToken, from: start, to: index, in: text))
                continue
            }

            if ",;().".contains(text[index]) {
                let start = index
                index = text.index(after: index)
                tokens.append(token(.punctuation, from: start, to: index, in: text))
                continue
            }

            if isIdentifierStart(text[index]) {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isIdentifierPart(text[index]) {
                    index = text.index(after: index)
                }

                let value = String(text[start..<index]).uppercased()
                if keywords.contains(value) {
                    tokens.append(token(.keyword, from: start, to: index, in: text))
                } else if types.contains(value) {
                    tokens.append(token(.type, from: start, to: index, in: text))
                } else if functions.contains(value) {
                    tokens.append(token(.function, from: start, to: index, in: text))
                }
                continue
            }

            index = text.index(after: index)
        }

        return tokens
    }

    private static func token(_ kind: SQLTokenKind, from start: String.Index, to end: String.Index, in text: String) -> SQLSyntaxToken {
        SQLSyntaxToken(
            kind: kind,
            range: NSRange(start..<end, in: text),
            text: String(text[start..<end])
        )
    }

    private static func isNumberStart(at index: String.Index, in text: String) -> Bool {
        if text[index].isNumber {
            return true
        }

        guard text[index] == "-", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex, text[next].isNumber else {
            return false
        }

        if index == text.startIndex {
            return true
        }

        let previous = text[text.index(before: index)]
        return previous.isWhitespace || "(=<>!,+-*/%".contains(previous)
    }

    private static func operatorEnd(from index: String.Index, in text: String) -> String.Index? {
        let next = text.index(after: index)
        if next < text.endIndex {
            let pair = String(text[index...next])
            if ["<>", "!=", "<=", ">=", "||"].contains(pair) {
                return text.index(after: next)
            }
        }

        return "=<>+-*/%".contains(text[index]) ? next : nil
    }

    private static func dollarQuotedStringEnd(from index: String.Index, in text: String) -> String.Index? {
        var tagEnd = text.index(after: index)
        while tagEnd < text.endIndex, isIdentifierPart(text[tagEnd]) {
            tagEnd = text.index(after: tagEnd)
        }

        guard tagEnd < text.endIndex, text[tagEnd] == "$" else {
            return nil
        }

        let delimiter = String(text[index...tagEnd])
        let searchStart = text.index(after: tagEnd)
        guard let closingRange = text.range(of: delimiter, range: searchStart..<text.endIndex) else {
            return nil
        }

        return closingRange.upperBound
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierPart(_ character: Character) -> Bool {
        character == "_" || character == "$" || character.isLetter || character.isNumber
    }
}
