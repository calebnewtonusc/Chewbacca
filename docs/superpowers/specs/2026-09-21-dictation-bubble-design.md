# The dictation bubble: point at the field, then talk into it

Gavin, 2026-09-21. Approved shape: a bubble he drags onto any text input, bound
to that field's accessibility element rather than to a spot on the screen, click
to start and click again to stop, the transcript cleaned by a model before it
lands. All of it in Swift except the model call.

## The problem

Push to talk gets words to the assistant. Nothing gets words into the field the
person is actually looking at. Today dictating a text message means saying it to
the assistant and asking it to send, which is three hops and a name that has to
be heard right, or reaching for Apple's dictation, which has no idea what
Chewbacca knows.

Every tool in this genre (Wispr Flow, superwhisper, MacWhisper) solves it the
same way: the text goes **wherever the caret already is**, so the person has to
click into the field first and the tool has to be told to start by a hotkey.

This does it the other way around. The bubble is the destination, placed once
and reused, and the caret never has to be found. That is the whole idea and it
is also the hard part, because the bubble has to put text into a field it is
only sitting on top of.

**The reason it is worth building is disambiguation, not convenience.** Gavin,
2026-09-21: "this is due to now having the regular agent be confused with talk
to text when i ask regular questions to the assistant."

That is the same failure the router has, arriving from the other side. `route.py`
tries to infer a destination from the frontmost app, a warm history and a
classifier, and the log for 2026-09-21 shows what inference costs: 7 of 11
sentences went somewhere the person did not mean. A bubble removes the inference
entirely. Clicking it says where the words go, with a rectangle, and no
classifier is consulted, no destination is warm, and no frontmost app is read.

So the bubble is not a nicer dictation tool. It is the explicit-destination
escape from a guess that keeps being wrong, and it should be judged on whether
it makes the guess unnecessary rather than on how it feels.

## What this is not

It does not touch push to talk, the wake word or the pill. A bubble is a second
consumer of the same microphone and the rules below make the two mutually
exclusive by construction rather than by care.

A sentence spoken into a bubble never reaches `route.py` at all, because its
destination is already known. That takes work away from the router without
changing a line of it, and fixing the router is still its own job.

It does not read the screen. The bubble knows one accessibility element and
nothing else about what is on the display.

## The object

One bubble per `id`, so several can exist at once: one parked on iMessage, one
on the Terminal. Each is a small draggable disc on the glass with a ring that
pulses while it is live and the transcript running under it.

| State | What it means | What a click does |
| --- | --- | --- |
| `unbound` | just spawned, sitting at its home by the pill | says "drag me onto a text box", and nothing else |
| `idle` | bound, and its app is frontmost | starts dictating |
| `dimmed` | bound, its app is behind or hidden | nothing, and the pill says which app it is waiting for |
| `live` | microphone open, words accumulating on the bubble | stops and inserts |
| `thinking` | stopped, the cleanup call is in flight | nothing |
| `orphaned` | the element is gone | nothing; the bubble fades after saying so |

`dimmed` is the safety property, not a nicety. A bubble that fires while its app
is behind is a bubble that types a sentence into whatever happens to be in
front, which is how "running ten late" becomes a shell command.

`unbound` answers a click with words rather than silence. A bubble that looks
ready and does nothing is the failure the pill spent today teaching: "Did not
catch that" said to somebody whose microphone had already been torn down.

## The socket verb

```
b <id> <x> <y>              deploy at a point, or move an existing one there
b <id> off                  take it down
b <id> insert text="..."    the cleaned text, from the bridge
```

`b <id> <x> <y>` places a bubble and binds it in one step. `bin/hud-guide`
already walks the front window's controls to find a field's coordinates, so
"put a bubble on my messages" can land one directly. Dragging is for correcting
it, and for the apps whose fields the tree does not expose.

## How a bubble is asked for

Out loud, and never through the model.

