import AppKit
import SwiftUI

/// One transparent window covering the whole screen, that you can click through.
///
/// The first version made a window per surface. That is wrong for a heads-up
/// display: windows fight each other for stacking, each one has a shadow and an
/// edge, and putting a second one anywhere means asking the window server for
/// permission. A HUD is not a set of windows. It is a layer of glass over
/// everything you were already doing, with things drawn on it.
///
/// So: one borderless transparent panel the size of the screen, never key, never
/// in the Dock, and **click-through everywhere except on the surfaces
/// themselves**. That last part is what makes it usable rather than a nuisance.
/// You keep working underneath it and only interact with the glass where there
/// is actually something drawn.
@MainActor
public final class OverlayWindow: NSPanel {
    public init(content: some View) {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        // No shadow: the window is the whole screen, so a shadow would be a dark
        // border around the display.
        hasShadow = false
        hidesOnDeactivate = false
        // Ignore everything by default.
        //
        // Returning nil from `hitTest` passes *clicks* through, but scroll wheel
        // events are routed at the window level and never reach view hit
        // testing, so the glass silently ate every scroll on the screen. The only
        // reliable fix is for the window to not accept mouse events at all, and
        // to flip that off for the moments the pointer is genuinely over a
        // surface. `updateInteractive(at:)` does the flipping.
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        // Keep the glass out of screen captures where that is still possible.
        //
        // This is honored by the older CGWindowList and `screencapture` paths
        // and is no longer reliably honored by ScreenCaptureKit-based capture,
        // which is most of what people actually share with. So it is worth
        // setting and it is not a guarantee, and the guarantee has to come from
        // the person hiding the layer themselves. Option-Command-Space does
        // that, and it is in the menu.
        sharingType = .none
        acceptsMouseMovedEvents = true

        contentView = PassThroughHostingView(rootView: AnyView(content))
        setFrame(frame, display: false)
    }

    /// The panel may become key, but only when a control actually needs it.
    ///
    /// This looks like it contradicts "never steals focus" and does not, because
    /// `.nonactivatingPanel` is what governs that: clicking the glass never
    /// activates the *application*, so the app you were in stays frontmost and
    /// your caret stays where it was. What `canBecomeKey` governs is whether a
    /// control inside can respond at all, and with it false every button
    /// highlighted on hover and then did nothing.
    ///
    /// `becomesKeyOnlyIfNeeded`, set in the initialiser, is what keeps this
    /// honest: the panel takes key for a text field or a button and for nothing
    /// else.
    public override var canBecomeKey: Bool { true }

    /// Main is different and stays false. A main window owns the menu bar and
    /// the document context, which a HUD has no business claiming.
    public override var canBecomeMain: Bool { false }

    /// Follow the active display and any resolution change, so the glass always
    /// covers exactly what is in front of the person.
    ///
    /// "Active" means the screen the pointer is on, not `NSScreen.main`. Main is
    /// the screen holding the key window, and this panel is never key, so on a
    /// second display it reported whichever screen the person had last clicked
    /// in. The glass would then cover the other monitor and every surface would
    /// be laid out against the wrong bounds.
    public func fitToScreen() {
        guard let screen = Self.active else { return }
        guard frame != screen.frame else { return }
        setFrame(screen.frame, display: true)
    }

    /// The screen the pointer is on, falling back to main and then to the first.
    public static var active: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    public func show() {
        fitToScreen()
        orderFrontRegardless()
    }

    /// Accept mouse events only while the pointer is over a surface.
    ///
    /// Called from a global mouse-moved monitor. The cost of getting this wrong
    /// in one direction is a HUD you cannot use; in the other, a screen you
    /// cannot scroll. The second is far worse, so anything outside a known
    /// surface rectangle is glass.
    public func updateInteractive(surfaces: [CGRect], mouse: NSPoint) {
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        // A few points of slack so a control right at the edge of a card is not
        // unreachable by a pixel.
        let over = surfaces.contains { $0.insetBy(dx: -3, dy: -3).contains(local) }
        if ignoresMouseEvents == over {
            ignoresMouseEvents = !over
        }
    }
}

/// The overlay's content view.
///
/// There was a `hitTest` override here that returned nil for "empty glass", and
/// it was the reason no control on any surface ever worked. `NSHostingView` is a
/// single NSView: SwiftUI draws its entire tree inside it and creates no child
/// views for buttons or text fields. So `hitTest` returns the hosting view
/// itself for *everything*, and a test of `hit === self` cannot tell a button
/// from a gap. Returning nil meant clicks never reached SwiftUI at all.
///
/// Click-through is the window's job instead, via `ignoresMouseEvents`, which
/// operates at the right level and gets scroll right too.
final class PassThroughHostingView: NSHostingView<AnyView> {
    // The window never becomes key on its own, so this view must not try to take
    // first responder and steal the caret from what the person is typing in.
    override var acceptsFirstResponder: Bool { false }

    /// Act on the very first click rather than spending it on activation.
    ///
    /// A non-activating panel is inactive by definition, and AppKit's default is
    /// to swallow the first click into an inactive window. For a HUD that is
    /// never frontmost, every click is a first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Tell AppKit this view genuinely needs the panel to be key.
    ///
    /// `becomesKeyOnlyIfNeeded` asks before handing key over, and NSHostingView
    /// answers no because AppKit cannot see what SwiftUI put inside it. Hover is
    /// a tracking concern and needs no key; a control's action does.
    override var needsPanelToBecomeKey: Bool { true }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}
