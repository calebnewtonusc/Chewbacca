---
name: mac-debug
description: Diagnose a Mac automation that is failing, especially one failing silently. Use when a click does nothing, typing does not appear, the accessibility tree is empty, an AppleScript hangs or errors, coordinates land in the wrong place, or something that worked before stopped working.
---

# Debugging Mac automation

Most of these fail with no error, which is what makes them expensive. Diagnose before
you retry, and **never respond to a failure by escalating to a screenshot.** A failing
layer-3 read almost always means one specific fixable thing.

## Triage

```bash
chewie doctor                    # grants, host app, tools
chewie doctor --secure-input     # is the keyboard being blocked
```

## By symptom

### Typing does nothing, no error
**Secure Input.** A password field has focus somewhere, and macOS discards synthetic
keystrokes with no error. It is a process-global reference-counted flag, so one stuck
app starves the whole system.

```bash
ioreg -l -w 0 -d 1 -k IOConsoleUsers | grep -o 'kCGSSessionSecureInputPID"=[0-9]*'
```

Nonzero is the pid holding it. Fix: `open -a Finder`, retry. If an app is stuck, focus
and unfocus it, or quit it.

### Clicks do nothing from inside an app
**App Sandbox** silently blocks `CGEvent.post`. No error. No fix inside the sandbox;
this is why every serious macOS automation tool ships outside the App Store.

### Accessibility tree is empty or all elements unnamed
**Chromium builds it lazily.** Chrome, Edge, VS Code, Slack, Discord, Notion, Figma,
Spotify.

```bash
chewie see --app Slack --force-ax
```

Sets `AXManualAccessibility`, waits ~400ms, re-reads. The wait matters: an immediate
re-read still looks empty.

If that returns `kAXErrorAttributeUnsupported` (-25208) on a non-Chromium app, the app
genuinely has no tree and you are at layer 5.

### Clicks land at double the offset
**Retina.** Screenshots are 2x device pixels; `CGEvent` takes screen points. Halve the
coordinate, or stop using coordinates and use refs.

### Clicks land on the wrong monitor
Multi-display origins go negative. Use `CGGetActiveDisplayList` geometry, do not assume
0,0.

### Clicking a ref hits the wrong element
**Stale ref.** It was scoped to a snapshot from before the UI changed. Re-snapshot after
any sheet, navigation, resize, or scroll.

### AppleScript errors
| Code | Meaning | Fix |
|------|---------|-----|
| -1743 | Not authorized | `tccutil reset AppleEvents`, retry in the foreground |
| -600 | App not running | `open -a "App"`, then poll until System Events sees it |
| -1712 | Timeout (~2min) | `with timeout of 300 seconds`. Check for a blocking modal |
| -1728 | Object does not exist | Not permissions. Read the app's dictionary |
| -1750 | errOSASystemError | Usually TCC, reported uselessly |

### `defaults write` had no effect
Apps cache preferences in memory and rewrite on quit. Write with the app closed, or
restart it. `killall cfprefsd` if a read looks stale.

### `chat.db` rows have NULL text
Bodies moved to `attributedBody` on Ventura and later. Decode the typed stream, or use
`mac_messages_mcp`.

### "database is locked"
Open read-only (`file:...?mode=ro`) or copy to `/tmp` first.

### `do JavaScript` fails in Safari
Develop > Allow JavaScript from Apple Events is off by default. Enable the Develop menu
in Safari > Settings > Advanced first.

### The web task dies at a login page
A fresh Playwright browser has no profile. Attach to the user's running Chrome:
`open -a "Google Chrome" --args --remote-debugging-port=9222`.

### It worked yesterday
Almost always: the TCC prompt was dismissed once and never returns, or the host app
changed (different terminal, an update that re-signed the binary). `chewie doctor`.

## Inspecting an element by hand

When `chewie click "Save"` cannot find something, the element is probably not called
what it looks like it is called. Apple's **Accessibility Inspector** (bundled with
Xcode) shows the real role, title, and available actions.

## The stop rule

Three failures on the same action: stop and report what you tried and what you saw. Do
not loop, and do not switch layers to route around a diagnosis you have not made.

Full list with detectors: `docs/WORKAROUNDS.md` and `data/failure-modes.json`.
