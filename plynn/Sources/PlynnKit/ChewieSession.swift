import Foundation

/// A Claude Code process kept alive so Chewie does not pay for a cold start on
/// every request.
///
/// Measured on this machine: a one-shot `claude -p` took 26 seconds to say
/// hello. Of that, roughly 15 was the CLI booting and most of the rest was the
/// model reading a large CLAUDE.md and writing a session opener nobody asked
/// for. Holding the process open and giving it a small replaced system prompt
/// takes the same request to about 4.6 seconds.
///
/// Two things make that work, and both matter:
///
/// - `--input-format stream-json` keeps the process reading turns from stdin
///   instead of exiting after one.
/// - A bare working directory and `--system-prompt` (replacing, not appending)
///   keep the project and user instructions out of every turn. The tools are
///   unaffected: they are configured separately from the prompt, and a run in
///   that shape still shells out to `people` correctly.
public actor ChewieSession {

    private var proc: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    /// Bytes read but not yet split into a complete line.
    private var pending = Data()
    private let queue = DispatchQueue(label: "chewie.session")

    public init() {}

    public var isRunning: Bool { proc?.isRunning == true }

    /// A directory with no CLAUDE.md, so no project instructions load. Created
    /// rather than reused so a stray file in a real project cannot leak in.
    private static var workingDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "chewie-session", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("CLAUDE.md"))
        return dir
    }

    /// Spawn the process. Safe to call repeatedly; a live session is left alone.
    public func start() {
        if proc?.isRunning == true { return }
        guard let exe = ChewieRouter.claudeExecutable() else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",  // stream-json output requires it
            "--strict-mcp-config",
            "--model", UserDefaults.standard.string(forKey: "chewieModel") ?? "haiku",
            "--system-prompt", ChewieRouter.voiceStyle,
        ]
        p.currentDirectoryURL = Self.workingDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] =
            "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + (env["PATH"] ?? "")
        p.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch { return }
        proc = p
        input = inPipe.fileHandleForWriting
        output = outPipe.fileHandleForReading
        pending = Data()
    }

    public func stop() {
        try? input?.close()
        proc?.terminate()
        proc = nil
        input = nil
        output = nil
        pending = Data()
    }

    /// Send one turn and wait for its result.
    ///
    /// Throws rather than hanging: a wedged session must fall back to a
    /// one-shot run, not leave the user holding a key in front of a spinner.
    public func ask(_ prompt: String, timeout: TimeInterval = 120) async throws -> String {
        start()
        guard let input, let output, proc?.isRunning == true else {
            throw ChewieRouter.ChewieError.notInstalled
        }

        let turn: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": prompt]]],
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: turn) else {
            throw ChewieRouter.ChewieError.failed("Could not encode the request.")
        }
        line.append(0x0A)
        do { try input.write(contentsOf: line) } catch {
            // The far end died between the liveness check and the write.
            stop()
            throw ChewieRouter.ChewieError.failed("Chewie's session closed; retrying cold.")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let obj = try await nextMessage(from: output, before: deadline) else { break }
            guard let type = obj["type"] as? String else { continue }
            // Everything before the result is progress: assistant turns, tool
            // calls, tool results. Only the result line ends the wait.
            if type == "result" {
                if let isError = obj["is_error"] as? Bool, isError {
                    throw ChewieRouter.ChewieError.failed(
                        (obj["result"] as? String) ?? "Chewie failed.")
                }
                guard let result = obj["result"] as? String else {
                    throw ChewieRouter.ChewieError.failed("Chewie returned no result.")
                }
                return ChewieRouter.stripOpener(result)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // A session that stopped answering is worse than no session, because
        // every later request would queue behind it.
        stop()
        throw ChewieRouter.ChewieError.timedOut(seconds: Int(timeout))
    }

    /// Read the next complete JSON line, refilling the buffer as needed.
    private func nextMessage(
        from handle: FileHandle, before deadline: Date
    ) async throws -> [String: Any]? {
        while true {
            if let nl = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<nl]
                pending.removeSubrange(...nl)
                if lineData.isEmpty { continue }
                if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    return obj
                }
                continue  // a non-JSON line is noise, not the end of the stream
            }
            if Date() >= deadline { return nil }
            let chunk = await read(handle)
            if chunk.isEmpty { return nil }  // EOF: the process exited
            pending.append(chunk)
        }
    }

    /// One blocking read, moved off the actor so it cannot stall other work.
    private func read(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (c: CheckedContinuation<Data, Never>) in
            queue.async {
                let data = handle.availableData
                c.resume(returning: data)
            }
        }
    }
}
