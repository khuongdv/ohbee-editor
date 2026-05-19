import AppKit
import SwiftUI
import OhbeeEditorCore

struct SafeShareReviewView: View {
    let review: SafeShareReview
    let onApplyMask: () -> Void
    let onCancel: () -> Void

    @State private var copiedMaskedText = false
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

                Button("Copy Masked") {
                    copyMaskedText()
                }
                .disabled(!review.hasFindings)

                Button("Apply Mask") {
                    onApplyMask()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!review.hasFindings)
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 360)
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
                ? "\(review.findings.count) item(s) found in the current selection or document."
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
                    ForEach(Array(review.findings.enumerated()), id: \.offset) { _, finding in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(finding.category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 130, alignment: .leading)

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
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            ScrollView {
                Text(review.maskedText.isEmpty ? " " : review.maskedText)
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(review.maskedText, forType: .string)

        let feedbackID = UUID()
        copyFeedbackID = feedbackID
        copiedMaskedText = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard copyFeedbackID == feedbackID else {
                return
            }

            copiedMaskedText = false
        }
    }
}
