import Foundation

/// A Unix domain socket that accepts Bob Lines.
///
/// A socket rather than a port because there is nothing to configure, nothing to
/// collide with, and the filesystem already has the permission model: a socket
/// in the user's own directory is reachable by that user and nobody else. A HUD
/// that renders whatever is sent to it should not be listening on the network.
///
/// One connection at a time, deliberately. Two agents drawing to the same
/// floating panel simultaneously is not a feature, it is a race with a visible
/// symptom, so a second connection replaces the first and the surface resets.
public final class SocketServer: @unchecked Sendable {
    public struct Event: Sendable {
        public enum Kind: Sendable {
            case began
            case line(String)
            case ended
            case failed(String)
        }
        public let kind: Kind
    }

    private let path: String
    private let onEvent: @Sendable (Event) -> Void
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "bob.hud.socket")
    private var running = false

    public init(path: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    public static var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".bob/hud.sock").path
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

        // A socket file left by a crashed process would make bind fail with
        // EADDRINUSE forever, so clear it. Nothing else owns this path.
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not create the socket."])
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else {
            throw NSError(
                domain: "BobHUD", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Socket path is too long: \(path)"])
        }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source, maxLength - 1)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, size)
            }
        }
        guard bound == 0 else {
            close(listenFD)
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not bind \(path)."])
        }

        // Only the user who owns it may write to the HUD.
        chmod(path, 0o600)

        guard listen(listenFD, 4) == 0 else {
            close(listenFD)
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not listen on \(path)."])
        }

        running = true
        queue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        running = false
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if running && errno != EINTR {
                    onEvent(Event(kind: .failed("accept failed: \(errno)")))
                }
                continue
            }
            onEvent(Event(kind: .began))
            read(clientFD)
            close(clientFD)
            onEvent(Event(kind: .ended))
        }
    }

    private func read(_ fd: Int32) {
        var buffer = LineBuffer()
        var bytes = [UInt8](repeating: 0, count: 8192)

        while running {
            let count = recv(fd, &bytes, bytes.count, 0)
            if count <= 0 { break }

            // A chunk can split a multi-byte character, so decode leniently and
            // let the line buffer hold anything incomplete.
            let chunk = String(decoding: bytes[0..<count], as: UTF8.self)
            for line in buffer.push(chunk) {
                onEvent(Event(kind: .line(line)))
            }
        }

        if let tail = buffer.flush() {
            onEvent(Event(kind: .line(tail)))
        }
    }
}
