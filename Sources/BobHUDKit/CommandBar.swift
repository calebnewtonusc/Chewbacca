import AppKit
import SwiftUI

/// The typed front door.
///
/// Spotlight-shaped, because that muscle memory is already installed on every
/// Mac and inventing a new shape for the same gesture is a cost with no return.
///
/// It holds no model and no network. Pressing return emits the same `h` event
/// that speaking does, so whatever is listening on the socket handles both the
/// same way and there is exactly one path from "a person asked for something" to
/// "something is drawn". A second path would drift.
///
/// The strictest thing here is what it does *not* do: it never takes focus from
/// the app underneath until the person actually summons it, and it never blocks
/// that app's main thread. A command bar that drops a keystroke is not
/// forgivable, because the keystroke it drops is the first one.
@MainActor
public final class CommandBarWindow: NSPanel {
    private let onSubmit: (String) -> Void
    private let onDismiss: () -> Void

    public init(
        onSubmit: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 78),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        contentView = NSHostingView(
            rootView: CommandBarView(
                onSubmit: { [weak self] text in
                    self?.onSubmit(text)
                    self?.dismiss()
                },
                onEscape: { [weak self] in self?.dismiss() }))
    }

    /// It must become key, or nothing can be typed into it. That is the whole
    /// difference between this panel and the glass, which must never become key.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func present() {
        centerOnActiveScreen()
        makeKeyAndOrderFront(nil)
        // Activating is what puts the caret in the field. The overlay never does
        // this and this always does, which is the honest trade for a surface you
        // deliberately summoned.
        NSApp.activate(ignoringOtherApps: true)
    }

    public func dismiss() {
        orderOut(nil)
        onDismiss()
    }

    /// A third of the way down rather than the middle.
    ///
    /// Centring vertically puts an input box over whatever you were reading. A
    /// third down is where every launcher on this platform has settled, and it
    /// is above the line of most people's working content.
    private func centerOnActiveScreen() {
        // The screen the pointer is on, like everything else here. A front door
        // that opens on the other monitor is a front door people stop using.
        guard let screen = OverlayWindow.active else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - visible.height / 3 - size.height / 2))
    }
}

/// What the bar looks like, and the one thing it shows before you type.
struct CommandBarView: View {
    let onSubmit: (String) -> Void
    let onEscape: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The context receipt.
            //
            // The one element here that is not an input, and the reason the bar
            // is worth having over a terminal: it says what the assistant can
            // already see. A person learns from this, without being told, that
            // they do not have to explain themselves, and that is the single
            // most expensive habit to have to teach.
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.system(size: 8.5))
                Text(receipt)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HUD.faint)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            TextField("", text: $text, prompt: Text("Ask for something").foregroundStyle(HUD.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(HUD.ink)
                .focused($focused)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .onSubmit {
                    let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !asked.isEmpty else { return }
                    text = ""
                    onSubmit(asked)
                }
        }
        .background {
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow)
                Color.black.opacity(0.5)
                RadialGradient(
                    colors: [.white.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.08, y: -0.2),
                    startRadius: 0, endRadius: 420)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
        .onExitCommand { onEscape() }
    }

    /// What is in front of the person, without asking for a permission.
    ///
    /// `NSWorkspace` gives the frontmost application to anyone, with no
    /// Accessibility grant and no prompt. Window titles and selections need one,
    /// so they are not read here: a front door that triggers a permission dialog
    /// the first time you open it is a front door people close.
    private var receipt: String {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        guard let app, app != "Bob HUD" else { return "your screen" }
        return app
    }
}
