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
/// Several connections at once, because the design needs it.
///
/// This used to accept one client and then block reading it until it hung up,
/// which quietly broke the whole system the moment anything stayed connected. A
/// listening loop holds its connection open for the life of the session, so with
/// one running, every `hud draw` sat in the accept queue and drew nothing: no
/// error, no timeout, just a command that appeared to succeed and did nothing.
///
/// Each connection now gets its own reader, and events go to all of them. The
/// race that the single-client rule was guarding against is settled by surfaces
/// being addressable by name: two writers to different names cannot collide, and
/// two writers to the same name were always going to fight whatever this did.
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

    /// Guards `clients` and `subscribers`, which reader threads mutate and the
    /// main actor reads.
    private let lock = NSLock()
    private var clients: Set<Int32> = []

    /// The clients that asked to receive events.
    ///
    /// Events used to go to everyone connected, which meant a full speech
    /// transcript reached every process that happened to have the socket open.
    /// Anything running as this user can open it, so a second tool holding a
    /// connection to draw a panel was also being handed everything the person
    /// said out loud. Nobody asked for that and nothing disclosed it.
    ///
    /// Receiving is opt-in now: a client sends `listen` and only then hears
    /// anything back. Drawing needs no subscription, so the common case sees
    /// nothing it did not ask for.
    private var subscribers: Set<Int32> = []
    private var running = false

    /// One queue per connection, so a slow reader cannot stall the others or
    /// the accept loop.
    private let readers = DispatchQueue(
        label: "bob.hud.socket.readers", attributes: .concurrent)

    public init(path: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    /// What this build speaks.
    ///
    /// There was no version anywhere in the protocol, so a newer client talking
    /// to an older display failed one silent line at a time with no way to tell
    /// that was what was happening.
    public static let version = "bobhud/1 verbs=c,>,d,r,@,-,p,m,u,listen"

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
        let targets = subscribers
        lock.unlock()
        guard !targets.isEmpty else { return false }

        let payload = line.hasSuffix("\n") ? line : line + "\n"
        var delivered = false
        for fd in targets {
            if write(payload, to: fd) { delivered = true }
        }
        return delivered
    }

    /// Write one payload to one client, reporting whether it landed.
    private func write(_ payload: String, to fd: Int32) -> Bool {
        payload.withCString { pointer in
            let length = strlen(pointer)
            var written = 0
            while written < length {
                // MSG_NOSIGNAL is not available on Darwin, so SIGPIPE is
                // disabled per socket at accept time instead.
                let sent = Foundation.send(fd, pointer + written, length - written, 0)
                if sent <= 0 { return false }
                written += sent
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

        guard listen(listenFD, 16) == 0 else {
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
        // Closing each client's descriptor is what unblocks its reader: `recv`
        // returns 0 and the reader unwinds. Without this, quitting would leave
        // a thread parked on a socket that nobody was ever going to write to.
        for fd in clients { close(fd) }
        clients.removeAll()
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
            clients.insert(fd)
            lock.unlock()

            onEvent(Event(kind: .began))
            // Read on its own queue. Doing it here is what made the accept loop
            // serial: a client that stays connected blocked every later one.
            readers.async { [weak self] in
                guard let self else { return }
                self.read(fd)
                self.lock.lock()
                self.clients.remove(fd)
                self.subscribers.remove(fd)
                self.lock.unlock()
                close(fd)
                self.onEvent(Event(kind: .ended))
            }
        }
    }

    /// Whether anything is listening for events at all.
    public var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !subscribers.isEmpty
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
                // `listen` is handled here rather than in the parser: it is
                // about this connection, not about anything on the glass, and
                // the parser has no idea which socket a line arrived on.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "listen" {
                    lock.lock()
                    subscribers.insert(fd)
                    lock.unlock()
                    // Anything that subscribes is told what it is talking to,
                    // unprompted. A client should never have to guess whether
                    // the verb it is about to use exists in this build.
                    _ = write(
                        OutboundEvent.version(Self.version).line + "\n", to: fd)
                    continue
                }
                if trimmed == "version" {
                    _ = write(
                        OutboundEvent.version(Self.version).line + "\n", to: fd)
                    continue
                }
                onEvent(Event(kind: .line(line)))
            }
        }

        if let tail = buffer.flush() {
            onEvent(Event(kind: .line(tail)))
        }
    }
}
