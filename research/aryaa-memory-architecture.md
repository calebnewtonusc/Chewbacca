# The influence ladder, and what this kit is missing

Source: 130 LinkedIn posts by **Aryaa SK** (Trinity College, Cambridge; building
Zoral), read in full 2026-09-20 from an export Caleb pulled. Caleb is friends
with him and says he posts deliberately, for people to use.

Everything below is HIS, attributed. What is ours is the mapping onto this kit
and the gaps it exposes.

**Read section 9 first.** Caleb, same night: *"don't just assume he is the
truth lol bro is smart but he's not Jesus."* Correct, and the first draft of
this file did exactly that. Several claims below are contestable, one is
conflated, and one number does not check out. Marked inline.

## 1. The influence ladder, ordered by depth toward the model core

> "modifying a system prompt is only 1 way to influence an LLM's behaviour,
> and is one of the weakest methods."

1. **System prompt** (weakest)
2. **Dynamic context injection at query time** (text search, vector-db RAG)
3. **Fine-tuning**, e.g. LoRA adapters
4. **Steering vectors** added to the residual stream between transformer blocks
5. **Modifying the weights**
6. **Modifying the tokeniser**, encoding higher-level ideas into fewer tokens
   (most volatile: a new tokeniser AND the model must learn to reason over it)

