import Foundation

/// Maps line numbers to character index ranges within an NSString.
/// Built once per operation from newline scanning; O(n) construction, O(log n) lookup.
public struct LineMap {
    private let ns: NSString
    private let lineStarts: [Int]  // UTF-16 index of first character on each line

    public init(string ns: NSString) {
        self.ns = ns
        var starts = [0]
        var idx = 0
        let len = ns.length
        while idx < len {
            if ns.character(at: idx) == 10 { // '\n'
                starts.append(idx + 1)
            }
            idx += 1
        }
        lineStarts = starts
    }

    public var lineCount: Int { lineStarts.count }

    public func lineStart(_ line: Int) -> Int {
        guard line >= 0, line < lineStarts.count else { return ns.length }
        return lineStarts[line]
    }

    /// Number of characters on the line, excluding the trailing newline.
    public func lineContentLength(_ line: Int) -> Int {
        let start = lineStart(line)
        guard start < ns.length else { return 0 }
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd,
                        for: NSRange(location: start, length: 0))
        return max(0, contentsEnd - start)
    }

    public func lineAndColumn(for charIdx: Int) -> (line: Int, col: Int) {
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= charIdx { lo = mid } else { hi = mid - 1 }
        }
        return (lo, charIdx - lineStarts[lo])
    }
}

/// A rectangular text selection defined by line and character-column boundaries.
public struct ColumnSelection {
    public let startLine: Int
    public let endLine: Int
    public let startCol: Int
    public let endCol: Int

    public init(startLine: Int, endLine: Int, startCol: Int, endCol: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.startCol = startCol
        self.endCol = endCol
    }

    /// Returns one NSRange per line in the rectangle.
    /// Lines shorter than startCol get an empty range at their content end (no virtual space).
    public func ranges(in ns: NSString, lineMap: LineMap) -> [NSRange] {
        guard startLine <= endLine, startCol <= endCol else { return [] }
        return (startLine...endLine).map { line in
            let start = lineMap.lineStart(line)
            let len = lineMap.lineContentLength(line)
            let colA = min(startCol, len)
            let colB = min(endCol, len)
            return NSRange(location: start + colA, length: colB - colA)
        }
    }
}

/// Extracts text from each range and joins with newlines, preserving the rectangular shape.
public func copyColumnRanges(_ ranges: [NSRange], from ns: NSString) -> String {
    ranges.map { ns.substring(with: $0) }.joined(separator: "\n")
}
