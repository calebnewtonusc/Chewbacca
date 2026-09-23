import Foundation
import os

/// The second pass: whisper.cpp reads the whole dictated sentence again after
/// the person stops, and its version replaces the recogniser's.
///
/// Apple's on-device recogniser is what makes words appear while talking,
/// because it streams and Whisper does not. Whisper is what gets names and
/// punctuation right. Measured 2026-09-22 on an M4 Pro with large-v3-turbo q5:
/// with "Northwind, Sam" as its prompt it wrote "Northwind" where it wrote "Northwynd"
/// without, and a resident server answered in 0.5s against 1.2s for a cold
/// `whisper-cli` that loads the model every call. So the server is kept
/// running, on localhost only.
///
/// Everything here is optional. No binary or no model means no second pass,
/// and the recogniser's text stands.
public actor Whisper {
    public static let shared = Whisper()

    /// Off the common 8080 so it cannot collide with a dev server.
    static let port = 8178

    public static var modelPath: String {
        NSHomeDirectory() + "/.bob/whisper/ggml-large-v3-turbo-q5_0.bin"
    }

    static let binaries = ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]

    /// Longer than any sentence has needed. Past it the recogniser's text
    /// stands rather than the field changing seconds after the person moved on.
    static let answerTimeout: TimeInterval = 4

    private static let log = Logger(subsystem: "kyber", category: "whisper")
    private var launched: Process?

    public var available: Bool {
        FileManager.default.fileExists(atPath: Self.modelPath)
            && Self.binaries.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Start the server if it is not already answering. A server left behind
    /// by an earlier run of the display is reused rather than doubled.
    public func warm() async {
        guard available, launched?.isRunning != true else { return }
        if await answering() { return }
        guard let binary = Self.binaries.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "-m", Self.modelPath, "--host", "127.0.0.1", "--port", String(Self.port),
            "-nt", "-l", "en",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            launched = process
            Self.log.notice("whisper.server started pid=\(process.processIdentifier)")
        } catch {
            Self.log.error("whisper.server failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The sentence as Whisper hears it, or nil for any reason at all.
    public func transcribe(_ wav: Data, prompt: String) async -> String? {
        guard available else {
            Self.log.notice("whisper.turn skipped reason=not_installed")
            return nil
        }
        await warm()
        let boundary = "bob-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("response_format", "text")
        field("temperature", "0")
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"turn.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.url("/inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.answerTimeout
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Self.log.notice("whisper.turn failed status=\(status)")
                return nil
            }
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Self.log.notice(
                "whisper.turn ms=\(Int(Date().timeIntervalSince(started) * 1000)) chars=\(text.count)")
            return text.isEmpty ? nil : text
        } catch {
            Self.log.notice("whisper.turn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Why Whisper's reading should not replace what was typed, or nil when
    /// it should.
    ///
    /// Sized against the audio, never against the recogniser's text. The old
    /// rule wanted Whisper within twice the typed length, and on 2026-09-22
    /// it threw away a 93-character sentence because the recogniser had
    /// dropped all but 24 of it: the one turn the pass existed for. The audio
    /// is the thing both of them heard.
    public static func rejection(heard: String, typed: String, seconds: Double) -> String? {
        let words = heard.split(whereSeparator: \.isWhitespace)
        let typedWords = typed.split(whereSeparator: \.isWhitespace).count
        guard !words.isEmpty else { return "empty" }
        // Far fewer words than were already typed is Whisper missing audio,
        // not the recogniser inventing it.
        if words.count * 2 < typedWords { return "short" }
        // Conversational English runs about 2.5 to 3 words a second; 5 is a
        // fast talker with room to spare, and Whisper inventing text on long
        // audio overshoots it. The 2026-09-22 turn was 17 words in 11.7s,
        // 1.5 a second. The bound is from published speaking rates; guessed,
        // never measured here.
        if Double(words.count) > seconds * maxWordsPerSecond + 3 { return "too_long" }
        // Whisper's known failure on silence and noise is a phrase on repeat.
        // Three words recurring four times does not happen in dictation.
        var seen: [String: Int] = [:]
        let lower = words.map { $0.lowercased() }
        for index in 0..<max(0, lower.count - 2) {
            let key = lower[index..<index + 3].joined(separator: " ")
            let count = seen[key, default: 0] + 1
            seen[key] = count
            if count >= 4 { return "repeating" }
        }
        return nil
    }

    static let maxWordsPerSecond = 5.0

    /// The length of 16kHz mono 16-bit WAV, the format `AudioRecorder` writes.
    public static func seconds(ofWav wav: Data) -> Double {
        Double(max(0, wav.count - 44)) / 32_000
    }

    private func answering() async -> Bool {
        var request = URLRequest(url: Self.url("/"))
        request.timeoutInterval = 0.3
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    private static func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }
}
