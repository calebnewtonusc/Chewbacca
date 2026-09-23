# Backlog

Opened 2026-09-21 because Caleb asked *"how is chewbacca storing during session
important context? I feel like ur gonna forget the to dos we set at the
beginning of this session?"* and the answer was that it was not storing it at
all. `~/.chewbacca/session-state/` tracks which files a session wrote, which is
not the same thing as what a session decided.

**This file is the store.** It lives in the repo rather than in `~/.chewbacca`
so it survives a session, a machine, and a person, and so Gavin, Otis, Seabass
and Ravi see the same list. `backlog` is the CLI over it, and `SessionStart`
injects whatever is open.

Status: `open`, `doing`, `blocked`, `done`, `dead`. A `dead` item keeps its
reason, because deleting it means somebody proposes it again in three weeks.

---

## The direction

Caleb, 2026-09-21, and this is the item the rest serve:

> *"We have tried our best to make chewbacca good at many things, we need to get
> it to the point where it is an expert at literally everything. And an expert
> at learning."*
>
> *"If we can make Chewbacca do ANY job like Aryaa said is possible, chewbacca
> could be insane bruh. We're gonna help so many ppl be empowered to live
> creative, discerning lives instead of monotone non thinking ones. We're gonna
> build in prompt engineering for ppl to become human without needing to be an
> engineer."*

**The goal is not an impressive tool. It is a person who thinks better.** The
metric is already written down, from Jamie Winship by way of
[methods/doctrine.md](methods/doctrine.md): *are the people around us being
transformed?* Not headcount, not revenue, and here not skill count either. A
version of this that makes someone more capable and less able to work without it
has failed on its own terms, however impressive the demo.

### What exists to build on

| Piece | State |
| --- | --- |
| 105 skills | Installed. **Nothing routes to them.** See item 3, which is the hard blocker |
| `bin/method`, `methods/` | Picks a process and injects a falsifier before work starts. Works |
| `methods/doctrine.md`, `methods/proverbs.md` | The operating frame and one standing check per process. Works |
| `memory/`, `bin/scars` | Failures written down so the next session inherits them |
| `bin/evolve`, `bin/fitness` | A benchmark, a score, an archive, worktree isolation. The machinery for self-improvement exists and has barely been pointed at anything |
| `bin/consolidate`, `bin/maintain` | Slow offline consolidation, modelled on how memory moves from hippocampus to neocortex |

**The measured state of this, as of 2026-09-21, is in
[docs/LEARNING.md](docs/LEARNING.md), and it is that the loop has never
closed once.** Item 0 is the smallest next step.

### What "expert at learning" would concretely mean

Not a bigger prompt. Four things that can be tested:

1. **Acquiring an expertise on demand.** Given a domain it has never seen, it
   finds the practitioners, extracts the rules rather than the vibes, and writes
   them into a skill with evals. `.claude/rules/research-the-craft.md` already
   states this as a rule and `craft-gate` already enforces part of it. The gap
   is that a human still does the acquiring. Three corpora have been taken this
   way already (Winship, Erik Fish, Staci Rivera, ~652k words), by hand.
2. **Skills as executable programs, not prose.** Voyager's result is that a
   skill library of runnable code compounds where a library of descriptions does
   not. `skill-scan` measures exactly this and calls it determinism, and most
   skills here score 0 or 5 out of 25 on it.
3. **Empirical self-improvement with an archive.** The Darwin Gödel Machine
   (arXiv 2505.22954) replaces formal proof of improvement with measured
   benchmark performance and keeps every variant rather than only the best,
   because a worse intermediate is often the path to a better one. `bin/evolve`
   already has the archive and the worktree isolation. It needs a real benchmark
   pointed at it and a reason to run.
4. **Teaching, so the person does not need the tool.** This is the one that
   makes it Caleb's project rather than another agent. His words: *prompt
   engineering for people to become human without needing to be an engineer.*
   The nearest thing built is his own essay method, recorded in
   [methods/creative.md](methods/creative.md): dump everything, then be
   interviewed, so the person holds the judgment and the model holds the
   questions. That inversion generalises and almost nothing else does.

### The honest blockers, in order

1. **Skill routing.** 105 skills and nothing names one. Until a task reaches the
   expertise that already exists, "expert at everything" is 105 files nobody
   opens. Item 3.
