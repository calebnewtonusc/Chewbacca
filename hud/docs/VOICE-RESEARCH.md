# What the voice loop is built on

Research behind the HUD's listening and speaking path, in the format of
bob-the-builder's `docs/RESEARCH.md`: the claim, the source, and where a source
has an interest in the result, that is said rather than hidden.

Research current as of September 2026. Measurements marked "on this machine"
were taken on a MacBook Pro, macOS 15.7.3, Apple Silicon.

---

## The voice metric is time to first audio, not time to answer

NVIDIA's speech AI pages sell a pipeline (Nemotron Speech ASR, an LLM, Riva
Magpie TTS) and the vendor numbers on it are for datacentre GPUs, so they do not
transfer to a MacBook. What transfers is the metric they optimise and the shape
they optimise it into.

The metric is **time to first audio**: the gap between the person finishing and
the first sound coming back, not the time to a finished answer. NVIDIA reports
Magpie TTS at 32 ms TTFA single-stream on a B200, 47 ms on an H100, 79 ms on an
A100, and states the target the rest of the budget is sized against: an
end-to-end response inside roughly 200 ms, because that is the gap between
speakers in ordinary conversation. The model is 364M parameters and gets there
partly by predicting two audio frames per decoder step instead of one, which
halves the decoder iterations.

The budget a cascaded pipeline actually spends, from a GPU vendor's teardown and
therefore an interested source: network and VAD 30 to 80 ms, streaming ASR 100 to
300 ms, LLM time to first token 150 to 400 ms, TTS first audio chunk 100 to
200 ms, 600 ms to 1.7 s end to end. The point of quoting it is not the exact
figures. It is that a cascade is over the conversational budget before inference
finishes, so every stage has to start on the previous stage's partial output or
the sum is hopeless.

**In Kyber:** `../bin/hud-listen` already streams at two of the three
joins. It holds one Claude Code process open per session and feeds each request
as a `stream-json` turn rather than paying process start per request, and it
hands hud-speak each finished sentence as it arrives instead of the whole reply.
What it does not have is a measurement of the join that matters. Measured on
this machine, 2026-09-20: the log line `[+2.1s] voice:` on a one-line reply and
`[+2.5s] voice:` on a long one is the gap between handing the model the prompt
and handing hud-speak the first chunk, and Kokoro's generation sits on top of
that before anything is heard. Against a 200 to 300 ms conversational budget
that is roughly an order of magnitude over, and almost all of it is the model,
not the speech.

## End of turn is a model, not a silence timer

Every voice system starts with a silence timer over VAD and every one of them
outgrows it, because silence duration does not distinguish "I am finished" from
"I am thinking". Set it short and the agent cuts you off. Set it long and the
budget is spent on silence before any work starts.

The current answer is a small classifier that reads the turn and predicts
completion. LiveKit's Turn Detector v1 reads the **audio** rather than a
transcript, with a semantic branch (audio encoder, adapter into an LLM embedding
space, fine-tuned LLM) and an acoustic branch for timing and prosody, fused into
one prediction. It reports 9.9% false cutoffs at a 300 ms latency budget against
12.9% for the nearest competitor, and 4.5% at 600 ms against 5.5%. It needs no
prior turns of context, which is what keeps it fast. Weights are under LiveKit's
own model licence and LiveKit sells the hosting, so treat the comparison numbers
as an interested party's. The architecture claim is the durable part, and Pipecat
arrived at the same place independently by reading prosody straight from audio
with no transcript.

On Apple Silicon the same idea exists as an 8M CoreML model (Smart Turn v3.2,
23 languages), which is small enough that the question of whether to run it is
not a resource question.

**In Kyber:** `Sources/KyberKit/Voice.swift`. Push to talk sidesteps end of
turn entirely, which is the correct first move and why the mode exists. Wake mode
does not, and `silenceTimer` there is the timer this section is about. The
`commitGrace` band of 300 to 500 ms is sized off the same research as everyone
else's silence timer and has the same ceiling.

## The recogniser's final does arrive. The turns were being torn down

**Corrected 2026-09-21. The section below was true as an observation and wrong
as a conclusion, and the difference cost a day.**

