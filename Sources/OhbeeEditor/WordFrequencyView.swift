import SwiftUI
import OhbeeEditorCore

struct WordFrequencyView: View {
    let entries: [WordFrequencyEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Word Frequency")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            if entries.isEmpty {
                Text("No words found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Word")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Count")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        ForEach(entries) { entry in
                            GridRow {
                                Text(entry.word)
                                    .font(.system(.caption, design: .monospaced))
                                Text("\(entry.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 220)
    }
}
