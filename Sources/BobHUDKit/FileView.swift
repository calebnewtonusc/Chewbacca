import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A file, on the glass.
///
/// "Let's work on my resume, the PDF is in my downloads" should put the resume
/// on screen. Every generative UI system renders to HTML, so showing a real
/// document means converting it, losing its layout, or embedding a viewer in a
/// browser that then cannot float over anything. Rendering natively means the
/// system's own PDF and image machinery does the work and the result is the
/// document, not a picture of one.
///
/// Three shapes cover almost everything a person points at: a paged document, an
/// image, and text. Anything unrecognised is offered as its own metadata rather
/// than as a broken preview, because a wrong preview is worse than none.
struct FileView: View {
    let path: String
    let editable: Bool
    let page: Int
    /// Called with the new contents when the person saves a text file.
    let onSave: (String) -> Void

    /// A ceiling on what will be read into memory.
    ///
    /// The HUD is a panel on somebody's screen, not a file viewer, and reading a
    /// four hundred megabyte log into a String to show forty lines of it would
    /// stall the display for everything else on the glass.
    private static let maxBytes = 8 * 1024 * 1024

    private var url: URL {
        // `~` expansion only. No path construction, no resolution against a
        // base directory: the panel opens exactly the file it was handed.
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Read once, not on every redraw.
    ///
    /// `kind` used to be a computed property called from `body`, which meant
    /// every render hit the disk, decoded the file, and for an image built an
    /// `NSImage` again. A surface redraws whenever anything on it changes, and
    /// a panel holding a live metric next to a document would have re-read that
    /// document several times a second.
    @State private var loaded: Kind?
    @State private var loadedFrom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            content
        }
        .task(id: path) {
            // Keyed on the path, so pointing the same component at a different
            // file reloads and pointing it at the same one does not.
            guard loadedFrom != path || loaded == nil else { return }
            let read = kind
            loaded = read
            loadedFrom = path
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(HUD.accent)
            Text(url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.3)
                .foregroundStyle(HUD.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loaded ?? .loading {
        case .loading:
            Color.clear.frame(height: 1)

        case .missing:
            Label("Not on disk", systemImage: "questionmark.folder")
                .font(.system(size: 11))
                .foregroundStyle(HUD.faint)

        case .tooBig(let bytes):
            Text("\(bytes / 1_048_576) MB, too large to show")
                .font(.system(size: 11))
                .foregroundStyle(HUD.faint)

        case .pdf:
            PDFPane(url: url, page: page)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .text(let body):
            TextPane(text: body, editable: editable, onSave: onSave)

        case .opaque(let type):
            Text(type)
                .font(.system(size: 11))
                .foregroundStyle(HUD.faint)
        }
    }

    private enum Kind {
        /// Before the first read finishes. A blank moment beats a flash of
        /// "not on disk" for a file that is there.
        case loading
        case missing
        case tooBig(Int)
        case pdf
        case image(NSImage)
        case text(String)
        case opaque(String)
    }

    private var kind: Kind {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return .missing }
        let size = (try? manager.attributesOfItem(atPath: url.path))
            .flatMap { $0[.size] as? Int } ?? 0
        if size > Self.maxBytes { return .tooBig(size) }

        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true { return .pdf }
        if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url) {
            return .image(image)
        }
        // Decode as text last and by *trying*, not by extension. A file with no
        // extension is usually text and a list of known extensions is a list
        // that is always missing one.
        if let body = try? String(contentsOf: url, encoding: .utf8) {
            return .text(body)
        }
        return .opaque(type?.localizedDescription ?? "Not text")
    }

    private var icon: String {
        switch loaded ?? .loading {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .text: return editable ? "square.and.pencil" : "doc.plaintext"
        case .missing: return "questionmark.folder"
        case .loading: return "doc"
        default: return "doc"
        }
    }
}

/// Text, read-only or editable.
///
/// Editing writes back to the same path on save and nowhere else. That is a real
/// capability and it is bounded on purpose: the panel can only ever overwrite
/// the file it was told to display, and only when somebody typed in it and
/// pressed save.
private struct TextPane: View {
    let text: String
    let editable: Bool
    let onSave: (String) -> Void

    @State private var draft: String = ""
    @State private var loaded = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editable {
                TextEditor(text: $draft)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(HUD.ink)
                    .scrollContentBackground(.hidden)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                    .frame(height: 300)
                HStack(spacing: 8) {
                    Button("Save") {
                        onSave(draft)
                        saved = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(HUD.accent)
                    if saved {
                        Text("saved")
                            .font(.system(size: 10))
                            .foregroundStyle(HUD.good)
                    }
                    if draft != text && !saved {
                        Text("edited")
                            .font(.system(size: 10))
                            .foregroundStyle(HUD.warn)
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(HUD.ink.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 340)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = text
            loaded = true
        }
        .onChange(of: draft) { _, _ in saved = false }
    }
}

/// A real PDF, drawn by PDFKit.
private struct PDFPane: NSViewRepresentable {
    let url: URL
    let page: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        // No page shadows: they are drawn for a white app window and read as
        // grime on a dark translucent panel.
        view.pageShadowsEnabled = false
        view.document = PDFDocument(url: url)
        goTo(page, in: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        goTo(page, in: view)
    }

    private func goTo(_ number: Int, in view: PDFView) {
        guard number > 1, let document = view.document,
              let target = document.page(at: min(number, document.pageCount) - 1)
        else { return }
        view.go(to: target)
    }
}