What was recorded on 2026-09-20: every push to talk release came back from
`SFSpeechRecognizer` as error 1101 or 1110 within 7 to 78 ms of the microphone
closing, never as a final, so `commitGrace` had never fired.

What was actually happening: `PushKey.globe` read `flags.contains(.function)`
without checking the key code, so every modifier event on the machine reported a
talk-key state change. On 2026-09-20 `DoubleTap` was added in front of
`beginPush`, a stateful edge detector fed by that noisy signal, and a single
hold plus one stray release plus one stray press inside the double-click
interval read as the exit gesture. Three hours of log on 2026-09-21 carried 200
releases against 66 presses and 18 `voice.key double` fires, each one shutting
the microphone about 100 ms after it opened. The recogniser was not failing to
send a final. It was being killed before it could.

With the key code checked, the same machine and the same recogniser:

| | before | after |
| --- | --- | --- |
| `down=true` / `down=false` | 66 / 200 | 6 / 6 |
| false doubles | 18 | 0 |
| every turn | `source=error code=1110 partial_chars=0` | `source=final code=0 partial_chars=16 to 57` |
| final lag after release | never seen | 36 to 133 ms |

So the finals arrive, in 36 to 133 ms, and `commitGrace` at 0.4 s is a backstop
that rarely fires rather than one that never can. The Parakeet argument below
still stands on its own merits (an explicit end-of-utterance class beats an
error code as a commit signal), but it is no longer urgent, and it was never
the fix for this.

**The lesson worth more than the fix: a signal that is safe for idempotent
consumers is not safe for a stateful one.** `beginPush` and `endPush` could take
any amount of repeated noise, and the comment in `PushKey` said so as a defence.
The moment something with memory was attached to the same signal, the noise
became a gesture. Anything reading that key now goes through `state`, which
returns nil for events that are not the key, and the missed-release protection
the old reading bought lives in `heldByFlags`, which can only close a turn.

This is worse than a missing optimisation. The final is where the on-device
recogniser applies its revisions, proper nouns most of all, which is exactly what
the 400 ms wait was bought for. Committing the last partial means the HUD acts on
the unrevised text every single time, and the one measurement that would have
caught it is the one the code already logs.

A streaming ASR with an explicit end-of-utterance head does not have this
failure mode, because the commit signal is a class in the model's own output
rather than an error code from a task teardown. Parakeet EOU-120M is that model:
an RNN-T whose joint emits logits over vocabulary, blank, **and** an explicit EOU
class. Measured by its packagers on M-series silicon at roughly 0.056 RTF (about
18x real time), 640 ms mel chunks, about 30 ms of compute per chunk, roughly
340 ms partial latency, 120 MB INT8 CoreML, about 200 MB peak. Their own guidance
is to keep a VAD as a backstop, because background noise can make the joint emit
non-blank tokens and reset the debounce.

**In Kyber:** the relevant fact is local. `../plynn` already runs Parakeet
Unified on the Neural Engine through FluidAudio, with a Silero VAD gate at
`finish()` and a flush pad that recovers words spoken immediately before release.
That is the same vendor's ASR as the NVIDIA page is selling, already integrated,
already debugged, in the same working tree, wired into the wrong binary. The HUD
is on Apple's recogniser and Plynn is on NVIDIA's.

## Magpie on Apple Silicon is a quality upgrade, not a speed one

Magpie TTS has open weights and has been exported to CoreML and MLX for Apple
Silicon. The numbers, measured by the packagers on an M4 Pro at INT4: about
247 MB on disk, about 1.3 GB resident, batch RTF 0.23 to 0.32, and streaming RTF
**0.93** with about 120 ms first-packet latency, capped near 23 seconds of output
per run. A second port measured roughly 0.41x aggregate on an M2.

Streaming RTF of 0.93 means it generates a second of speech in 0.93 seconds. It
keeps up with playback and nothing more, on one of the fastest chips Apple makes,
with no margin for a model call happening at the same time. Kokoro-82M on the
Neural Engine is around 0.08 RTF on a phone.

