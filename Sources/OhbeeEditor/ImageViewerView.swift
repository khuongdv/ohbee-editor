import SwiftUI
import AppKit
import ImageIO
import OhbeeEditorCore

struct ImageViewerView: View {
    let document: EditorDocument
    let store: EditorStore

    @State private var nsImage: NSImage?
    @State private var zoom: CGFloat = 1.0
    @State private var metadata: ImageFileMetadata?
    @State private var loadFailed = false

    var body: some View {
        HStack(spacing: 0) {
            imagePane
            Divider()
            metadataPane
                .frame(width: 228)
        }
        .onAppear(perform: load)
        .onChange(of: document.id) { _ in
            load()
        }
        .onChange(of: document.requiresFileAuthorization) { requiresAuthorization in
            guard !requiresAuthorization else { return }
            load()
        }
    }

    private var imagePane: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image = nsImage {
                VStack(spacing: 0) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: image.size.width * zoom,
                                height: image.size.height * zoom
                            )
                            .padding(20)
                    }
                    zoomControls
                }
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Unable to load image.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button {
                zoom = max(0.05, zoom / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .accessibilityLabel("Zoom Out")
            }
            .buttonStyle(.borderless)
            .help("Zoom Out")
            .keyboardShortcut("-", modifiers: .command)

            Text("\(Int(zoom * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 48, alignment: .center)

            Button {
                zoom = min(20.0, zoom * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .accessibilityLabel("Zoom In")
            }
            .buttonStyle(.borderless)
            .help("Zoom In")
            .keyboardShortcut("+", modifiers: .command)

            Button("1:1") {
                zoom = 1.0
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Actual size")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private var metadataPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("File Info")
                    .font(.headline)

                Divider()

                if let meta = metadata {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 5) {
                        metaRow("Name", meta.fileName)
                        metaRow("Type", meta.fileType)
                        metaRow("Size", ByteCountFormatter.string(fromByteCount: meta.fileSize, countStyle: .file))

                        if let created = meta.createdDate {
                            metaRow("Created", formatDate(created))
                        }

                        if let modified = meta.modifiedDate {
                            metaRow("Modified", formatDate(modified))
                        }

                        if let w = meta.pixelWidth, let h = meta.pixelHeight {
                            metaRow("Dimensions", "\(w) × \(h) px")
                        }

                        if let dpi = meta.dpiWidth {
                            metaRow("Resolution", "\(Int(dpi)) DPI")
                        }

                        if let colorSpace = meta.colorSpace {
                            metaRow("Color", colorSpace)
                        }

                        if let creator = meta.creator {
                            metaRow("Creator", creator)
                        }
                    }
                    .font(.callout)
                } else {
                    ProgressView()
                }

                Spacer()
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func load() {
        guard let url = document.fileURL else { return }
        nsImage = nil
        metadata = nil
        loadFailed = false
        store.beginFileAccessOperation(at: url)

        DispatchQueue.global(qos: .userInitiated).async {
            let img = Self.downsampledImage(from: url)
            let meta = ImageFileMetadata.load(from: url)
            DispatchQueue.main.async {
                defer { store.endFileAccessOperation(at: url) }
                guard document.fileURL == url else { return }
                if img == nil { self.loadFailed = true }
                self.nsImage = img
                self.metadata = meta
            }
        }
    }

    // Cap display image at 4096px on the longest side to avoid loading multi-hundred-MB
    // bitmaps into memory. Original pixel dimensions are preserved in ImageFileMetadata.
    // Falls back to NSImage(contentsOf:) for SVG and other formats CGImageSource can't decode.
    private static func downsampledImage(from url: URL, maxDimension: CGFloat = 4096) -> NSImage? {
        guard let byteCount = EditorFileIO.byteCount(of: url),
              byteCount <= LargeFilePolicy.maximumImageByteLimit(for: url) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        // The fallback may content-sniff vector formats regardless of extension. Never hand
        // it a file larger than the strict SVG ceiling, even if header sniffing was inconclusive.
        guard byteCount <= LargeFilePolicy.maximumSVGByteLimit else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct ImageFileMetadata {
    var fileName: String
    var fileType: String
    var fileSize: Int64
    var createdDate: Date?
    var modifiedDate: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dpiWidth: Double?
    var colorSpace: String?
    var creator: String?

    static func load(from url: URL) -> ImageFileMetadata {
        var fileSize: Int64 = 0
        var createdDate: Date?
        var modifiedDate: Date?

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            createdDate = attrs[.creationDate] as? Date
            modifiedDate = attrs[.modificationDate] as? Date
        }

        var pixelWidth: Int?
        var pixelHeight: Int?
        var dpiWidth: Double?
        var colorSpace: String?
        var creator: String?

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            pixelWidth = props[kCGImagePropertyPixelWidth as String] as? Int
            pixelHeight = props[kCGImagePropertyPixelHeight as String] as? Int
            dpiWidth = props[kCGImagePropertyDPIWidth as String] as? Double
            colorSpace = props[kCGImagePropertyColorModel as String] as? String

            if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                creator = tiff[kCGImagePropertyTIFFArtist as String] as? String
                    ?? tiff[kCGImagePropertyTIFFSoftware as String] as? String
            }
        }

        return ImageFileMetadata(
            fileName: url.lastPathComponent,
            fileType: url.pathExtension.uppercased(),
            fileSize: fileSize,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpiWidth: dpiWidth,
            colorSpace: colorSpace,
            creator: creator
        )
    }
}
