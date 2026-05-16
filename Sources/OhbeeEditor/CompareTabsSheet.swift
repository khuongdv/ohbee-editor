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
        // Caller guarantees documents.count >= 2 before presenting this sheet.
        let first = documents[0].id
        let second = documents[1].id
        self._baseID = State(initialValue: first)
        self._changedID = State(initialValue: second)
    }

    private var sameTab: Bool { baseID == changedID }

    var body: some View {
        VStack(spacing: 20) {
            Text("Compare Tabs")
                .font(.headline)

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

            if sameTab {
                Text("Select two different tabs to compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    onCompare(baseID, changedID)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sameTab)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
