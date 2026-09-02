# Giving an Agent Control of Native macOS Apps

Claude Code can read your repo and run your shell. It cannot, on its own, read
your calendar, find a phone number in Contacts, or check what someone texted you
an hour ago. Those live behind app APIs that have no command-line surface.

[mac-cli](https://github.com/31Carlton7/mac-cli) closes that gap. One binary,
`mac`, exposes Calendar, Reminders, Contacts, Mail, Messages, Notes, Music, TV,
Finder, Shortcuts, and the iWork apps, with `--json` on every command and exit
codes an agent can branch on. MIT licensed.

---

## Install

There is no Homebrew formula yet. Build it:

```bash
git clone https://github.com/31Carlton7/mac-cli.git ~/Projects/mac-cli
cd ~/Projects/mac-cli
swift build -c release
install -d ~/.local/bin && install .build/release/mac ~/.local/bin/mac
```

Requires macOS 14 or newer and the Xcode command line tools. The upstream
`make install` targets `/usr/local/bin`, which needs `sudo`. Installing to
`~/.local/bin` avoids that and keeps the binary with the rest of your user
tools, as long as that directory is on your `PATH`.

**If the build dies fetching dependencies**, look for this:

```
fatal: cannot use bare repository '.../swift-argument-parser-54a11a8d'
  (safe.bareRepository is 'explicit')
```

That is not a mac-cli bug. SwiftPM caches dependencies as bare repositories, and
`safe.bareRepository = explicit` in your git config forbids reading them. Do not
change the global setting to work around one build. Override it for the single
command:

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository \
  GIT_CONFIG_VALUE_0=all swift build -c release
```

The same trick applies to any SwiftPM build on a machine with that setting.

---

## The permission model is the part that surprises people

macOS gates this through TCC, and the consent is granted to **your terminal**,
not to the `mac` binary. A terminal that already has Full Disk Access and has
been approved for Contacts gets those for free. A different terminal starts from
zero, so the same command works in one app and fails in another.

```bash
mac doctor
```

That reports every capability with a fix step. Three states matter:

| Report      | Meaning                                                       |
| ----------- | ------------------------------------------------------------- |
| `granted`   | Works now                                                     |
| `writeOnly` | Calendar only. It can add events but not read them            |
| `unknown`   | Not yet prompted. Open the app once, then re-run `mac doctor` |

`writeOnly` on Calendar is the one that looks broken and is not: macOS has a
separate "full access" toggle under Privacy & Security > Calendars, and until it
is on, reads fail while writes succeed. Reading Messages history additionally
needs Full Disk Access, because it reads `chat.db` directly.

An agent should run `mac doctor` before assuming a capability exists, and treat
exit code `2` as "ask the human to grant this," never as a retry.

---

## The contract an agent codes against

- `--json` on every command, sorted keys, ISO 8601 dates.
- Exit codes: `0` success, `1` not found or bad input, `2` permission denied,
  `64` malformed invocation (unknown flag, missing option).
- Mutations take exact IDs only. Get them from `list` or `find` first, never
  construct them.
- `--json` still prints under `--quiet`; `--quiet` only suppresses the human
  rendering.

Two rules worth hard-coding into your agent's instructions:

**Prefer `mac mail draft` over `mac mail send`** unless the human explicitly
asked to send. A draft is recoverable and a sent message is not.

**A successful `mac messages send` is not proof of delivery.** Messages accepts
sends to handles that were never registered with iMessage without raising an
error. If delivery matters, read the thread back with `mac messages history`.

---

## Where it is genuinely weak

The upstream README documents its limits honestly, which is rarer than it should
be. The ones that change how you write agent instructions:

- **Mail reads are windowed.** Every read examines only the newest `--scan`
  messages per inbox, default 30, max 500. Older mail is invisible, not missing.
  Cost scales with messages touched, roughly 1.5s per message on a 50k-message
  account, so a large `--scan` on a big mailbox is a hang, not a query.
- **Music and TV search your library, not the catalog.** A song you have never
  added will not appear.
- **Recurring calendar events share one ID** across occurrences. Editing or
  deleting hits the series, not the instance you meant.
- **Group chats are read-only**, and `mac messages send` does no phone-number
  normalization. Resolve names with `mac contacts find` first.
- **iWork commands address documents that are already open**, by name, and edits
  are text-only.

The recurring theme is that AppleScript's `whose` filtering is unusable at
scale: on a large mailbox it pins the app at 98% CPU indefinitely. Every
windowing limit above exists because of that, not because someone was lazy.

---

## A bug worth studying, because the shape is common

Version 0.6.0 walks the Notes folder tree with a queue and no visited set:

```applescript
set queue to (folders of a) as list
repeat while (count of queue) > 0
    set f to item 1 of queue
    -- pop, then append this folder's children
    try
        set queue to queue & ((folders of f) as list)
    end try
    set rec to ((id of f) as text) & ...   -- not guarded
end repeat
```

On an account carrying a stale iCloud row, a "ghost" folder is listed as a child
but cannot be resolved: `id of f` and even `name of f` throw `-1728`. Every
Notes read command dies on it with an opaque coercion error, so `list`,
`search`, and `folders` all fail at once.

The instructive part is what happens when you fix it carelessly. Wrapping the
unguarded line in a `try` makes the error go away and turns a two-second failure
into an infinite loop, because the ghost folder lists **itself** as its own
child and the queue never drains. The fast, loud failure had been hiding a
worse bug.

The real fix needs both halves:

```applescript
set visited to {}
...
set fid to ""
try
    set fid to ((id of f) as text)
end try
if fid is not "" and not (visited contains fid) then
    copy fid to end of visited
    -- enqueue children and emit the record only for folders that resolve
end if
```

Two rules generalize past this codebase:

1. **Any walk over a graph you did not build needs a visited set.** External
   data structures are not guaranteed acyclic just because they are drawn as
   trees.
2. **A `try` that converts an error into a skip changes control flow.** Before
   adding one, ask what the loop does now that it no longer exits. An error is
   sometimes the only thing terminating your program.

Diagnose this class of bug by capping the iteration count and printing progress,
rather than by reading harder:

```applescript
set n to n + 1
if n > 60 then return "CAP HIT, queue still=" & (count of queue)
```

Sixty iterations of the same name told the whole story in one run.
