---
name: graph-engineering
description: "Teaches an agent graph engineering, both halves: knowledge graphs (ontology design, entity/relation/event extraction, fusion, GraphRAG/memory serving) and task graphs (agent orchestration, parallel fan-out, verifier separation, the stop rule, human gates). Use when asked to build a knowledge graph, extract entities or relations from text, design an ontology, dedupe or merge entities, add graph memory or GraphRAG to an agent, orchestrate multi-agent workflows as a graph, or LEARN graph engineering. ALSO use without being asked, whenever the WORK has the shape, because this is the routing that keeps failing: many independent jobs being run one at a time, a test suite or batch or loop that runs sequentially and is slow, anything that could fan out but does not, planning subagents with no verifier and no stop rule, deciding whether two records are the same person or company, a fuzzy or first-name match about to be written down as fact, duplicate entities across sources, backlinks and orphan notes and link integrity in a notes repo, multi-hop questions over linked records, or any moment the answer is slow because the structure of the work was never designed."
---

# Graph Engineering

Graph engineering is the discipline of designing the structures agents work through, not the
prompts. It has two halves:

1. **Knowledge graphs**: what agents remember. Nodes are entities and facts, edges are
   relationships with time and provenance. This file's 9-stage pipeline covers it, distilled
   from Southeast University's graduate KG course
   (https://github.com/npubird/KnowledgeGraphCourse, Prof. Peng Wang), translated to English
   and adapted for LLM-era agents.
2. **Task graphs**: how agents work. Nodes are jobs, edges are execution dependencies:
   parallel fan-out, separate verifier contexts, the stop rule, the human gate.
   Read [references/task-graphs.md](references/task-graphs.md) when the request is about
   orchestrating agents rather than building memory.

Core mental model: a knowledge graph is a **product with a schema**, not a pile of triples.
Quality comes from the pipeline order, model the domain BEFORE extracting, fuse BEFORE storing,
evaluate at every stage.

## Teaching Mode

When the user wants to LEARN graph engineering (rather than build something), teach it, do
not just execute. Rules:

1. Anchor every stage in the user's own domain: ask for one real project or dataset, then use
   it as the running example through all stages.
2. **Generate visual artifacts as you teach.** Concepts in this discipline are shapes; show
   them. For each major concept, produce a small diagram the user can keep, mermaid diagrams
   (flowchart for the pipeline and task graphs, `graph LR` for example ontologies and
   subgraphs) or a single self-contained HTML page when interactivity helps. At minimum:
   the 9-stage pipeline, a 3-type ontology drawn from the user's domain, one extracted
   subgraph (5-10 nodes) from a real sample, and the diamond pattern with the user's own jobs
   as nodes.
3. Teach in the pipeline's order, one stage per exchange, each ending with a small exercise
   ("write 3 competency questions for your project") before moving on.
4. Close by assembling what was built during the lesson into a starter `ontology.yaml` and a
   drawn task graph for the user's first real build.

## The 9-Stage Pipeline

Run stages in order. For small projects stages 4-6 collapse into one extraction pass, but never
skip stages 3 (ontology) or 8 (fusion), they are where real-world graphs fail.

1. **Scope & value test**: Confirm a graph beats a simpler structure. A graph pays off when
   queries are multi-hop ("who worked with X on projects using Y"), when entities recur across
   documents, or when relationships ARE the data. If lookups are single-hop, use a table and stop.

2. **Knowledge representation choice**: Pick how facts are encoded: property graph
   (Neo4j-style, pragmatic default), RDF triples (interop/standards), or plain typed edges in
   JSON/SQLite (small scale). Decide now how time and provenance attach to every fact.

3. **Ontology modeling**: Define entity types, relation types (with domain/range), and
   attributes BEFORE extraction. Start minimal: 5-15 entity types, 10-30 relation types.
   Two rules from the course: every relation gets a precise verb name (`ACQUIRED`, not
   `RELATED_TO`), and if two types are always queried together, merge them.
   Details and worked examples: [references/modeling.md](references/modeling.md)

4. **Entity extraction (NER)**: Extract typed entities from sources. Method ladder: exact
   rules/dictionaries for closed vocabularies → LLM extraction with the ontology in the prompt
   for open text. Always extract with span + source pointer for provenance.

5. **Relation extraction**: Extract typed edges between recognized entities. Constrain the
   LLM to the ontology's relation list with domain/range checks; reject edges whose endpoints
   have incompatible types. This one validation step removes most hallucinated structure.

6. **Event extraction**: For dynamic domains (news, logs, transactions), extract events as
   first-class nodes (trigger + typed arguments + time), not just static edges.
   Extraction methods, prompt patterns, and failure modes for stages 4-6:
   [references/extraction.md](references/extraction.md)

7. **Quality gate**: Before fusion, sample and score: entity precision (are extracted
   entities real and correctly typed?), relation precision (does the source sentence actually
   assert the edge?). Fix the prompt/rules, not the output, then re-run. Target ≥90% precision
   on a 50-item sample before proceeding, recall improves with more passes; bad precision
   poisons the graph permanently.

8. **Knowledge fusion**: Merge duplicates within and across sources: same real-world entity,
   different surface forms ("SEU" = "Southeast University" = "东南大学"). Blocking + matching +
   merge policy. Skipping this is the #1 cause of useless graphs.
   Matching strategies: [references/fusion-and-llm.md](references/fusion-and-llm.md)

9. **Serve to LLMs (KG × LLM)**: Make the graph useful to agents: GraphRAG retrieval
   (subgraph → context), graph-as-memory (agent writes facts back through stages 4-8), and
   LLM-as-reasoner over paths. Patterns and pitfalls:
   [references/fusion-and-llm.md](references/fusion-and-llm.md)

## Working Rules

- **Schema first, always.** Extraction without an ontology produces a "graph" that is really a
  word cloud with arrows. If the user resists schema design, build the minimal 5-type ontology
  from 3 sample documents and show it for approval.
- **Provenance on every fact.** Each node/edge stores `source`, `extracted_at`, and confidence.
  Non-negotiable, fusion (stage 8) and trust both depend on it.
- **Incremental over big-bang.** Process a 10-document pilot through all 9 stages before
  scaling. The pilot exposes ontology gaps at 1% of the cost.
- **LLM extraction is stage machinery, not the pipeline.** The LLM slots into stages 4-6;
  the surrounding schema, validation, and fusion are what make the output a knowledge graph.

## Reference Files

- [references/curriculum.md](references/curriculum.md): Full translated curriculum of the
  source course with per-lecture summaries and links to the original Chinese slide decks.
  Read when the user wants theory depth, the academic grounding, or the original materials.
- [references/modeling.md](references/modeling.md): Knowledge representation & ontology
  engineering (course lectures 2-3). Read during stages 2-3.
- [references/extraction.md](references/extraction.md): Entity, relation, and event
  extraction from rules to LLM prompting (lectures 4-7). Read during stages 4-7.
- [references/fusion-and-llm.md](references/fusion-and-llm.md): Knowledge fusion and
  KG × LLM integration (lectures 8-9). Read during stages 8-9.

## The field, scanned 2026-09-21

`github.com/topics/graph-engineering` returned 98 repositories. The survey at
`DEEP-JLU/Awesome-Graph-Engineering` puts this file's subject inside a larger
frame: six sub-disciplines, of which two are covered here.

    prompt engineering     chain of thought, tree of thoughts, graph of thoughts
    context engineering    RAG, Self-RAG, GraphRAG, retrieval compression
    loop engineering       control flow, StateFlow, adaptive planning
    runtime engineering    scaffolding, execution, sandbox, safety
    graph engineering      task DAGs, agent topologies          <- here
    ontology engineering   the semantic layer, constraints      <- here

### The other four, enough to reach for the right one

This file teaches the bottom two rows. The other four are named above and
then dropped, which is the gap a reader hits the moment the work is not
graph-shaped. Each below is: what it is, the technique to reach for, the
failure it prevents, and where this repo already does or fails it. Each is a
map to the row, not a course in it.

**Prompt engineering: chain, tree, graph of thoughts.** The unit is a single
reasoning call and how much structure you impose inside it. Chain of thought
is one linear trace. Tree of thoughts branches, scores the branches, and
keeps the best, for a problem with dead ends worth abandoning. Graph of
thoughts lets branches merge again, for a problem whose sub-results combine.
The rule is to spend the cheapest one that works: a chain is one call, a tree
is many, and reaching for a tree on a problem a chain solves is the
prompt-level version of spawning a fleet for 40 seconds of work. The failure
it prevents is a confident single trace down a path that had a fork in it.
This kit's own instance: the vibe guard exists because a chain asserted "fixed"
with no branch that checked the running screen.

**Context engineering: what is in the window, and why.** Retrieval is the
first half and is covered above (GraphRAG, stages 7-8). The half this file
skips is management of the window itself: retrieval compression (summarise the
retrieved chunks before they enter, so the model reasons over signal, not raw
dumps), Self-RAG (the model decides whether to retrieve at all and grades what
came back, rather than always stuffing k chunks), and the ordering problem,
because a model reasons over a truncated middle when the window is full. This
is the same failure as the synthesis bottleneck in the fleet rules, one level
down: too much in, and the middle is lost. This kit does the crude version
right (`bound the fan-in`, layer past ~50) and the fine version nowhere: the
second brain retrieves by term overlap with no compression and no relevance
grade.

**Loop engineering: the control flow around the calls.** A single prompt is a
node; loop engineering is the shape of the edges when the next call depends on
the last. StateFlow models the agent as a state machine, so "planning",
"acting", "verifying" are explicit states with defined transitions rather than
one prompt asked to do all three and drifting between them. Adaptive planning
re-plans when a step fails instead of running a plan written before the first
result came back. The rule that binds it: a loop needs a bound and an exit
that is not the model's opinion. This kit reached the same place from the other
side, in `headsign` and `bin/closeout`: exit codes decide advance / retry with
a cap / escalate / done, and the narrative is ignored at that junction. A loop
without that cap is the indefinite-spinner failure the HUD's presence ring also
forbids.

**Runtime engineering: what the agent runs inside.** Everything that is not
the model: the scaffolding that gives it tools, the sandbox that bounds
what a tool can touch, the state that survives a context reset, and the safety
that makes the dangerous thing unreachable rather than forbidden. This is rule
7 above, `topology over prompts`, stated as a discipline: a permission a prompt
asks the model not to use is weaker than a tool the runtime never exposes.
Durable state is the other half, and `levi-qiao/longgraph-skill` is the shape:
progress in files, not chat history, single-writer edges, gates rerun against
real output. This kit is mostly runtime, `.githooks/pre-commit`, the Stop
guards, `write-log.sh`, the sandbox in `mac-runtime`, and it is the row it
covers best without having named it.

**How to route between the six.** The question decides the row. A single hard
reasoning step is prompt. A model that needs facts it does not have is context.
A multi-step task that branches on results is loop. Anything about tools,
sandboxes, durable state or safety is runtime. A structure of connected
entities is graph. The meaning and constraints on that structure is ontology.
Most real work touches three or four at once; the point of the split is to
notice which one is failing, because the fix lives in that row and nowhere
else.

### The three failure modes of a parallel fleet

From `wilsonwu-ai/graph-engineering-kit`, and all three are things this repo
has done:

1. **Workspace collision.** Two agents write the same file. This kit's
   `.githooks/pre-commit` exists because two sessions did exactly that and one
   commit swallowed the other's work, three times in one day.
2. **Fake verification.** The verifier reads the worker's own reasoning
   instead of ground truth. On 2026-09-21 a fix was reported done three times
   while the claim was checked against the code's arithmetic rather than the
   running screen. `hooks/vibe-guard.sh` is the answer to this one.
3. **Synthesis bottleneck.** Hundreds of findings into one prompt, so the
   model reasons over a truncated middle while producing output that looks
   complete. `hooks/list-guard.sh` exists because five investor lists were
   called finished four times with 2,121 duplicate people in them.

### Ten rules, same source

1. **The fake edge test.** Does the next step read the previous step's output?
   No, then cut the arrow. Most sequential work is sequential by habit.
2. **The reverse fake edge test.** Two steps that look independent but share a
   workspace have a hidden edge.
3. **A verifier needs an anchor.** No ground truth to check against means
   label it unverified. Never fake the check.
4. **Budget the whole fleet**, not each agent.
5. **Bound the fan-in.** Past about 50 records, layer the synthesis.
6. **Tier the model per node.** Do not let a default decide.
7. **Topology over prompts.** Make the unsafe thing unreachable rather than
   forbidden. This is the same instruction as this kit's "enforce, do not
   document", arrived at independently.
8. **Freeze the rules an optimiser would weaken** to succeed.
9. **Estimate the speedup before spawning.** See below.
10. **Run the retro.** Five metrics after, then widen or narrow.

### When not to bother, with this repo's own numbers

Amdahl, where `p` is the genuinely independent fraction and `N` the workers:

    S = 1 / ((1 - p) + p/N)          ceiling = 1 / (1 - p)

Below `p = 0.7` the ceiling is under 3.3x and parallelising is not worth the
complexity. Measured against this repo's test suite, which is the thing that
prompted the question:

    total sequential        ~600s
    slowest single group      41s   (installer)
    p                        0.932
    ceiling                   14.6x
    S at N=15                  7.7x  ->  about 78s

So it is worth it here, and the answer is the group, not the check. Fanning
out all 155 checks individually would raise N and not p, and p is what binds.

### Exit codes decide, not the model

`meganemura/headsign` states the rule this kit reached separately: when the
agent asks whether the work can advance, the runtime runs the phase's shell
checks and **their exit codes determine the answer**, with the model's
narrative ignored at that junction. Advance, retry with a cap, escalate to a
human, done. That is what `bin/closeout` and the Stop guards are, and it is
worth knowing the pattern has a name and other implementations.

### Deterministic memory, for the retrieval problem here

`DrDroidLab/open-index` stores typed entities with schemas and `related_to`
edges carrying a `relationship_edge_meaning`, and ranks with per-field `boost`
weights rather than embedding geometry. It has no decay or pruning either,
which is worth noting before assuming that part is solved anywhere.

### Durable state across context loss

`levi-qiao/longgraph-skill`: one node is one prompt and one single-writer
edge, progress lives in files rather than chat history, acceptance gates are
rerun against real output rather than self-reported done, and a supervisor
verifies from a separate context. Markdown, not a framework.

## Practitioners on this machine, and where they converge

One graduate course is a curriculum, not a field. These are working
practitioners whose material is already in this repo, and the point of listing
them here is that the router now reaches this skill on the SHAPE of the work,
so whatever it cites gets reached too.

**Aryaa SK** (Trinity College, Cambridge; building Zoral), 130 posts read in
full 2026-09-20, distilled with attribution in
the team's internal notes.
Caleb's own caveat on that file, which belongs here too: _"don't just assume he
is the truth lol bro is smart but he's not Jesus."_ Its section 9 marks where
he is contestable, one claim conflated and one number that does not check out.

**Where he and the course agree, independently.** His build list item 3 asks
for _"described edges between memories. Not term overlap. A link that says WHY
two things are related, so a walk discovers what a search cannot."_ Stage 3 of
the pipeline above says every relation gets a precise verb name, `ACQUIRED`,
never `RELATED_TO`. Two sources, different traditions, same instruction.

**And the kit does not do it.** `second-brain` links with bare `[[wikilinks]]`,
which carry no relation type, so every edge means "these two mention each
other". That is the word-cloud-with-arrows this file warns about in its own
working rules. Retrieval over it has to fall back to term overlap, which is why
`scars` ranks badly even with indexing fixed.

**His item 1 is already here, arrived at without reading him:** _"where a rule
keeps being violated, promote it to a hook that refuses."_ That is
`hooks/vibe-guard.sh` and `hooks/fusion-guard.sh`, both written 2026-09-21
after the same mistake happened twice. His items 2 and 4, decay and pruning of
banks that only ever grow, and climbing past prompt text, are not done.

## Credits

Distilled and translated from 东南大学《知识图谱》研究生课程 (Southeast University graduate
course on Knowledge Graphs), Prof. Peng Wang, https://github.com/npubird/KnowledgeGraphCourse.
All original lecture PDFs are in Chinese; this skill is an independent English distillation
adapted for AI-agent workflows.
