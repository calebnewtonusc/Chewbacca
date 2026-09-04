---
name: mac-act
description: Click, type, drag, scroll, press keys, and drive UI on the user's Mac. Use when the user asks to click something, fill in a field, press a shortcut, select a menu item, or perform any action in a Mac app.
---

# Acting on a Mac

## Click

Best to worst, in order.

```bash
chewie click "@s8f3k2p9:e12"          # a ref from a snapshot. use this.
chewie click "Sign In" --app Safari    # by label
chewie click "412,208"                 # a raw coordinate. last resort.
```

A ref is unambiguous. A label is usually fine. A coordinate is a guess that happens to
be right, and it stops being right when the window moves.

**Refs are scoped to the snapshot that produced them.** After anything that changes the
UI (a sheet opens, a page navigates, a list scrolls, a window resizes), re-snapshot.
A stale ref does not error, it clicks the wrong thing.

## Type

```bash
chewie type "hello"
chewie type "$LONG_TEXT" --paste       # clipboard, auto for >200 chars
```

For anything long, use the clipboard. Character-by-character typing is slow and every
keystroke is a chance for a dropped event. `peekaboo paste` sets the clipboard, sends
Cmd+V, and **restores what the user had copied**, which matters more than it sounds.

Better than typing at all, when the app supports it: set the value directly through the
tree.

```bash
agent-desktop type @s8f3k2p9:e4 "hello"
```

**If typing silently does nothing, it is Secure Input.** A password field somewhere has
focus and macOS is discarding your keystrokes with no error. `chewie doctor
--secure-input` names the process holding it. Fix by moving focus off the field:
`open -a Finder`, then retry.

## Keys, menus, windows

```bash
peekaboo hotkey cmd+s
peekaboo press escape
peekaboo menu click --app Safari --path "File > New Window"
peekaboo window list --app Mail
peekaboo dialog click --button "OK"
peekaboo scroll down --amount 5
peekaboo drag --from 100,100 --to 400,400
```

Menu paths are more reliable than hunting for a button. If the action exists in a menu,
use the menu.

## Ask the app instead

Before any of the above, check whether the app will just do it:

```bash
sdef /Applications/Foo.app | head -50            # does it have a dictionary?
chewie run 'tell application "Mail" to send message 1'
```

An AppleScript either works or returns an error. It does not have a success rate. Every
action you push down from clicking to scripting leaves the probabilistic regime.

## Verify

Always. `see → act → see`. Twenty steps at 95% each is 36% overall, and the failure
usually happens on the step you were not watching.

## The gate

Send, pay, delete, post, submit, reply-all, purchase, confirm: **stop and ask.** State
exactly what you are about to do. This does not lift because the user said to act
without asking; what needs authorizing is the outbound consequence, not your autonomy.
