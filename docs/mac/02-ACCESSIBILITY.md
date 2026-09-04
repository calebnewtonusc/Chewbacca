# Layer 3: The accessibility tree

The single highest-leverage thing in this repo. If you take one idea away, take this
one: **macOS already hands you every UI element as structured data, and you are
probably screenshotting instead.**

## What it is

`AXUIElement` is the C API behind VoiceOver. Every running application publishes a
tree of elements, and each element carries attributes:

| Attribute | Example |
|-----------|---------|
| `AXRole` | `AXButton`, `AXTextField`, `AXMenuItem`, `AXRow`, `AXWindow` |
| `AXTitle` / `AXDescription` | `"Sign In"` |
| `AXValue` | the text currently in a field |
| `AXPosition` / `AXSize` | where it is, in screen points |
| `AXEnabled`, `AXFocused`, `AXSelected` | state |
| `AXChildren` / `AXParent` | the tree |

And actions you can perform on it: `AXPress`, `AXIncrement`, `AXShowMenu`,
`AXConfirm`, `AXCancel`.

The tree is not a rendering of the screen. It is the app's own model of its interface,
which is why it is stable: the button is still `"Sign In"` after the window moves, the
theme changes, or the layout reflows.

## Why it beats screenshots, in numbers

- Reading a tree takes roughly **50 milliseconds**. A screenshot round trip through a
  vision model takes **one to several seconds**.
- Tools that measured it report **78 to 96 percent fewer tokens** on dense
  applications compared to sending the image.
- You get **names**, not guessed coordinates. `click "Sign In"` cannot land on the
  wrong button the way `left_click [412, 208]` can.
- It works on **background windows**. No focus stealing, no cursor hijack. The user
  can keep typing while your agent works in another app.

## Using it

Three tools, all installed by `install.sh`, all wrapped by `chewie see`.

**agent-desktop** (Rust, Apache-2.0, ~1k stars) is the cleanest pure-AX driver.

```bash
agent-desktop snapshot --app Finder -i     # tree with interactive refs
agent-desktop find --role AXButton --name "Save"
agent-desktop click @s8f3k2p9:e12
agent-desktop type @s8f3k2p9:e4 "hello"
agent-desktop get @s8f3k2p9:e4 value
agent-desktop permissions --request
```

**Peekaboo** (Swift, MIT, ~5k stars) has the widest macOS surface: menu bars, the Dock,
Spaces, system dialogs, status items.

```bash
peekaboo see --app Safari
peekaboo click "Sign In"
peekaboo menu click --app Safari --path "File > New Window"
peekaboo dialog click --button "OK"
peekaboo window list --app Mail
```

**System Events** through AppleScript, when you are already in a script and need one
click. See [01-SCRIPTING.md](01-SCRIPTING.md).

## Element refs and staleness

Refs look like `@s8f3k2p9:e12`, a snapshot ID and an element index. **A ref is only
valid for the snapshot that produced it.** Anything that changes the UI invalidates
it: a click that opens a sheet, a page navigation, a window resize, a list scrolling.

The loop is:

```
see → pick a ref → act → see again
```

Not:

```
see once → act, act, act, act
```

The second one works until it silently clicks the wrong row, which it will, on the
step you were not watching.

## The Electron problem, and the fix

Chromium builds its accessibility tree **lazily**. It stays off until it sees a client
ask for it, to avoid the performance cost. So the first time you snapshot a Chrome,
VS Code, Slack, Discord, Notion, Figma, or Spotify window, you get back a nearly empty
tree, or a tree full of unnamed `AXGroup` nodes.

Chromium watches for `AXEnhancedUserInterface` being set on the main window, which is
what VoiceOver sets. Electron additionally supports `AXManualAccessibility`, added
specifically so non-VoiceOver tools could turn the tree on without pretending to be a
screen reader.

The fix is to set the attribute on the **application** element and then re-read:

```swift
let app = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
// then snapshot again
```

`chewie see --force-ax` does this for you. Three notes from experience:

- Setting it can return `kAXErrorAttributeUnsupported` on some Electron versions. Set
  `AXEnhancedUserInterface` as a fallback.
- The tree does not populate instantly. **Retry after 200 to 500 milliseconds.** An
  immediate re-read still looks empty and people conclude the fix does not work.
- Leaving it on costs the app some performance. Well-behaved tools set it, work, and
  unset it.

If you snapshot an Electron app, get nothing, and immediately take a screenshot, you
have just paid ten times as much for worse information. Try the fix first.

### What this actually did, measured

Tested on this machine, 2026-09-04, macOS 15:

- **Slack** (Electron): `AXUIElementSetAttributeValue(app, "AXManualAccessibility", true)`
  returned `0` (kAXErrorSuccess). `AXEnhancedUserInterface` returned `-25208`
  (kAXErrorAttributeUnsupported) when set on the application element, so treat it as a
  fallback that often will not take, not as an equivalent.
- **VS Code** (Electron): a snapshot returned **284 refs** with a full labeled tree.
- **Google Chrome**: **18 refs before the fix and 18 after.** Setting the attribute did
  not expose page content.

That last one is the useful correction. Chrome's *browser chrome* is accessible, but its
**renderer** accessibility is a separate switch that `AXManualAccessibility` does not
flip; it wants the `--force-renderer-accessibility` launch flag. So do not expect to read
a web page out of Chrome through the AX tree.

You should not be trying to anyway. Web content is layer 6: attach to the running browser
over CDP and read the DOM, which is better than either the AX tree or a screenshot. See
[06-BROWSER.md](06-BROWSER.md).

## What genuinely has no tree

Some things really are opaque and belong at layer 5:

- Games and anything rendering to a single OpenGL/Metal surface
- Figma, Sketch canvases, video editors, DAW timelines (chrome is accessible, the
  canvas is one big element)
- Video and image content
- Custom-drawn UIs from developers who skipped accessibility, which is more common in
  indie Mac apps than you would hope
- Remote desktop and screen sharing windows

Recognizing these fast is what keeps you from burning ten minutes fighting the tree.
A snapshot returning a single `AXImage` or `AXUnknown` the size of the window is the
tell.

## Reading the tree by hand

For debugging, Apple ships **Accessibility Inspector** (in Xcode, or
`/Applications/Xcode.app/Contents/Applications/Accessibility Inspector.app`). Point it
at an element and it shows you the exact role, title, and available actions. When
`chewie click` cannot find something, this tells you what the element is actually
called, which is frequently not what it looks like it is called.

## Permission

**Accessibility**, in System Settings > Privacy & Security > Accessibility. Granted to
the process that makes the call, which for an agent means the terminal or editor
hosting it. There is no API to grant this. See [PERMISSIONS.md](PERMISSIONS.md).

Note that reading the tree and posting events are the same TCC bucket, so once you have
Accessibility you have both layers 3 and 4.
