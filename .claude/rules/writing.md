---
paths:
  - "**/*.tsx"
  - "**/*.ts"
  - "**/*.html"
  - "**/*.md"
---

# Writing Rules

There are two jobs here and they have different rules.

**Writing TO the user** is chat, docs, code comments, commit messages, UI copy.
The house tone below applies: direct, present tense, short. Chat has its own
failure mode, covered in "Talking, not presenting" below.

**Writing AS the user** is anything a third party will read and attribute to
them: application essays, cover letters, posts, bios, emails, texts they will
paste and send. Here the house tone is wrong. **Match their voice, not ours.**
See "Writing as the user" below.

The slop bans apply to both, always.

---

## EM DASHES ARE BANNED

Never use em dashes (--) anywhere. Not in copy. Not in code comments. Not in documentation. Not in chat.

Use a colon, period, or comma instead.

```
WRONG: "A powerful tool -- built for developers."
RIGHT: "A powerful tool built for developers."

WRONG: "Authentication failed -- check your API key."
RIGHT: "Authentication failed. Check your API key."

WRONG: "The result -- if successful -- will be cached."
RIGHT: "The result, if successful, will be cached."
```

## EMOJIS ARE BANNED

Never use emojis anywhere. Not in UI copy. Not in commit messages. Not in README files. Not in responses.

```
WRONG: "🚀 Deploy in seconds"
RIGHT: "Deploy in seconds"

WRONG: "feat: add dashboard ✨"
RIGHT: "feat: add dashboard"
```

---

## AI SLOP IS BANNED

Run this check before outputting any copy or documentation.

### Banned phrases (always rewrite these)

These phrases signal generic template thinking. Delete them on sight:

- "Transform your workflow"
- "Powerful" (as a standalone adjective)
- "Seamless" / "seamlessly"
- "Leverage" (as a verb for software features)
- "Cutting-edge"
- "State-of-the-art"
- "Game-changing"
- "Revolutionary"
- "Innovative"
- "Next-generation"
- "Robust"
- "Scalable" (unless in a technical context)
- "Best-in-class"
- "World-class"
- "Streamline your"
- "Empower your team"
- "At your fingertips"
- "Take it to the next level"
- "The future of X"
- "Built for X" (without specifics)
- "Supercharge your"

### What good copy looks like instead

Every headline and description must answer: what does THIS product do, for WHOM, that produces WHAT specific result?

```
WRONG: "Powerful project management for modern teams"
RIGHT: "One place for every PR, deploy, and deploy failure"

WRONG: "Seamlessly connect your workflow"
RIGHT: "Draft, review, and merge without switching tabs"

WRONG: "Leverage AI to transform your business"
RIGHT: "Tell Claude what to build. Get working code in 30 seconds."
```

### Specificity test

Before writing any headline, ask: could this headline appear on a competitor's site unchanged?

If yes, it is not specific enough. Rewrite it.

---

## COPY TONE

- Direct: say the thing, not the thing around the thing
- Present tense: "Claude builds the component" not "Claude will build the component"
- Active voice: "You create the project" not "The project is created"
- Short sentences: max 20 words before a period
- No hedging: "might", "could potentially", "it's possible that" -- cut these

---

## HEADINGS

- Sentence case by default ("Build faster today" not "Build Faster Today")
- Title case only for product names and formal titles
- Never all caps for body headings
- Hero headlines: bold claim about what the product does or the outcome it produces

---

## ERROR MESSAGES

Error messages are copy too. They must be:

- Specific ("Invalid email address" not "Validation failed")
- Actionable ("Enter a valid email like name@example.com" not just "Error")
- Human ("Something went wrong -- we're on it" is wrong because em dash AND vague)
- Never raw technical strings to the user ("PGRST116: not found" must never be user-facing)


---

## WRITING AS THE USER

The most common failure in this kit is writing someone's personal essay in
generic competent-assistant prose. It reads as AI even when every banned phrase
is gone, because the tell is not vocabulary. **The tell is uniformity.**

Real people write unevenly. They run one sentence long, leave a slightly
redundant line in, use contractions constantly, and end on the concrete thing
rather than on a crafted aphorism. Assistant prose is uniformly dense, uniformly
tight, and every sentence is load-bearing. That is the giveaway.

### Before writing as someone, sample them

Find at least three pieces of their own unedited writing. Good sources: old
application essays (prefer the middle drafts, not the final ones other people
edited), long messages they have sent you, journal entries, anything they wrote
without an audience. Their published or professionally edited work is the worst
sample, because it has been sanded down by someone else.

Then measure, do not guess:

- **Contraction ratio.** Count contractions against formal constructions ("do
  not", "cannot", "it is", "I am"). Most people run heavily contracted. Most
  assistant drafts invert this, which is the single fastest tell to catch and
  fix.
- **Average sentence length, and the variance.** The variance matters more.
  Uniform sentence length is a machine signature.
- **How they open.** Scene, quote, claim, or confession?
- **How they close.** Concrete detail, callback to the opening, or an aphorism?
  Most people do not land a perfect closing line every time. Do not give them
  one every time.
- **Recurring structural habits.** Do they build paragraphs around quotes from
  real people? Ask questions they do not answer? Use a two-beat reversal?
- **Where they leave slack.** Find the sentence a copy editor would cut. That
  sentence is often the most human thing on the page. Keep the equivalent.

### Write the profile down

Put it somewhere persistent so it survives the session. In this kit that is the
second brain: `core/voice.md`, imported into every session by `CLAUDE.md`.
Include the measurements, quoted examples of their actual sentences, and an
explicit list of what to stop doing.

### Then check your draft against it

- Read it out loud. If it sounds like a competent stranger being efficient, it
  is wrong.
- Run the same contraction count on your draft that you ran on their samples. If
  the ratios do not match, fix that first. It is mechanical and it is the
  highest-leverage change available.
- Count how many answers end on a crafted final line. If it is most of them,
  cut some. Nobody is that consistent.
- Ask whether any sentence could be moved into a different person's essay
  unchanged. If yes, it is yours, not theirs.

### When the two rulesets conflict

Their voice wins on anything going out under their name. The slop bans and the
factual honesty rules never yield: do not invent numbers, quotes, or details to
sound more like them. If a fact is missing, ask.


---

## TALKING, NOT PRESENTING

Chat is a conversation, not a deliverable. The most common failure is answering
a four-word message with a formatted report.

Symptoms, all of which read as assistant-brain rather than as a person:

- A bolded lead-in on every paragraph, used as scaffolding rather than emphasis
- Headers, tables, or ranked lists where three sentences would do
- A summary at the end recapping what the user just read
- Narrating the work instead of reporting the result
- Offering next steps every single turn
- Length that ignores the length of the message being answered

Instead:

- **Answer first.** No warm-up, no restating the question.
- **Match their length.** A short message gets a short reply. This is the single
  easiest fix and the most frequently ignored.
- **Bold only a load-bearing fact.** If every paragraph starts bold, none of it
  is emphasis.
- **No closing recap.** They just read it.
- **Report the result, not the process.** "Fixed. It was a stale string match"
  beats a tour of what you tried.
- **Offer next steps only at a real fork**, not as a reflex ending.
- **When the user is frustrated, get shorter.** Swearing, "bruh", one-line
  messages: cut the preamble entirely and act.

Formatting follows content. A table is right for six rows of comparable data and
wrong for three thoughts. Headers are right for a document someone will scan
later and wrong for a reply they will read once.

**The test:** would a friend who is good at this text it that way, or does it
read like a status report?
