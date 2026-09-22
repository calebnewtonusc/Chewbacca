# Roadmap

Everything between this kit and being worth running for any person in any role.
Written 2026-09-21 so the answer stops living in one person's scrollback.

Three sections, in the order they matter:

1. **Broken now.** Things that are wrong today. Fix before building.
2. **The wall.** The single item that decides whether anyone else can use this.
3. **The build.** Caleb's 30, with an honest state against the repo.

A note on honesty here, because it is the whole point of the file: "partly
done" below means code exists and does something, not that it works well. Where
something was never tested it says so.

---

## 1. Broken now

Each of these is a real defect someone hit, not a wish.

|     | what                                                                                                                                         | where it came from                                                               |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| B1  | Five false opens in the portal gesture battery: 2.5:1 oval, square, line, 70% arc, 90% arc all open a portal                                 | `tests/portal_live.sh`, 2026-09-21                                               |
| B2  | Drawing a circle slowly does not register. Tremor dominates direction between consecutive samples at low speed                               | measured in the running app, 2026-09-21; the fix was reverted as the wrong shape |
| B3  | `closeout` takes ten minutes: 155 independent checks run strictly sequentially, zero parallelism anywhere                                    | `tests/run.sh`                                                                   |
| B4  | The suite's group filter returns instantly for every group, so scoping a run does nothing. Never diagnosed                                   | `bash tests/run.sh hud` returns in 0.0s                                          |
| B5  | `hud: the suite collects under pytest` fails                                                                                                 | handoff, 2026-09-21                                                              |
| B6  | `kit-autopush.sh` p95 at 3117ms                                                                                                              | handoff, 2026-09-21                                                              |
| B7  | `.githooks/pre-commit` false-positives on genuine pathspec commits                                                                           | handoff, 2026-09-21                                                              |
| B8  | `scars` retrieval ranks badly even with indexing fixed                                                                                       | handoff, 2026-09-21                                                              |
| B9  | `second-brain` edges are bare `[[wikilinks]]` with no relation type, so retrieval falls back to term overlap. This is the likely cause of B8 | `skills/graph-engineering`, stage 3                                              |
| B10 | Every memory bank only grows. No decay, no pruning, no retirement                                                                            | `research/aryaa-memory-architecture.md`, item 2                                  |
| B11 | The portal's fn-key listener autostart builds but was never tested against a real keypress                                                   | 2026-09-21                                                                       |

---

## 2. The wall

**Onboarding.** Item 8 below. Nothing else on this list matters to a stranger
until a stranger can install it.

Today the install is a git clone plus `start.sh` plus a bootstrap that checks a
GitHub account and a git identity, and it has been broken on main at least once
(2026-09-19, `setup.sh` pushed without checksums). Two people were watched
installing it on their own machines on 2026-09-19 and every installer test in
the suite came from something they actually hit.

The target Caleb set: single paste or single link, an "allow once" permission
flow, no visible API keys, Mac first then Windows.

Everything in section 3 is depth on a thing almost nobody can run.

---

## 3. The build

Caleb's list, renumbered as given, with state.

### Done, or substantially so

**5. Iron Man maxing.** `hud/Sources` has BobHUD, BobHUDKit, HandDemo and
Portal, all building. The voice half (hud-voice on the Neural Engine, the
router, `chewie` terminal, hud-music, hud-guide) is Gavin Munroe's.

**20. Hand control.** `HandTracker` in BobHUDKit, `HandDemo`, pinch and draw in
Portal. Works. See `.claude/rules/spatial-one-mapping.md` for the rule that
cost six alignment bugs in one morning.

**24. Open source Apple Vision Pro / VR / XR.** OpenVision is Caleb's own,
built 2026-09-04: portal, hand and eye tracking. Check his repos before
building anything here.

### Partly done, real code exists

**2. Deep UI/UX research, component and workflow frameworks.** `ux-engine`
indexes 74 design systems by what they REFUSE, on the finding that the
generated look is an empty deny list. `craft-gate` fires on UI work.
Missing: the compile step from framework to full UX on command.

**3. Finish interface, ship a beta.** `skills/interface` and
`crafts/interface.md` exist. No beta, no distribution.

**4. Whisper / ElevenLabs, the Jarvis feel, max out Plynn.** `bin/plynn` and
the Plynn app are here and running. hud-voice does local recognition. No
ElevenLabs, no TTS personality, no continuous-presence loop.

