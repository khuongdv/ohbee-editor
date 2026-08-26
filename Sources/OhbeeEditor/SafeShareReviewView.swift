import AppKit
import SwiftUI
import OhbeeEditorCore

struct SafeShareReviewView: View {
    let review: SafeShareReview
    let onApplyMask: (String) -> Void
    let onCancel: () -> Void

    @State private var selectedFindingIndexes: Set<Int> = []
    @State private var copiedMaskedText = false
    @State private var copyStatusText = ""
    @State private var copyFeedbackID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if review.hasFindings {
                categoryStrip
                findingList
                maskedPreview
            } else {
                emptyState
            }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)

                Button("Copy Summary") {
                    copySummary()
                }
                .help("Copies only category counts, not sensitive values.")
                .disabled(!review.hasFindings)

                Button("Copy Masked") {
                    copyMaskedText()
                }
                .help("Copies the masked preview to the pasteboard without changing the document.")
                .disabled(selectedFindingIndexes.isEmpty)

                Button("Apply Mask") {
                    onApplyMask(currentMaskedText)
                }
                .help("Replaces the reviewed text with the masked preview. This is undoable in the editor.")
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFindingIndexes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 360)
        .onAppear {
            selectedFindingIndexes = Set(review.findings.indices)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: review.hasFindings ? "exclamationmark.shield" : "checkmark.shield")
                    .foregroundStyle(review.hasFindings ? .orange : .green)

                Text(review.hasFindings ? "Potential sensitive text found." : "No obvious sensitive patterns found.")
                    .font(.headline)
            }

            Text(review.hasFindings
                ? "\(review.findings.count) item(s) found in the current selection or document. \(selectedFindingIndexes.count) selected for masking."
                : "Safe Share is best-effort and conservative; it does not guarantee complete secret detection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryStrip: some View {
        HStack(spacing: 8) {
            ForEach(review.categorySummaries) { summary in
                Label("\(summary.category): \(summary.count)", systemImage: "tag")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()
        }
    }

    private var findingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Findings")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(review.findings.enumerated()), id: \.offset) { index, finding in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Toggle("", isOn: bindingForFinding(at: index))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                            Text(finding.category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 130, alignment: .leading)
                                .help("Finding on line \(finding.line)")

                            Text(SafeShare.maskedSnippet(for: finding))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: 120)
        }
    }

    private var maskedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Masked Preview")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if copiedMaskedText {
                    Text(copyStatusText)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("Copy Masked uses the local pasteboard only and leaves the document unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(currentMaskedText.isEmpty ? " " : currentMaskedText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 110)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safe Share checks the text locally for likely emails, phone numbers, tokens, API keys, JWT-like strings, and secret-looking key/value pairs.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Nothing is sent outside this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copyMaskedText() {
        copyToPasteboard(currentMaskedText)
        showCopyFeedback("Copied masked text. Document unchanged.")
    }

    private func copySummary() {
        copyToPasteboard(review.copyableFindingsSummary)
        showCopyFeedback("Copied findings summary. No sensitive values copied.")
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showCopyFeedback(_ message: String) {
        let feedbackID = UUID()
        copyFeedbackID = feedbackID
        copyStatusText = message
        copiedMaskedText = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard copyFeedbackID == feedbackID else {
                return
            }

            copiedMaskedText = false
            copyStatusText = ""
        }
    }

    private var currentMaskedText: String {
        review.maskedText(includingFindingIndexes: selectedFindingIndexes)
    }

    private func bindingForFinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: { selectedFindingIndexes.contains(index) },
            set: { isSelected in
                if isSelected {
                    selectedFindingIndexes.insert(index)
                } else {
                    selectedFindingIndexes.remove(index)
                }
            }
        )
    }
}
