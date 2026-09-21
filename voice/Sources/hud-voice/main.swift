import AVFoundation
import FluidAudio
import Foundation
import HudVoiceKit

// hud-voice: the reply, read aloud, with Kokoro on the Neural Engine.
//
// hud-speak did this in Python: uv, MLX, espeak-ng from Homebrew, a spaCy
// model, and a minute of installing on a fresh Mac before the first word.
// This is the same voice (Kokoro 82M, af_heart) through FluidAudio's
// CoreML split of it, one binary with nothing to install and a 24 MB
// download on first run. Measured 2026-09-20 on an M4 Pro, model on disk:
// 0.7s to load, 0.8s for the first sentence (the compile), then 0.11s for
// six words and 0.20s for fifteen. hud-speak, warm, took 0.16s and 0.26s
// to the first sound.
//
// The protocol on stdin and stdout is hud-speak's to the letter; see
// `Lines`. The bridge picks which of the two it runs with HUD_SPEAKER.

/// Lines out, one at a time, from any thread.
final class Emitter: @unchecked Sendable {
    private let lock = NSLock()
    func send(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        print(line)
        fflush(stdout)
    }
}

/// Resumes a continuation once, whichever of the end of playback and a
/// stop comes first: `AVAudioPlayerNode.stop()` fires the completion
/// handler of what was playing, and so does the sound ending.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<Void, Never>
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func fire() {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { continuation.resume() }
    }
}

struct Clip: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let sentence: String
    let generation: Int
}

enum Item: Sendable {
    case clip(Clip)
    case end(Int)
}

/// Plays clips in order and drops everything on a hush.
///
/// `generation` is bumped by `hush`; anything queued under an older number
/// is skipped when it comes up, which is how a reply that was half-made
/// when the person spoke again never reaches the speaker. An `end` is the
/// end of one `say`: everything queued before it has played, and the
/// display is told quiet. While a clip plays its envelope goes out one
/// frame at a time, on the clock, so the ring moves with the voice.
actor Player {
    /// How long the engine takes from `play()` to sound, so the envelope is
    /// not ahead of the voice. Guessed, never measured; hud-speak used 60ms
    /// for afplay opening a file, and there is no file here.
    static let lead = 0.02

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let emit: Emitter
    private let volume: Float
    private(set) var generation = 0
    private var pending = 0
    private var connectedRate: Int?
    private var attached = false
    private let items: AsyncStream<Item>
    private let feed: AsyncStream<Item>.Continuation

    init(emit: Emitter, volume: Float) {
        self.emit = emit
        self.volume = volume
        var continuation: AsyncStream<Item>.Continuation?
        items = AsyncStream { continuation = $0 }
        guard let continuation else { fatalError("AsyncStream gave no continuation") }
        feed = continuation
    }

    /// Nothing queued and nothing playing. `pending` and not
    /// `node.isPlaying`, which stays true after the last buffer has played
    /// until `stop()` is called, so `--say` waited on it forever.
    var idle: Bool { pending == 0 }

    func enqueue(_ item: Item) {
        pending += 1
        feed.yield(item)
    }

    func hush() -> Int {
        generation += 1
        if node.isPlaying { node.stop() }
        return generation
    }

    /// The output device changed (headphones in, a display with speakers
    /// out): the system stops the engine and the graph's formats may no
    /// longer match. Forget the connection so the next clip rebuilds it,
    /// which is what afplay-per-file gave hud-speak for free.
    private func reconfigure() {
        connectedRate = nil
    }

    func run() async {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
            Task { await self.reconfigure() }
        }
        for await item in items {
            switch item {
            case .clip(let clip):
                if clip.generation == generation {
                    emit.send(Lines.saying(clip.sentence))
                    await play(clip)
                    if clip.generation != generation {
                        // Cut off. Nothing queued under this generation
                        // will play, so the end marker never comes; say
                        // quiet here instead.
                        emit.send(Lines.quiet)
                    } else {
                        // Between sentences, while the next is still being
                        // made: the voice is not gone, it is between words.
                        emit.send(Lines.level(0))
                    }
                }
            case .end(let marked):
                if marked == generation { emit.send(Lines.quiet) }
            }
            pending -= 1
        }
    }

    private func play(_ clip: Clip) async {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(clip.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)),
              let channel = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        clip.samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel[0].update(from: base, count: clip.samples.count)
        }
        if connectedRate != clip.sampleRate {
            if engine.isRunning { engine.stop() }
            if !attached {
                engine.attach(node)
                attached = true
            }
            engine.connect(node, to: engine.mainMixerNode, format: format)
            node.volume = volume
            connectedRate = clip.sampleRate
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                FileHandle.standardError.write(Data("hud-voice: audio engine did not start: \(error)\n".utf8))
                return
            }
        }
        let levels = Envelope.of(clip.samples, sampleRate: clip.sampleRate)
        let marked = clip.generation
        let started = ContinuousClock.now
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Once(continuation)
            node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
                once.fire()
            }
            node.play()
            Task { [emit] in
                for (index, level) in levels.enumerated() {
                    let due = started + .seconds(Double(index) * Envelope.frame + Self.lead)
                    try? await Task.sleep(until: due, clock: .continuous)
                    if generation != marked { break }
                    emit.send(Lines.level(level))
                }
            }
        }
    }
}

