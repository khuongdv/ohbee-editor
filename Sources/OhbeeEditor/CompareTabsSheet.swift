import SwiftUI
import OhbeeEditorCore

struct CompareTabsSheet: View {
    let documents: [EditorDocument]
    @Binding var isPresented: Bool
    let onCompare: (EditorDocument.ID, EditorDocument.ID) -> Void

    @State private var baseID: EditorDocument.ID
    @State private var changedID: EditorDocument.ID

    init(
        documents: [EditorDocument],
        isPresented: Binding<Bool>,
        onCompare: @escaping (EditorDocument.ID, EditorDocument.ID) -> Void
    ) {
        self.documents = documents
        self._isPresented = isPresented
        self.onCompare = onCompare
        let first = documents.first?.id ?? EditorDocument.ID()
        let second = documents.dropFirst().first?.id ?? first
        self._baseID = State(initialValue: first)
        self._changedID = State(initialValue: second)
    }

    private var sameTab: Bool { baseID == changedID }
    private var canCompare: Bool {
        documents.count >= 2
            && documents.contains { $0.id == baseID }
            && documents.contains { $0.id == changedID }
            && !sameTab
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Compare Tabs")
                .font(.headline)

            if documents.count < 2 {
                Text("Open at least two tabs to compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Base (−):")
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: $baseID) {
                            ForEach(documents) { doc in
                                Text(doc.title).tag(doc.id)
                            }
                        }
                        .frame(width: 200)
                    }
                    GridRow {
                        Text("Changed (+):")
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: $changedID) {
                            ForEach(documents) { doc in
                                Text(doc.title).tag(doc.id)
                            }
                        }
                        .frame(width: 200)
                    }
                }
            }

            if documents.count >= 2 && sameTab {
                Text("Select two different tabs to compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    guard canCompare else { return }
                    onCompare(baseID, changedID)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCompare)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
