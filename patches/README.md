# Patches

## plynn-macos15.patch

Lets [Plynn](https://github.com/31Carlton7/plynn) build and run on macOS 15 (Sequoia). Upstream targets macOS 26.

Plynn is by **Carlton Aikins** and is MIT licensed. This patch is a derivative of his source and inherits that license. It is applied to a fresh clone of his repository at install time, so nothing here vendors or redistributes his app.

### What it changes

The manifest claimed macOS 26, but every dependency supports macOS 14 or lower (FluidAudio 14, MLX 13.3, Sparkle 10.13). Only three features actually needed 26, and each already had a fallback in the codebase:

| macOS 26 feature                             | Falls back to                                     |
| -------------------------------------------- | ------------------------------------------------- |
| FoundationModels (Apple Intelligence polish) | Local Qwen3-4B via MLX                            |
| SpeechAnalyzer / SpeechTranscriber           | Parakeet via FluidAudio                           |
| Liquid Glass                                 | `.ultraThinMaterial` under the existing rim light |

`AppleFMFormatter` and `AppleSpeechEngine` become `@available(macOS 26, *)`. `TranscriptFormatter` holds the formatter type-erased and reaches it through availability-checked helpers. `EngineManager` substitutes a stub below 26, and `EngineChoice.select` takes an `appleAvailable` flag so it forces Parakeet when there is no Apple engine to fall back to.

Dropping the deployment target to 15.0 is what actually fixes loading: the linker then weak-links FoundationModels and Speech, so missing symbols resolve to null instead of aborting in dyld. Verified `minos 15.0`, `sdk 26.0`, both frameworks marked `weak`.

It also turns off Sparkle background checks, because upstream releases are built for macOS 26 and would replace a working install with one that cannot launch.

### What it costs

No Apple Intelligence polish (the local Qwen model does it instead, and downloads about 2.3 GB on first use). No zero-download bootstrap engine, so the first launch has no dictation until Parakeet finishes downloading, about 1 GB. Glass renders as a plain translucent material.

On macOS 26 none of this applies. `bin/install-plynn.sh` downloads Carlton's notarized release there instead.

### Verified against

Upstream `main` at the time of writing, applying cleanly with `git apply`. 135 tests pass on macOS 15.6.1. If upstream moves and the patch stops applying, the installer says so rather than half-applying it.

The full method, written up generically, is in [docs/SWIFT-MACOS-PORTING.md](../docs/SWIFT-MACOS-PORTING.md).
