# Writing System Prompts

Eight techniques for the prompt that governs an agent across every session.

Six come from production system prompts that leaked: Cluely (both the general assistant and the live-meeting copilot), Claude 4 Opus, Meta.ai / Llama 4, and Google Assistant. The last two come from Anthropic's current model guidance, and they are about deleting instructions rather than writing them.

[docs/PROMPTS.md](PROMPTS.md) is about the prompts you type into a session. This file is about the prompt that governs an agent across every session: a `CLAUDE.md`, a rules file, a subagent definition, an API system prompt.

The gap between the two literatures is the point. Public prompt libraries are almost entirely "act as a senior X." That sentence is roughly 2% of what shipped in production.

---

## What production prompts actually spend their length on

Open any leaked system prompt expecting a task description and you find a fence instead.

Cluely says what it is in one sentence, then spends thousands of words on when **not** to act: when intent is unclear, when the screen is empty, when a term should not be defined, when not to summarize, when to say "Not sure what you need help with right now" and stop. Claude 4 Opus is the same shape, with roughly a third of its length on refusal and a meta-rule about how a refusal should read.

Capability is assumed. The prompt is a boundary around it.

This inverts the usual advice. You are not writing instructions for a model that cannot do the task. You are writing them for a model that will confidently do the wrong task, and that failure is invisible in a demo.

---

## 1. Rank your rules, do not list them

A flat list of rules has undefined behavior the moment two of them apply.

Cluely's meeting copilot refuses to be a list. It says "Execute in the following priority order" and names six modes in sequence: answer the question, define the term, advance the conversation, handle the objection, solve what is on screen, stay passive.

When a transcript triggers three at once, the order decides. The decision is inspectable instead of emergent, and it encodes a product judgment you can argue with: answering beats defining, because a user who asked a question and got a definition has been failed.

**In practice:**

```markdown
When rules conflict, resolve in this order:

1. Never break a passing test
2. Match existing patterns in the file
3. Follow the style guide
4. Optimize for readability
```

Put the fallback last and name it. Making "do nothing" the terminal entry stops silence from being the thing that happens when no rule fires.

Your `CLAUDE.md` probably already does this implicitly. Making the order explicit is what lets you extend it without the tail becoming ambiguous.

---

## 2. Give ambiguity a number

"Ask a clarifying question if the request is ambiguous" does nothing. The model still has to decide what counts as ambiguous.

Cluely replaces the adjective with numbers, and uses a different one for each decision:

| Decision                                | Threshold | Why                               |
| --------------------------------------- | --------- | --------------------------------- |
| Treat a garbled utterance as a question | 50%       | Answering a non-question is cheap |
| Infer a speaker from context            | 70%       | Plus a stated fallback direction  |
| Admit it does not know what you want    | 90%       | Bailing out is expensive          |

The asymmetry is the technique. A single uniform threshold makes the agent either useless or reckless.

The 70% rule also names the direction to fall in when under the bar: "If you're not 70% confident, err towards the request at the end being made by the other person." That second half is what most prompts leave out, and it is the half that lets an agent proceed instead of stalling.

**In practice:**

```markdown
If you are less than 80% confident which file the user means, pick the one
most recently edited and say which you picked. Do not ask.
```

A threshold is also tunable. When the agent bails too often you move 90 to 80. There is nothing to move in "if unclear."

---

## 3. Ship the boundary next to the capability

Every capability in these prompts arrives with its exclusion list attached.

Cluely can define terms. Immediately below that, `<definition_exclusions>`: do not define common words, terms already explained, basic terms like email or code. Not in a separate section. Adjacent.

**In practice:**

```markdown
Run the formatter after edits.
Do NOT run it on: generated files, vendored code, anything in dist/.
```

The version where capabilities live in one section and prohibitions in another is worse, because the model has to join them itself.

---

## 4. Pair every good example with a bad one

