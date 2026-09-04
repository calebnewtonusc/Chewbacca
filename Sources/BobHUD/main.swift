import AppKit
import BobHUDKit
import SwiftUI

/// BobHUD: a floating surface that draws streamed interfaces as native views.
///
/// The whole program is: listen on a Unix socket, parse Bob Lines, apply them to
/// a store, and let SwiftUI redraw. No browser, no window that steals focus, no
/// model in this process at all.
///
/// Run it with no arguments and it sits in the menu bar waiting. An agent writes
/// lines to ~/.bob/hud.sock and the panel appears, assembles, and stays until
/// something replaces it or you dismiss it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SurfaceStore()
    private var panel: HUDPanel?
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var idleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = HUDPanel(store: store)
        self.panel = panel

        setUpMenuBar()

        let server = SocketServer(path: SocketServer.defaultPath) { [weak self] event in
            // The socket runs on its own queue; every touch of the store and the
            // panel has to happen on the main actor.
            Task { @MainActor in self?.handle(event) }
        }
        self.server = server

        do {
            try server.start()
        } catch {
            presentFatal(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func handle(_ event: SocketServer.Event) {
        switch event.kind {
        case .began:
            // A new stream replaces whatever was on screen. Two agents drawing
            // to one panel is a race with a visible symptom, so the last one in
            // wins and says so by clearing first.
            idleTimer?.invalidate()
            store.reset()
            panel?.show()

        case .line(let line):
            do {
                if let op = try LineParser.parse(line) {
                    store.apply([op])
                    resize()
                }
            } catch {
                // A malformed line degrades one component rather than killing
                // the surface, which is the same choice the web renderer makes.
                store.warn(String(describing: error))
            }

        case .ended:
            resize()

        case .failed(let message):
            store.warn(message)
        }
    }

    /// Let the panel grow to what the content needs, once the layout settles.
    private func resize() {
        guard let panel, let hosting = panel.contentView else { return }
        let fitting = hosting.fittingSize
        panel.fit(to: CGSize(width: fitting.width, height: fitting.height))
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Bob HUD")

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(
            withTitle: "Hide", action: #selector(hidePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let socket = NSMenuItem(title: SocketServer.defaultPath, action: nil, keyEquivalent: "")
        socket.isEnabled = false
        menu.addItem(socket)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() { panel?.show() }
    @objc private func hidePanel() { panel?.hide() }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Bob HUD could not start"
        alert.informativeText =
            "\(error.localizedDescription)\n\nSocket: \(SocketServer.defaultPath)"
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory rather than regular: no Dock icon, no app switcher entry, and
// showing the panel never pulls focus away from what you were doing.
app.setActivationPolicy(.accessory)
app.run()
