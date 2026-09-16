---
name: demo
description: Record a product demo video by reading the product's own code and the craft of demo-making, not by guessing at either. Use when the user asks to record a demo, make a demo video, film the product, show the product working, or produce a launch clip. Also use when a demo already recorded is wrong, boring, or missed the point of the product. Needs the repo and a running instance.
---

# Record a demo of the product, from its own source

## The failure this exists to fix

Cap's bundled `cap-demo` skill scouts the page at runtime and scores every
anchor and button to pick a "CTA": `+3` if the text matches
`/features|pricing|docs/`, `+2` for a background colour, `-5` for "sign up". Nothing in
that scoring has any knowledge of the product it is pointed at.

Run against a real site it produced this:

```
STORY=scroll cta=none accent=null
cursor track synthesized: 182 moves, 0 clicks
```

No CTA found, so it scrolled. **Zero clicks** in a product demo. Nothing was
demonstrated, because nothing in that pipeline knows what the product does.

**You are not in that position.** You have the repo. Read it, decide what the
demo should show, and write the storyboard yourself. That is the whole skill.

## Before any of that: you do not know how to make a demo video

You know how to drive a UI and run an encoder. Those are the mechanics. A demo
video is a **craft with its own rules**, and the first version of this skill had
none of them, so the first demo it produced was four taps on a tab bar. That is
a screen recording. Caleb's response was "there's more to UX than just the nav
bar lol", and he was right.

**Research the craft before producing the artifact.** For a demo that means
watching people who make them for a living, not reasoning from first principles
about what a demo probably is. The rules below came from doing that once, and
they are here so the research does not have to be repeated. If the work drifts
outside them, go watch two more and add what you learn.

### The rules, from practitioners who have made hundreds

**One to three features. Never more.** Stated as *the* biggest mistake people
make: "include way too many features... otherwise people will just switch off."
This is the rule most likely to be overridden by the person asking, who will
say "show everything". Showing everything is the failure mode with a name.

**A storyline, not a tour.** The demos that work have "a clear narrative... not
jumping around between different aspects of the product." Ask what one job the
viewer watches somebody complete. Most products already have this written down
in their own onboarding copy; Silo's how-it-works screen says "Three taps to
dinner", which is the storyboard, pre-written by the founder.

**Cut the login.** "I often see people record their login process, but it's not
really something that people find that interesting."

**Show it with data in it.** A populated product is the whole advantage a demo
has over a free trial. Empty states are not a feature.

**Do not over-zoom.** "It can actually be a little bit dizzying... most people
really want to see the context about what you're interacting with." Zoom for one
specific thing, then pull back out.

**Describe the benefit, not the action.** Not "now we click the filter": "you
see only what is still open near you."

**Increase complexity over time.** Open on the simplest possible beat and build.

**End on a CTA.** Somebody who reached the end is the most engaged viewer the
product will get that week.

### When the brief and the craft disagree

"Show me all the screens" is a reasonable thing to ask for and a bad demo. Say
so in one line, make the narrative version, and offer the full screen tour as a
separate artifact if it is still wanted. Do not silently deliver either one.

## What to read, in order of how much it is worth

**1. The e2e specs, which are where you should always start.** `e2e/`, `tests/`, `cypress/`,
`playwright/`, `*.spec.ts`, `*.cy.ts`. These are the single best source in any
repo and almost nobody thinks to use them: a passing e2e test is a recorded
script of the exact journey the team already decided _is_ the product, written
with the real selectors, in the real order, with the real fixture data. A demo
plan is an e2e spec with dwell times.

```bash
rg -l "test\(|it\(|describe\(" --glob "**/*.{spec,cy,e2e}.{ts,tsx,js}" .
rg "getByTestId|data-testid|getByRole" -N --glob "**/*.spec.ts" . | head -40
```

**2. `data-testid` attributes.** Stable by contract, which is exactly what a
storyboard needs. A class name is a refactor away from breaking the demo.

```bash
rg -o 'data-testid="[^"]+"' -N . | sort -u
```

**3. The routes.** `app/**/page.tsx`, `pages/`, the router config. They are the
product's own table of contents, and the order they were built in usually is
the order they should be shown in.

**4. The landing copy and the README.** What the product _claims_ to do is what
the demo has to deliver. If the hero says "find a home cook near you" and the
demo never finds a cook, the demo is wrong no matter how good it looks.

**5. Recent commits.** `git log --oneline -30`. For a launch clip, the feature
that just shipped is usually the point.

## Then decide the story, out loud, before writing any JSON

Answer these three in one line each. If you cannot, read more:

- **What does this product do for someone?** One sentence, their words.
- **What is the single moment that shows it?** Not the homepage. The moment the
  thing pays off: the search returning cooks, the file becoming a chart, the
  message arriving.
- **What is the shortest path from load to that moment?** Every beat that is not
  on that path is cut. You have 12 seconds.

## Write the plan

```json
{
  "url": "http://localhost:3000",
  "beats": [
    { "do": "aim", "selector": "h1", "label": "hero" },
    { "do": "dwell", "ms": 1200, "label": "settle" },
    {
      "do": "type",
      "selector": "[data-testid=search]",
      "text": "tacos",
      "label": "search"
    },
    {
      "do": "click",
      "selector": "[data-testid=search-submit]",
      "label": "run_search"
    },
    { "do": "scroll", "selector": "[data-testid=results]", "label": "results" },
    { "do": "idle", "ms": 1800, "label": "land" }
  ]
}
```

Beats: `aim` (mark a landmark for the 3D shot, moves nothing), `dwell`, `move`,
`click`, `type`, `scroll` (by `selector` or `by` pixels), `idle`.

