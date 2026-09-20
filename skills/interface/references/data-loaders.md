# Loading any data on this machine

The second half of building fast. A preset renders in seconds and then the
session spends ten minutes working out where the numbers come from, so the
sources are written down the same way the components are.

Every row is something this kit can already reach. Prefer the row over writing
a scraper, and prefer a CLI with `--json` over parsing a UI.

## Already wired, use these first

| Data | Command | Notes |
| --- | --- | --- |
| People and relationships | `people <verb> --json` | SQLite at `~/.chewbacca/people`. 3,349 rows |
| iMessage history | `sqlite3 ~/Library/Messages/chat.db` | `text` is usually empty; decode `attributedBody` |
| Coursework, deadlines, grades | `coursework <verb> --json` | The ledger is the source of truth for dates |
| Calendar, Contacts, Mail, Reminders, Notes, Finder | `mac <app> <verb> --json` | `mac doctor` first; exit 2 means consent is needed |
| Screen contents | `chewie see --app <App>` | Accessibility tree, not pixels. Fast and exact |
| A window as an image | `peekaboo image --app <App>` | Only when the tree does not carry it |
| Any URL, video or PDF | `summarize "<url>" --cli claude` | Handles YouTube without an API key |
| YouTube transcript | `yt-transcript "<url>"` | Never WebFetch a YouTube URL |
| Repo state | `git`, `gh` | `gh api` for anything the CLI does not surface |
| The user's own notes | `grep -ri "<term>" ~/second-brain` | `hot.md` then `index.md` |
| Clipboard history | Maccy | Recovers a value already scrolled past |

## The decode nobody remembers

`chat.db.text` is NULL on modern macOS. The words live in `attributedBody`, a
NeXT typedstream. The payload follows the marker `NSString\x01\x95\x84\x01+`
and a length prefix: one byte under `0x80`, `0x81` plus a uint16 LE, `0x82`
plus a uint32. Reading `text` alone silently returns an empty thread, which
reads as "they never messaged" rather than as a bug.

## The four shapes every source arrives in

Knowing which one you have decides the loader, and there are only four.

| Shape | Reach it with | Examples |
| --- | --- | --- |
| **A CLI with `--json`** | Run it, parse stdout | `people`, `coursework`, `mac`, `gh` |
| **A local database** | Open read-only, `file:...?mode=ro` | `chat.db`, AddressBook, Notes, Photos |
| **A local file tree** | Walk it | Downloads, a repo, an export, a Drive folder |
| **A live UI with no API** | Accessibility tree first, DOM second, pixels last | a dashboard behind a login, a native app |

**Read-only, always.** Open every user database with `mode=ro`. A generator
exploring someone's Messages must not be able to write to it.

## Never do these

- Never parse a UI for something a CLI exposes. `mac calendar list --json`
  beats screenshotting Calendar, and it beats it on speed and on accuracy.
- Never copy a user database to a temp directory to read it. Open it read-only
  in place, or you have made a second copy of their private data with no
  lifecycle.
- Never cache personal data into the artifact you are generating. The page
  reads the source at render time, or it goes stale and leaks at the same time.
- Never claim a source is unavailable before checking this table.