**9 and 30. Any LLM from the browser, free Chewbacca through the browser.**
`browser-bridge`, `chatgpt-gateway`, `chatgpt-tab`, `claude-tab`, `chrome-js`
exist. There is a `browser-ux-guard` hook that refuses to drive a browser
through pixels, which is the right instinct and worth keeping.

**15. LinkedIn scraping.** `clay-history` and the LinkedIn/Clay sync exist. The
2,130-person scrape is paused at 162 and resumable in `~/.chewbacca/clay-history/`.

**17 and 18. GTM synthesis, world class at Clay.** `reference_clay_query_grammar`
has the query language including the fact that search is free at 1M/day.
`clay-balance`, the Clay history fix, the Zeutara engagement, the cold-email
craft note (kept private, see below). Not synthesized into a system.

**21. Doctor Strange, and any other effect.** The portal. A full day on it
2026-09-21 and it is close: the reveal is a fragment shader, the two ends fuse
with a metaball smooth minimum, the edge dissolves through four octaves of
noise. B1 and B2 above are what is left.

**26. Learn any software, push what it learns to main.** The procedures/maps
layer (Gavin's) lets the kit learn a task by doing it once. `watch-skill`,
`methods/`, `scars`. The "push to main so everyone gets it" half is not built.

**29. Navigate macOS like a beast.** `peekaboo`, `mac-cli`, the
`macos-automator` MCP. Window moving and scaling is partly reachable. There is
no separate Chewbacca cursor, which is the interesting half of the ask.

### Not started

Nothing exists for any of these yet.

**1.** Research `me.sh` and work out what it does better than this kit does.
**6.** Synthesize `github.com/modelcontextprotocol/servers` into what is worth wiring.
**7.** Same for `github.com/punkpeye/awesome-mcp-servers`, which is the larger list.
**10.** An open source Granola, meaning meeting capture that does not phone home.
**11.** Identify the open source version of every app worth integrating or rebuilding.
**14.** Sound design for the HUD, which currently has none at all.
**16.** Synthesize every good thing anyone has built in OpenClaw.
**19.** The GTM data companies, starting with the one Sagar sent over.
**23.** The playlist at `youtube.com/playlist?list=PLVfsVcqGNNSBNOMOPvQuIb65eezSVojjs`,
read with `yt-transcript` rather than WebFetch, which returns nothing for YouTube.
**25.** Animation quality good enough that the portal stops being the only example.
**27.** Convert any file type to any other file type.

### Blocked on other people

**12.** Sagar's changes, once he onboards.
**13.** Karthik's changes, once he onboards.

### Cannot see from here

**22.** The rest of the todo in the Chewbacca group chat.
**28.** The random things in the repo todo list, beyond `BACKLOG.md`'s seven.

---

## 4. Standing principles this kit keeps relearning

Written down because each one cost a day.

**Enforce, do not document.** A rule that has been read and disobeyed is not a
control. When a mistake repeats, promote it to a hook that refuses. Three exist
now: `slop-guard`, `vibe-guard`, `fusion-guard`. An advisory hook does nothing:
`slop-guard` once exited 0 on an unrecognised JSON field and twelve sloppy
replies shipped.

**Prove the guard fires.** Two authorship guards in this kit had never refused
anything. Every gate ships with a test that makes it refuse on purpose.

**Prove the code ran.** Not that it compiled, not that the source is right. On
2026-09-21 several rounds of "fixed" were reported while the code path being
described was not executing, because a texture upload failed silently and the
old path took over.

**Measure before theorising.** The portal's oscillating boundary took four
attempts; three blamed a clock and were built without measuring anything. The
fourth measured and found a signed accumulator walking backwards on hand noise.

**A continuous field belongs in a shader, not in stacked shapes.** Six separate
portal bugs were one wrong tool. See
`second-brain/memory/feedback_field_not_geometry.md`.

**Resolve an identity before writing it down.** A first name is not a person.
See `hooks/fusion-guard.sh` and the Jonah Graham incident.

**Chewbacca is a PUBLIC repo.** Craft notes quoting named clients live in
`second-brain/wiki/`, not here. `craft-gate` reads `~/.chewbacca/craft/`, so
the gate still passes without publishing anything.

---

## 5. Where the answers already live

- `BACKLOG.md`, seven items, older
- `research/aryaa-memory-architecture.md`, 130 posts by Aryaa SK with his
  build list, and section 9 marking where he is contestable
- `research/what-is-actually-proprietary.md`
- `skills/graph-engineering`, both halves, now routed on the shape of the work
- `second-brain/memory/`, the fastest-moving record of what broke and why
- `bin/closeout`, which answers "is it safe to close this tab" from evidence