2. **No definition of expert.** There is no benchmark that says whether it is
   better at a job this week than last. `bin/fitness` scored 84.8 once (139 of
   164) and **which 25 failed was never written down**, so the number is not
   actionable. Fix that before anything claims to be improving.
3. **Aryaa's ladder.** His point is that influence runs system prompt (weakest),
   context injection, LoRA, steering vectors, weights, tokeniser, and that the
   move is to consolidate downward. Almost everything here sits on the top two
   rungs. That is a real ceiling and it should be named rather than worked
   around. Caleb has read his whole public corpus and has not talked to him yet:
   *"I'll reach out once chewbacca is gas enough."*

### The hard line on this one

A system that can do any job is a system that can do harm at scale, and the
person it most easily replaces is the one it was supposed to free. The doctrine
file already carries the counterweight and it applies here first: the test is
whether the person can now do something they could not, **and eventually without
it.** Build the teaching half at the same time as the doing half, not after.

## Now

| # | Item | Status | Notes |
| --- | --- | --- | --- |
| 0 | **Close the learning loop. The score has never moved.** | open | Caleb, 2026-09-21, asked for a big emphasis on this. Ten `fitness` runs, `structural_score` **90.12 in all ten**; `behavioural_score` recorded once; `failed` is the integer 25 with no record of WHICH 25, so credit assignment is impossible; `evolve` never merges, so an archive with no selection is a museum; and the 86 asks in `~/.chewbacca/asks.jsonl` are read by nothing. Five ordered steps and the hard line in [docs/LEARNING.md](docs/LEARNING.md). **Step 1 is small and blocks the rest: make `fitness` record which cases failed, by id.** This is item 32 and the "expert at learning" direction above, made concrete |
| 1 | **GTM engineering for Jonah and his 5 companies** | doing | Sagar, 9/20: "i need you to do one thing." Tooling shipped at `calebnewtonusc/prometheus-targeting` (private). **Blocked on one fact: which 5 companies are raising.** One-pagers exist for 8 |
| 2 | **Onboarding: single paste, allow-once permissions, no visible API keys, Mac then Windows** | open | Caleb's #8. Now evidence-backed: Sagar called the installer malware on 9/20 and a second person flagged permissions the same afternoon. Closing screen fixed in `8e47d04`; the flow itself is not |
| 3 | **Skill descriptions cannot route** | done | 105 skills installed, nothing names one when work starts. `skill-route.sh` built and unregistered in `4cca1fd` after misfiring twice. skill-scan grades the descriptions at 16-21 trigger points of 25. Fix descriptions first |
| 4 | **TTS site** | open | Needs the design corpus in #5. ArcRank mockup shows the real competitor set: SparkSC, Sigma Eta Pi, LavaLab, TroyLabs, VC Academy |
| 5 | **Deep UI/UX research, component and workflow frameworks** | doing | Caleb's #2. Four reference images captured 9/21. `dembrandt` (3,506 stars) already extracts tokens, type scale, motion and hover patterns from a live site into a DESIGN.md. **Research half done 9/22:** ux-engine now holds 92 transcribed practitioner videos on craft and on how taste is acquired, searchable by timestamp with `ux-video`, synthesised in `research/17-video-corpus.md`. The frameworks half is still open: the component preset layer exists at 9 presets and the workflow layer does not exist |
| 6 | **Self-correcting cold outreach** | open | Caleb to Sagar: "has anyone ever built that?" Sagar: "unless you set up some cli magic." Caleb: "cli magic it is." The genuinely novel item |
| 50 | **The HUD orphans its listener on every restart, and voice silently dies** | done | Fixed 2026-09-22 in `bin/hud-listen`, no Swift change. The listener records its parent at start and exits instead of reconnecting once that parent is gone, and it takes an exclusive `flock` on `<socket>.listener.lock` before building its prompt, so a second one leaves naming the holder's pid. The 2 s grace in main.swift could not do this: the orphan's reconnect backoff grows to 5 s. Two tests in `tests/test_hud_listen.py` reproduce both halves against the old script (two subscribers; an orphan that never exits) and pass against the new. Live on Gavin's Mac, where BobHUD runs as an app with no KeepAlive agent, so the repro is kill and `open -a`: two restarts, each time the old listener logged "the display that started this listener is gone" and one new listener came up parented by the new BobHUD. The one running before the fix was a manual `--verbose` run from 2026-09-21 13:05, ppid 1, a day of reconnects on day-old code. Caleb, 2026-09-21: *"it is pretty fucked up rn"*, handed to Gavin. `KeepAlive` restarts BobHUD; the `hud-listen` it spawned survives as `ppid=1`, disconnected from the new socket. The new HUD's launch spawn then sees a listener already running by name and the person holds the talk key into nothing. Seen three times in one evening (pids 90698, 17618, and again after an auto-restart). The socket's `send()` is a deliberate no-op with no subscribers, so **nothing anywhere reports it**. Fix is one of: kill the child in `applicationWillTerminate`, have `hud-listen` exit when its socket drops, or have the launch spawn check subscribers rather than process names. Repro: `launchctl kickstart -k gui/$(id -u)/com.calebnewton.chewbacca.hud` twice, then `ps -o ppid= -p $(pgrep -f hud-listen)` |

