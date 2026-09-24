# Learning any site: what the leaders do, and what Chewbacca takes from them

Research from 2026-09-23. The question: how the best web agents turn a page
into something a model can act on, and what Chewbacca should copy so it can
learn a site once and use it fast afterwards. The companion is
[LEARNING-TO-ACT.md](LEARNING-TO-ACT.md), which lays out the plan for
procedures and maps; this one covers the reading.

## How a page becomes something a model can use

Every agent picks one of three representations, or mixes them.

| Representation     | What it gives the model                             | Cost and failure                                                     | Who leans on it                                |
| ------------------ | --------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| Raw DOM            | everything, including what is hidden                | hundreds of thousands of tokens on a real page, and past 1M at worst | nobody, uncompressed                           |
| Accessibility tree | every control by role and visible name, focus state | a few thousand tokens; misses canvas UIs and sites with bad markup   | browser-use (89.1% WebVoyager), Playwright MCP |
| Screenshot         | layout, position, anything drawn                    | cheap in tokens, can't see what's covered, grounding a click is hard | OpenAI CUA (87%), Anthropic computer use       |
| Hybrid             | the tree to act, the picture to check               | two reads per step                                                   | Project Mariner (83.5%), Surfer 2 (97.1%)      |

The tree wins on the axis Chewbacca cares about. Its role-and-name pairs are
also the locators a procedure should click by, because they survive a site
redeploy and a CSS class does not. A saved snapshot is therefore already
written in the vocabulary a procedure runs on.

One warning from 2026 data: accessibility markup on the web is getting worse
for the first time in six years. Sites with poor markup come back thin in the
tree. That is where Chewbacca's existing ladder takes over: `chewie` climbs
from data to scripting to the tree to vision, and a thin tree is the signal to
climb.

## How the leaders stop paying the model twice

This is the finding that matters most. Four separate teams built the same
thing in 2025 and 2026:

- **Stagehand** (Browserbase): the first `act()` runs the model and caches the
  selector and action. Later runs replay the cache without calling the model.
  When a cached selector fails, it calls the model once, finds the new
  element, and rewrites the cache (self-healing).
- **Skyvern**: after a successful run, it generates Playwright code from what
  the agent did. Repeat runs execute the code and skip the model. Skyvern
  claims 3 to 5 times faster and up to 70% cheaper.
- **browser-use**: an action cache in its tools layer.
- **Project Mariner**: Teach & Repeat. Show it once and it repeats the task.

The pattern: explore with the model once, keep the deterministic skeleton,
and fall back to the model only at the step that broke. It is the plan in
LEARNING-TO-ACT.md, arrived at independently. The one place Chewbacca differs
is on purpose: the cache is a plain directory a person can read and edit
(`procedures/<name>/`), not an opaque store.

The counterweight is a 2026 budget-matched study. Memory modules that feed
learned _text_ back into the prompt did no better than simply giving the agent
more steps. What pays is learned _code_ that runs with the model out of the
path, which is exactly what the four teams above ship.

## Where "vectorization" fits

Embeddings show up in two places in this field, and only one of them is worth
building now.

1. **Grounding an element.** Instead of storing a brittle DOM path, some
   systems embed each element's description and match the target by cosine
   similarity (DOMSTEER uses `text-embedding-3-small`). Role plus visible name
   gets most of the way there without a model, because it is already
   semantic. Build this later, when a procedure fails on a renamed button and
   the name alone no longer matches.
2. **Finding what the kit already knows.** Before exploring, match the task
   against every procedure and map. At a few dozen files written in the kit's
   own words, full-text BM25 matches the right one with no key, no model and
   no index on disk. Embeddings pay off at the registry stage: thousands of
   procedures written by strangers in different words.

## The other direction: sites exposing tools

WebMCP lets a site register its own tools for agents (`document.modelContext`,
formerly `navigator.modelContext`). It shipped in Chrome 146 Canary in February
2026, entered an origin trial in Chrome 149 (announced at Google I/O on May 19)
and moved to `document` in 150. Stable support is expected in Q4 2026. When a
site offers tools, they are the cheapest layer above the tree, and `chewie`'s
ladder should try them first. Almost no site offers them yet, so this is a
watch item, not a build.

## What got built from this

`bin/site`, with tests in `tests/test_site.py`:

