# How the voice answers, and why

The rules `bin/hud-agent.md` gives the model and the two things `hud listen`
does around it, with where each came from. Read this before changing how the
assistant talks; the prompt is the artifact, this is the reasoning.

## The moment after the key comes up

Three things happen, in this order, and each covers a different gap.

1. **Receipt, at 0 s.** The band moves and the pill shows the sentence the
   moment the press is heard. A 40 ms tone (`Earcon`, "Sound when heard") is
   there for anyone who wants it and off by default: it shipped on, and a day
   of use said a tone on every release is a tone on every sentence. Alexa's
   Brief Mode went the other way for the same reason, replacing spoken
   confirmations with a chime: receipt is a signal, not a sentence.
2. **The model's first sentence, at about 1 s.** Under the lean profile the
   first words arrived 1.0 to 1.7 s after the prompt (2026-09-20). For a task
   that sentence says back what is being done, in the person's terms, then a
   short acknowledgement: "Texting Caleb you're running ten late. On it."
3. **A filler, only past 2 s.** If the model has said nothing by then, the
   bridge says "Okay." for a task or "Let me see." for a question, and the
   model's words queue behind it instead of cutting it off.

The filler threshold is the one number here with real evidence behind it.
Studies of conversational agents from 2019 to 2025 agree that a filler improves
perceived response time once the wait passes roughly two seconds, that quality
of experience degrades past four, and that a filler shaped to the request
("Checking the forecast for Boulder") beats a generic one ("um"). Under two
seconds a filler is talk over the answer. Google Duplex found the same in its
user studies: disfluencies made calls sound more familiar, and quick, simple
utterances needed instant replies while complex ones could take a beat.

## Confirmation

Google's conversation design guide, which is the most complete published set
of rules from a team that shipped a voice assistant to hundreds of millions of
people, sorts confirmations four ways and the prompt follows it:

- **Implicit confirmation of the details, most of the time.** "Dentist,
  Tuesday at two. Booking it." The details are the confirmation. Never "I heard
  you say", never a restatement of the yes or no.
- **Implicit confirmation of the action, unless self-evident.** "Sent."
  "Booked." A result said as a result.
- **Explicit confirmation, rarely.** Only before what cannot be undone or costs
  them: sending mail, deleting, calling, paying. One line: "That's the call
  with Caleb at three. Delete it?"
- **No confirmation** when the answer itself shows understanding: "It's one
  thirty-six."

Gavin's own earlier rule stands with it: no cancel window on a spoken request.
Release the key, think, reply, act.

## Sounding like a person

From the same guide, OpenAI's Realtime prompting guide, and Sesame's work on
voice presence, reduced to what a text-only prompt can do (Kokoro has no
prosody control, so the words carry all of it):

- **One breath per sentence.** Speech cannot be skimmed; the longer the floor
  is held the more it costs the listener. Under fifteen words is the norm.
- **Known thing first, new thing last.** "Your next call is at three." The
  end of the sentence is where the ear puts the stress.
- **Contractions always. Times and dates as spoken.** "Three fifteen", "the
  twenty-first". Never an id, a URL or a hash aloud.
- **Sample lines over prose rules.** OpenAI's guide is blunt that the model
  follows example phrases far more closely than descriptions, and Bob's own
  catalog work found the same. The prompt carries a dozen request-to-reply
  pairs and the rotation of acknowledgements.
- **Vary the wording.** The same guide names repetition as the first tell of a
  robot. No two answers open the same way; no acknowledgement twice running.
- **A persona, stated.** Every voice projects one whether designed or not
  (Google Design). Calm, quick, dry, warm, matching the person's register.
- **Hesitate when unsure.** Duplex used hesitant phrasing when its confidence
  was low; Sesame's team calls it embracing imperfection. "I think that's
  Tuesday, checking" is more human and more honest than a confident wrong date.
- **Nothing promotional or instructional.** No "let me know if you need
  anything else", no "you can also ask me to". Speech is for moving forward.

## Where a sentence goes

Since 2026-09-20 a sentence is routed before it is answered. The rules live in
`bin/lib/route.py` and the table that pins them is `tests/test_route.py`; the
design and the evidence are in
`docs/superpowers/specs/2026-09-20-voice-routing-design.md`.

The short version: "in terminal" or "in chrome" at the start wins; a
correction ("no, the terminal") inside fifteen seconds re-routes the last
sentence; a person-shaped act (text, remind, call, a known name) is the
assistant's whatever is on screen; a continuation ("and add tests", "fix
that") follows whichever destination was used in the last ten minutes; the
frontmost app decides next; "look up" and "search" go to Chrome; and one haiku
call settles the rest, with three seconds to answer before the warm
destination wins.

Nothing is submitted to the terminal by the machine. A terminal sentence
becomes a drafted prompt sitting in Claude Code's input, the pill reads
"draft in terminal, say send", and the person presses Return or says "send
it". "Scrap that" clears it; "no, to you" hands the sentence to the assistant
instead.

Every routed sentence is a line in `~/.bob/memory/transcript.jsonl` with its
destination, confidence, and reason, which is the data for moving any of the
thresholds above. The constants and what set them are listed in the spec.

## Measuring it

Every turn writes a `turn:` line to `~/.bob/listen.log` with `text=` (prompt
to first words) and `audio=` (prompt to first sound). The filler logs
`filler: Okay.` with its time. If `text=` stays under two seconds for a week,
the filler never fires and can go; if it sits above three, the threshold is
too high and the number above should move, with the new evidence written next
to it.

## Sources

- Google, Conversation design: confirmations
  (developers.google.com/assistant/conversation-design/confirmations)
- Google Design, Speaking the same language: six principles of VUI
  (design.google/library/speaking-the-same-language-vui)
- Google Research, Google Duplex: an AI system for accomplishing real-world
  tasks over the phone (2018)
- OpenAI, Realtime prompting guide (developers.openai.com/cookbook/examples/
  realtime_prompting_guide) and the voice agent metaprompt in
  openai/openai-realtime-agents
- Sesame, Crossing the uncanny valley of conversational voice (2025)
- Mitigating Response Delays in Free-Form Conversations with LLM-powered
  Intelligent Virtual Agents (arXiv 2507.22352, 2025): fillers help in
  high-delay conditions, quality degrades past 4 s
- Behavioral and Symbolic Fillers as Delay Mitigation for Embodied
  Conversational Agents (arXiv 2508.11781, 2025): behavioral fillers preferred
  by 75% over progress indicators
- Don't Just Fill the Silence: Exploring Conversational Filler Strategies in
  Embodied Virtual Agents (ACM TAP, 2025): context-specific fillers beat
  generic ones on rapport and perceived response time
- Stream, Speculative tool calling for voice (2026): the two-track pattern, an
  acknowledgement buys 1.5 to 2 s
- Amazon, Alexa Brief Mode (2018): a chime in place of spoken confirmations