## Next

| # | Item | Status | Notes |
| --- | --- | --- | --- |
| 51 | **Work through the 59 design sources** | open | Caleb sent these 2026-09-23 with "we'll go through all of these a later day". Saved as data at `ux-engine/effects/sources.json`, categorised, with his own twelve-to-keep marked `priority`. **How they get used matters more than the list:** `research/12` is explicit that a reference library is not a retrieval store, it is "training data for a classifier, and it only works while you are actively judging items against each other", so these feed `ux-trial` as paired comparisons rather than becoming a swipe file. Kellman: what transfers is attuned selectivity, not stored instances. **Five blind spots they would fill**, which is the actual reason to keep the list: flow-level patterns (the effects catalog is element-level and has nothing about multi-step sequences), mobile (the catalog is entirely desktop-web), copywriting structure (`saaspages.xyz`, nothing in the kit covers it), tested conversion evidence rather than taste (GoodUI, Baymard), and section-level solutions (Sections.wtf, CTA Gallery, SupaHero). **Security note preserved in the file:** do not follow any historical Rowlab link, the domain expired and redirects to a scam page |
| 7 | Animation extraction by navigating a live UX | doing | **Answered 2026-09-23 by an adversarial prior-art pass: PARTIAL, not novel.** `ux-crawl --states film` now scrolls at a constant 9px per animation frame and records every frame from inside the page; `ux-film` labels each element SPAWN / CONSTANT / SCROLL-LINKED / STATE-SWAP / STATIC. But **CinematicBench** (`MustBeSimo/web-design-studio`, MIT, 61 reference sites captured) already ships the same constant-rate rAF scroll ramp, the same in-page probes, and derives three of the five categories as page-level scalars. It samples elements at only two scroll depths, so it cannot tell a loop from a one-shot, which is the one category it lacks. **component-picker #117** specifies the per-element `[t, value]` tracks and loop-period detection, open and unimplemented. And the **Layout Instability API** has done per-element per-frame re-render attribution in every Chromium browser since 2019 (`LayoutShift.sources`, excludes transform-driven movement), which is a better STATE-SWAP discriminator than the plateau heuristic in `ux-film`. **Next step: use LayoutShift instead of the heuristic.** Surviving novelty is thin and is assembly, not capability |
| 8 | Replace 5 archived MCP servers | open | github, postgres, puppeteer, google drive and slack are `servers-archived` reference code. Live replacements: `github/github-mcp-server`, `microsoft/playwright-mcp`, `korotovsky/slack-mcp-server` |
| 9 | Add Context7 and MotherDuck MCP | open | Context7 (62k stars, 3.5M npm/mo) serves version-correct docs, which is the mechanical cause of slop UI. MotherDuck queries a local CSV in place, which is the 1M-row problem |
| 10 | Hand control, the 10% that is real | doing | Apple Vision, not MediaPipe. Measured 7.56ms one hand, 4-6% of one core sustained on the M4 Pro. `HandTracker.swift` ships palm-to-dismiss and point-to-deixis on `feat/hand-control`; `OutboundEvent.region` already exists. **Plan now written: [docs/SPATIAL-OS.md](docs/SPATIAL-OS.md)** |
| 11 | Framing stage, the level above `method` | open | Researched 2026-09-21. **Build the opposite of what was asked.** Deep meta-planning is the anti-pattern: optimal thinking length varies 7.5x with difficulty, and Russell proves the regress has no interior solution, so the budget is a constant set at design time, not a computation (optimal metareasoning is NP-hard and PSPACE-hard). Spec: budget by reversibility (two-way door = zero framing, one-way = full stage), one artifact, "write the problem a second way such that a different plan follows." Justified by Einstellung, not by the framing literature, which is weak: experts drop 3 SD when a workable answer is already in mind and report searching while eye tracking shows they are not |
| 12 | Whisper / ElevenLabs for the Jarvis feel, max out Plynn | open | Caleb's #4. Gavin: subscriptions are not an option, so on-device only |
| 13 | Sound design for the HUD | open | Caleb's #14 |
| 14 | Open-source Granola | open | Caleb's #10 |
| 15 | Identify open-source versions of apps worth integrating | open | Caleb's #11 |
| 16 | Synthesize everything built in openclaw | open | Caleb's #16 |
| 17 | Synthesize every GTM thing | open | Caleb's #17. Partially started by the Clay work |
| 18 | World class at Clay, then other software | open | Caleb's #18. Sagar, 9/20: "Focus on clay" and "benchmark everything against clay" |
| 19 | LinkedIn scraping | open | Caleb's #15. **Note the risk:** the best LinkedIn MCP drives the site with your own session cookie. ToS violation, account-ban risk. Clay does this without risking the account |
| 20 | Karthik's changes when he onboards | open | Caleb's #13 |
| 21 | Doctor Strange effects | open | Caleb's #21. Research verdict stands: a demo, not a feature, Gavin independently agrees, ship as a separate target with a README saying so. **But the cost collapsed:** Caleb already wrote the portal in `calebnewtonusc/OpenVision` on 2026-09-04, ~100 lines of Canvas 2D reading 21 landmarks. Two days, not two weeks. See [docs/SPATIAL-OS.md](docs/SPATIAL-OS.md) |
| 22 | Research `me.sh` and `mog` | open | Caleb's #1. Not yet looked at |
| 23 | Work for any LLM, simply, in the browser | open | Caleb's #9 |
| 24 | Iron man maxing | open | Caleb's #5. Needs a definition before it is actionable |
| 25 | Rest of the todo in the Chewbacca group chat | blocked | Gavin's iCloud note, `icloud.com/notes/0f5WeJHPg27B2DB_3-z1Nyweg`. Not in Caleb's local store, so Gavin has to paste it |
| 26 | Audit every file for staleness and fit | open | Caleb, 9/21: "So much of chewbacca is outdated / out of sync / not fitting well w the rest." Needs a real pass, not a spot check |
| 27 | Team check-in so two people do not build the same thing | open | Gavin's ask on the 1am call. Three shapes proposed in `docs/handoffs/2026-09-21-team-context.md`, middle one favoured: a pre-push hook that warns on overlap with recent remote commits |
| 28 | `hud-voice` does not build | done | Bisected 2026-09-21. Not a code problem. An agent sandbox exports `GIT_CONFIG_COUNT` with `safe.bareRepository=explicit`; git then refuses to operate on SwiftPM's package cache, because that cache IS a bare repository, so SwiftPM can never UPDATE it. A cache that cannot be updated cannot heal, and a half-fetched FluidAudio stayed half-fetched forever, surfacing as `unable to read tree`. Moving the 348M cache aside fixed it in one build. `doctor.sh` now recognises the combination and prints the purge instead of the `swift build` that would just fail again. A first guess that `GIT_CONFIG_PARAMETERS` was the carrier was wrong, and testing it took a minute |
| 29 | `hud doctor` does not check Accessibility | open | It is the permission the whole voice path depends on and doctor is blind to it |
| 30 | pre-commit refused the very thing it advised | done | The diagnosis in this row was wrong and the bug was worse. `git commit -- a b` builds a TEMPORARY index holding only those paths, so from inside the hook a two-file pathspec commit and a bare commit of a two-file index are identical, and the gate fired on both while telling the author to do what they had just done. A ONE-file pathspec commit slipped through on the `-gt 1` clause, which is exactly why it hid. Git does distinguish them, in `GIT_INDEX_FILE`: `.git/index` for a bare commit, `.git/next-index-<pid>.lock` for a pathspec one. Fixed, verified both ways, and this commit was made with a plain multi-file pathspec commit and no env var |

