import Foundation
import Testing

@testable import BobHUDKit

/// The socket, with more than one thing talking to it.
///
/// This suite exists because of a bug that broke the whole system silently. The
/// accept loop used to read each connection to completion before accepting the
/// next, so anything that stayed connected — which is exactly what a listening
/// loop does — meant every later client sat in the accept queue and was never
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
        return ok == 0 ? fd : -1
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

    @Test("an event reaches a client that is only listening")
    func eventsReachListeners() async throws {
        let path = temporaryPath()
        let server = SocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }

        let listener = connect(to: path)
        #expect(listener >= 0)
        defer { close(listener) }
        try await Task.sleep(for: .milliseconds(150))

        #expect(server.send(#"h "show me my week""#))

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = recv(listener, &buffer, buffer.count, 0)
        #expect(count > 0)
        let text = String(decoding: buffer[0..<max(count, 0)], as: UTF8.self)
        #expect(text.contains("show me my week"))
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