Common keys: `label` names the beat in the timeline, `ms` is the glide or dwell
duration, `settle` is the pause after, `text` on a `click` disambiguates by
visible text, `waitFor: false` on a click that does not navigate.

**A missing selector is a hard error, on purpose.** A demo that silently skips
its own climax is worse than one that stops and tells you the selector moved.

## Run it

```bash
demo-shoot plan.json <outDir> <slug>
python3 ~/.claude/skills/cap-demo/lib/treat.py <outDir> <slug> [--bg-gradient FROM,TO]
```

`demo-shoot.mjs` writes `<slug>.cap` and `<slug>.timeline.json` in Cap's own
format, so Cap's `treat.py` does the 3D camera, gradient, cursor and music
unchanged. That stage is Cap's work and is good; only the scouting was the
problem.

## Frame-QA between the stages. Do not skip this.

```bash
ffmpeg -y -ss <t> -i <outDir>/<slug>.cap/content/segments/segment-0/display.mp4 \
  -frames:v 1 /tmp/raw-<t>.png
```

Then **look at the frames**. Check the right content is captured, no cookie
banner leaked, the click landed somewhere that proves the product works, and
the tail is clean. Reshoot before spending an export.

After the export, pull four beat frames and look again. Check the fps first,
because `cap record --detach` engages late and the true rate is often ~58, not 60. Passing `--quality hd` on a 58fps capture buys judder:

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames,duration \
  -of csv=p=0 <outDir>/<slug>.cap/content/segments/segment-0/display.mp4
```

**Set the brand gradient by eye.** `getComputedStyle` lies on pastel and
gradient-heavy sites: one that reads white with lavender accents samples as
black. Look at the raw frame and pass `--bg-gradient`.

## The editorial rules, which are Cap's and are right

- **12 seconds, hard.** Past that the tail is shaved evenly and the ending is
  lost. `demo-shoot.mjs` refuses a plan that budgets over it.
- **A camera cut must be a content cut.** Never cut mid-idle.
- **Cut on the action, resume on the loaded page.** No spinners, no blur-up.
- **One motion system.** The 3D shot carries the emphasis. Never stack 2D zoom
  segments on top.
- **Aim at content, not the container.** Point at the hero, the clicked thing,
  the destination header.

## Requirements

macOS on Apple Silicon. `cap` on PATH with Screen Recording granted, `node`,
`python3`, `ffmpeg`. `npm install` once in `~/.claude/skills/cap-demo` for
`playwright-core`. **The product must be running and reachable at the plan's
url**, which is usually a local dev server you start first.

## Native apps: iOS Simulator, not a browser

`demo-shoot.mjs` drives Playwright, so it only works on something a browser can
open. An Expo or React Native app is not that. Check `app.json` first: Silo lists
`platforms: ["ios","android"]`, so `expo start --web` refuses outright.

The path that works, learned by doing it badly first:

**Boot a simulator that already has the app.** A native build is minutes and can
fail. Look before building:

```bash
find ~/Library/Developer/CoreSimulator/Devices -name "*.app" -path "*Bundle*" | grep -i <app>
xcrun simctl boot <udid> && open -a Simulator
xcrun simctl launch <udid> <bundle.id>
```

**Deep links are a trap.** `xcrun simctl openurl booted myapp://feed` raises an
**"Open in App?"** system dialog every single time, so it cannot be used to jump
between screens in a recording. Navigate by tapping.

**Wheel scroll does nothing.** `peekaboo scroll` sends wheel events and a
simulator wants a touch drag. Use a swipe, and note the flags are
`--from-coords` / `--to-coords`, not `--from`:

```bash
peekaboo swipe --from-coords 233,720 --to-coords 233,400 --duration 420 --steps 22 --app Simulator
```

**Clicking by element label is unreliable here.** `peekaboo see` reads the whole
accessibility tree inside the simulator, which is genuinely useful for
discovering labels, but clicking `--on elem_N` landed one element low every
time. Calibrate coordinates instead, from the window bounds in
`peekaboo list windows --app Simulator`:

```
screen_x = win.x + device_pt_x * (win.width / device_pt_width)
```

**VERIFY THE WINDOW EXISTS BEFORE EVERY COORDINATE CLICK.** This is the one that
did damage. Mid-session the simulator shut down, its window vanished, and the
next clicks at `y=885` landed on the **Dock** and launched applications on the
user's real machine. A coordinate click is a click on the desktop when the thing
you meant to hit is gone.

```bash
cap record windows --json | grep -q '"id": *<winid>' || { echo "window gone"; exit 1; }
```

**Never send keystrokes with System Events.** `osascript -e 'tell application
"System Events" to keystroke "..."'` goes to the frontmost macOS app, not the
device, and it **shut the simulator down** mid-run. Text entry into a React
Native field is the one unsolved piece: taps and swipes work, typing does not.
`xcrun simctl pbcopy` fails with "Unable to connect to device pasteboard".
`idb-companion` is installed and is the next thing to try (`idb ui text`).

**Record and export without treat.py**, since its 12s ceiling and its editorial
cut are built for the browser storyboard:

```bash
cap record start --detach --window <winid> --fps 60 --path out.cap
cap record stop --path out.cap
cap export out.cap --output out.mp4
ffmpeg -y -i out.mp4 -vf "crop=500:1008:0:72" -c:v libx264 -crf 18 final.mp4
```

That crop removes the Simulator's macOS title bar and keeps the phone bezel,
which reads as a product shot rather than a screen grab.

## When there is no repo

Fall back to `cap-demo <url>`, Cap's deterministic pipeline, and say plainly
that it is the ~70% version. Do not pretend a scouted demo read the product.
