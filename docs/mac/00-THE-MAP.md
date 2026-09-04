# The map: seven ways to control a Mac

Every method anyone has found to make an AI drive a Mac lands in one of seven layers.
They are not alternatives to pick between by taste. They are a ladder, ordered by
cost and reliability, and the correct move is almost always to start at the bottom.

---

## Layer 1: Data

**Read the app's own storage. Never open the UI at all.**

Most Mac apps keep their state in a SQLite database or a plist inside `~/Library`.
Messages, Notes, Photos, Safari history, Mail indexes, Reminders, Music. If the task
is "what did she text me last week," the answer is a SQL query, not a screenshot of
the Messages window.

```bash
sqlite3 ~/Library/Messages/chat.db "SELECT text FROM message ORDER BY date DESC LIMIT 5"
defaults read com.apple.dock orientation
```

- **Cost:** effectively zero. Milliseconds, no tokens beyond the result.
- **Reliability:** total, until Apple changes the schema.
- **Reach:** narrow, and read-mostly. Writing into a live app's database while the app
  is running corrupts it.
- **Permission:** Full Disk Access.

Details: [05-DATA-LAYER.md](05-DATA-LAYER.md)

---

## Layer 2: Native scripting

**Ask the app to do the thing, in the app's own vocabulary.**

AppleScript and JXA talk to apps through Apple Events. A scriptable app exposes a
dictionary of objects and verbs, and you address them semantically: `the third message
of mailbox "Inbox"`, not "the pixel at 412, 208."

```bash
osascript -e 'tell app "Safari" to get URL of front document'
osascript -l JavaScript -e 'Application("Notes").notes[0].name()'
shortcuts run "Daily Digest"
open -a "Visual Studio Code" ~/project
```

- **Cost:** near zero.
- **Reliability:** excellent where supported. Survives redesigns, window moves, dark
  mode, anything visual.
- **Reach:** entirely app-dependent. Apple's own apps are well scripted. Most modern
  third-party apps, especially Electron ones, expose nothing.
- **Permission:** Automation (Apple Events), per app pair.

The `System Events` trick is the escape hatch: `tell application "System Events" to
click button "OK" of window 1 of process "Foo"` drives the accessibility tree through
AppleScript. That is really layer 3 wearing a layer 2 costume, and it needs
Accessibility, not just Automation.

Details: [01-SCRIPTING.md](01-SCRIPTING.md)

---

## Layer 3: The accessibility tree

**The layer almost nobody uses and almost every task should.**

macOS exposes every UI element of every running app as a queryable tree through the
`AXUIElement` API. Buttons, text fields, menu items, table rows, each with a role, a
label, a value, a position and a size. It is the same API VoiceOver uses, which is why
it works everywhere: apps are legally and practically motivated to support it.

```bash
chewie see --app Mail --json
agent-desktop snapshot --app Finder -i
peekaboo see --app Safari
```

You get back structured JSON with stable refs like `@s8f3k2p9:e12`. You click `e12`,
not a coordinate.

- **Cost:** roughly 50ms per read. Between 40 and 100 times faster than a screenshot
  round trip, and 78 to 96 percent fewer tokens on a dense app.
- **Reliability:** very high. Element identity survives the window moving, the theme
  changing, the layout reflowing.
- **Reach:** nearly everything native. Canvas-rendered apps (games, Figma, video) are
  genuinely opaque and belong at layer 5.
- **Permission:** Accessibility.

The one real trap: Chromium and Electron build their tree lazily and hand you nothing
until a client asks. The fix is one attribute set, documented in
[02-ACCESSIBILITY.md](02-ACCESSIBILITY.md).

---

## Layer 4: Synthetic input

**Actually move the mouse. Actually press the key.**

`CGEventCreateMouseEvent` and `CGEventPost` put real events into the system event
stream. Nothing can tell them from a human, which is the point: it works on anything,
including apps that expose no tree and no script dictionary.

```bash
cliclick c:412,208
chewie type "hello"
peekaboo hotkey cmd+s
```

- **Cost:** zero to send. The cost is that you had to know *where*, which usually
  means you already paid for layer 3 or layer 5.
- **Reliability:** the event always fires. Whether it lands on the thing you meant is
  a different question.
- **Reach:** universal.
- **Permission:** Accessibility.

Three traps live here and all three are silent. Secure Input kills your keystrokes
whenever a password field has focus anywhere on the system. App Sandbox makes
`CGEvent.post` a no-op with no error. And it steals the user's cursor, which is
obnoxious if they are sitting there.

Details: [03-SYNTHETIC-INPUT.md](03-SYNTHETIC-INPUT.md)

---

## Layer 5: Vision

**Screenshot the screen, ask a model where to click, click there.**

This is what "computer use" means in the marketing, and it is the most general and
worst-performing layer you have. Anthropic's `computer_toolset_20260801` and OpenAI's
CUA both live here: an image goes up, `left_click` with a coordinate comes back.

```bash
chewie shot --app Figma
```

- **Cost:** high. About 1,500 tokens per screenshot, a second or more per round trip,
  and you need one on every step because you cannot see the result otherwise.
- **Reliability:** the weakest link in the stack. Grounding a coordinate on a dense UI
  is genuinely hard, and models still miss. See [BENCHMARKS.md](BENCHMARKS.md) for what
  the numbers actually are.
- **Reach:** universal. It is the only thing that works on a canvas.
- **Permission:** Screen Recording.

Use it for what it is uniquely good at: canvas apps, visual judgment ("does this look
right"), and as the last resort when the tree came back empty and you have already
tried the Electron fix.

Details: [04-VISION.md](04-VISION.md)

---

## Layer 6: The browser

**A browser is its own operating system. Drive it as one.**

Half of all real tasks happen inside a browser tab. Driving a browser through
screenshots is strictly worse than driving it through the DOM: Playwright and the
Chrome DevTools Protocol give you the whole page as structured text, with selectors
that do not move.

The exception worth knowing: `browser-use` and `page-agent` are built for exactly this
and are two of the most-starred projects in the whole space. Safari has an AppleScript
dictionary that keeps the user's logins and costs nothing.

Details: [06-BROWSER.md](06-BROWSER.md)

---

## Layer 7: The sandbox

**Give the agent a machine that is not yours.**

An agent with Accessibility can read every pixel on your screen and click every button
on it. It also takes your cursor while it works, which makes the machine unusable. A
VM solves both.

Apple's Virtualization framework runs macOS on Apple Silicon at near-native speed.
Lume, Lumier, UTM, and trycua all wrap it. The cost is a full OS image and no access
to your real logged-in state, which is often exactly the thing you wanted.

Details: [07-SANDBOX.md](07-SANDBOX.md)

---

## The routing table

| Task | Layer | Why |
|------|-------|-----|
| "What did she text me?" | 1 | It is a SQL query |
| "What tab is open?" | 2 | `osascript` one-liner |
| "Click Sign In" | 3 | The tree has a button named "Sign In" |
| "Press Cmd+S" | 4 | No element involved, just a key |
| "Is this chart readable?" | 5 | Genuinely a visual question |
| "Fill this form on the web" | 6 | The DOM beats pixels every time |
| "Run this untrusted thing" | 7 | Not on the real machine |

Same table as JSON: [`../data/layers.json`](../../mac/data/layers.json).