So the trade is real and it is not the trade the NVIDIA page implies. Magpie buys
multilingual output and brand-specific voices from a short reference clip. It
costs roughly ten times the compute per second of speech and a hard cap on
utterance length. For a HUD whose replies are capped at twenty words and whose
first-audio budget is already blown by the model, it is the wrong place to spend.

**In Kyber:** `../bin/hud-speak` runs Kokoro-82M through MLX in Python,
which is the right model reached the expensive way. It costs a `uv` environment,
a PyTorch import, and 6 to 10 seconds of priming per session (`primed in 10s` in
`~/.bob/listen.log`), to run a model that FluidAudio runs in-process in Swift on
the ANE. The interesting move is not changing the voice model. It is deleting the
Python.

## Fillers are not an answer to latency

Sierra, who sell voice agents and so have every incentive to game this, state
that they measure time to the first **relevant** response specifically so that
filler audio cannot be used to hit the number, and that "uh-huh" is not a
strategy. What they do instead when reasoning genuinely runs long is a
context-aware interim response, which is a different thing: it is about the
request, so it is information rather than noise.

Their other three levers are all structural. Cache the phrases that recur.
Stream synthesis sentence by sentence rather than per reply. Prefetch the data
the turn is probably going to need before the model asks for it.

**In Kyber:** the second is already done, in `run_streamed`. The first is not, and
the HUD says a small closed set of things constantly (acknowledgements, "stepping
back", the presence transitions) that could be synthesised once and played from
disk at zero cost. The third is the one that matters most here, because the
measurement above says the model is the budget: 2.1 seconds to first chunk on a
reply as short as "Okay, stepping back."

## The hosted voices, and why none of them is the next move

Asked on 2026-09-21: who leads text to speech, and what is the efficient way to
put a better voice in the assistant. The survey, and then the reason it does not
change anything here.

The field as of September 2026, from vendor comparison write-ups, every one of
which is published by a party selling one of the entries or a competitor, so
read the rankings as marketing and the architecture claims as the durable part:

| | Who | The claim |
|---|---|---|
| Speed | Cartesia Sonic 4 | About 40 ms time to first audio, held under load. State space models rather than transformers, which is why the number survives concurrency. |
| Quality | ElevenLabs v3 | 70+ languages, thousands of voices, cloning, the expressiveness bar everyone else is measured against. |
| Agent pricing | Deepgram Aura-2 | About 90 ms, built and priced for agents rather than for studios. |
| Emotion | Hume Octave | Prosody directed in the prompt rather than fixed per voice. |
| Open weights | Kokoro 82M, Chatterbox (Resemble, MIT), Orpheus (Canopy, 150M to 3B) | Chatterbox clones from about five seconds of audio and took 63.75% preference against ElevenLabs in the blind tests its authors ran. Kokoro is what this repo runs. |

None of them is worth wiring in, and the reason is one measurement already in
this file. The budget is the model, not the speech: 2.1 seconds to the first
chunk, of which synthesis is roughly 0.2. A hosted voice makes the assistant
sound better and arrive later, because it adds a network round trip to the one
stage that was never the problem, plus a key on a machine that has none and a
per-character bill on a thing that talks all day. Cartesia at 40 ms is close to
latency-neutral on paper and still pays the hop.

What the survey does change is the order of the local work, which is free:

1. **`hud-voice` becomes the default speaker.** Same model, measured faster at
   both joins, and it needs no uv, no espeak-ng and no spaCy on a fresh Mac.
   The gate written into `bin/hud-listen` is a day of use, not a benchmark.
2. **A voice picker in the panel.** The model ships 54 voices and the only way
   to reach one is `HUD_VOICE` in the environment, which means nobody has ever
   changed it. Preview on select, persisted like the long-answer switch.
3. **Chatterbox is the one open model worth a spike**, and only for cloning: a
   voice the person chose, or their own, with no key and no hop. It is an order
   of magnitude larger than Kokoro, so the spike is a latency measurement on the
   ANE before it is anything else.

Revisit if the model side ever gets fast enough that 200 ms of synthesis is a
visible share of the wait. Today it is noise under a two second number.