Few-shot prompting is normally taught as showing what right looks like. Cluely almost never shows one example alone. It ships `<good_summary_example>` next to `<bad_summary_example>`, `<good_suggestion_example>` next to `<bad_suggestion_example>`, mislabeled transcripts next to a `<correct_interpretation>`.

One good example fixes a target. A pair fixes the line between them, which is the thing the model has to find.

The bad examples are also real. Cluely's bad summary is `"Talked about a lot of things... you said some stuff about tools, then they replied..."` That is an observed degenerate output someone wrote down, not a strawman. Its bad suggestion example is not even prose, it names the shape of the failure: `5+ options / Dense bullets with multiple clauses per line`.

**In practice:** when you write a rule and find yourself reaching for "be concise" or "don't overdo it," you have found a place that needs a pair instead.

---

## 5. Ban the literal string, not the disposition

"Don't be sycophantic" fails because the model has no shared referent for the word.

Anthropic and Meta solved this independently, the same way:

- **Claude 4 Opus:** never open by calling something "good, great, fascinating, profound, excellent, or any other positive adjective."
- **Llama 4:** never use "it's important to," "it's crucial to," "it's essential to," "it's unethical to," "it's worth noting," "Remember."

Two competing labs, same technique. A banned string is checkable on any output. A banned disposition is not.

Note that both keep the general rule and add the strings under it. Llama 4 says "phrases that imply moral superiority or a sense of authority, **including but not limited to**" and then enumerates. The abstraction gives the category, the strings make it real.

**Caveat:** this is brittle by design. The model routes around a listed phrase into an unlisted synonym, and the list has to grow. It also cannot catch structural patterns, which have no fixed wording. For those you need a shape description ("no fake-profound closing line") and you lose the mechanical checkability.

---

## 6. Constrain the format, not the character

The persona in these prompts is one or two sentences. The format rules run for pages.

Cluely: headline of six words or fewer, bullets of fifteen words or fewer, no markdown headers, no pronouns, LaTeX for all math, escaped dollar signs.

Claude 4 Opus spends a full paragraph on one decision, that prose beats bullets for anything explanatory, then closes the loophole: "Inside prose, it writes lists in natural language like 'some things include: x, y, and z' with no bullet points, numbered lists, or newlines."

You can grep an output for a header or count words in a bullet. "Did it sound like a seasoned strategist" has no test, which is why that style survives in prompt libraries and not in production.

**Honest limit:** all three leaked prompts are assistant products with tight output surfaces. Creative and roleplay work may weight persona much more heavily, and nothing here covers that case.

---

## 7. Delete what the model already does

The six techniques above are about what to write. This one is about what to
remove, and on current models it is worth more.

Prompts written for 2024 models carry instructions that now fight the model
instead of steering it. Anthropic's own migration guidance for Claude Opus 5 is
mostly a list of deletions:

| Delete                                                    | Why                                                                                                         |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| "Include a final verification step"                       | The model verifies without being told. Removing it "reduces wasted tokens with no loss in quality."         |
| "Double-check your answer", "re-verify before responding" | Compounds with self-correction the model already performs. Adds cost, finds nothing.                        |
| "CRITICAL: You MUST use this tool when..."                | Written to fix under-triggering. Now causes over-triggering. Use plain "Use this tool when...".             |
| "If in doubt, use [tool]"                                 | Named specifically as an over-trigger.                                                                      |
| "Default to using [tool]"                                 | Replace with "Use [tool] when it would enhance your understanding of the problem."                          |
| Anti-laziness and thoroughness prompting                  | Newer models already explore aggressively. If it still overshoots, lower `effort` rather than adding words. |
| Any rule telling the model not to think                   | Increases leakage of internal tags into visible output.                                                     |

Two are no longer judgment calls. **Response prefilling** returns a 400 error
from Claude 4.6 onward: migrate format-forcing to Structured Outputs or a tool
enum. **`budget_tokens`** returns a 400 error on Claude 4.7 and later: use the
`effort` setting, or `max_tokens` with adaptive thinking.

