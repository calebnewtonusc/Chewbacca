import Foundation

/// Stands in for `AppleSpeechEngine` on macOS versions without SpeechAnalyzer.
/// It never becomes the active engine (`EngineChoice.select` forces Parakeet
/// when Apple's engine is unavailable), but `EngineManager` still needs a
/// concrete value for its `apple` slot.
public actor UnavailableSpeechEngine: DictationEngine {
    public enum EngineError: Error { case requiresMacOS26 }

    public nonisolated let displayName = "Apple (needs macOS 26)"

    public init() {}

    public func start() async throws { throw EngineError.requiresMacOS26 }
    public func setPartialCallback(_ callback: @escaping @Sendable (String) -> Void) {}
    public func append(samples: [Float]) async throws { throw EngineError.requiresMacOS26 }
    public func finish() async throws -> String { "" }
}
