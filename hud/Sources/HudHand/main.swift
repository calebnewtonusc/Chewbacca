import AppKit

// hud-hand: the agent's hands, with the agent's cursor drawn where they are.
//
//     hud-hand list  --app <name> [words]         controls the agent could use
//     hud-hand point --app <name> <words>         move the agent cursor there
//     hud-hand press --app <name> <words>         move there, then press it
//     hud-hand type  --app <name> <words> --text "..."   move there, then set its text
//     hud-hand off                                take the agent cursor down
//
// Nothing here posts a mouse event or moves the real cursor. Pressing is
// AXPress and typing is setting AXValue, both of which reach a window that is
// not in front. Tested 2026-09-23: a click posted to a background app's pid
// never arrived, while these two landed with the person's cursor unmoved and
// the frontmost app unchanged.

let actionable: Set<String> = [
    "AXButton", "AXTextField", "AXTextArea", "AXLink", "AXCheckBox", "AXPopUpButton",
    "AXMenuButton", "AXRadioButton", "AXComboBox", "AXSearchField", "AXTab",
]

struct Control {
    let element: AXUIElement
    let role: String
    let name: String
    let frame: CGRect
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, "AXPosition"), let size = attribute(element, "AXSize")
    else { return nil }
    var point = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func name(of element: AXUIElement) -> String {
    for key in ["AXTitle", "AXDescription", "AXPlaceholderValue", "AXHelp"] {
        if let text = attribute(element, key) as? String, !text.isEmpty { return text }
    }
    if let text = attribute(element, "AXValue") as? String, !text.isEmpty { return text }
    return ""
}

/// Guessed, never measured: deep enough for a web page's controls, bounded so
/// a page with an endless feed cannot stall the walk.
let walkBudget = 40_000

func controls(in pid: pid_t) -> [Control] {
    let app = AXUIElementCreateApplication(pid)
    // Chrome and Electron build their web content's tree only when asked.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    var found: [Control] = []
    var budget = walkBudget
    func walk(_ element: AXUIElement, _ depth: Int) {
        guard depth < 60, budget > 0 else { return }
        budget -= 1
        let role = (attribute(element, "AXRole") as? String) ?? ""
        if actionable.contains(role), let rect = frame(of: element), rect.width > 0, rect.height > 0 {
            found.append(Control(element: element, role: role, name: name(of: element), frame: rect))
        }
        for child in (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
    }
    walk(app, 0)
    return found
}

func best(_ found: [Control], _ words: String) -> Control? {
    let wanted = words.lowercased()
    let named = found.filter { !$0.name.isEmpty }
    return named.first { $0.name.lowercased() == wanted }
        ?? named.first { $0.name.lowercased().hasPrefix(wanted) }
        ?? named.first { $0.name.lowercased().contains(wanted) }
}

func send(_ line: String) {
    let path = (ProcessInfo.processInfo.environment["BOB_HUD_SOCKET"]
        ?? NSHomeDirectory() + "/.bob/hud.sock")
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        let bytes = Array(path.utf8.prefix(raw.count - 1))
        raw.copyBytes(from: bytes)
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        FileHandle.standardError.write("hud-hand: the HUD is not listening at \(path)\n".data(using: .utf8)!)
        return
    }
    let data = Array((line + "\n").utf8)
    _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
}

/// Glide to the control's centre, and pulse when `act` is set.
func point(at control: Control, act: Bool = false) {
    send(String(format: "a %.0f %.0f%@", control.frame.midX, control.frame.midY, act ? " act=true" : ""))
}

/// Spring response 0.5 in AgentCursorView settles in roughly this long, so the
/// press lands after the pointer has visibly arrived rather than mid-flight.
let glide: useconds_t = 650_000

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("hud-hand: \(message)\n".data(using: .utf8)!)
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

guard AXIsProcessTrusted() else { fail("needs Accessibility for the app running it") }
let command = arguments.first ?? "help"
arguments = Array(arguments.dropFirst())
if command == "off" { send("a off"); exit(0) }

let appName = option("--app")
let text = option("--text")
let words = arguments.joined(separator: " ")

guard let appName,
      let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName })
else { fail("usage: hud-hand list|point|press|type --app <running app> [words] [--text ...]") }

let found = controls(in: app.processIdentifier)

switch command {
case "list":
    for control in found where words.isEmpty || control.name.lowercased().contains(words.lowercased()) {
        print(String(format: "%-14@ %5.0f,%-5.0f %@", control.role as NSString,
                     control.frame.midX, control.frame.midY, control.name as NSString))
    }
case "point", "press", "type":
    guard let control = best(found, words) else { fail("no control named \"\(words)\" in \(appName)") }
    point(at: control)
    usleep(glide)
    if command == "press" {
        point(at: control, act: true)
        let result = AXUIElementPerformAction(control.element, kAXPressAction as CFString)
        guard result == .success else { fail("press failed: AXError \(result.rawValue)") }
    } else if command == "type" {
        guard let text else { fail("type needs --text") }
        point(at: control, act: true)
        let result = AXUIElementSetAttributeValue(control.element, kAXValueAttribute as CFString, text as CFString)
        guard result == .success else { fail("type failed: AXError \(result.rawValue)") }
    }
    print("\(command) \(control.role) \"\(control.name)\" at \(Int(control.frame.midX)),\(Int(control.frame.midY))")
default:
    fail("unknown command \(command)")
}
