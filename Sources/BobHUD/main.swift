import AppKit
import BobHUDKit
import SwiftUI

/// BobHUD: a layer of glass over everything, with things drawn on it.
///
/// Listen on a Unix socket, parse Bob Lines, place surfaces around the screen,
/// and send events back when someone uses a control. No browser, no window that
/// steals focus, no model in this process at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OverlayModel()
    private var overlay: OverlayWindow?
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var hotKeyMonitor: Any?
    private var escMonitor: Any?
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayWindow(content: OverlayView(model: model))
        self.overlay = overlay
        overlay.show()

        setUpMenuBar()
        setUpKeys()
        observeScreenChanges()

        let server = SocketServer(path: SocketServer.defaultPath) { [weak self] event in
            // The socket runs on its own queue; every touch of the model has to
            // happen on the main actor.
            Task { @MainActor in self?.handle(event) }
        }
        self.server = server

        model.onEvent = { [weak server] event in server?.send(event.line) }

        do {
            try server.start()
        } catch {
            presentFatal(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        for monitor in [hotKeyMonitor, escMonitor, mouseMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handle(_ event: SocketServer.Event) {
        switch event.kind {
        case .began:
            model.reset()
            overlay?.show()

        case .line(let line):
            do {
                if let op = try LineParser.parse(line) {
                    model.apply(op)
                    updateInteractive()
                }
            } catch {
                // A malformed line degrades one component rather than clearing
                // the glass, which is the same choice the web renderer makes.
                model.warn(String(describing: error))
            }

        case .ended:
            break

        case .failed(let message):
            model.warn(message)
        }
    }

    /// Option-Command-Space hides and shows everything. Escape clears it.
    ///
    /// Global monitors rather than a registered hot key, because registering one
    /// system-wide needs Accessibility permission, and a panel you can summon is
    /// not worth a permission prompt on first launch.
    private func setUpKeys() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.modifierFlags.contains([.option, .command]),
                  event.keyCode == 49 // space
            else { return }
            Task { @MainActor in self?.toggle() }
        }

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // escape
            Task { @MainActor in self?.dismissAll() }
        }

        // Follow the pointer so the glass only becomes solid over a surface.
        // Without this the overlay swallows every scroll on the display.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.updateInteractive() }
        }
    }

    private func updateInteractive() {
        overlay?.updateInteractive(surfaces: model.frames, mouse: NSEvent.mouseLocation)
    }

    /// The glass has to follow the display it is over.
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.overlay?.fitToScreen() }
        }
    }

    private func toggle() {
        guard let overlay else { return }
        if overlay.isVisible { overlay.orderOut(nil) } else { overlay.show() }
    }

    private func dismissAll() {
        guard !model.isEmpty else { return }
        model.onEvent?(.dismissed)
        model.reset()
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles.rectangle.stack",
            accessibilityDescription: "Bob HUD")

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Show or hide", action: #selector(toggleFromMenu), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let clearItem = NSMenuItem(
            title: "Clear everything", action: #selector(clearFromMenu), keyEquivalent: "\u{1b}")
        clearItem.target = self
        menu.addItem(clearItem)
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

    @objc private func toggleFromMenu() { toggle() }
    @objc private func clearFromMenu() { dismissAll() }

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
app.setActivationPolicy(.accessory)
app.run()
