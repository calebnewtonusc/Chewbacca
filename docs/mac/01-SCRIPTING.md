# Layer 2: Native scripting

AppleScript, JXA, Shortcuts, and the small pile of command-line tools that talk to
macOS directly. This layer is free, fast, and survives every visual change, and it is
worth exhausting before you go anywhere near a screenshot.

## osascript

The universal entry point. Runs AppleScript by default, JavaScript with `-l JavaScript`.

```bash
osascript -e 'tell application "Safari" to get URL of front document'
osascript -e 'tell application "Music" to play'
osascript -l JavaScript -e 'Application("Notes").notes[0].name()'
osascript ~/scripts/thing.scpt arg1 arg2
```

Multi-line from a heredoc, which is how you actually write these:

```bash
osascript <<'SCRIPT'
tell application "Mail"
  set unreadCount to unread count of inbox
  return unreadCount
end tell
SCRIPT
```

**Finding out what an app can do.** Every scriptable app ships a dictionary. Open
Script Editor > File > Open Dictionary, or:

```bash
sdef /System/Applications/Mail.app | head -100
osascript -e 'tell app "System Events" to get name of every application process'
```

If `sdef` returns nothing useful, the app is not scriptable and you are going to
layer 3.

## JXA

Same Apple Events, JavaScript syntax. Better when you need real data structures, JSON,
or anything involving arrays and maps. Worse documented, and it has genuine bugs that
AppleScript does not.

```javascript
// chewie run --js 'Application("Notes").notes().map(n => n.name())'
const Notes = Application("Notes")
Notes.notes().slice(0, 5).map(n => ({name: n.name(), modified: n.modificationDate()}))
```

Practical rule: AppleScript for app control, JXA when you need to shape data before
returning it. JXA can `JSON.stringify` its result, which makes it much easier to parse.

## System Events: the escape hatch

`System Events` is Apple's own AppleScript bridge into the accessibility tree. It lets
you click and type in apps that expose no dictionary at all.

```applescript
tell application "System Events"
  tell process "Notes"
    click button "New Note" of group 1 of window 1
    keystroke "hello"
    key code 36 -- Return
  end tell
end tell
```

**This is layer 3, not layer 2.** It needs Accessibility permission, not just
Automation, and it is slower and clumsier than a real AX driver. Reach for it when you
are already in AppleScript and only need one click. Reach for `chewie see` /
`agent-desktop` when you need to actually navigate a UI.

Reading the tree in AppleScript is possible and painful:

```applescript
tell application "System Events" to tell process "Notes"
  get entire contents of window 1
end tell
```

That dumps everything with no refs and no structure. Use a real tool.

## Shortcuts

macOS ships a `shortcuts` CLI. Shortcuts is the one automation surface Apple is
actively investing in, so it reaches things AppleScript no longer does, including some
iOS-originated actions and system toggles.

```bash
shortcuts list
shortcuts run "Daily Digest"
echo "input text" | shortcuts run "Process Text"
shortcuts run "Make PDF" --input-path ~/doc.md --output-path ~/out.pdf
```

**The pre-warm requirement.** A shortcut that touches a protected resource (contacts,
photos, a specific app) prompts on first run. That prompt cannot be answered from a
headless context. Run each shortcut once by hand, answer Always Allow, confirm it runs
prompt-free from the terminal, and only then let an agent or a launchd job call it.

There are two runtimes and they are not the same. The `shortcuts` CLI is for shell
callers. `Shortcuts Events` is the Apple Events target, used from AppleScript, and it
has to be running. `tell application "Shortcuts Events" to run shortcut "X"` fails
with "isn't running" if the process is not up.

## defaults

Reads and writes preference plists. This is how you change a setting without opening
System Settings.

```bash
defaults read com.apple.dock
defaults write com.apple.dock autohide -bool true && killall Dock
defaults read -g AppleInterfaceStyle 2>/dev/null   # "Dark" or an error if light
defaults domains | tr ',' '\n' | grep -i slack
```

Two things bite. Many apps cache preferences in memory and overwrite your change on
quit, so write while the app is closed or restart it. And `cfprefsd` caches reads, so
a `defaults read` right after a GUI change can return the old value.

## open, launchctl, and friends

```bash
open -a "Safari" "https://example.com"
open -R ~/file.txt                       # reveal in Finder
open -na "Chrome" --args --new-window    # force a new instance
launchctl list | grep -i com.apple.Spotlight
pmset displaysleepnow                     # sleep the display
osascript -e 'display notification "done" with title "Chewbacca"'
```

`open -a` is the cheapest way to make an app frontmost, and it is much more reliable
than clicking the Dock.

## Small tools worth knowing

| Tool | What for |
|------|----------|
| `pbcopy` / `pbpaste` | The clipboard, which is often the easiest data channel into an app |
| `screencapture` | Built-in screenshots, no third-party install needed |
| `sqlite3` | Layer 1, and it is already on the machine |
| `plutil -p file.plist` | Read a binary plist as text |
| `mdfind` | Spotlight from the shell, faster than `find` for content search |
| `networksetup`, `systemsetup` | System config, some parts need sudo |
| `say` | Speech, occasionally the right output channel |
| `caffeinate -d` | Keep the display awake during a long automation |

## Hammerspoon

A Lua runtime with deep macOS bindings, running permanently in the background. It
covers things nothing else does cleanly: window management, hotkey triggers, file
watchers, screen-change watchers, wifi-change watchers, USB events.

For an agent, Hammerspoon's value is not scripting, it is **triggers**. An agent
cannot sit in a loop waiting for something to happen. Hammerspoon can, and it can
shell out to your agent when it does.

```lua
-- ~/.hammerspoon/init.lua
hs.hotkey.bind({"cmd", "alt"}, "J", function()
  hs.execute("/usr/local/bin/chewie see --app " .. hs.application.frontmostApplication():name())
end)

hs.pathwatcher.new(os.getenv("HOME") .. "/Downloads", function(paths)
  hs.execute("~/bin/on-download.sh " .. table.concat(paths, " "))
end):start()
```

It is not installed by `install.sh` because most tasks do not need it. `brew install
--cask hammerspoon` when you want event-driven behavior.

## Permission model for this layer

Everything here needs **Automation** (Apple Events), granted per caller-target pair.
The System Events path additionally needs **Accessibility**.

The part that confuses everyone: a CLI tool has no TCC identity of its own unless it
was built with an embedded `Info.plist` and a bundle ID. Without one, macOS attributes
the request to whatever launched it, so your agent's `osascript` call shows up as
"Terminal wants to control Mail." Grant it to the terminal. Full explanation, including
how to give a CLI real identity, is in [PERMISSIONS.md](PERMISSIONS.md).
