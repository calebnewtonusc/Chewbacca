# When it does not work

Organized by what you noticed, not by what the cause turns out to be.

Before anything else: `chewbacca doctor`. It runs 60-odd checks, names what is
broken, and `chewbacca doctor --fix` repairs what it can on its own.

## Claude does not seem to know my standards

The rules are not loading. Check:

```
chewbacca doctor          # "every import resolves to a real file"
chewbacca why "<a phrase from a rule you expect>"
```

`chewbacca why` traces a behavior to the file that should be causing it. If it
finds nothing, the rule is not installed. `chewbacca setup --only rules`.

## A skill never fires

Skills load from their `description`, so a skill whose description does not
share vocabulary with how you actually phrase things will not load.

```
chewbacca skills search <word you would use>
chewbacca evals                      # flags a prompt that shares no vocabulary
```

## Something asks for permission, or does nothing

macOS permissions, almost always. They fail silently by design.

```
chewbacca doctor          # checks Full Disk Access by actually reading the database
```

Screen Recording and Accessibility live in System Settings, Privacy & Security.
Grant them to the app you actually run Claude from: Terminal, iTerm, Ghostty
and VS Code are four separate grants, and switching terminals loses the grant.
Reinstalling a tool also invalidates its grant, which is why something that
worked last week stops.

## Reading my texts fails

Full Disk Access, given to your terminal. The check that proves it:

```
sqlite3 ~/Library/Messages/chat.db "select count(*) from message" | head -1
```

An error means the grant is missing, not that the kit is broken.

## Sessions feel slow to start

```
chewbacca bench           # times every hook against a budget
chewbacca log slow        # the slowest runs recorded
chewbacca context         # what loads before you type
```

The session context hook caches for 15 minutes. `CHEWBACCA_NO_CACHE=1` turns
that off if you are debugging it.

## An MCP server is not there

Three of the twelve need you to authorize them in a browser, which cannot
happen inside an agent session. Run `/mcp` in an interactive Claude Code
session, or `claude mcp list` to see which are connected.

## The install stopped partway

Re-run it. Every section is written to be safe to repeat.

```
chewbacca setup                    # all of it again
chewbacca setup --only mac-tools   # just the section that failed
```

The section names are the `# ── Name ──` headers in `setup.sh`.

## I want it gone

```
chewbacca uninstall --dry-run   # see exactly what would be removed
chewbacca uninstall             # do it, exporting your data first
```

Your context repo, your git identity, Homebrew, node and the claude CLI are
never touched. Your people store and ledger are exported to a tarball before
anything is removed.

## Nothing here matches

```
chewbacca doctor --json > doctor.json
chewbacca log errors
```

Those two plus what you typed is enough for anyone to help. Open an issue.
