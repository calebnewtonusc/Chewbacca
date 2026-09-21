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

Built as:

```
b                           one, beside the pill, named by the display
b <id>                      that one, beside the pill
b <id> <x> <y> [state=] [app=] [note=]   move it there, and restate it
b <id> insert "<text>"      the cleaned text, from the bridge
b <id> off                  take it down
b clear                     take them all down
```

and back the other way:

```
b <id> <state> [app="..."] [note="..."]   it was dropped, refused, orphaned
b <id> said "<text>"                      a sentence went into the field
b <id> clean "<text>"                     tidy this up, quickly
```

**A bare `b` is the spawn, and the point is optional.** The design had a bubble
placed by coordinates, on the reasoning that `bin/hud-guide` already finds a
field's rectangle and could land one directly. That is still true and the
coordinate form still exists for it, but where a *new* bubble goes is the
display's question, not the sender's: it goes beside the pill, and the pill's
position depends on its measured width and on which display the glass is
currently on. A sender computing that gets it wrong on a second monitor.

The insert carries a JSON string rather than `text=`, matching `s` and `h`
rather than the prop-list verbs, because a dictated sentence has spaces in it
and a prop reader takes the first word.

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

1. Find the frontmost ordinary window under the point that is not ours, from
   `CGWindowListCopyWindowInfo`, and take its pid.
2. `AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), x, y)`.
3. Walk up `kAXParentAttribute` to the first element whose role is
   `AXTextField`, `AXTextArea` or `AXComboBox`, or whose subrole is
   `AXSearchField`.
4. Store the element, its pid, and the application's name.

**Step 1 is not in the design and the feature does not work without it.** The
plan asked the system-wide element, which answers with whatever is topmost at
that point. The bubble is drawn on a window of this application directly over
the field, so every bind came back with the display's own glass: the bubble
bound to itself. Hit-testing inside the owning application is what makes the
question mean "what is under the bubble" rather than "what is on top", and it
needs no screen recording permission, because the window list gives bounds and
owner pid without it and only titles are gated.

Layer zero only, in that filter. The Dock sits at 20 and this display's glass at
3, so excluding our own pid also excludes every other floating panel on the
machine. That is the right default: a dictation bubble belongs on a document or
a message field, and another application's HUD is not one.

Nothing text-shaped under the point and the bubble **stays where it was dropped**
and says "no text field there" in its own caption. That is a change from the
design, which had it snap back to the pill. Snapping back was chosen to stop a
bubble bound to nothing looking identical to a bound one, and the six states
solve that better: `unbound` has a different glyph, a different rim and a
different label from `idle`, visible from across the desk. Given that, staying
put is strictly better, because the person aimed at something and moving the
bubble hides what they aimed at.

**A field whose `kAXSubroleAttribute` is `AXSecureTextField` is refused at bind
time**, with the reason said out loud. A dictation tool that can be aimed at a
password box will eventually be aimed at one, and the transcript of a password
goes through a model under the cleanup rule below.

## Tracking

While a bubble exists, read `kAXPositionAttribute` and `kAXSizeAttribute` on the
bound element every `POLL`. The element vanishing moves the bubble to
`orphaned`.

**It moves by the field's delta, not to the field's edge, and that is a
correction the probe forced.** The first version pinned the bubble to the
trailing edge of the bound element, on the reasoning that a send button lives
there and it is the part of a text box least likely to hold text somebody is
reading. Then the probe bound to the middle of a Terminal window and the field
came back as `230,-255 2117x1631` for a window about 1100 points tall, because
an `AXTextArea`'s frame covers the whole scrollback rather than the visible box.
Pinning to that edge threw the bubble hundreds of points from where it was
dropped, and clean off the top of the screen in a long buffer.

So the drop records where the field was and where the bubble was, and each poll
moves the bubble by however far the field has moved. It is zero while the window
is still, it is exact while the window is dragged, and it cannot be wrong about
a field whose frame is nothing like its visible box. Editors, terminals and mail
compose bodies are all that shape, so this was not an edge case.

The result is clamped to the glass. A window dragged most of the way off screen
should take its bubble with it, right up until the bubble is the part that has
gone: at -40 it cannot be clicked or moved and the only way back is
`hud-bubble clear`. It stops at the edge instead, still bound, and comes back
when the window does.

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

**Built without a new mode, and that is a change from the design.** The plan
put `.dictation` beside `.off`, `.pushToTalk` and `.wake` inside
`VoiceListener`. What shipped leaves that class untouched and forks outside it:
`AppDelegate.dictating` holds which bubble owns the open turn, and
`dictationSignal` consumes `.partial`, `.heard`, `.failed`, `.level` and
`.listening` before the assistant's handler sees them.

