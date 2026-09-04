import Foundation

/// A Unix domain socket carrying Bob Lines in, and events back out.
///
/// A socket rather than a port because there is nothing to configure, nothing to
/// collide with, and the filesystem already has the permission model: a socket in
/// the user's own directory is reachable by that user and nobody else. A panel
/// that renders whatever is sent to it should not be listening on the network.
///
/// The channel is bidirectional on purpose. A display that cannot answer is a
/// poster: you can look at it and that is all. Sending events back on the same
/// connection is what lets an agent ask a question, draw the options, and find
/// out which one was picked, without a second transport or a polling loop.
///
/// One connection at a time, deliberately. Two agents drawing to the same panel
/// simultaneously is a race with a visible symptom, so a second connection
/// replaces the first and the surface resets.
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

    /// Guards `clientFD`, which the socket thread sets and the main actor writes.
    private let lock = NSLock()
    private var clientFD: Int32 = -1
    private var running = false

    public init(path: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["BOB_HUD_SOCKET"] {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".bob/hud.sock").path
    }

    /// Send a line back to whoever is connected. No-op when nobody is.
    ///
    /// Failure here is deliberately quiet: an agent that streamed a surface and
    /// walked away is the normal case, not an error, and a panel that popped an
    /// alert every time a click had nowhere to go would be unusable.
    @discardableResult
    public func send(_ line: String) -> Bool {
        lock.lock()
        let fd = clientFD
        lock.unlock()
        guard fd >= 0 else { return false }

        let payload = line.hasSuffix("\n") ? line : line + "\n"
        return payload.withCString { pointer in
            let length = strlen(pointer)
            var written = 0
            while written < length {
                // MSG_NOSIGNAL is not available on Darwin, so SIGPIPE is
                // disabled per socket at accept time instead.
                let n = Darwin.send(fd, pointer + written, length - written, 0)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

        // A socket file left by a crashed process makes bind fail with
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

        // Only the user who owns it may draw on their own screen.
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
        lock.lock()
        if clientFD >= 0 { close(clientFD) }
        clientFD = -1
        lock.unlock()
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if running && errno != EINTR {
                    onEvent(Event(kind: .failed("accept failed: \(errno)")))
                }
                continue
            }

            // A client that hangs up mid-write would otherwise kill the whole
            // process with SIGPIPE, taking the panel with it.
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            lock.lock()
            let previous = clientFD
            clientFD = fd
            lock.unlock()
            if previous >= 0 { close(previous) }

            onEvent(Event(kind: .began))
            read(fd)

            lock.lock()
            if clientFD == fd { clientFD = -1 }
            lock.unlock()
            close(fd)
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