| 30b | **Finish the interface and ship a beta** | open | Caleb's #3, and the only one of his original 22 that was never written down. `skills/interface` exists and the HUD is the surface. "Some sort of beta" needs a definition of what a beta means here: who installs it, what they are asked to do, and what counts as it working. Five testers were asked on 9/20 ([[../memory/project_chewbacca_tester_outreach]]) with no beta to give them |
| 31 | **Ingest more of Scripture, NASB95** | open | Gavin, 9/21: "Make it NASB95. Most accurate translation." Proverbs is in (`8e47d04`) as a standing check per process. Which books earn a place, and on what test, is unanswered: `methods/proverbs.md` says a line only belongs if it names a failure it would have caught |
| 32 | **Prompting that reads itself as self-learning** | open | Gavin, 9/21, and Caleb loved it: "Figure out a way we can just automate prompting where whatever I say automatically gets interpretted by the engine as self learning." The nearest existing pieces are `bin/scars`, `memory/` and `bin/evolve`. Nothing closes the loop from a sentence he says to a change in the kit |
| 33 | **Reorganize and refactor the files** | open | Caleb, 9/21: "a bunch of them need reorganizing and refactoring." The audit so far found 3 orphan hooks, 5 undocumented commands and 57 dead links, all now fixed or recorded. The reorganize itself is untouched |
| 34 | **Make it an actual graph engineer** | open | Caleb, 9/21: "I shouldn't hv to ever ask this question if chewbacca was truly an intelligent graph engineer." `skills/graph-engineering` holds both halves already and nothing routes to it. Same blocker as item 3 |
| 35 | `superassistant` and `portal` were not on PATH | done | `superassistant` was already in setup.sh's hud install group, so this was a stale install rather than a code bug: the line postdates the last `setup.sh` run on this Mac. `portal`, written 2026-09-21, was in no list at all and would not have installed anywhere. Added to the hud group and both linked. `superassistant recent` now runs, and its log is where the two failed portal asks are recorded |

