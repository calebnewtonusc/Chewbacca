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
        acceptsMouseMovedEvents = true

        contentView = PassThroughHostingView(rootView: AnyView(content))
        setFrame(frame, display: false)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Follow the active display and any resolution change, so the glass always
    /// covers exactly what is in front of the person.
    public func fitToScreen() {
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)
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
        if ignoresMouseEvents == over { ignoresMouseEvents = !over }
    }
}

/// The view that decides what is glass and what is solid.
///
/// `hitTest` walks down and asks what the click landed on. If the answer is the
/// hosting view itself, the click landed on empty glass and must be handed to
/// whatever is underneath, which returning nil does. If it landed on a real
/// control inside a surface, the click belongs to us.
///
/// Without this the window would swallow every click on the screen, which is the
/// single fastest way to make an overlay hated.
final class PassThroughHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === self ? nil : hit
    }

    // The window never becomes key, so it must not try to take first responder
    // and steal the caret from whatever the person is typing in.
    override var acceptsFirstResponder: Bool { false }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}