And `effort` is now the primary cost and latency control, not a fallback. Start
at the default, sweep it against your own evals, and use `low` and `medium`
liberally wherever quality holds. Thinking enabled at `low` effort generally
beats thinking disabled at similar cost.

The pattern underneath all of these: **every emphatic instruction you write is
tuned to a specific model's failure mode, and it outlives that failure mode.**
Prompts accumulate corrections for problems that no longer exist. Re-read yours
when you change models, and delete before you add.

---

## 8. Context is the other half, and it is the bigger half

A system prompt is one input into the context window. Everything else in that
window (tool definitions, retrieved files, message history, tool output)
competes with it for the same finite attention.

Anthropic frames this as a resource problem: context has diminishing marginal
returns, and recall degrades as the window fills, which they call _context rot_.
The discipline is finding the smallest set of high-signal tokens.

Four techniques that matter more than prompt wording:

- **Right altitude.** Aim the system prompt between brittle hardcoded logic and
  vague high-level guidance: specific enough to steer, flexible enough to be a
  heuristic. Both extremes fail, in opposite directions.
- **Tool design is prompt design.** Tools should be self-contained and
  unambiguous, with descriptive parameters and no overlapping responsibilities.
  The test: if a human engineer cannot say which tool applies in a given
  situation, the model cannot either.
- **Curate examples, do not accumulate them.** A set of diverse canonical
  examples beats a laundry list of edge cases.
- **Manage the long horizon.** Compaction that keeps decisions and open problems
  while dropping redundant tool output; external note files the agent maintains
  and re-reads; subagents that return a distilled summary rather than their
  whole transcript.

This is why most of this kit is not prompts. `CLAUDE.md`, the conditional rule
loading behind the stack-rules skill, the hooks, and the second brain are all
context engineering. The prompt is the small part.

---

## A checklist

Before shipping a system prompt:

- [ ] Rules ranked, with the fallback named last
- [ ] Every "if unclear" replaced by a number and a default direction
- [ ] Every capability followed by its exclusions
- [ ] Every fuzzy rule ("be concise") replaced by a good/bad pair
- [ ] Every banned behavior expressed as banned strings where possible
- [ ] Output format specified in counts and structures, not adjectives
- [ ] More length on boundaries than on the task description
- [ ] No verification, double-check, or thoroughness instructions left in it
- [ ] No emphatic capitals pushing tool use
- [ ] No prefill and no `budget_tokens` anywhere in the calling code
- [ ] `effort` swept against your own evals rather than inherited from an older model

That last one is the tell. If your prompt is mostly task description, you have written a prompt-library entry, not a system prompt.

---

## What to skip

Three genres dominate public prompt libraries and none survive scrutiny.

**Duration instructions.** "Think deeply for five minutes." "Triple-verify everything." "Use at least twice as many verification tools as you typically would." The model has no clock and no record of its typical behavior. The structural parts hiding inside these prompts do real work: outline the task, decompose into subtasks, call out uncertainties, challenge your assumptions. The stopwatch is decoration around them.

**Token minimizers.** A family of prompts exists to compress other prompts, some written in the compressed dialect they advocate (`act as txt opt, Reduce Tkn w/o Lose Mean`). Abbreviation removes the redundancy that made the instruction unambiguous. A system prompt is written once and amortized over every call; its token cost is a rounding error. Context budget is a real constraint in long agent loops and large retrieved documents, which is a different problem with a different name.

**Role stacking.** Several popular meta-prompts spend most of their length negotiating which expert roles to adopt before doing anything. No evidence anywhere that it contributes.

---

## Further reading

- [docs/PROMPTS.md](PROMPTS.md) for task prompts to type into a session
- [docs/METHODOLOGY.md](METHODOLOGY.md) for the workflow these prompts sit inside
- [docs/INTERNALS.md](INTERNALS.md) for how `CLAUDE.md` and rules files load
