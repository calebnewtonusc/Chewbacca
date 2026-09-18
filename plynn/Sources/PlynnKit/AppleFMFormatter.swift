import Foundation

// FoundationModels ships in the macOS 26 SDK and nowhere else. `@available`
// is a RUNTIME gate and does not help here: the import is resolved at compile
// time, so on a machine with the macOS 15 SDK this file failed the whole
// PlynnKit build with "no such module", after compiling 766 of 770 other
// files. Every use of the type below is already correctly guarded, so the
// only thing missing was the compile-time half of the same condition.
#if canImport(FoundationModels)
import FoundationModels

/// AI polish on Apple's on-device Foundation Model (Apple Intelligence).
/// The default polish engine — no download, Apple-tuned for the hardware.
/// Falls back to the input text on every failure mode, like all polish paths.
/// FoundationModels ships in macOS 26; below that `TranscriptFormatter` never
/// constructs this and the local Qwen model carries the polish path.
@available(macOS 26, *)
public actor AppleFMFormatter {
    public init() {}

    public nonisolated var ready: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Human-readable availability, for logs and Settings.
    public nonisolated var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled in System Settings"
        case .unavailable(.modelNotReady):
            return "model still downloading — will be used once ready"
        case .unavailable(.deviceNotEligible):
            return "this Mac doesn't support Apple Intelligence"
        case .unavailable(let reason):
            return "unavailable (\(reason))"
        }
    }

    /// Ask the system to page the model in so the first dictation is fast.
    public func warm() {
        guard ready else { return }
        LanguageModelSession().prewarm()
    }

    /// One stateless prompt → raw completion (nil on timeout/error/unavailable).
    public func complete(_ prompt: String) async -> String? {
        guard ready else { return nil }
        return await withTaskTimeout(seconds: 10) {
            try await LanguageModelSession().respond(to: prompt).content
        }
    }

    public func format(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String] = []
    ) async -> String {
        let prompt = PolishPrompt.build(
            transcript: text, tone: tone, technical: technical,
            preferredSpellings: preferredSpellings)
        return PolishPrompt.sanitize(
            await complete(prompt), input: text, glossary: preferredSpellings,
            removeRepeatedTrailingList: true)
    }
}
#endif
