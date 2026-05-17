import Foundation

public enum EditorLanguage: String, CaseIterable, Codable, Equatable, Identifiable {
    case plainText
    case c
    case java
    case javascript
    case json
    case html
    case xml
    case cSharp
    case cPlusPlus
    case sql
    case yaml
    case markdown
    case swift
    case python
    case shell
    case css

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .plainText:
            return "Plain Text"
        case .c:
            return "C"
        case .java:
            return "Java"
        case .javascript:
            return "JavaScript"
        case .json:
            return "JSON"
        case .html:
            return "HTML"
        case .xml:
            return "XML"
        case .cSharp:
            return "C#"
        case .cPlusPlus:
            return "C++"
        case .sql:
            return "SQL"
        case .yaml:
            return "YAML"
        case .markdown:
            return "Markdown"
        case .swift:
            return "Swift"
        case .python:
            return "Python"
        case .shell:
            return "Shell"
        case .css:
            return "CSS"
        }
    }

    public static func inferred(from fileURL: URL?) -> EditorLanguage {
        guard let ext = fileURL?.pathExtension.lowercased(), !ext.isEmpty else {
            return .plainText
        }

        switch ext {
        case "java":
            return .java
        case "js", "mjs", "cjs":
            return .javascript
        case "json", "jsonl":
            return .json
        case "html", "htm":
            return .html
        case "xml":
            return .xml
        case "cs":
            return .cSharp
        case "c", "h":
            return .c
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx":
            return .cPlusPlus
        case "sql":
            return .sql
        case "yaml", "yml":
            return .yaml
        case "md", "markdown":
            return .markdown
        case "swift":
            return .swift
        case "py":
            return .python
        case "sh", "bash", "zsh":
            return .shell
        case "css":
            return .css
        default:
            return .plainText
        }
    }
}
