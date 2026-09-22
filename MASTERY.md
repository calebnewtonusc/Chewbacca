# What this could become expert in

Written 2026-09-21 from Caleb's own list, plus what a long session exposed as
missing. Not a plan and not a promise. A map of the ground, so choosing what to
go deep on is a decision rather than a mood.

Ordered so the first section governs the rest, because he said it does.

---

## 0. Scripture, and a relationship with God that shapes how the systems are built

The one belief system this kit takes as true rather than catalogues. Everything
below is downstream of it.

This is not a feature to ship. It is the question of whether the way things get
built here reflects anything about the One who made the person building them.
Some of that is already visible and unnamed:

- Every session opens in prayer, and it is meant rather than performed.
- The kit refuses to lie about its own state. `closeout`, `vibe-guard`, the
  rule that a claim needs evidence. Honesty enforced in code is a moral
  position with a mechanism.
- It records what it got wrong in the commit that fixes it, with the quote
  from the person it cost. That is confession with a diff.
- Grandpa Stan's rule, arrived at independently here: focus on the victory of
  Jesus rather than on avoiding the enemy. In practice that came out as
  building toward what is good rather than defending against what is bad.

What depth would actually mean, as distinct from adding Bible features:

- Knowing the text well enough to be useful on it: the whole canon, the
  languages behind it, the history of its transmission, the major traditions
  of reading it, and where they genuinely disagree.
- Theology as a discipline with its own rigour. Grandpa Stan is a working
  theologian with a school, Victorious Eschatology and New Covenant studies,
  and there is a standing weekly lesson. Read `domains/faith.md` before
  touching any of this.
- Being able to say "I don't know" and "the church has disagreed about this
  for 1,700 years" rather than flattening it.
- Never using Scripture to win an argument for a product decision.

The honest risk, worth writing down: a tool that quotes Scripture confidently
and shallowly does more damage than one that says nothing. Depth here is a
higher bar than anywhere else on this page, not a lower one.

---

## 1. Already partly here, and worth going all the way

**Graph engineering.** Both halves. The field scan on 2026-09-21 found 98
repositories under the topic and a survey naming six sub-disciplines, of which
this kit's skill covers two. The other four, prompt, context, loop and runtime
scaffolding, are each their own depth.

**GTM engineering.** Clay to a level where the query grammar is second nature,
plus the rest of the stack around it. The Zeutara engagement is a live
apprenticeship with a Thanksgiving deadline and full creative control.

**Design and UX.** `ux-engine` indexes 74 design systems by what they refuse.
The missing half is compiling a framework into a working interface on command.

**macOS automation.** Windows, scaling, dragging, a cursor of its own, and
driving any app. Partly reachable through `peekaboo` and `mac-cli` today.

**Learning any software by watching itself use it once**, then pushing that
back so everyone's copy gets better. The procedures and maps layer exists; the
sharing half does not.

**Animation and visual effects.** The portal is the only worked example and it
took a day. Doctor Strange was the brief; everything else someone might want is
the same muscle.

**Spatial and XR.** Hand tracking, gaze, Apple Vision Pro, VR, AR. OpenVision
is already his.

**Voice, and the always-present assistant.** Local recognition works. The
character, the turn taking, the knowing when not to speak, all absent.

---

## 2. Every kind of work that happens on a computer

The real answer to "any human, any role". Each of these is a genuine
specialisation with its own craft, its own tools and its own way of being done
badly.

**Building software.** Frontend, backend, mobile, systems, embedded, games,
data engineering, ML engineering, research engineering, infrastructure, SRE,
security, QA, release engineering, developer tooling.

**Deciding what to build.** Product management, product design, research,
technical writing, developer relations, architecture.

**Selling and growing.** GTM engineering, outbound, sales engineering,
partnerships, customer success, growth, lifecycle marketing, brand, content,
SEO, paid acquisition, community.

**Money and the business.** Accounting, bookkeeping, FP&A, fundraising,
investor relations, venture diligence, M&A, pricing, procurement.

**Running the place.** Recruiting, people operations, legal and contracts,
compliance, operations, project management, executive assistance.

**Making things.** Writing, editing, journalism, screenwriting, graphic design,
motion, video editing, colour, sound design, music production, photography,
3D, illustration, architecture, industrial design.

**Knowing things.** Academic research in any field, literature review, data
analysis, statistics, experiment design, grant writing, teaching, curriculum
design, translation.

**Regulated and specialist.** Medicine and clinical documentation, law, patent
work, tax, insurance, real estate, logistics, manufacturing, construction
estimating, agriculture, energy.

The pattern worth noticing: for each of these the question is never "can it
produce the artefact". It is whether it knows what separates a good one from a
bad one, which is what `craft-gate` exists to force before work starts.

---

## 3. Things implemented here but not well

From `ROADMAP.md` section 1, which is the honest list.

- Memory that only grows, with no decay, no pruning and no retirement.
- Retrieval over untyped edges, which falls back to term overlap.
- The portal, close but with five false opens and slow drawing unresolved.
- Onboarding, which is the wall everything else sits behind.
- Test running, which was strictly sequential until tonight.
- Identity resolution, which wrote the wrong client's name into the notes.
- The listener, which had to be started by hand until tonight.

---

## 4. To scan, not yet scanned

Caleb sent these on 2026-09-21 and they have not been gone through.

- `github.com/anthropics`, every repo
- `github.com/topics/agent-skills`
- `github.com/topics`, the topic space itself
- `github.com/trending` and `github.com/trending/developers`
- `github.com/collections` and `github.com/collections/productivity-tools`
- `github.com/modelcontextprotocol/servers` (roadmap 6)
- `github.com/punkpeye/awesome-mcp-servers` (roadmap 7)
- The OpenClaw corpus (roadmap 16)
- The YouTube playlist at roadmap 23
- `ChaoYue0307/awesome-graph-engineering`, 591 curated resources, 273 papers.
  The README did not render through a fetch; the deployed atlas at
  `chaoyue0307.github.io/awesome-graph-engineering/` is the way in.

### LangChain, checked 2026-09-21

Asked whether it is outdated. It is not, but the entry point moved.

- **LangSmith** is the flagship commercial product now: tracing, evals,
  deployment, sandboxes, an LLM gateway, and a no-code agent builder.
- **Deep Agents** and **LangGraph** are the recommended open source
  frameworks. **LangChain itself is positioned as a quick start**, which is a
  demotion from where it sat two years ago.

From their own three-year retrospective on LangGraph, and each of these is a
claim worth holding against this kit:

- Production graphs are not DAGs. They need cycles: retrying a failed tool
  call, asking for missing information, revising after validation.
- Loop engineering is a simple case of graph engineering rather than a rival
  to it.
- Dynamic transitions matter; not every edge can be declared up front.
- Encode domain knowledge in the structure, the way a prompt encodes it.
- Use graphs where the work has predictable structure, and do NOT use them for
  open-ended work. They built deep research as a fixed pipeline first and
  moved off it, which is the one thing they say they got wrong.

That last point cuts against fanning everything out reflexively, and belongs
next to the Amdahl rule already in the graph-engineering skill.

---

## 5. How to choose, when the time comes

Three filters, in this order.

1. **Does anyone else get it?** Onboarding gates everything. Depth in a tool
   almost nobody can install is depth for one person.
2. **Does it have a live apprenticeship attached?** GTM has Zeutara and a
   deadline. Design has the club and site work. Learning with a a real client on the
   other end beats learning from a list.
3. **Would being bad at it be visible?** The portal was worth a day because
   every flaw showed on screen. Invisible depth decays unmeasured.