> "spawn a bubble", "create a bubble", "generate a bubble", "make me a bubble",
> "drop a bubble", "new bubble", "put a bubble on this"
>
> and to take it away: "take the bubble down", "close the bubble",
> "get rid of the bubble"

`bin/hud-bubble` owns that vocabulary as one regular expression per verb and
exposes `parse(said)`, and the bridge asks it before anything else, exactly as
it already asks `bin/hud-music` at `bin/hud-listen:1906`. When `parse` answers,
the bubble is placed, one sentence is spoken, and **the model is never called
and `route.py` is never consulted.**

This is not an optimisation. It is the whole point of the feature. A request for
a bubble that went through the router would be routed by the same broken
inference the bubble exists to escape: with Terminal in front on 2026-09-21,
"create a bubble" would have come back as a drafted terminal prompt asking what
to draft. A feature whose purpose is to remove a guess cannot be summoned
through that guess.

The same reasoning puts the phrases in a module rather than in the prompt. A
prompt instruction is advice the model can weigh against everything else in its
context. A regex is not.

## Where it spawns

Next to the hyper bar, every time, unbound. Gavin, 2026-09-21: "it needs to
spawn next to the hyper bar, then i can drag it to any window that i want to
use talk to text for."

One home, one gesture, no inference. The earlier draft of this section guessed:
under the pointer if it happened to be over a field, else the front window's
first text field, else centre screen. That is three rules to learn and it is the
same instinct the router already proves wrong, applied to geometry instead of
destinations. A fixed home is muscle memory.

The home is **to the left of the pill**, vertically centred on it, with a 12pt
gap. The pill is bottom centre at `PillView.maxWidth` 440, and the presence ring
owns bottom-trailing at `bottomInset + 14`, so the right-hand side is taken. A
bubble that sat right of the pill on a wide display and flipped left on a narrow
one would have no home at all, which is the one property this rule is for.

Spawning never binds. The bubble arrives `unbound` and stays there until it is
dropped on something text-shaped, so a bubble is only ever aimed by hand. It
does not return home once moved, and the home is free again for the next one.

## Binding

On deploy, and again on every drag release:

1. `AXUIElementCopyElementAtPosition(systemWide, x, y)`.
2. Walk up `kAXParentAttribute` to the first element whose role is
   `AXTextField`, `AXTextArea`, or `AXComboBox`.
3. Store the element, its pid, and the owning app's bundle identifier.

Nothing text-shaped under the point means the bubble snaps back to where it was
and the pill says "no text field there". Snapping back rather than staying is
deliberate: a bubble bound to nothing looks identical to a bound one, and the
person finds out by speaking a sentence into a void.

**A field whose `kAXSubroleAttribute` is `AXSecureTextField` is refused at bind
time**, with the reason said out loud. A dictation tool that can be aimed at a
password box will eventually be aimed at one, and the transcript of a password
goes through a model under the cleanup rule below.

## Tracking

While a bubble exists, read `kAXPositionAttribute` and `kAXSizeAttribute` on the
bound element every `POLL` and draw against the result. The element vanishing, or
the read failing twice in a row, moves the bubble to `orphaned`.

Foreground and background come from
`NSWorkspace.didActivateApplicationNotification` compared against the stored
bundle identifier. That is an event, so `idle` and `dimmed` cost nothing between
app switches.

**The hazard here is that an accessibility read is synchronous IPC into another
process.** A busy or beachballed app blocks whoever asked. The poll therefore
runs off the main actor and sets `AXUIElementSetMessagingTimeout` to `AX_TIMEOUT`,
which has to stay under `POLL` or the polls stack up behind each other. Without
both, the entire heads-up display stutters whenever any app the person has a
bubble on hangs, and the cause would be nearly impossible to find from the
symptom.

## The microphone

`.dictation` joins `.off`, `.pushToTalk` and `.wake` as a mode of the existing
`VoiceListener`. One `AVAudioEngine` and one `SFSpeechRecognizer`, as now, so the
two paths cannot both be live: there is one microphone and one person talking.

