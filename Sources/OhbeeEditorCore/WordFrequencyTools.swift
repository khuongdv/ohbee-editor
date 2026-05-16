import Foundation

public struct WordFrequencyEntry: Identifiable, Sendable {
    public var id: String { word }
    public let word: String
    public let count: Int

    public init(word: String, count: Int) {
        self.word = word
        self.count = count
    }
}

public enum WordFrequencyTools {
    private static let separators: CharacterSet = {
        var cs = CharacterSet.whitespacesAndNewlines
        cs.formUnion(.punctuationCharacters)
        cs.formUnion(.symbols)
        return cs
    }()

    public static func topWords(in text: String, limit: Int = 20) -> [WordFrequencyEntry] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var counts: [String: Int] = [:]
        text
            .components(separatedBy: separators)
            .map { $0.lowercased() }
            .filter { $0.count >= 2 }
            .forEach { counts[$0, default: 0] += 1 }

        return counts
            .sorted { lhs, rhs in
                lhs.value > rhs.value || (lhs.value == rhs.value && lhs.key < rhs.key)
            }
            .prefix(limit)
            .map { WordFrequencyEntry(word: $0.key, count: $0.value) }
    }
}