/// Makes the sound, in order, one sentence at a time.
///
/// A reply arrives in parts (`say` for the first, `add` for the rest,
/// `end` when it is complete), so the first sentence of a long answer is
/// heard while the last is still being written. One worker, because two
/// making two sentences race for the player and the second can land first.
actor Speaker {
    enum Job: Sendable {
        case text(String, Int)
        case end(Int)
    }

    private let manager: KokoroAneManager
    private let voice: String
    private let speed: Float
    private let player: Player
    private let emit: Emitter
    private let jobs: AsyncStream<Job>
    private let feed: AsyncStream<Job>.Continuation

    init(voice: String, speed: Float, player: Player, emit: Emitter) {
        manager = KokoroAneManager(variant: .english, defaultVoice: voice)
        self.voice = voice
        self.speed = speed
        self.player = player
        self.emit = emit
        var continuation: AsyncStream<Job>.Continuation?
        jobs = AsyncStream { continuation = $0 }
        guard let continuation else { fatalError("AsyncStream gave no continuation") }
        feed = continuation
    }

    /// Load, and pay the first generation's compile before "ready", which
    /// is what makes the first spoken line land in under half a second.
    /// On a first run the load is a download, and the pill is told so.
    func warm() async throws {
        emit.send(Lines.status("Getting the voice ready"))
        try await manager.initialize()
        _ = try await manager.synthesizeDetailed(text: "Ready.", voice: voice, speed: speed)
    }

    func handle(_ message: Lines.Message) async {
        switch message {
        case .say(let text, let more):
            let marked = await player.hush()
            feed.yield(.text(text, marked))
            if !more { feed.yield(.end(marked)) }
        case .add(let text):
            feed.yield(.text(text, await player.generation))
        case .end:
            feed.yield(.end(await player.generation))
        case .hush:
            _ = await player.hush()
        }
    }

    func run() async {
        for await job in jobs {
            switch job {
            case .end(let marked):
                await player.enqueue(.end(marked))
            case .text(let text, let marked):
                for sentence in Lines.sentences(text) {
                    if await player.generation != marked { break }
                    do {
                        let result = try await manager.synthesizeDetailed(
                            text: sentence, voice: voice, speed: speed)
                        await player.enqueue(.clip(Clip(
                            samples: result.samples, sampleRate: result.sampleRate,
                            sentence: sentence, generation: marked)))
                    } catch {
                        FileHandle.standardError.write(Data("hud-voice: could not say \(sentence.prefix(40)): \(error)\n".utf8))
                    }
                }
            }
        }
    }
}

// MARK: - Arguments

var voice = ProcessInfo.processInfo.environment["HUD_VOICE"] ?? KokoroAneConstants.defaultVoice
var speed: Float = 1
var volume: Float = 1
var once: String?
var list = false
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    func value() -> String { arguments.isEmpty ? "" : arguments.removeFirst() }
    switch flag {
    case "--voice": voice = value()
    case "--speed": speed = Float(value()) ?? 1
    case "--volume": volume = Float(value()) ?? 1
    case "--say": once = value()
    case "--list": list = true
    case "-h", "--help":
        print("""
            hud-voice [--voice af_heart] [--speed 1.0] [--volume 1.0] [--say "text"] [--list]
            Reads JSON lines on stdin ({"say"}, {"add"}, {"end"}, {"hush"}) and writes
            {"level"}, {"saying"}, {"quiet"} and {"status"} lines; "ready" once warm.
            """)
        exit(0)
    default:
        FileHandle.standardError.write(Data("hud-voice: unknown flag \(flag)\n".utf8))
        exit(64)
    }
}
if list {
    for name in KokoroAneConstants.englishVoices { print(name) }
    exit(0)
}
if !KokoroAneConstants.englishVoices.contains(voice) {
    FileHandle.standardError.write(Data("hud-voice: no voice \(voice); using \(KokoroAneConstants.defaultVoice)\n".utf8))
    voice = KokoroAneConstants.defaultVoice
}

// MARK: - Run

let emit = Emitter()
let player = Player(emit: emit, volume: volume)
let speaker = Speaker(voice: voice, speed: speed, player: player, emit: emit)
Task { await player.run() }
Task { await speaker.run() }
do {
    try await speaker.warm()
} catch {
    FileHandle.standardError.write(Data("hud-voice: the voice did not load: \(error)\n".utf8))
    exit(1)
}
emit.send("ready")

if let once {
    await speaker.handle(.say(once, more: false))
    // Wait for every sentence to be made and the last to finish playing,
    // rather than exiting mid-sentence.
    try? await Task.sleep(for: .milliseconds(200))
    while await !player.idle { try? await Task.sleep(for: .milliseconds(50)) }
    try? await Task.sleep(for: .milliseconds(100))
    exit(0)
}

// The bridge is the only thing on the other end, and when it is killed the
// pipe does not always close. Two hud-speaks were found running after two
// bridge restarts on 2026-09-19, each holding the model.
Task.detached {
    while true {
        try? await Task.sleep(for: .seconds(2))
        if getppid() == 1 { exit(0) }
    }
}

let lines = AsyncStream<String> { continuation in
    Thread {
        while let line = readLine(strippingNewline: true) { continuation.yield(line) }
        continuation.finish()
    }.start()
}
for await line in lines {
    guard let message = Lines.parse(line) else { continue }
    await speaker.handle(message)
}
exit(0)