The reason is the lesson in `hud/docs/VOICE-RESEARCH.md`, written the same day
and paid for with a day: **a signal that is safe for idempotent consumers is not
safe for a stateful one.** `VoiceListener` holds one microphone, one recogniser
and one turn counter, and the deafness bug came from attaching something with
memory to a signal feeding it. A `.dictation` mode would have put a second state
machine inside the class that already holds the fragile one. The fork outside it
cannot be reached by anything the bubble does, and push-to-talk's own tests
still pin its behaviour unchanged.

One `AVAudioEngine` and one `SFSpeechRecognizer` either way, so the two paths
cannot both be live: there is one microphone and one person talking.

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

The `SILENCE` backstop is its own task in the display rather than wake mode's
`silenceTimer`, for the reason above: that timer belongs to a mode this feature
does not enter. It restarts on every `.partial`, so a revision is a sign of
life.

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

**`kAXValueAttribute` is never a tier, and the spike is why.** Probed read-only
on 2026-09-21 with `AXUIElementIsAttributeSettable`, which answers "would a
write land" without writing:

| field | `kAXSelectedText` | `kAXValue` |
| --- | --- | --- |
| Chrome, omnibox | YES | YES |
| Terminal, toolbar search | no | YES |
| Mail, toolbar search | no | YES |
| Terminal, the shell itself (`AXTextArea`) | **no** | not probed |

Every field that refused `kAXSelectedText` still offered `kAXValue`, which is
the trap. Setting a value replaces the **entire** contents of the field, so a
bubble reaching for it as a fallback would silently delete a half-written
message to insert a sentence at the end of nothing. It is the one attribute that
looks like the easy answer and is the only one that destroys work, so the
fallback stays `peekaboo paste`, which inserts at the caret and keeps what is
already there.

The last row was measured on 2026-09-21 against the built `TextTarget`, with a
throwaway probe that binds and asks but never writes. It matters more than the
others: the shell is the single most likely place to want dictation that is not
a message box, and it is a hard no on tier 1. **Tier 2 is the path for
Terminal**, which is the strongest argument in this document for the clipboard
tier existing at all.

The rest of the table is incomplete on purpose: an app in the background exposes
little or nothing of its text tree, so Messages and Notes returned no text
element at depth 14 and Terminal and Mail returned their toolbars rather than
their real inputs. Finishing it needs each app frontmost with a caret in it,
which needs the machine for a minute. What the runs did settle is that the
settable check discriminates, that the two-tier split is real rather than
theoretical, and that hit-testing inside the owning application reaches past
this display's own glass.

## Cleanup

On stop, the bubble's raw transcript goes to the bridge and the cleaned text
comes back:

```
HUD    -> b b1 clean "hey so um can you tell caleb comma i am running late"
bridge -> haiku, one turn: punctuate, capitalise, remove filler words,
          change nothing else, return only the text
bridge -> b b1 insert "Hey, can you tell Caleb I'm running late?"
```

The bridge owns this because the bridge owns every model call in this system.
It is also the only thing in the feature that crosses the socket.

**Two passes, not one, and the split is load-bearing.** `Bubble.punctuate` runs
in the display on every transcript and is deliberately conservative: the
multi-word forms ("question mark", "new paragraph") anywhere, and a single word
like "period" or "comma" only as the last word of the utterance. That floor is
what makes the hop optional rather than required.

It stops there because "a period of time", "the colon", and "put a comma after
the name" are all real sentences, and a rule that fired mid-utterance turned the
first into "a. of time". Destroying a sentence to save a full stop is the wrong
trade, so the aggressive half is the model's, which reads the whole sentence and
can tell the two apart. That is the hop's reason to exist. Without the
deterministic floor it would be a nicety; with it, the division is real.

**The race is settled by a token, not by arrival order.** Two paths reach the
insert, the answer and the timeout, and a text field takes both happily: a
sentence typed twice is worse than a sentence typed without a comma. Each turn
takes a token, the loser finds the token gone and does nothing. Same pattern as
`VoiceListener.turn`, which exists for the same reason.

