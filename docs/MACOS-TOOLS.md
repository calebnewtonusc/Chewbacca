# macOS tools

Claude Code can read and write files all day and still be blind to the rest of
the machine. It cannot see a window, click a button, read your calendar, or
remember what you copied ten minutes ago. These six tools close that gap, and
`setup.sh` installs them.

None are vendored. Each is a third-party project installed from its own source,
so each keeps its own license and updates on its own schedule.

| Tool                                                | Source                 | Needs                                     |
| --------------------------------------------------- | ---------------------- | ----------------------------------------- |
| [peekaboo](https://github.com/openclaw/Peekaboo)    | openclaw/tap           | Screen Recording plus Accessibility       |
| [gog](https://github.com/openclaw/gogcli)           | openclaw/tap           | One Google OAuth login                    |
| [summarize](https://github.com/steipete/summarize)  | steipete/tap           | A provider key, or the Claude CLI         |
| [mac-use](https://github.com/browser-use/macOS-use) | clone plus a uv venv   | Accessibility, and a provider key         |
| [mac](https://github.com/31Carlton7/mac-cli)        | clone plus swift build | Per-app consent, granted to your terminal |
| [Maccy](https://github.com/p0deje/Maccy)            | Homebrew cask          | Nothing                                   |

Plus one skill pack, [agent-scripts](https://github.com/steipete/agent-scripts),
covered at the bottom.

---

## peekaboo

Screenshots, accessibility inspection, and real input. It is the difference
between Claude guessing what your app looks like and Claude looking at it.

```bash
brew install openclaw/tap/peekaboo
peekaboo permissions          # both must say Granted
```

Screen Recording and Accessibility are granted once in System Settings under
Privacy and Security. Until both are on, capture returns an empty image and
clicks do nothing, with no error worth reading.

```bash
peekaboo image --app Safari --path /tmp/shot.png   # capture one app
peekaboo list apps                                  # what is running
peekaboo click "Sign In"                            # click by accessibility label
peekaboo type "hello"                               # keyboard input
peekaboo menu --app Finder --item "New Folder"      # drive the menu bar
peekaboo learn                                      # the full agent-facing guide
```

`peekaboo learn` prints a usage guide written for an agent rather than a person.
Point Claude at it before asking for anything complicated.

### As an MCP server

Peekaboo also speaks MCP, which gives Claude the tools directly instead of
through shell calls:

```bash
claude mcp add peekaboo --scope user -- peekaboo mcp serve
claude mcp list | grep peekaboo     # expect: Connected
```

Prefer the MCP server for interactive work and the CLI inside scripts.

---

## gog

Gmail, Calendar, Drive, Docs, Sheets, Contacts, and Tasks from the terminal.

```bash
brew install openclaw/tap/gogcli     # the binary is `gog`, not `gogcli`
gog auth login                       # opens a browser, once
gog auth status                      # config_exists should flip to true
```

The login is the only step a person has to do by hand. Until it runs,
`gog auth status` reports `config_exists false` and every command fails.

```bash
gog gmail list --json                 # scriptable output
gog calendar list --plain             # TSV, stable for parsing
gog drive ls
```

Use `--json` when Claude will parse the result and `--plain` for TSV. Add
`--no-input` in anything automated so it fails instead of hanging on a prompt,
and `--account` when more than one Google account is logged in.

---

## summarize

Point it at a URL, a YouTube video, a podcast, or a local file and get the gist.
It handles transcript fetching, audio transcription, and slide extraction.

```bash
brew install steipete/tap/summarize
summarize "https://example.com"
summarize "https://youtube.com/watch?v=..." --extract --format md
summarize ~/Downloads/paper.pdf
```

### It does not need an API key

`--cli claude` routes the summarization through the Claude CLI already on the
machine, so no provider key is involved:

```bash
summarize "https://example.com" --cli claude
```

`--cli` also takes `gemini` and `codex`. With a key set instead
(`OPENAI_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, and others), it calls
the provider directly and `--model openai/gpt-5-mini` picks the model.

**One catch with `--cli claude`:** the Claude CLI loads `~/.claude/CLAUDE.md`
like any other session, so your global instructions shape the summary. Anything
that tells Claude to always open with a certain line will put that line on top
of every summary. Use a provider key when you want the summary and nothing else.

Every run prints its own cost and word count on the last line.

---

## mac-use

A natural-language agent that drives any Mac app through the Accessibility API.
Upstream ([browser-use/macOS-use](https://github.com/browser-use/macOS-use))
ships a Python library and example scripts, not a CLI, so this kit adds one:
[bin/mac-use](../bin/mac-use) plus [bin/mac_use_cli.py](../bin/mac_use_cli.py).

```bash
mac-use "open Calculator and compute 5 x 4"
mac-use --steps 40 --vision "read the title of the frontmost Safari tab"
mac-use --provider anthropic "create a note titled Groceries"
```

Manual install, if you are not running `setup.sh`:

```bash
git clone https://github.com/browser-use/macOS-use.git ~/Projects/macOS-use
cd ~/Projects/macOS-use && uv venv --python 3.11
uv pip install --python .venv/bin/python --editable .
cp bin/mac_use_cli.py ~/Projects/macOS-use/mac_use_cli.py
cp bin/mac-use ~/.local/bin/mac-use && chmod +x ~/.local/bin/mac-use
```

It needs one of `GEMINI_API_KEY`, `OPENAI_API_KEY`, or `ANTHROPIC_API_KEY` and
picks the first it finds, in that order. Without one it prints which variables
it looked for and exits 2. `MACOS_USE_HOME` overrides the clone location.

Upstream turns on PostHog telemetry by default. The wrapper sets
`ANONYMIZED_TELEMETRY=false` unless you export it yourself.

This one moves the real mouse and types into the real keyboard. Give it small,
checkable tasks and watch the first few runs.

---

## mac

The native Apple apps as JSON. Calendar, Reminders, Contacts, Mail, Messages,
Notes, Music, TV, Finder, Shortcuts, and the iWork apps, all from one binary
with `--json` on every command.

Where `peekaboo` and `mac-use` drive the GUI, `mac` talks to the apps directly.
Prefer it whenever the thing you want is data rather than a click: reading a
calendar, resolving a phone number, checking a thread. It is faster and it does
not move the mouse.

There is no Homebrew tap yet, so `setup.sh` clones and builds it:

```bash
git clone https://github.com/31Carlton7/mac-cli.git ~/Projects/mac-cli
cd ~/Projects/mac-cli && swift build -c release
install -d ~/.local/bin && install .build/release/mac ~/.local/bin/mac
```

Needs macOS 14 or newer and the Xcode command line tools. If the build fails on
`safe.bareRepository is 'explicit'`, that is your git config blocking SwiftPM's
bare dependency cache, not a bug in the tool. Override it for the one build:

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository \
  GIT_CONFIG_VALUE_0=all swift build -c release
```

Consent is per capability and is granted to **your terminal**, not to the
binary, so the same command can work in one terminal and fail in another.

```bash
mac doctor                                  # every capability, with fix steps
mac calendar list --from today --to +7d
mac contacts find "Sarah" --json
mac messages history +15551234567 --limit 5
mac reminders add "Buy milk" --list Groceries --due "tomorrow 9am"
```

`mac doctor` reporting `writeOnly` for Calendar is the confusing one: macOS has
a separate full-access toggle under Privacy and Security > Calendars, and until
it is on, writes work while reads fail. Reading Messages history additionally
needs Full Disk Access. Exit code `2` always means permission, never retry it.

Two safety rules worth hard-coding: prefer `mac mail draft` over `mac mail send`
unless sending was explicitly asked for, and treat a successful
`mac messages send` as unconfirmed until you read the thread back, because
Messages accepts sends to unregistered handles without an error.

The JSON contract, the windowing limits on Mail and Music, and a worked
debugging case study live in
[docs/MACOS-APP-CONTROL.md](MACOS-APP-CONTROL.md).

---

## Maccy

Clipboard history in the menu bar, so a token or URL you scrolled past is still
recoverable. Shift + Command + C opens it.

```bash
brew install --cask maccy
open -a Maccy          # launch it once, then it stays in the menu bar
```

It skips pasteboard types marked concealed or transient, which covers most
password managers. To pause recording during sensitive work:

```bash
defaults write org.p0deje.Maccy ignoreEvents true    # and false to resume
```

Auto-paste needs Maccy under Privacy and Security, Accessibility. Without it,
picking an item copies rather than pastes.

Only `maccy.app` is the real site. `maccyapp.com` and `maccyapp.net` distribute
malware under the same name.

---

## The agent-scripts skill pack

[steipete/agent-scripts](https://github.com/steipete/agent-scripts) is one repo
holding dozens of agent skills: Swift and SwiftUI review, Instruments profiling,
GitHub triage, macOS release work, Obsidian, Reminders, and more. `setup.sh`
clones it and symlinks each skill into `~/.claude/skills/`, so `git pull` in the
clone updates all of them at once.

**Do not run its `scripts/sync-skills`.** That script is the pack's own
installer, and among other things it points `~/.claude/CLAUDE.md` at the pack's
`AGENTS.MD`. On a machine where `CLAUDE.md` holds your own instructions, that
replaces them. The install in `setup.sh` does the linking itself and touches
nothing outside `~/.claude/skills/`.

Two things the installer skips:

- **`codex-first`**, which routes implementation work to the Codex CLI. It is a
  workflow decision, not a capability, and it belongs to the pack author's
  setup rather than yours. Link it by hand if you want it.
- **Broken symlinks.** Roughly a dozen entries in `skills/` point at sibling
  repos the author keeps checked out next to this one (`gog`, `imsg`, `wacli`,
  `discrawl`, and others). Without those clones the links dangle, so the
  installer only takes entries that actually contain a `SKILL.md`.

Skill descriptions load into every session, so a pack this size is not free. To
see what you have and drop what you do not use:

```bash
ls -l ~/.claude/skills | grep agent-scripts        # what came from the pack
rm ~/.claude/skills/<name>                          # removes the link only
```

Removing a link never touches the clone, and re-running `setup.sh` puts back
anything you removed.

---

## Verifying

```bash
peekaboo permissions                  # Granted, twice
gog auth status                       # config_exists true
summarize "https://example.com" --cli claude
mac-use --help
mac doctor
ls /Applications/Maccy.app
ls ~/.claude/skills | wc -l
```
