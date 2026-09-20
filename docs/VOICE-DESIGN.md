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

## Long answers go to the hyper bar

The floating pill is "the hyper bar" to the person. A spoken answer is up to
three sentences or three things. A summary, a recap, an explanation, a
comparison or a longer list is written for the panel behind the hyper bar and
not read out; the voice says one sentence that names the topic and points
there: "All the info on the Civil War is ready for you in the hyper bar." Then
a blank line, then the whole answer, written to be read, so headings and lists
are fine there.

The bridge makes the pointer mean it: a spoken sentence that names the hyper
bar ends the spoken part of that block, and a long block that never pointed is
cut at `SPOKEN_CAP` words with "The rest is in the hyper bar." said after it.
The glass holds twenty seconds rather than ten after such a reply, for the
click that opens it. The read-aloud button on an answer in the panel starts
at the answer: the pointer sentence is taken off the front first, because
whoever pressed it has already found the hyper bar.

## Connected to the brain, both ways

The lean profile that makes the voice affordable also cut it off: none of the
person's settings means none of the session briefing, so the voice knew
nothing about who it was talking to, and nothing it was asked went anywhere.
`bin/superassistant` closes both halves. Before every run the bridge rebuilds
the prompt from `hud-agent.md` plus a digest of the second brain (identity,
all of NOW.md, the people, the memory index, and a map of the rest with the
rule to read the file before answering), rewritten only when those files
change. After every run the request and its written answer are appended to
`superassistant/questions.jsonl`, which the session-context hook reads back
into every Claude Code session and `superassistant recent` and `search`
query. Asked for on 2026-09-20: "make sure this application is connected to
chewbacca and has all the current up to date information, vice versa".

It is the person's call, not the bridge's. The panel's header has a switch,
"Speech off for long answers", on by default and kept across launches. Off,
the display sends `e prefer voice long=spoken`, the bridge withholds nothing
from the voice, and every spoken request carries one line telling the model
to read the answer out in full and not point at the hyper bar. The line goes
on every request rather than once, because the pointing rule sits in the
system prompt for every turn and a note said once fades under it. The bridge
is told again whenever it subscribes, so a restart starts right.

Why: speech cannot be skimmed, so every extra spoken sentence is time the
person cannot get back, and Google's VUI brevity principle and Alexa's
one-breath test both say the same thing from the other side. Asked for by
Gavin on 2026-09-20: "when the user asks questions with large summaries that
require a lot of speaking for the assistant, it just says something along the
lines of 'all info on x topic is ready for you in the hyper bar'".

## Showing them where

Asked for on 2026-09-20, for somebody who is not the builder: "if a grandma
is trying to fill out information on a page and she's getting stuck, a little
bubble will appear exactly where she needs to click." The voice could already
describe a screen; describing is what a phone call with a relative does, and
it is why those calls take an hour.

`bin/hud-guide` reads the front window's controls through the accessibility
tree peekaboo walks, and puts one mark on the glass with `tone=guide`: a ring
around the control, a bubble above it in words a person would use, a slow
pulse. The display treats that one mark as a control of its own: a click
inside it takes it down and sends `e hit guide label="..."` up the socket,
the bridge relays that to the model marked as coming from the screen rather
than from the person, and the model looks again and shows the next step. The
person follows along without saying a word.

The rules the model guides by, in `hud-agent.md`: one step at a time, in
their words, calling things by the name on the screen; their hands, never the
model's, while guiding; the bubble only ever on request. And the offer, from
the same ask: "if the user is asking a task that you can complete, show them
the highlighted version and then follow up with something like, I can
complete this for you if you want as well, just ask." So when the task is
one the machine section covers, the highlighted step comes first and the
offer once, after it, never per step, and the model acts on it only when
asked, and stops before anything they cannot undo.

The display also notes the app it took focus from, in `~/.bob/front-app`,
because the conversation panel takes key: without that, a typed "where do I
click" had the screen reader reading the panel it was typed into.

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