| 36 | **Voice agent asked him to do something manually** | done | Caleb, to the voice agent 2026-09-21: "Bro chewbacca u must be stupid to hv to ask me to do something manual." Fixed by the imperative rule in `bin/hud-agent.md` (`0637f46`): an instruction is a task, not a topic, and "just get to it" removes the option to ask |
| 37 | **BISC 101 quiz went through the voice agent** | open | 2026-09-21, 02:22 and 02:29: "Do the biology quiz, I already did my answers on paper. I am just double checking." **BISC bans AI outright.** `submit-guard.sh` blocks turning work in, and nothing stops the voice path answering quiz questions. Whether that gap gets closed is his call, not the kit's, but the policy should at least be said out loud when a course that bans AI is named |
| 38 | **Ask-capture proved itself in one hour** | done | Seven asks captured that no backlog row mentioned, two of them voice failures nobody had reported. `backlog inbox` is the part that works |

| 39 | **Doctor Strange plus Iron Man: hands, voice and the glass at once** | open | Caleb, 2026-09-21: "I wanna be doctor strange iron man mixed tgt" and "I'm tryna open a doctor strange portal and control chewbacca w hand gestures and voice together." Every piece now exists and none have been run together: the voice agent has his brain and narrates, `HandTracker` ships palm-dismiss and point-deixis on Apple Vision, `HandDemo` draws the skeleton, and the field draws. The work is composition, not capability. Point-deixis already emits `OutboundEvent.region`, which is the same event the voice layer consumes, so that pair is the shortest path to the demo. **Plan written 2026-09-21 as [docs/SPATIAL-OS.md](docs/SPATIAL-OS.md)**, four steps, each shippable, each visible |
| 40 | **Browser bridge, an LLM in a tab driving the kit** | parked | `bin/browser-bridge` written 2026-09-21, stdlib only, allowlisted, token-gated, loop-guarded. Missing the userscript, a CLI entry point and any test. See `crafts/google-ai-bridge.NOTES.md` for the fork that should be decided first: browser transport versus a provider abstraction for item 9 |

