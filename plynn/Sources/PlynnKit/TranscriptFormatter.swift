import Foundation

public struct FormatResult: Equatable, Sendable {
    public let text: String
    public let pressEnter: Bool
    public let verbatim: String
}

/// The full formatting pipeline: rules pass, snippet expansion, dictionary
/// correction, then optional LLM polish. Every path returns something
/// pasteable; LLM problems degrade to the deterministic output.
public actor TranscriptFormatter {
    /// `AppleFMFormatter` needs macOS 26, so it is stored type-erased and only
    /// reached through the helpers below. Nil on macOS 15, where every polish
    /// call falls through to the local Qwen model.
    private let appleFMBox: Any?
    private let llm = LLMFormatter()  // fallback when Apple Intelligence is off
    /// Reloaded per call so Settings edits apply immediately.
    private let personalization: @Sendable () -> (
        snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
    )

    public init(
        personalization: @escaping @Sendable () -> (
            snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
        ) = { ([], []) }
    ) {
        self.personalization = personalization
        if #available(macOS 26, *) {
            appleFMBox = AppleFMFormatter()
        } else {
            appleFMBox = nil
        }
    }

    // MARK: - Apple Intelligence, behind availability

    private var appleFMReady: Bool {
        if #available(macOS 26, *), let fm = appleFMBox as? AppleFMFormatter {
            return fm.ready
        }
        return false
    }

    private func appleFMComplete(_ prompt: String) async -> String? {
        if #available(macOS 26, *), let fm = appleFMBox as? AppleFMFormatter {
            return await fm.complete(prompt)
        }
        return nil
    }

    private func appleFMFormat(
        _ text: String, tone: Tone, technical: Bool, preferredSpellings: [String]
    ) async -> String {
        if #available(macOS 26, *), let fm = appleFMBox as? AppleFMFormatter {
            return await fm.format(
                text, tone: tone, technical: technical, preferredSpellings: preferredSpellings)
        }
        return text
    }

    private func appleFMWarm() async {
        if #available(macOS 26, *), let fm = appleFMBox as? AppleFMFormatter {
            await fm.warm()
        }
    }

    /// Which polish engine is live, for status display. Nil = rules only.
    public var polishEngine: String? {
        get async {
            if appleFMReady { return "Apple Intelligence" }
            if await llm.ready { return "Qwen3-4B (local)" }
            return nil
        }
    }

    /// Why Apple's model isn't in use (nil when it is).
    public var appleFMStatus: String? {
        if #available(macOS 26, *), let fm = appleFMBox as? AppleFMFormatter {
            return fm.ready ? nil : fm.availabilityDescription
        }
        return "Apple Intelligence needs macOS 26 — polishing with the local model"
    }

    /// Raw completion on whichever polish engine is live — the summarizer's
    /// backend. Nil when no engine is available.
    public func complete(_ prompt: String) async -> String? {
        if appleFMReady { return await appleFMComplete(prompt) }
        if await llm.ready { return await llm.complete(prompt) }
        return nil
    }

    /// Command mode: apply a spoken instruction to selected text.
    /// Nil = no engine or the transform failed — caller must touch nothing.
    public func transform(selection: String, instruction: String) async -> String? {
        let prompt = TransformPrompt.build(selectedText: selection, instruction: instruction)
        let raw: String?
        if appleFMReady {
            raw = await appleFMComplete(prompt)
        } else if await llm.ready {
            raw = await llm.complete(prompt)
        } else {
            return nil
        }
        let out = PolishPrompt.sanitize(raw, input: selection)
        return out == selection ? nil : out
    }

    /// Warm the polish path: Apple's on-device model when available,
    /// otherwise the bundled-model fallback (downloads on first use).
    public func warmLLM() async {
        if appleFMReady {
            await appleFMWarm()
            return
        }
        // This used to be `try?`, and the swallowed error cost a real evening.
        // An expired HuggingFace token in the shared cache made every download
        // 401, the polish model never arrived, and dictation quietly fell back
        // to the rules formatter. The symptom was "it just types what I said",
        // with nothing anywhere saying why. On macOS 15 there is no Apple
        // Intelligence to fall back to, so this model is the only polish there
        // is and its absence has to be loud.
        do {
            try await llm.ensureLoaded()
        } catch {
            NSLog(
                "plynn: POLISH UNAVAILABLE — could not load %@: %@. "
                    + "Dictation will paste the raw transcript. "
                    + "If this is a 401, check `hf auth list` for an expired token.",
                LLMFormatter.modelID, error.localizedDescription)
        }
    }

    public func format(
        _ transcript: String, context: ContextSnapshot, aiPolish: Bool
    ) async -> FormatResult {
        let (snippets, terms) = personalization()
        let rules = RulesFormatter.format(transcript)
        var text = rules.text
        text = SnippetExpander.expand(text, snippets: snippets)
        text = DictionaryCorrector.correct(text, terms: terms)
        let profile = context.profile
        if profile.isTechnical {
            text = ReferenceResolver.tagFileReferences(
                text, terms: terms, fileCandidates: context.fileCandidates)
        }
        // Latency gate: clean short dictations paste instantly; the LLM only
        // runs when there are fillers/backtracks/lists to fix or it's long.
        if aiPolish, !text.isEmpty, PolishGate.needsPolish(text) {
            let spellings = DictionaryCorrector.relevantTerms(for: text, terms: terms)
            if appleFMReady {
                text = await appleFMFormat(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            } else if await llm.ready {
                text = await llm.format(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            }
            // The LLM can regress a spelling it saw in the raw text; re-assert.
            text = DictionaryCorrector.correct(text, terms: terms)
            if profile.isTechnical {
                text = ReferenceResolver.tagFileReferences(
                    text, terms: terms, fileCandidates: context.fileCandidates)
            }
        }
        return FormatResult(text: text, pressEnter: rules.pressEnter, verbatim: transcript)
    }

    /// Backward-compatible convenience for callers that only know the app ID.
    public func format(
        _ transcript: String, bundleID: String?, aiPolish: Bool
    ) async -> FormatResult {
        await format(
            transcript,
            context: ContextSnapshot(bundleID: bundleID),
            aiPolish: aiPolish)
    }
}
