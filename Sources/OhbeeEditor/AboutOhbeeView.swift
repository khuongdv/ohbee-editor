import SwiftUI
import AppKit

struct AboutOhbeeView: View {
    @Environment(\.dismiss) private var dismiss

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OhbeeLogoImage(size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ohbee Editor")
                        .font(.title2.weight(.semibold))
                    Text("A lightweight, local-first text workbench for macOS.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PrincipleRow(text: "Works fully offline. No account, no internet, no telemetry. Your text stays on your Mac.")
                PrincipleRow(text: "Built for messy, temporary, and sensitive text — the kind you wouldn't trust to a cloud app.")
                PrincipleRow(text: "Practical tools for cleanup, inspection, and safe sharing — new tools added with every update.")
                PrincipleRow(text: "Lightweight by design. Not an IDE, not an AI assistant, not a subscription.")
            }

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    Text("© \(String(currentYear)) by Ohbee Labs")
                    Text("·")
                    Text("ohbee.link")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct OhbeeLogoImage: View {
    let size: CGFloat

    var body: some View {
        if let image = Self.logoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: size * 0.54, weight: .semibold))
                .frame(width: size, height: size)
        }
    }

    private static var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private struct PrincipleRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .frame(width: 5, height: 5)
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