| 41 | **OpenVision is his, and it was never opened** | open | Caleb sent `github.com/calebnewtonusc/OpenVision` on 9/20 at 22:20 and again on 9/21 with *"Bro ru stupid and not listening?"*, and this kit rebuilt hand tracking from scratch in Swift both times. The repo is public, live at `openvision.vercel.app`, and holds a documented zero-dependency toolkit: gesture classifier with tests, pinch detector with tests, WebGazer eye tracking, dwell-to-click, glass panels, and the portal. **The open item is not the port, it is the pattern.** Tenth instance of [[../memory/feedback_built_but_never_fires]] this session, and the first where the existing capability was in a different repo of his own. Nothing in the kit looks at his other repos before building |

| 42 | **`cap record status` reports dead recordings as live** | open | 2026-09-21, 03:10. Caleb: *"Bruh how do I make it stop recording me lol"*. `cap record status` listed **14 active recordings**; all 14 pids were dead. `cap record stop` answered `recording process exited without finalizing the recording` and left the row in place, so the registry only ever grows. A tool that says it is recording you when it is not is worse than one that crashes, because the user cannot tell it apart from the real thing. Fix: reap `~/.cap/sessions/*.json` whose pid is gone, on every `status`. The 14 stale rows are archived at `~/.cap/sessions-stale-20260921/`. **The actual recorder was Granola**, holding `audio.mojom.AudioService` and `video_capture.mojom.VideoCaptureService` for 3 days 15 hours |

| 43 | **Portal: the voice line and the dashboard INSIDE the ring** | open | Shipped 2026-09-21: `Portal.app`, `bin/portal`, named targets, a real hole with the window behind it. Two pieces of what he actually described are missing. He wants to say *"Can I open a portal to some dashboards"* and hear *"sure go ahead doctor strange"* BEFORE he draws, which means the voice reply and the arming are one turn; right now `portal open` arms silently. And he wants the dashboard **in the middle of the portal**, whereas today the window sits BEHIND a hole, so it is framed rather than contained and does not move or scale with the ring. Both are in `[[../memory/project_portal]]` |
| 44 | **The voice agent is much weaker than the chat agent** | open | Caleb, 2026-09-21: *"It's retarded and nowhere near as smart as you bruh."* The immediate cause was fixed by giving it a lookup table instead of a puzzle ([[../memory/feedback_never_make_an_agent_infer]]), but the general gap stands: the lean profile carries the brain and doctrine and a skill index, not the repo. Item 3 is the same blocker. Measure before rebuilding: 68 seconds of that answer was research it should never have started |
| 45 | **Portal needs a plausibility test suite, not a correctness one** | open | Four visual bugs shipped at once with 47 tests green, and the detector fired 0/20 on a jittery circle while passing every perfect-circle test. `circle.noise.test.ts` and the ill-conditioned-fit tests are the pattern to extend: assert what must be TRUE ON SCREEN, a radius that fits the frame, a centre that stays on it. See [[../memory/feedback_the_screenshot_beat_the_code]] |

| 46 | **The strategy doc he asked for twice** | open | "strategize all the upgrades fixes and refactoring and research and creative problem solving", then "a billion times better in EVERY way". Four research findings came back and live only in a transcript; they are written down in [docs/handoffs/2026-09-21-morning.md](docs/handoffs/2026-09-21-morning.md). The doc itself was never written |
| 47 | **The behavioural pass has never run, still** | open | `fitness.jsonl` has 12 rows and **0** with per-case results. The credit-assignment path from item 0 has not executed once. Same shape as everything else built and never fired. Costs model calls; run `fitness --run` in the background |
| 48 | **Voice prompt cache misses on the first turn** | open | Measured on "Good morning": `cache_creation 57,888, cache_read 0`, while the turn before it read 75,801. Cache ordering is worth 7% to 84% hit rate in production reports, so what sits ahead of the stable prefix is worth one measurement. Do not theorise first |
| 49 | **Portal defaults are guesses** | open | reach 0.4, size 0.3, gain 0.2 are where tuning stopped when he left for class. All three are live (`portal reach`, `portal size`, `portal gain`). Whatever numbers feel right become the defaults |
| 51 | Humor experiments nobody has run | open | Opened 2026-09-22, written up in [docs/HUMOR-EXPERIMENTS.md](docs/HUMOR-EXPERIMENTS.md). Four experiments the computational-humor literature has never run. Cheapest and most useful to the kit is #3, whether a model ranks its own candidates worse than a sibling's, which is an afternoon and decides whether a generator may ever select its own output. #1 and #2 need Caleb to rank his 44 tweets before posting; #2 tests Gulman's claim that creator uncertainty predicts quality, which if true inverts every generate-then-self-rank design. Relevant to item 0 because it is a bounded domain with a human grader already in place, so it is the cheapest available test of whether the learning loop can close at all |

