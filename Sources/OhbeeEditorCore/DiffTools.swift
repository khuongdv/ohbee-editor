import Foundation

public enum DiffTools {
    public enum LineKind {
        case common, added, removed
    }

    public struct DiffLine {
        public let kind: LineKind
        public let text: String

        public init(kind: LineKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    // LCS-based line diff. O(nm) — DP table capped at 10M cells (~80 MB) to prevent OOM.
    public static let maxDiffCells = 10_000_000

    public static func diff(base: [String], changed: [String]) -> [DiffLine] {
        let m = base.count
        let n = changed.count

        guard m > 0 else { return changed.map { DiffLine(kind: .added, text: $0) } }
        guard n > 0 else { return base.map { DiffLine(kind: .removed, text: $0) } }

        guard m * n <= maxDiffCells else {
            return base.map { DiffLine(kind: .removed, text: $0) }
                 + changed.map { DiffLine(kind: .added, text: $0) }
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = base[i - 1] == changed[j - 1]
                    ? dp[i - 1][j - 1] + 1
                    : max(dp[i - 1][j], dp[i][j - 1])
            }
        }

        var result: [DiffLine] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && base[i - 1] == changed[j - 1] {
                result.append(DiffLine(kind: .common, text: base[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(DiffLine(kind: .added, text: changed[j - 1]))
                j -= 1
            } else {
                result.append(DiffLine(kind: .removed, text: base[i - 1]))
                i -= 1
            }
        }
        result.reverse()
        return result
    }

    public static func annotatedText(baseTitle: String, changedTitle: String, base: String, changed: String) -> String {
        let baseLines = base.components(separatedBy: "\n")
        let changedLines = changed.components(separatedBy: "\n")
        let header = "--- \(baseTitle)\n+++ \(changedTitle)"

        guard baseLines.count * changedLines.count <= maxDiffCells else {
            return header + "\n\n[Diff unavailable: \(baseLines.count) × \(changedLines.count) lines exceeds the LCS limit.]"
        }

        let lines = diff(base: baseLines, changed: changedLines)
        let body = lines.map { line -> String in
            switch line.kind {
            case .common:  return "  \(line.text)"
            case .added:   return "+ \(line.text)"
            case .removed: return "- \(line.text)"
            }
        }.joined(separator: "\n")

        return header + "\n\n" + body
    }
}
