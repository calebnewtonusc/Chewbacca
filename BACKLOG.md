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

## Now

| # | Item | Status | Notes |
| --- | --- | --- | --- |
| 1 | **GTM engineering for Jonah and his 5 companies** | doing | Sagar, 9/20: "i need you to do one thing." Tooling shipped at `calebnewtonusc/prometheus-targeting` (private). **Blocked on one fact: which 5 companies are raising.** One-pagers exist for 8 |
| 2 | **Onboarding: single paste, allow-once permissions, no visible API keys, Mac then Windows** | open | Caleb's #8. Now evidence-backed: Sagar called the installer malware on 9/20 and a second person flagged permissions the same afternoon. Closing screen fixed in `8e47d04`; the flow itself is not |
| 3 | **Skill descriptions cannot route** | open | 105 skills installed, nothing names one when work starts. `skill-route.sh` built and unregistered in `4cca1fd` after misfiring twice. skill-scan grades the descriptions at 16-21 trigger points of 25. Fix descriptions first |
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
| 11 | Framing stage, the level above `method` | doing | "Before chewbs does anything, it should deeply craft the best way to even figure out how to plan making the plan." Research agent running |
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