## Done this session

| Item | Where |
| --- | --- |
| Globe key push-to-talk | `hud.listening` was never written, so mode came up `off`. Not Accessibility |
| `hud doctor` false staleness on docs commits | `be0e8a3`. Obeying it re-signed the bundle and dropped the Accessibility grant |
| Installer says how to remove itself, and what leaves the Mac | `8e47d04`, with a test refusing any printed "nothing is uploaded" claim |
| Proverbs wired into `bin/method` as a standing check per process | `8e47d04` |
| Talk key raises the overlay, and the recogniser stays warm | `2b511a2`. Held with the glass hidden it opened the mic behind a blank screen. First press of a sitting cost 651ms against 73ms warm, because `warmUp()` ran once at launch |
| Accessibility survives a HUD rebuild | `2b511a2`. It was never macOS: the bundle was ad-hoc signed, so the requirement named the binary hash. `bundle.sh` now takes any Apple Development cert before falling back |
| The HUD LaunchAgent can find the model CLI | `fc0a21b`. launchd gives `PATH=/usr/bin:/bin:/usr/sbin:/sbin`; `claude` lives under nvm. Speech transcribed correctly and went nowhere, with no error in any log |
| Listener starts at login, and its output is kept | `b100a1c`. It was spawned lazily, so the first talk-key hold paid for a Python start, a 70KB prompt build and a synchronous `prime()`. stdout went to `nullDevice`, which is why none of tonight's failures left a trace |
| MCP servers stop booting through npx | `a5ae9b1`. 9.27s to 1.33s across six, verified with a real initialize handshake. `doctor.sh` now fails when a server path goes missing |
| One process's PATH can no longer delete tools from the published catalog | `54db658`. A narrow PATH dropped bd, cap, mac, mac-use and yt-transcript from `toolkit.json`, took 116 lines out of `setup.sh` and rewrote REFERENCE.md from nine tools to four |
| Gavin's and Caleb's creative procedures captured | `b57dceb` |
| Operating doctrine from the three corpora, with the stop rule | `6e6e901` |
| Prometheus targeting: 1.04M rows to 51,320 reachable | `calebnewtonusc/prometheus-targeting`, private |
| Team context handoff | `a0fc155`, sent to the group chat |
| Credit assignment: fitness records WHICH cases failed | item 0 step 1 |
| `evolve --gate`, the retention step | 12 tests, refusals proved by firing them |
| `bin/corpus`, the reward environment | 209 sessions, 35,611 assistant turns |
| `handoff-guard`, `durable-guard` | 2 of the 4 top recurring corrections now enforced |
| `bin/preflight` | what the installer does, before it does it |
| `slop-guard` actually enforces | it was advisory and had never stopped a reply |
| Greetings cost no model turn | 21.4s, of which 854 thinking tokens, for "Morning." |
| Portal: rough depths, reach, size, gain | 117px of wander became 17px |
| The Doctor Strange portal, browser and HUD | `calebnewtonusc/OpenVision` `/strange`, and `feat/portal-hud` here |
| `cap record status` reported 14 dead recordings as live | item 42; Granola held mic and camera for 3.5 days |
| Hand control turned off | `hud.handControl` false. Palm and point stay in the code, unwired |

## Dead

| Item | Why |
| --- | --- |
| "Implement Sagar changes once he onboards" | He onboarded on 9/20 and quit after two hours. "It's not a product I need to work for me." Rewritten as item 2 |

---

Built with Chewbacca