| Event | What happens |
| --- | --- |
| click an `idle` bubble | mode goes to `.dictation`, microphone opens, `.partial` signals route to that bubble instead of the pill |
| click a `live` bubble | commit: microphone closes, state goes to `thinking`, and insertion follows the cleanup hop below |
| `SILENCE` of quiet | same as a second click |
| Escape | cancel: microphone closes, nothing is inserted, nothing is sent to the model |
| talk key down while live | **commit as above, then hand the microphone to push to talk** |
| click a second bubble while one is live | the live one commits first, then the second goes live |
| the live bubble's app leaves the foreground | microphone closes, the text stays on the bubble, and nothing is inserted until that app is frontmost again and the bubble is clicked |

That last row is the rule Gavin approved on 2026-09-21, and it is chosen over
the two alternatives on purpose. Ignoring the talk key would add a state where
the assistant cannot be reached until the person finds the bubble again.
Discarding the sentence would make a stray keypress cost a paragraph. Committing
loses nothing and matches the rule the rest of the loop already runs on, which
`docs/VOICE-DESIGN.md` states as: what they most recently asked for is what they
mean.

The `SILENCE` backstop reuses the `silenceTimer` that wake mode already has.

The last two rows both exist because there is one microphone and one caret. Two
live bubbles would mean two transcripts racing for one recogniser. Inserting
into an app that just went behind would mean tier 2 pasting into whatever came
forward, which is the same failure `dimmed` exists to prevent, arriving through
a different door: the app was frontmost when the person started talking and is
not when the text is ready. Holding the text on the bubble makes that visible
rather than silent, and costs one click.

**v1 keeps `SFSpeechRecognizer`.** `hud/docs/VOICE-RESEARCH.md` records its real
weakness: the final never arrives, so every turn commits an unrevised partial
with proper nouns intact from the first guess. The cleanup pass below fixes
capitalisation and punctuation regardless, which is most of what the final would
have bought. Parakeet through FluidAudio, already in this tree under `plynn`, is
the upgrade after this ships, not a prerequisite for it.

## Insertion

Two tiers, in order, and **never a synthetic click on the field**:

1. Set `kAXFocusedAttribute` true on the bound element, then set
   `kAXSelectedTextAttribute` to the text. This inserts at the caret and does not
   touch the clipboard.
2. On any result other than `.success`, `peekaboo paste`, which sets the
   clipboard, sends Command-V, and restores what was there before.

A click is excluded rather than merely unpreferred. It moves the caret, it can
collapse a selection the person meant to keep, and it is the action most likely
to do something surprising inside an app nobody here controls. Tier 1 already
puts the caret where it needs to be for tier 2 to work.

Which tier runs where is unknown until the spike below measures it. The design
holds either way; only the expected latency changes.

## Cleanup

On stop, the bubble's raw transcript goes to the bridge and the cleaned text
comes back:

```
HUD    -> e dictate id=msg text="hey so um can you tell caleb..." app=com.apple.MobileSMS
bridge -> haiku, one turn: punctuate, capitalise, remove filler words,
          change nothing else, return only the text
bridge -> b msg insert text="Hey, can you tell Caleb I'm going to be about ten minutes late?"
```

The bridge owns this because the bridge owns every model call in this system.
It is also the only thing in the feature that crosses the socket.

**On `CLEAN_TIMEOUT` with no answer, the raw transcript is inserted instead.** A
sentence is never lost to a model being slow, and a person who watched the
bubble hear them correctly and then got nothing would stop trusting the feature
in one afternoon.

The transcript is the person's own speech, so it is not untrusted content in the
sense `.claude/rules/untrusted-content.md` means. The prompt still says return
only the text, because a transcript can contain a sentence shaped like an
instruction and the answer goes straight into an app.

## Constants, and what set them

