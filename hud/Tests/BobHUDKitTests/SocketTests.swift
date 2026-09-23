import Foundation
import Testing

@testable import BobHUDKit

/// The socket, with more than one thing talking to it.
///
/// This suite exists because of a bug that broke the whole system silently. The
/// accept loop used to read each connection to completion before accepting the
/// next, so anything that stayed connected, which is exactly what a listening
/// loop does, meant every later client sat in the accept queue and was never
/// served. No error, no timeout: a command that appeared to succeed and drew
/// nothing.
@Suite("Socket")
struct SocketTests {
    /// A socket path in a fresh temporary directory, so a failed run cannot
    /// leave a file that makes the next one fail to bind.
    private func temporaryPath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("hud.sock").path
    }

    private func connect(to path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        // The capacity is read before taking the pointer, because reading it
        // from inside the closure is a second access to the same field and
        // exclusivity rejects it.
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer)
                        .assumingMemoryBound(to: CChar.self),
                    source, maxLength - 1)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        if ok != 0 { close(fd); return -1 }
        return fd
    }

    private func legacyListener(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, capacity - 1) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 && listen(fd, 16) == 0 else {
            let error = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }
        return fd
    }

    @Test("an older listener without a lock keeps its endpoint")
    func legacyOwner() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let legacy = try legacyListener(at: path)
        defer { close(legacy) }
        let newcomer = SocketServer(path: path) { _ in }
        #expect(throws: (any Error).self) { try newcomer.start() }
        newcomer.stop()
        let fd = connect(to: path)
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
    }

    @Test("ordinary files are never removed as stale sockets")
    func preservesFile() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        try Data("keep".utf8).write(to: URL(fileURLWithPath: path))
        let server = SocketServer(path: path) { _ in }
        #expect(throws: (any Error).self) { try server.start() }
        server.stop()
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "keep")
    }

    @Test("stop preserves a replacement endpoint owned by another listener")
    func preservesReplacement() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let server = SocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }
        // Model an older process that does not cooperate with the new lock.
        unlink(path)
        let replacement = try legacyListener(at: path)
        defer { close(replacement) }
        server.stop()
        let fd = connect(to: path)
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
    }

    @Test("a contender and repeated stop cannot remove the owner's endpoint")
    func exclusiveOwnership() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let owner = SocketServer(path: path) { _ in }
        let lines = Mailbox()
        let contender = SocketServer(path: path) { event in
            if case .line(let line) = event.kind { lines.add(line) }
        }
        try owner.start()
        defer { owner.stop(); contender.stop() }
        #expect(throws: (any Error).self) { try owner.start() }
        #expect(throws: (any Error).self) { try contender.start() }
        contender.stop()
        let first = connect(to: path)
        #expect(first >= 0)
        if first >= 0 { close(first) }
        owner.stop()
        try contender.start()
        owner.stop()
        let second = connect(to: path)
        #expect(second >= 0)
        if second >= 0 {
            let payload = "r successor\n"
            _ = payload.withCString { send(second, $0, strlen($0), 0) }
            try await Task.sleep(for: .milliseconds(100))
            close(second)
        }
        #expect(lines.all.contains("r successor"))
    }

    @Test("failed startup releases ownership for a later server")
    func failedStartReleasesOwnership() throws {
        let path = temporaryPath()
        let directory = (path as NSString).deletingLastPathComponent
        defer { try? FileManager.default.removeItem(atPath: directory) }
        // An existing directory is rejected after obtaining the ownership lock.
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        let failed = SocketServer(path: path) { _ in }
        #expect(throws: (any Error).self) { try failed.start() }
        try FileManager.default.removeItem(atPath: path)
        let successor = SocketServer(path: path) { _ in }
        try successor.start()
        defer { successor.stop() }
        failed.stop()
        let fd = connect(to: path)
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
    }

    @Test("kernel ownership survives contention and is released after process death")
    func processOwnership() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        // Independent process holds the same kernel contract and leaves a stale
        // bound socket after SIGKILL; no HUD application or private socket is used.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
        import fcntl, os, signal, socket, sys
        fd = os.open(sys.argv[1] + '.lock', os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(sys.argv[1])
        sock.listen()
        os.write(1, b'R')
        signal.pause()
        """, path]
        let ready = Pipe()
        process.standardOutput = ready
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        var descriptor = pollfd(fd: ready.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        try #require(poll(&descriptor, 1, 5000) == 1)
        #expect(try ready.fileHandleForReading.read(upToCount: 1) == Data([82]))
        let server = SocketServer(path: path) { _ in }
        #expect(throws: (any Error).self) { try server.start() }
        server.stop()
        let stillOwned = connect(to: path)
        #expect(stillOwned >= 0)
        if stillOwned >= 0 { close(stillOwned) }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        try server.start()
        defer { server.stop() }
        let recovered = connect(to: path)
        #expect(recovered >= 0)
        if recovered >= 0 { close(recovered) }
    }

    @Test("a second client is served while the first stays connected")
    func concurrentClients() async throws {
        let path = temporaryPath()
        let lines = Mailbox()
        let server = SocketServer(path: path) { event in
            if case .line(let line) = event.kind { lines.add(line) }
        }
        try server.start()
        defer { server.stop() }

        // The first client connects and says nothing, the way a listening loop
        // waiting to be spoken to does.
        let idle = connect(to: path)
        #expect(idle >= 0)
        defer { close(idle) }
        try await Task.sleep(for: .milliseconds(150))

        // The second draws. Before the fix this was never accepted at all.
        let drawer = connect(to: path)
        #expect(drawer >= 0)
        defer { close(drawer) }
        let payload = "r s\n"
        _ = payload.withCString { send(drawer, $0, strlen($0), 0) }

        try await Task.sleep(for: .milliseconds(400))
        #expect(lines.all.contains("r s"))
    }

    @Test("a client that never asked hears nothing")
    func eventsAreOptIn() async throws {
        // Events used to go to every connected client, so a full speech
        // transcript reached any process that happened to hold the socket open.
        // Anything running as this user can open it. Nobody asked for that and
        // nothing disclosed it.
        let path = temporaryPath()
        let server = SocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }

        let drawer = connect(to: path)
        #expect(drawer >= 0)
        defer { close(drawer) }
        try await Task.sleep(for: .milliseconds(150))

        #expect(!server.hasSubscribers)
        // Nothing is listening, so this must report that it went nowhere.
        #expect(!server.send(#"h "my private sentence""#))
    }

    @Test("an event reaches a client that is only listening")
    func eventsReachListeners() async throws {
        let path = temporaryPath()
        let server = SocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }

        let listener = connect(to: path)
        #expect(listener >= 0)
        defer { close(listener) }
        // Subscribing is a line on the wire, not a separate channel.
        let subscribe = "listen\n"
        _ = subscribe.withCString { send(listener, $0, strlen($0), 0) }
        try await Task.sleep(for: .milliseconds(250))

        #expect(server.hasSubscribers)
        #expect(server.send(#"h "show me my week""#))

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = recv(listener, &buffer, buffer.count, 0)
        #expect(count > 0)
        let text = String(decoding: buffer[0..<max(count, 0)], as: UTF8.self)
        #expect(text.contains("show me my week"))
    }

    @Test("subscribing is reported after the version, so the app can add its own greeting")
    func subscribingIsReported() async throws {
        let path = temporaryPath()
        let kinds = Mailbox()
        let server = SocketServer(path: path) { event in
            if case .subscribed = event.kind { kinds.add("subscribed") }
            if case .line = event.kind { kinds.add("line") }
        }
        try server.start()
        defer { server.stop() }

        let listener = connect(to: path)
        #expect(listener >= 0)
        defer { close(listener) }
        let subscribe = "listen\n"
        _ = subscribe.withCString { send(listener, $0, strlen($0), 0) }
        try await Task.sleep(for: .milliseconds(250))

        #expect(kinds.all == ["subscribed"], "listen is about the connection, never a line for the glass")
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = recv(listener, &buffer, buffer.count, 0)
        let text = String(decoding: buffer[0..<max(count, 0)], as: UTF8.self)
        #expect(text.hasPrefix("v! "), "the version is on the wire before the app hears of the subscriber")
    }

    @Test("send reports failure when nobody is connected")
    func sendWithNoClients() throws {
        // The command bar relies on this to tell the person their request went
        // nowhere, so a wrong answer here is a silent failure in the UI.
        let path = temporaryPath()
        let server = SocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }
        #expect(!server.send("p dormant"))
    }
}

/// A thread-safe box, because the server calls back from its own queues.
private final class Mailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// Telling the sender when it got something wrong.
@Suite("Talking back")
struct FeedbackTests {
    @Test("a problem is a quoted string, so a sentence survives the wire")
    func problemIsQuoted() {
        let line = OutboundEvent.problem("`c` needs an id and a type").line
        #expect(line.hasPrefix("! "))
        #expect(line.contains("needs an id"))
    }

    @Test("the version says which verbs exist")
    func versionListsVerbs() {
        // A newer client talking to an older display used to fail one silent
        // line at a time with no way to tell that was what was happening.
        #expect(SocketServer.version.contains("bobhud/"))
        for verb in ["c", "d", "r", "@", "p", "s", "q", "w", "m", "u", "listen"] {
            #expect(SocketServer.version.contains(verb), "version omits \(verb)")
        }
    }

    @Test("a problem and a request are different events")
    func problemIsNotHeard() {
        #expect(OutboundEvent.problem("x") != OutboundEvent.heard("x"))
    }

    @Test("a typed request is the same line with a flag after the string")
    func typedIsFlagged() {
        // A listener that reads only the string still gets the request;
        // one that reads the flag can answer in writing.
        #expect(OutboundEvent.typed("what is due").line == #"h "what is due" via=typed"#)
        #expect(OutboundEvent.heard("what is due").line == #"h "what is due""#)
    }
}
