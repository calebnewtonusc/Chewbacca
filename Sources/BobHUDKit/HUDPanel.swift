import AppKit
import SwiftUI

/// The floating panel.
///
/// The important properties, and why each one:
///
/// - `.nonactivatingPanel` plus `canBecomeKey == false` means showing the HUD
///   never steals focus. You ask for a dashboard mid-sentence in another app and
///   your cursor stays where it was, which is the entire difference between a
///   HUD and a window.
/// - `.floating` level keeps it above ordinary windows without the
///   screen-saver-level aggression that makes an overlay feel broken.
/// - `.canJoinAllSpaces` and `.fullScreenAuxiliary` mean it follows you across
///   desktops and survives a full-screen app, which is where you are when you
///   actually want to glance at something.
/// - A clear background with a real `NSVisualEffectView` behind the content, so
///   it reads as part of the system rather than as a web page pretending to be.
@MainActor
public final class HUDPanel: NSPanel {
    private let store: SurfaceStore

    public init(store: SurfaceStore) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        contentView = NSHostingView(rootView: HUDRootView(store: store))
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public func show() {
        positionTopRight()
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
    }

    /// Top right, under the menu bar, out of the way of most work.
    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 16
        setFrameOrigin(NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - frame.height - margin))
    }

    /// Grow to fit the content, within limits, so a one-line status does not sit
    /// in a half-empty box and a long table does not run off the screen.
    public func fit(to size: CGSize) {
        guard let screen = NSScreen.main else { return }
        let maxHeight = screen.visibleFrame.height * 0.75
        let width = min(max(size.width, 320), 560)
        let height = min(max(size.height, 90), maxHeight)

        var next = frame
        // Anchor the top edge so the panel grows downward rather than jumping.
        next.origin.y += next.height - height
        next.size = CGSize(width: width, height: height)
        setFrame(next, display: true, animate: true)
    }
}

/// The panel's content: the surface, its chrome, and its material.
struct HUDRootView: View {
    let store: SurfaceStore

    var body: some View {
        ScrollView(.vertical) {
            SurfaceView(store: store)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            // A real system material rather than a translucent colour, so it
            // picks up the wallpaper and the appearance the way every other
            // floating surface on the machine does.
            VisualEffect(material: .hudWindow, blending: .behindWindow)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