> "each of these methods trades plasticity (how easily the model can change)
> for performance (how efficiently we can influence the model's outputs)."

**WHERE THIS KIT SITS: levels 1 and 2. Every single component.** `CLAUDE.md`,
`methods/`, `crafts/`, the hooks, `scars` retrieval, the baseline refusals in
ux-engine. All of it is prompt text and query-time lookup, which is the two
weakest rungs he names.

## 2. The part that makes it an architecture, not a list

> "a key area we are researching is to use the higher plasticity methods to
> encode shorter term memories... and consolidate downwards through the lower
> levels to ingrain knowledge used frequently into deeper levels of the
> inference engine"

High plasticity for what is new, then **consolidate downward** as it proves
itself. That is the missing mechanism here, identified independently from the
neuroscience earlier the same night and left unbuilt.

**The kit already has the layers and none of the movement:**

| Layer | Here | Plasticity | What it should hold |
|---|---|---|---|
| Episodic | `scars`, 53 recorded failures | highest | what happened once |
| Semantic | `methods/`, 6 rules | medium | what keeps happening |
| Procedural | hooks that refuse | lowest | what must never happen again |

53 episodes have never become a rule. A rule has never become a gate. Nothing
moves down.

## 3. Memory and reasoning cannot be separated

> "The agent needs to already know what it's looking for. You can't search for
> what you don't know exists." and "Every lookup is a round trip."

His argument runs: chain facts in a graph so retrieval brings neighbours; then
shrink node granularity; take it to the limit and each node is a single bit,
at which point you have a neural network, the facts ARE the weights, and
reasoning IS the forward pass. Any external store reintroduces the separation.

**`scars find` is exactly the query-a-database shape he is arguing against**,
and it failed in exactly his predicted way: asked about "a capture tool that
records state and handles errors" it returned weak matches, because term
overlap requires already knowing the words.

## 4. Store / mechanism / modulator

A framework for any continually-learning stateful system:

- **Stores** hold state. Axes: plasticity, coding density, retrieval cost.
- **Mechanisms** operate on stores. Axes: latency, effect size, function
  (encode, retrieve, transfer, delete).
- **Modulators** are scalars that gate mechanisms. Axes: variability,
  persistence, reach.

His mapping: KV cache = working memory. RAG = hippocampus. LoRA = cortex.
Frozen base weights = brainstem. Dopamine = one scalar broadcasting everywhere.

> "But sleep replay distillation? Reconsolidation? Reward-gated plasticity
> with the right reach? None of those have an ML equivalent yet."

## 5. Asymmetry tracing, as a thinking method

> "every asymmetry must be caused by a previous asymmetry... observe an
> asymmetry, trace back, keep going until you find the root. if the root is an
> arbitrary choice: reverse it. if the root is unknown: you've found something
> fundamental."

His worked example: why can't AI learn continuously? Trace it back to
sequential computing chosen ~70 years ago, not to any law of physics.
Therefore reversible.

Belongs in `methods/` as a thinking tool. It is sharper than anything already
in there because it terminates: you stop when you hit either an arbitrary
choice or a genuine unknown.

## 6. Plasticity over parameters

> "take ax + b. Tune a and b however you like, you will never reproduce the
> shape of 1/(ax + b)... The function constrains what shapes are reachable."

Weights are flexible; which neurons exist and what connects to what is frozen.
The brain's topology is not. His practical compromise, buildable today:

> "Give each node a full concept in natural language. Give each edge a
> description. A 10,000-node graph at this abstraction level can represent
> what would take a billion numerical neurons. Retrieval becomes an agent
> walking the graph, not a deterministic matrix multiply."

That is a concrete design for this kit's memory, and it is reachable from
where `scars` already is.

## 7. Prediction error is the only clean signal

> "Current systems use weak signals - similarity scores, access patterns,
> recency, even asking LLMs for feedback? No clear loss function. The
> prediction-error loop gives you an exact one."

Plus multi-timescale. **His numbers here do not check out.** He cites "Fusi's
cascade model shows this beats a single timescale approach by 73%" and "three
tiers is the mathematical minimum for seconds-to-months."

The model is real: Fusi, Drew & Abbott, *Neuron* 2005, synapses with a cascade
of states at different plasticity levels, and it does "significantly
outperform alternative models" at combining storage with retention. **The 73%
and the three-tier minimum are not findable in the paper or its summaries.**
Treat the direction as sound and the figures as unsourced.

Arrived at independently in ux-engine the same night from Schultz's dopamine
work, and built as `ux-viewer check --predict`. His addition is the timescale
requirement, which is not built anywhere.

## 8. Sleep is not optional, and it cannot run during behaviour

> "Every animal with a nervous system sleeps. Dolphins sleep with half their
> brain at a time so they don't drown. Evolution tried everything to eliminate
> sleep and failed every time."

NREM consolidates, REM makes cross-domain associations, pruning removes dead
connections. OS equivalent: defrag, cache eviction, cron. The reason it is
offline in every case is that these operations cannot run while the system is
active.

## What to build here, in order

1. **Consolidation upward then downward.** Cluster `scars`; where several
   share a mechanism, promote to a `methods/` rule citing its episodes; where
   a rule keeps being violated, promote it to a hook that refuses. Run offline.
2. **Decay and pruning.** Every bank in this kit only grows. Power-law decay on
   unused scars, retirement for questions that never change an outcome.
3. **Described edges between memories.** Not term overlap. A link that says
   WHY two things are related, so a walk discovers what a search cannot.
4. **Climb the ladder past level 2**, eventually. Everything here is prompt
   text. The next rung that is actually reachable without training infra is
   better retrieval structure, which is item 3.


---

## 9. Where he is contestable, and where he is selling

He is a nineteen-year-old undergraduate raising money, and he says himself
that he engineers these posts for attention. Posts 1, 3, 4 and 8 are
explicitly about attention arbitrage and distribution as a quant pipeline.
Nearly every post ends in zoral.ai. **The corpus is genuine thinking and
marketing at the same time**, and reading it as one or the other misses it.

**The ladder conflates depth with effect.** "System prompt is one of the
weakest methods" is true about PERSISTENCE and false about POWER. Measured in
ux-engine the same night: moving universal bans into every generation prompt
took emoji from 26 to 0 on an identical brief, same model, same stance. That
is a decisive effect from the rung he calls weakest. Read as a ladder of
persistence it is useful; read as a ladder of power it argues you past the
cheapest intervention that works.

**"Put the knowledge in the weights" proves too much.** The limit argument is
elegant: shrink nodes until each is a bit and you have a neural network, so
facts are weights and reasoning is the forward pass. Taken literally it says
every database should be a neural net. It also throws away auditability: a row
can be read, corrected and deleted, a weight cannot. For a kit holding facts
about real people that is not a minor cost. His case is strongest for SKILL
and weakest for FACT, and he does not make that distinction.

**Store / mechanism / modulator is unfalsifiable as stated.** Every stateful
system can be described as stores, operations on stores, and things that gate
them. A framework that fits everything predicts nothing. Useful as a
vocabulary for comparing designs; not evidence for any of them. The same
objection applies to "every complex adaptive system is running the same
algorithm", which is Friston's free energy principle, contested in the
literature for exactly this reason.

**Unsupported as stated:** "the average llm is already smarter than any human
alive". "I think I just built AGI?". "The universe is an LLM, which means
we're probably living in a simulation." The last is fun and not load-bearing.

**The 705% quant return is a backtest.** 206 trades over 18 months held out.
He flags limitations in the repo himself and says the model is not ready for
paper trading. Backtests overfit and the post does not clearly report costs
and slippage. Not a reason to dismiss him. A reason not to repeat the number.

**What survives all of that:** the consolidation direction in section 2, the
asymmetry-tracing method in section 5, the plasticity-vs-parameters argument
in section 6, and the observation in section 7 that similarity scores and
recency are not a loss function. Those are the four worth building on, and
three of them are arguments rather than claims, so they stand or fall on
whether they work here.
