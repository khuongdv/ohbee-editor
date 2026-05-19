import SwiftUI

struct OhbeeHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                OhbeeLogoImage(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ohbee Editor Help")
                        .font(.title2.weight(.semibold))
                    Text("Quick reference for keyboard shortcuts and gestures.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HelpSection(title: "Keyboard Shortcuts") {
                        HelpRow("New Note",               shortcut: "⌘N")
                        HelpRow("Open File",              shortcut: "⌘O")
                        HelpRow("Save",                   shortcut: "⌘S")
                        HelpRow("Save As",                shortcut: "⌘⇧S")
                        HelpRow("Close Tab",              shortcut: "⌘W")
                        HelpRow("Find",                   shortcut: "⌘F")
                        HelpRow("Find & Replace",         shortcut: "⌘⌥F")
                        HelpRow("Format JSON",            shortcut: "⌘⇧J")
                        HelpRow("Minify JSON",            shortcut: "⌘⇧M")
                        HelpRow("Clean AI Output",        shortcut: "⌘⇧K")
                        HelpRow("Review Safe Share",      shortcut: "⌘⇧R")
                        HelpRow("Duplicate Line",         shortcut: "⌘⇧D")
                        HelpRow("Move Line Up",           shortcut: "⌥↑")
                        HelpRow("Move Line Down",         shortcut: "⌥↓")
                        HelpRow("Increase Font Size",     shortcut: "⌘+")
                        HelpRow("Decrease Font Size",     shortcut: "⌘−")
                        HelpRow("Reset Font Size",        shortcut: "⌘0")
                    }

                    HelpSection(title: "Gestures") {
                        HelpRow("Vertical Selection",        shortcut: "⌥ Drag")
                        HelpRow("Exit Vertical Selection",   shortcut: "Escape")
                    }

                    HelpSection(title: "Notable Tools") {
                        HelpDetail(
                            name: "Clean AI Output  ⌘⇧K",
                            detail: "Strips surrounding Markdown code fences, collapses excess blank lines, trims trailing spaces, and normalizes line endings. Paste from ChatGPT or Claude, then run this."
                        )
                        HelpDetail(
                            name: "Review Safe Share  ⌘⇧R",
                            detail: "Reviews API keys, tokens, emails, phone numbers, and .env-style secrets before you share. Detection is local and conservative; it flags likely candidates, not a guarantee."
                        )
                        HelpDetail(
                            name: "Vertical Selection  ⌥ Drag",
                            detail: "Hold Option and drag to select a rectangular block across multiple lines. Copy, cut, or delete the column. Press Escape to exit."
                        )
                    }

                    HelpSection(title: "Tips") {
                        HelpTip("All tools run locally. No internet connection is needed.")
                        HelpTip("Text cleanup tools are available under the **Text Tools** menu.")
                        HelpTip("Change syntax highlighting via **View → Language**.")
                        HelpTip("Toggle line numbers via **View → Show Line Numbers**.")
                        HelpTip("Document stats (lines, words, characters) appear in the status bar **(i)** button.")
                        HelpTip("SHA-256 and MD5 hashes are available under the **Hash** status bar menu.")
                    }
                }
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.top, 12)
                .padding(.bottom, 14)

            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            content
        }
    }
}

private struct HelpRow: View {
    let label: String
    let shortcut: String

    init(_ label: String, shortcut: String) {
        self.label = label
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(shortcut)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
        }
    }
}

private struct HelpDetail: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

private struct HelpTip: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
