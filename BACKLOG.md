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
| 1 | **GTM engineering for Jonah and his 5 companies** | doing | Sagar, 9/20: "i need you to do one thing." Tooling shipped at `calebnewtonusc/prometheus-targeting` (private). **Blocked on one fact: which 5 companies are raising.** One-pagers exist for 8 |
| 2 | **Onboarding: single paste, allow-once permissions, no visible API keys, Mac then Windows** | open | Caleb's #8. Now evidence-backed: Sagar called the installer malware on 9/20 and a second person flagged permissions the same afternoon. Closing screen fixed in `8e47d04`; the flow itself is not |
| 3 | **Skill descriptions cannot route** | done | 105 skills installed, nothing names one when work starts. `skill-route.sh` built and unregistered in `4cca1fd` after misfiring twice. skill-scan grades the descriptions at 16-21 trigger points of 25. Fix descriptions first |
| 4 | **TTS site** | open | Needs the design corpus in #5. ArcRank mockup shows the real competitor set: SparkSC, Sigma Eta Pi, LavaLab, TroyLabs, VC Academy |
| 5 | **Deep UI/UX research, component and workflow frameworks** | open | Caleb's #2. Four reference images captured 9/21. `dembrandt` (3,506 stars) already extracts tokens, type scale, motion and hover patterns from a live site into a DESIGN.md |
| 6 | **Self-correcting cold outreach** | open | Caleb to Sagar: "has anyone ever built that?" Sagar: "unless you set up some cli magic." Caleb: "cli magic it is." The genuinely novel item |

## Next

| # | Item | Status | Notes |
| --- | --- | --- | --- |
| 7 | Animation extraction by navigating a live UX | open | Caleb's claim "no one's built that" is **partly wrong**: dembrandt covers static tokens and hover. Scroll and click sequencing across a navigated session may still be open |
| 8 | Replace 5 archived MCP servers | open | github, postgres, puppeteer, google drive and slack are `servers-archived` reference code. Live replacements: `github/github-mcp-server`, `microsoft/playwright-mcp`, `korotovsky/slack-mcp-server` |
| 9 | Add Context7 and MotherDuck MCP | open | Context7 (62k stars, 3.5M npm/mo) serves version-correct docs, which is the mechanical cause of slop UI. MotherDuck queries a local CSV in place, which is the 1M-row problem |
| 10 | Hand control, the 10% that is real | open | Apple Vision, not MediaPipe. Measured 7.56ms one hand, 4-6% of one core sustained on the M4 Pro. Build palm-to-dismiss and point-to-deixis only; `OutboundEvent.region` already exists |
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
| 21 | Doctor Strange effects | open | Caleb's #21. Research verdict: a demo, not a feature. Gavin independently agrees. Ship as a separate demo target with a README saying so |
| 22 | Research `me.sh` and `mog` | open | Caleb's #1. Not yet looked at |
| 23 | Work for any LLM, simply, in the browser | open | Caleb's #9 |
| 24 | Iron man maxing | open | Caleb's #5. Needs a definition before it is actionable |
| 25 | Rest of the todo in the Chewbacca group chat | blocked | Gavin's iCloud note, `icloud.com/notes/0f5WeJHPg27B2DB_3-z1Nyweg`. Not in Caleb's local store, so Gavin has to paste it |
| 26 | Audit every file for staleness and fit | open | Caleb, 9/21: "So much of chewbacca is outdated / out of sync / not fitting well w the rest." Needs a real pass, not a spot check |
| 27 | Team check-in so two people do not build the same thing | open | Gavin's ask on the 1am call. Three shapes proposed in `docs/handoffs/2026-09-21-team-context.md`, middle one favoured: a pre-push hook that warns on overlap with recent remote commits |
| 28 | `hud-voice` does not build | open | Fails fetching FluidAudio, "unable to read tree". Never bisected |
| 29 | `hud doctor` does not check Accessibility | open | It is the permission the whole voice path depends on and doctor is blind to it |
| 30 | pre-commit's advice message is wrong | open | It says to name your paths, but the two-live-sessions gate inspects the index, which `git commit -- paths` does not change. Only `CHEWBACCA_PATHSPEC_COMMIT=1` clears it |