**Nobody listening is answered at once, not after the budget.** The display
knows whether a line was delivered, so a `clean` request that reached no bridge
commits the deterministic version immediately. Waiting out 1.5 seconds of
nothing in front of somebody who just finished speaking is the version of this
that feels broken.

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
| `dictationSilence` | 6.0s | **Raised from the 2.0s in this design, deliberately.** Two seconds is the gap at which a person notices silence in a conversation, which is the right number for turn-taking and the wrong one for dictation: it fires while somebody is composing the second half of a sentence. Click-again is the primary way out, so this is a backstop and a backstop that cuts people off is the failure mode every silence timer in `hud/docs/VOICE-RESEARCH.md` outgrew. Guessed, never measured against this gesture. |
| `Bubble.poll` | 0.1s | Guessed against the eye. The bubble must not visibly trail a window being dragged, and 10Hz is the coarsest rate that does not read as lag. Never measured past 30Hz, where the only difference on this machine was three times the IPC. |
| `TextTarget.timeout` | 0.05s | One hard constraint: it must stay below `poll` or a hung app queues polls until the display stalls. Measured 2026-09-21: a settled application answers a position read in under 2ms, and only Chrome during a page load ever approached it. A timeout means "unchanged", so the bubble holds still for a frame. |
| `cleanupBudget` | 1.5s | Guessed. No measurement of a haiku turn from this bridge exists; the first week of `b clean` lines replaces this number with one. |
| `Bubble.size` | 34pt | Smaller than the 44pt Fitts's law floor on purpose, because the thing it sits on is a text field 22pt tall and a 44pt circle covers the field it points at. `hitFrame` pads to 44, so the target meets the floor while the circle stays out of the way. |
| `Bubble.clickSlop` | 4pt | Not zero, because pressing a physical trackpad moves the cursor a point or two, and at zero roughly one click in four became a one-pixel drag: it rebound to the same field and did not start the turn, which reads as the bubble ignoring the click. |
| `TextTarget.maxHops` | 6 | The probe's worst case doubled. Chrome's omnibox was three hops above the deepest hit. Walking further returns the window, which accepts a value set and puts the text nowhere. |
| `OverlayModel.maxBubbles` | 3 | One is the case. Three because dictating into a chat and a terminal at once is a real thing to want; past that a click near two of them is ambiguous. At the cap the oldest is recycled rather than the new one refused: a silent no is indistinguishable from the feature being broken. |

Every dictation writes a line with the tier that inserted, the transcript
length, and whether the timeout fired: `log show --predicate 'subsystem ==
"bob.hud" AND category == "bubble"'`. That is the data for moving all four.

## The spike

Run read-only on 2026-09-21 and reported in Insertion above. It settled the
design question it existed for, that the two tiers are real and that `kAXValue`
must not be one of them, and it ruled out a permission blocker
(`AXIsProcessTrusted` is true).

**Still open:** the per-app table, which needs each app frontmost with a caret
in its real input rather than probed from the background. Worth finishing before
tier 2's share of traffic is quoted anywhere, and not worth blocking the build
on, because the code path is the same either way.

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
As built, which differs from the plan above in three places: no `Voice.swift`
change, the AX work in its own file rather than split in two, and the behaviour
in the executable rather than the kit, because it drives the microphone and the
window server and the kit owns neither.

| File | Change |
| --- | --- |
| `hud/Sources/BobHUDKit/Bubble.swift` | new: the six states, the geometry, `punctuate` |
| `hud/Sources/BobHUDKit/TextTarget.swift` | new: binding, following, the AX write |
| `hud/Sources/BobHUDKit/BubbleView.swift` | new: the circle, the ring, the caption |
| `hud/Sources/BobHUD/Dictation.swift` | new: the gesture, the turn, the two insert tiers |
| `hud/Sources/BobHUDKit/Spec.swift` | `bubble`, `spawnBubble`, `unbubble`, `bubbleInsert` |
| `hud/Sources/BobHUDKit/LineParser.swift` | the `b` verb, all five forms |
| `hud/Sources/BobHUDKit/Interaction.swift` | `bubble`, `dictated` and `clean` going back |
| `hud/Sources/BobHUDKit/OverlayModel.swift` | the bubbles, the spawn point, the hit test, `frames` |
| `hud/Sources/BobHUDKit/OverlayView.swift` | draw them, on one 20Hz clock |
| `hud/Sources/BobHUD/main.swift` | the monitors, the voice fork, the undelivered `clean` |
| `bin/hud-bubble` | new: the spoken vocabulary, `parse(said)`, `doctor` |
| `bin/hud-listen` | ask `hud-bubble.parse` first, ahead of the music and the router |
| `hud/Tests/BobHUDKitTests/BubbleTests.swift` | new: 27 tests, the wire and the glass |
| `tests/test_hud_bubble.py` | new: the vocabulary, including what must not match |
| `tests/run.sh` | register it |

Still to do: `bin/hud-agent.md` (when to put a bubble up), `hud/CLAUDE.md` (the
`b` verb in the vocabulary), and the bridge's haiku turn for `b <id> clean`,
which the deterministic floor makes optional rather than blocking.

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