```
site find "places to stay in lisbon"      # procedures, maps and saved pages that fit, best first
site snap https://example.com             # the page as the tree: controls by role and name
site snap https://example.com --save      # filed under maps/<host>/pages/, MAP.md started
site show example.com                     # the map and every page read so far
```

- `find` is the retrieval-before-acting step that LEARNING-TO-ACT.md listed as
  missing. Its score floor was measured on the real maps: true matches scored
  1.2 to 6.7 and unrelated queries 0.6 or below.
- `snap` reads with headless Chromium and saves only with `--save`. A human
  check, a rate-limit page or a page with no controls comes back `BLOCKED`
  (exit 3) and nothing is saved. Vrbo returned "Too Many Requests" on the first
  live try. The kit does not try to look human. A blocked task moves into the
  person's own Chrome through `chrome-js`.

## Measured: Jev as the pointer

`tests/eval_ground_jev.py` runs 30 spoken-style requests over six real pages
(Airbnb, Booking, Wikipedia, GitHub, Hacker News, Stripe), each page's
controls going to Jev as one choice question. It was run 2026-09-23 and cleared
its falsifier (top-1 under about 90%, or wrong answers as confident as right
ones). The scores stay off this public repo: TypeSafe's customer agreement
(2.3(f)) bars publishing Jev performance results.

What it taught is design. The answer key was corrected in three places where
the page proved Jev's pick right: Booking has two support links, Wikipedia
links Español directly, and Stripe's two "Contact sales" controls differed only
by an invisible U+2060 character, which `site snap` now strips. The one real
miss was "open the comments on the Claude post" on Hacker News: the tree
flattens the story list, so a comments link loses the row it belongs to. Its
confidence was low, so a confidence-shaped interface ("act at 0.7 or above,
otherwise show the top two, otherwise ask") would have asked instead of
clicking the wrong link. Thirty rows is a small set, so this is a go for
building, not proof it works everywhere.

## Next to build, in order

0. **The Jev pointer in `hud-guide`.** Add a choice over `site snap`
   controls with the 0.7 and top-two bands above. Give each option its row
   context (the story title next to "918 comments") to fix the one miss.
   Send page text through `amber-redact` first, because the page leaves the
   Mac.

1. **Snap inside the person's Chrome.** `chrome-js` can walk the page's
   controls on a signed-in session (Clay, Blackboard). It waits on Chrome's
   "Allow JavaScript from Apple Events" setting being on.
2. **The recorder.** Every chewie, chrome-js and Playwright step in a
   free-form session gets appended to a trace, as described in LEARNING-TO-ACT.md.
3. **Distill and self-heal.** Turn a successful trace into
   `procedures/<name>/run.py` with role-and-name locators. On a failed step,
   hand that one step to the model and rewrite it, the way Stagehand does.
4. **Element embeddings**, only once a renamed control actually breaks a
   procedure.
5. **WebMCP first**, once stable Chrome ships it.

## Sources

- [Beyond Pixels: DOM downsampling for LLM web agents](https://arxiv.org/pdf/2508.04412)
- [Building browser agents: architecture, security, practical solutions](https://arxiv.org/pdf/2511.19477)
- [The accessibility tree is how AI agents read your site, and it's breaking](https://www.searchenginejournal.com/the-accessibility-tree-is-how-ai-agents-read-your-site-its-breaking/578171/)
- [Firecrawl: best AI browser agents in 2026](https://www.firecrawl.dev/blog/best-browser-agents)
- [Steel.dev WebVoyager leaderboard](https://leaderboard.steel.dev/leaderboards/webvoyager/)
- [browser-use state-of-the-art technical report](https://browser-use.com/posts/sota-technical-report)
- [Stagehand act() and caching](https://docs.stagehand.dev/v3/basics/act)
- [Skyvern cost control and cached code](https://www.skyvern.com/docs/developers/optimization/cost-control)
- [Field guide to browser harnesses in 2026](https://theairuntime.com/p/the-complete-field-guide-to-browser)
- [GUI agents for in-situ assistance (DOM grounding by embedding)](https://arxiv.org/pdf/2604.14668)
- [WebMCP browser support in 2026](https://dev.to/ai-agent-economy/webmcp-in-2026-which-browsers-support-navigatormodelcontext-complete-compatibility-status-1oe4)
- [The state of WebMCP, July 2026](https://www.spronta.com/blog/state-of-webmcp-july-2026/)

Built with Chewbacca