| 30b | **Finish the interface and ship a beta** | open | Caleb's #3, and the only one of his original 22 that was never written down. `skills/interface` exists and the HUD is the surface. "Some sort of beta" needs a definition of what a beta means here: who installs it, what they are asked to do, and what counts as it working. Five testers were asked on 9/20 ([[../memory/project_chewbacca_tester_outreach]]) with no beta to give them |
| 31 | **Ingest more of Scripture, NASB95** | open | Gavin, 9/21: "Make it NASB95. Most accurate translation." Proverbs is in (`8e47d04`) as a standing check per process. Which books earn a place, and on what test, is unanswered: `methods/proverbs.md` says a line only belongs if it names a failure it would have caught |
| 32 | **Prompting that reads itself as self-learning** | open | Gavin, 9/21, and Caleb loved it: "Figure out a way we can just automate prompting where whatever I say automatically gets interpretted by the engine as self learning." The nearest existing pieces are `bin/scars`, `memory/` and `bin/evolve`. Nothing closes the loop from a sentence he says to a change in the kit |
| 33 | **Reorganize and refactor the files** | open | Caleb, 9/21: "a bunch of them need reorganizing and refactoring." The audit so far found 3 orphan hooks, 5 undocumented commands and 57 dead links, all now fixed or recorded. The reorganize itself is untouched |
| 34 | **Make it an actual graph engineer** | open | Caleb, 9/21: "I shouldn't hv to ever ask this question if chewbacca was truly an intelligent graph engineer." `skills/graph-engineering` holds both halves already and nothing routes to it. Same blocker as item 3 |
| 35 | `superassistant` is not on PATH | open | The voice prompt references it and the module loads by path, but the CLI named in `CLAUDE.md` (`superassistant recent 10`) does not run |

| 36 | **Voice agent asked him to do something manually** | done | Caleb, to the voice agent 2026-09-21: "Bro chewbacca u must be stupid to hv to ask me to do something manual." Fixed by the imperative rule in `bin/hud-agent.md` (`0637f46`): an instruction is a task, not a topic, and "just get to it" removes the option to ask |
| 37 | **BISC 101 quiz went through the voice agent** | open | 2026-09-21, 02:22 and 02:29: "Do the biology quiz, I already did my answers on paper. I am just double checking." **BISC bans AI outright.** `submit-guard.sh` blocks turning work in, and nothing stops the voice path answering quiz questions. Whether that gap gets closed is his call, not the kit's, but the policy should at least be said out loud when a course that bans AI is named |
| 38 | **Ask-capture proved itself in one hour** | done | Seven asks captured that no backlog row mentioned, two of them voice failures nobody had reported. `backlog inbox` is the part that works |

| 39 | **Doctor Strange plus Iron Man: hands, voice and the glass at once** | open | Caleb, 2026-09-21: "I wanna be doctor strange iron man mixed tgt" and "I'm tryna open a doctor strange portal and control chewbacca w hand gestures and voice together." Every piece now exists and none have been run together: the voice agent has his brain and narrates, `HandTracker` ships palm-dismiss and point-deixis on Apple Vision, `HandDemo` draws the skeleton, and the field draws. The work is composition, not capability. Point-deixis already emits `OutboundEvent.region`, which is the same event the voice layer consumes, so that pair is the shortest path to the demo |
| 40 | **Browser bridge, an LLM in a tab driving the kit** | parked | `bin/browser-bridge` written 2026-09-21, stdlib only, allowlisted, token-gated, loop-guarded. Missing the userscript, a CLI entry point and any test. See `crafts/google-ai-bridge.NOTES.md` for the fork that should be decided first: browser transport versus a provider abstraction for item 9 |

## Done this session

| Item | Where |
| --- | --- |
| Globe key push-to-talk | `hud.listening` was never written, so mode came up `off`. Not Accessibility |
| `hud doctor` false staleness on docs commits | `be0e8a3`. Obeying it re-signed the bundle and dropped the Accessibility grant |
| Installer says how to remove itself, and what leaves the Mac | `8e47d04`, with a test refusing any printed "nothing is uploaded" claim |
| Proverbs wired into `bin/method` as a standing check per process | `8e47d04` |
| Gavin's and Caleb's creative procedures captured | `b57dceb` |
| Operating doctrine from the three corpora, with the stop rule | `6e6e901` |
| Prometheus targeting: 1.04M rows to 51,320 reachable | `calebnewtonusc/prometheus-targeting`, private |
| Team context handoff | `a0fc155`, sent to the group chat |

## Dead

| Item | Why |
| --- | --- |
| "Implement Sagar changes once he onboards" | He onboarded on 9/20 and quit after two hours. "It's not a product I need to work for me." Rewritten as item 2 |

---

Built with Chewbacca
