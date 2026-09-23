# Credits

Everything this kit was built out of, and who it belongs to.

`.github/CONTRIBUTING.md` says "vendored work keeps its author." That was a
policy with no page behind it, which is item 814 on the thousand-things list:
"nothing credits vendored authors prominently." This is the page.

Two lists. What came from somewhere else, then what did not. The split matters
because the second list is the only part that is actually mine, and a kit that
blurs the line is taking credit for other people's work.

---

## Part 1: what this was built out of

### Vendored, forked, or installed as code

Shipped inside this repo, or cloned onto the machine by `setup.sh`.

| Source | Author | License | What it gives this kit |
| --- | --- | --- | --- |
| [31Carlton7/plynn](https://github.com/31Carlton7/plynn) | Carlton Aikins | MIT | On-device Mac dictation. **Forked and vendored** at `plynn/`, ported back to macOS 15 and given the Chewie voice route. See [plynn/NOTICE.md](plynn/NOTICE.md) |
| [31Carlton7/mac-cli](https://github.com/31Carlton7/mac-cli) | Carlton Aikins | MIT | The `mac` command. Cloned and built by `setup.sh` |
| [31Carlton7/skills](https://github.com/31Carlton7/skills) | Carlton Aikins | see upstream | The `deslop` skill, which holds the judgement half of code slop review |
| [openclaw/Peekaboo](https://github.com/openclaw/Peekaboo) | Peter Steinberger | MIT | The widest macOS control surface anywhere: see, click, type, menus, Dock, Spaces, dialogs, windows |
| [steipete/summarize](https://github.com/steipete/summarize) | Peter Steinberger | MIT | The `summarize` command for pages and PDFs |
| [steipete/macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) | Peter Steinberger | MIT | AppleScript and JXA over MCP with a callable script knowledge base |
| [steipete/agent-scripts](https://github.com/steipete/agent-scripts) | Peter Steinberger | MIT | A skill pack, linked per skill rather than copied |
| [onvoyage-ai/gtm-engineer-skills](https://github.com/onvoyage-ai/gtm-engineer-skills) | OnVoyage AI | MIT | Twelve SEO, AEO and GEO skills (keyword research, AI-search audits, content, backlinks, Reddit), linked per skill from a clone by `setup.sh` |
| [browser-use/macOS-use](https://github.com/browser-use/macOS-use) | browser-use | MIT | The runtime under `mac-use`. Chewbacca owns the provider adapters, macOS-use supplies the agent loop |
| [lahfir/agent-desktop](https://github.com/lahfir/agent-desktop) | lahfir | Apache-2.0 | The accessibility-tree driver. Stable element refs, JSON out |
| [BlueM/cliclick](https://github.com/BlueM/cliclick) | BlueM | custom | Synthetic input. Does one thing and has since forever |
| [petergyang/no-ai-slop](https://github.com/petergyang/no-ai-slop) | Peter Yang | MIT | 20+ AI slop patterns, voice-preserving edit pass |
| [conorbronsdon/avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing) | Conor Bronsdon | MIT | 61 pattern categories, a 112-word replacement table, and the deterministic Node detector that `ai-scan` wraps |
| [blader/humanizer](https://github.com/blader/humanizer) | blader | MIT | A second opinion, built from Wikipedia's "Signs of AI writing" rather than the same catalogue as the other two |
| [Egonex-AI/Understand-Anything](https://github.com/Egonex-AI/Understand-Anything) | Egonex AI | see upstream | A codebase turned into an explorable knowledge graph |
| [CapSoftware/Cap](https://github.com/CapSoftware/Cap) | Cap Software | see upstream | Screen recording, plus the `cap` and `cap-demo` skills the demo pipeline shells out to |
| [linshenkx/prompt-optimizer](https://github.com/linshenkx/prompt-optimizer) | linshenkx | AGPL-3.0 | Prompt rewriting over MCP. Run as a container, never copied in, because AGPL |
| [gastownhall/beads](https://github.com/gastownhall/beads) | gastownhall | see upstream | `bd`, an issue tracker the agent reads and writes, so work survives a context reset |
| [ankitects/anki](https://github.com/ankitects/anki) | Anki | AGPL-3.0 | Where the flashcards the study skills write actually live |
| [p0deje/Maccy](https://github.com/p0deje/Maccy) | Alexey Rodionov | MIT | Clipboard history, so a value scrolled past is recoverable |
| [jdepoix/youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) | Jonas Depoix | MIT | The primary engine behind `yt-transcript` |
| [millionco/react-doctor](https://github.com/millionco/react-doctor) | Million | see upstream | Per project, by `install.sh`, and only when it finds React |
| [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Anthropic | see upstream | context7, serena, playwright, vercel, railway, expo, pinecone, bigquery |

MCP servers installed from the [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)
tree (`fetch`, `time`, `git`, `sequentialthinking`), plus
[antvis/mcp-server-chart](https://github.com/antvis/mcp-server-chart) and
`chrome-devtools-mcp`. Keyed servers, installed only when the key already
exists: [exa](https://github.com/exa-labs/exa-mcp-server),
[tavily](https://github.com/tavily-ai/tavily-mcp),
[firecrawl](https://github.com/firecrawl/firecrawl-mcp-server),
[elevenlabs](https://github.com/elevenlabs/elevenlabs-mcp),
[browserbase](https://github.com/browserbase/mcp-server-browserbase),
[magic](https://github.com/21st-dev/magic-mcp). The catalog came from
mcpmarket.com, checked entry by entry against npm and PyPI, and two of its own
most-engaged entries did not survive that check.

### Ideas taken, code not taken

Read, learned from, and deliberately not installed. The full verdicts are in
[docs/mac/LANDSCAPE.md](docs/mac/LANDSCAPE.md) (every tool in the space with
stars, license, and a reason) and [docs/STARRED-AUDIT.md](docs/STARRED-AUDIT.md)
(115 starred repos, 17 installed, and a stated reason for each of the other 98).

The three worth reading even if you never install them:

- [OpenAdaptAI/OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt). Record a
  human demonstration, compile it to a program, and report VERIFIED only when an
  independent check agrees. The only project in the category treating
  reliability as the primary problem. `mac-runtime`'s plan/verify/log shape
  comes from here.
- [AmrDab/clawdcursor](https://github.com/AmrDab/clawdcursor). Accessibility
  tree and OCR fused into one addressable map, screenshot only when needed,
  every action through one safety gate.
- [anthropics/claude-quickstarts](https://github.com/anthropics/claude-quickstarts)
  `computer-use-demo`. The canonical see-act-see loop in under a thousand lines.

Also read: [bytedance/UI-TARS](https://github.com/bytedance/UI-TARS) and
[UI-TARS-desktop](https://github.com/bytedance/UI-TARS-desktop),
[trycua/cua](https://github.com/trycua/cua) and
[trycua/acu](https://github.com/trycua/acu),
[simular-ai/Agent-S](https://github.com/simular-ai/Agent-S),
[microsoft/OmniParser](https://github.com/microsoft/OmniParser),
[microsoft/UFO](https://github.com/microsoft/UFO),
[microsoft/fara](https://github.com/microsoft/fara),
[ghostwright/ghost-os](https://github.com/ghostwright/ghost-os),
[bytebot-ai/bytebot](https://github.com/bytebot-ai/bytebot),
[OthersideAI/self-operating-computer](https://github.com/OthersideAI/self-operating-computer),
[openinterpreter/openinterpreter](https://github.com/openinterpreter/openinterpreter),
[e2b-dev/open-computer-use](https://github.com/e2b-dev/open-computer-use),
[showlab/ShowUI](https://github.com/showlab/ShowUI),
[yuruotong1/autoMate](https://github.com/yuruotong1/autoMate),
[mediar-ai/terminator](https://github.com/mediar-ai/terminator),
[screenpipe/screenpipe](https://github.com/screenpipe/screenpipe),
[Hammerspoon](https://github.com/Hammerspoon/hammerspoon),
[andelf/axcli](https://github.com/andelf/axcli),
[AgentiLoop/Agent](https://github.com/AgentiLoop/Agent),
[skalesapp/skales](https://github.com/skalesapp/skales),
[callstack/agent-device](https://github.com/callstack/agent-device),
[X-PLUG/MobileAgent](https://github.com/X-PLUG/MobileAgent),
[browser-use/browser-use](https://github.com/browser-use/browser-use),
[alibaba/page-agent](https://github.com/alibaba/page-agent),
[Skyvern-AI/skyvern](https://github.com/Skyvern-AI/skyvern),
[web-infra-dev/midscene](https://github.com/web-infra-dev/midscene),
[openai/openai-cua-sample-app](https://github.com/openai/openai-cua-sample-app).

Apple app MCP servers studied for the data layer:
[supermemoryai/apple-mcp](https://github.com/supermemoryai/apple-mcp),
[carterlasalle/mac_messages_mcp](https://github.com/carterlasalle/mac_messages_mcp)
(the `attributedBody` decode, which is why the `texts` skill can read messages
whose `text` column is empty),
[peakmojo/applescript-mcp](https://github.com/peakmojo/applescript-mcp),
[joshrutkowski/applescript-mcp](https://github.com/joshrutkowski/applescript-mcp),
[achiya-automation/safari-mcp](https://github.com/achiya-automation/safari-mcp).

Dictation research behind Plynn, in [plynn/docs/PLAN.md](plynn/docs/PLAN.md):
[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0, the
ASR/VAD backbone), [Handy](https://github.com/cjpais/Handy) (MIT, paste
read-receipt and secure-input taxonomy, ported),
[VoiceInk](https://github.com/Beingpax/VoiceInk) (GPL-3, read-only reference and
never copied), WhisperKit, parakeet-mlx, and Apple's WWDC25 session 277 plus
TN2150.

Ecosystem and method reading, in [docs/ECOSYSTEM.md](docs/ECOSYSTEM.md):
[cloudflare/vibesdk](https://github.com/cloudflare/vibesdk),
[coleam00/context-engineering-intro](https://github.com/coleam00/context-engineering-intro),
[sha256/local-d1](https://github.com/sha256/local-d1),
[cpjet64/vibecoding](https://github.com/cpjet64/vibecoding),
[roboco-io/awesome-vibecoding](https://github.com/roboco-io/awesome-vibecoding),
[punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers),
[VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills),
[ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills).

### Academic and research sources

| Source | Where it lands |
| --- | --- |
| Southeast University graduate course 知识图谱 (Knowledge Graphs), Prof. Peng Wang, [npubird/KnowledgeGraphCourse](https://github.com/npubird/KnowledgeGraphCourse) | `skills/graph-engineering/` in full. Nine lectures distilled and translated from the Chinese slide decks into an English curriculum plus three reference files |
| Roediger and Karpicke, "Retrieval-Based Learning: A Decade of Progress" (ERIC ED599273), plus the 2006 and 2007 Purdue Learning Lab papers | [crafts/study-guide.md](crafts/study-guide.md), and through it `study-guide`, `study-system`, and the `guide` CLI. The 13%-versus-56% forgetting result is why a guide never presents material back |
| macOSWorld, [arXiv 2506.04135](https://arxiv.org/html/2506.04135v4) | [docs/mac/BENCHMARKS.md](docs/mac/BENCHMARKS.md). 202 tasks, 30 apps, proprietary agents above 30% and open models below 5% |
| OSWorld and OSWorld 2.0, [arXiv 2606.29537](https://arxiv.org/pdf/2606.29537) | Same. The 85% versus 20.6% gap, and the compounding-failure math (twenty steps at 95% is 36%) that makes see-act-see mandatory rather than ceremonial |
| MacArena [2606.06560](https://arxiv.org/pdf/2606.06560), OSUniverse [2505.03570](https://arxiv.org/pdf/2505.03570), OpenComputer [2605.19769](https://arxiv.org/pdf/2605.19769), ScreenSpot | Same |
| Daniele Procida, Diátaxis (diataxis.fr) | [crafts/onboarding-kit.md](crafts/onboarding-kit.md) and `skills/kit-builder/`. Tutorial, how-to, reference, explanation, and why mixing two serves neither |

### Craft research

Five genres studied before producing in them, because driving the tool is not
the skill. Each file is rules only, each rule falsifiable, each traceable to a
practitioner. The rule that forced this is
[.claude/rules/research-the-craft.md](.claude/rules/research-the-craft.md), and
`craft-gate` is the code that enforces it.

| Craft | Studied from |
| --- | --- |
| [Demo video](crafts/demo-video.md) | Two teardowns by the co-founder of HowdyGo, who has made and reviewed thousands of SaaS demos, plus Consensus' five-example piece |
| [Daily brief](crafts/daily-brief.md) | Becky Root on writing the President's Daily Brief (The Cipher Brief), and Aaron Berman's guide to writing for busy decision-makers |
| [Application essay](crafts/application-essay.md) | A former Dartmouth admissions officer's account of reading the pile, College Essay Guy and Collegewise on show-don't-tell, plus one outcome retro diffing five rejections against two advances in a single cycle |
| [Study guide](crafts/study-guide.md) | Roediger and Karpicke, above |
| [Onboarding kit](crafts/onboarding-kit.md) | Diátaxis, above |

### People, by permission

The `people` skill and CLI are ported from **Amber's identity service** with the
permission of its authors, **Karthik Devarakonda** and **Sagar Tiwari**. Amber
is a multi-tenant Cloud SQL service. This is one SQLite file on a laptop. The
ideas carried over, the tenancy did not.

`skill-scan`'s rubric weights started from a public review of 100 Claude skills
that reported roughly 70% of them failing it. The five dimensions and the
thresholds are ours.

---

## Part 2: what is not from anywhere else

Nothing below ships with Claude, and none of it is a wrapper over something
that does. Ordered by how load-bearing it is.

**Enforcement is code that runs, not a paragraph.** This is the governing idea
and every item after it is a consequence. A repo full of good judgement in
markdown fires almost none of it, because a rule in `CLAUDE.md` is a user
message competing with everything else by hour three of a session. So the
judgement gets compiled into hooks and exit codes. `slop-guard` refuses a turn.
`craft-gate` exits 1 and stops production. `prose-guard` reads files written
through the Write tool, not just chat replies. The test of a rule here is
whether something breaks when it is violated.

**Research the craft before producing the artifact, gated in code.** Asked to
record a product demo, this kit once drove the UI competently and produced four
taps on a tab bar. Every mechanical part worked and the artifact was worthless,
because nothing had asked what makes a demo good. `craft-gate <genre>` now exits
1 until the craft has been recorded to `~/.chewbacca/craft/<genre>.md`, so the
research happens once and every later session inherits it.

**A four-layer writing detector stack, with a house list at the top.**
`ai-scan` wraps avoid-ai-writing's vocabulary detector. `slop-check` is ours and
reads structure instead: bolded drama fragments, colon reveals, stacked
one-liners, the tells that survive an edit pass looking only for banned words.
`prose-check` is ours and reads one specific person's list, sourced to
`voice.md`. `code-slop` is ours and is the first of any of them to look at code
rather than prose, because narration comments and hand-rolled stdlib are a trust
problem, not a style problem. The reason all four exist: `ai-scan` gave a draft
a clean bill while it carried six kickers, three not-X-but-Y constructions and
two announced turns.

**Nobody should ever have to type a slash command.** A command is a keyboard
shortcut for someone who already knows the kit. The person it is for types
"what's due" and never types `/due`. So every command has a skill covering the
same ground, the skill is the real artifact, and `tools/commands.py` ranks
commands by how little of their language any skill shares. Three consequences
follow: a skill description is load-bearing product surface, malformed
frontmatter is a total silent outage rather than a lint warning, and judgement
must live in the skill or the spoken path gives a worse answer than the typed
one.

**Kits.** A repo somebody lives inside for weeks while an agent walks them
through a process they have never done and will not do again for years:
applications, appeals, accommodations, estate admin, a fundraise. `kit-builder`
has a seven-property test for whether something should be one at all, because
most things should stay skills. `kits` finds every kit on the machine and
`kit-route.sh` fires on the actual prompt to route into one, because a list read
at session start has lost to everything else in context by the time it matters.

**Crafts as a first-class artifact type.** Five genre files, extensible, each
one rules-only and falsifiable, each with a stated protocol for when the brief
contradicts the craft: name the rule it breaks in one line, build the version
that works, offer the literal version separately. Delivering the anti-pattern
silently and delivering something unasked-for silently are both wrong.

**The `people` CLI as identity-before-facts.** Ported design, but the rule is
ours and came from a real near-miss: this address book holds fourteen people
named Tobias, two called Tobias Lund and two called Tobias Lane, one of them
stored twice for editing a LinkedIn vanity URL between exports. Resolve the
person before writing the fact, and treat a refusal to resolve as the answer
rather than the obstacle.

**A coursework ledger, machine-readable, with per-course AI policy.** Built out
of the actual syllabi. It is checked before helping with graded work, because
one course bans AI, one requires prompt disclosure, and one allows ideation
only. Nothing in a general assistant knows that a given class forbids it.

**Second brain as one repo with enforced invariants.** One fact, one home, plus
a `brain-check.sh` that refuses a commit over broken wikilinks, an orphaned
note, an em dash, an emoji outside the README footer, a memory file missing from
the index, or `MEMORY.md` past its byte budget. Every one of those is a failure
that already happened, which is the only reason it is checked.

**A context budget, measured and enforced.** 28,000 tokens always-on, with
`doctor.sh` failing the build when it is exceeded and `tools/context_cost.py`
reporting what each import costs. Twelve stack rules moved out of always-on
into a skill for exactly this reason: a Python service should not pay for the
Tailwind rules.

**`doctor.sh` as a promise-checker.** 81 checks, and the interesting ones verify
that what a skill promises actually exists: every tool a skill names is on PATH,
every frontmatter block parses, every always-on import resolves, every hook is
executable and fast, and each failure names the skill that made the promise.

**A layered model of Mac control, with vision as the last resort.** Seven
documented layers from AppleScript up to pixels, a decision tree, and the
finding that the whole field gets wrong on macOS: nearly everything is ported
from a cross-platform design where vision is the only universal option, so
vision becomes the default here too, leaving a free, fast, structured
accessibility API on the table.

**`mac-runtime`, a typed and verified plan instead of improvised bash.** Plans
are type-checked, executed, verified and logged, so a multi-step task that ends
in an irreversible action can be debugged afterward. This is the OpenAdapt idea
applied to an agent that writes its own plan.

**The HUD.** Live interfaces drawn on the screen above everything, no browser
and no window, for when the answer should be seen rather than told.

**Chewie.** A held-warm Claude session behind Plynn's dictation: say "Chewie" or
hold left Option and it routes to Claude Code with these CLIs, skills and second
brain instead of typing the words out. Small talk goes to a local model. Answers
are shown and copied, never pasted, because a reply to a question is not
dictated text. About 26 seconds down to about 5.

**`guide`, retrieval that persists.** A study session's questions used to die
with the session. A guide is one HTML file plus a JSON sidecar of per-topic
results, so the next session opens on the three things that were missed instead
of asking what to review.

**The thousand-things list.** [docs/1000.md](docs/1000.md) is a thousand
specific ways this kit is incomplete, and [docs/1000-STATUS.md](docs/1000-STATUS.md)
is generated from the commit log rather than written by hand: a commit closes an
item by naming it. It also records the 14 items that were simply wrong when
written. This page is item 814.

**The starred-repo audit.** All 115 repos the author has starred, checked
against what the installer actually wires, with a stated reason for each of the
98 skipped, so the question does not have to be asked twice.

**A prayer opener, customizable, that ships whole.** First words of every
response, specific to the moment rather than a formula. It is the one thing in
here that is not an engineering decision, and it does not get stripped out of
demos, screenshots or anything else.

---

All glory to God! ✝️❤️