| Name | Value | Evidence |
| --- | --- | --- |
| `SILENCE` | 2.0s | Chosen by Gavin from three stop mechanisms, 2026-09-21. `docs/VOICE-DESIGN.md` puts two seconds at the point where a person notices a gap in conversation, which is the same threshold at which a speaker has clearly finished rather than paused. Not measured against real dictation. |
| `POLL` | 0.1s | Guessed against the eye. The bubble must not visibly trail a window being dragged, and 10Hz is the coarsest rate that does not read as lag. Never measured. |
| `AX_TIMEOUT` | 0.1s | Guessed, with one hard constraint: it must stay below `POLL` or a hung app queues polls until the display stalls. |
| `CLEAN_TIMEOUT` | 1.5s | Guessed. No measurement of a haiku turn from this bridge exists yet; the first week of `e dictate` lines should replace this number with one. |

Every dictation writes a line with the tier that inserted, the transcript
length, the model round trip, and whether the timeout fired. That is the data
for moving all four.

## The spike, before any of the above

Tier 1 against Messages, Terminal, Mail and Chrome, in a throwaway binary, with
a scratch TextEdit window as the control. The output is a four-row table saying
which apps accept `kAXSelectedTextAttribute`.

It is first because it decides whether tier 2 is a rare fallback or the normal
path, which changes the expected latency of the whole feature and would be
expensive to discover after the state machine is written. It is throwaway: the
answer is kept, the code is not.

## Testing

- The state machine, every transition in the table above, against a faked
  accessibility provider. No real apps.
- `orphaned`: the element disappears mid-poll, and the bubble does not fire.
- The `AXSecureTextField` refusal at bind time.
- Tier 1 failing over to tier 2, with a stubbed element that refuses
  `kAXSelectedTextAttribute`.
- `CLEAN_TIMEOUT` firing, and the raw transcript landing.
- The talk key arriving while live: the text is inserted, and push to talk gets
  the microphone.

Swift tests alongside `hud_voicePackageTests`.

## Files

| File | Change |
| --- | --- |
| `hud/Sources/BobHUDKit/DictationBubble.swift` | new: the state machine, binding, tracking |
| `hud/Sources/BobHUDKit/TextInsertion.swift` | new: the two tiers |
| `hud/Sources/BobHUDKit/Voice.swift` | the `.dictation` mode and the talk-key rule |
| `hud/Sources/BobHUDKit/SocketServer.swift` | the `b` verb |
| `hud/Sources/BobHUDKit/Overlay.swift` | register each bubble's rect as an interactive surface |
| `hud/Sources/BobHUDKit/OverlayView.swift` | draw the bubble, the ring, the transcript, the drag |
| `bin/hud-bubble` | new: the spoken vocabulary, `parse(said)`, and the command form |
| `bin/hud-listen` | ask `hud-bubble.parse` before the router; `e dictate` to haiku to `b <id> insert`, with the timeout |
| `bin/hud-agent.md` | when to deploy a bubble and how to place it |
| `hud/CLAUDE.md` | the `b` verb in the vocabulary |

## Later, deliberately not now

- Parakeet through FluidAudio in place of `SFSpeechRecognizer`.
- A per-app cleanup rule, raw in Terminal and cleaned in prose apps. Offered and
  not taken on 2026-09-21; revisit once the spike says how often a bubble ends
  up on a terminal at all.
- Voice commands inside dictation ("new line", "scratch that").
- Bubbles surviving a HUD restart.

## Sources

- Wispr Flow help, "Fix text not pasting after dictation": the accessibility
  path first and a clipboard fallback, which is the same two tiers, from a
  vendor selling the result
- superwhisper, on running system-wide wherever the caret lands, including
  terminals and editors
- `docs/VOICE-DESIGN.md`, for the two second threshold and the most-recent-wins
  rule the talk-key row follows
- `hud/docs/VOICE-RESEARCH.md`, for why `SFSpeechRecognizer` commits an
  unrevised partial and what replaces it later
