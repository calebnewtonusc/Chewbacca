# Layer 1: Data

The layer people skip entirely. Most questions about a Mac are answerable with a SQL
query, and the answer is exact rather than a model's reading of a screenshot.

## Messages

`~/Library/Messages/chat.db` is SQLite. Full Disk Access required.

```bash
sqlite3 ~/Library/Messages/chat.db \
  "SELECT datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') AS d,
          handle.id, message.is_from_me, message.text
   FROM message JOIN handle ON message.handle_id = handle.ROWID
   ORDER BY message.date DESC LIMIT 20"
```

Two gotchas:

- **Apple epoch.** Dates are nanoseconds since 2001-01-01, not 1970. The
  `/1000000000 + 978307200` above converts it.
- **`text` is usually NULL**, and "usually" is not an exaggeration. Measured on a real
  library on 2026-09-04: **of the last 2,000 messages, 72 had plain text and 1,828 did
  not.** That is 3.6% coverage from the naive query, and the missing 96% skews heavily
  toward messages the user *sent*.

  Bodies moved to `attributedBody`, an NSArchiver **typedstream**, not a plist, not
  NSKeyedArchiver, so `plistlib` cannot touch it. The layout:

  ```
  \x04\x0bstreamtyped ... NSString\x01<ref>\x84\x01+ <len> <utf-8 bytes> \x86
  ```

  `+` (0x2B) is the type code for a C string. The length is one byte, or `0x81` plus a
  uint16 LE, or `0x82` plus a uint32 LE.

  **The byte after `NSString\x01` varies and this is the trap.** It is 0x94 for an
  `NSAttributedString` and 0x95 when the payload is an `NSMutableAttributedString`.
  Hardcoding 0x94, which is what most snippets on the internet do, silently drops
  every mutable message. On the library above that was 22 of 400 non-attachment blobs,
  and fixing it took coverage from 92.7% to **95.0%**, with zero parser failures across
  3,000 messages. The remaining 5% are genuine attachments and reactions with no text.

  `lib/attributed_body.py` in this repo is the parser. Or use
  [carterlasalle/mac_messages_mcp](https://github.com/carterlasalle/mac_messages_mcp)
  (323 stars), which handles it and exposes the result over MCP.

Read-only, always. Open with `file:...?mode=ro` and never write while Messages is
running.

```bash
chewie texts --days 7 --unanswered     # threads where they spoke last
chewie texts --who "Sagar" --json      # one person, structured
```

Contact names come from `~/Library/Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb`.
Match on the last 10 digits so `+1 310 555 1234` and `3105551234` resolve to the same
person.

## Notes

`~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`. Bodies are
gzipped protobuf, so raw SQL gets you metadata but not readable text. For actual note
content, AppleScript is easier than reverse-engineering the blob:

```bash
osascript -e 'tell application "Notes" to get body of note 1'
```

## Everything else worth knowing

| What | Where |
|------|-------|
| Safari history | `~/Library/Safari/History.db` |
| Chrome history | `~/Library/Application Support/Google/Chrome/Default/History` |
| Photos | `~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite` |
| Mail index | `~/Library/Mail/V*/MailData/Envelope Index` |
| Reminders / Calendar | `~/Library/Calendars/Calendar.sqlitedb` |
| Music library | `~/Music/Music/Music Library.musiclibrary` |
| App preferences | `~/Library/Preferences/*.plist` (`defaults read`, `plutil -p`) |
| Downloads provenance | `xattr -p com.apple.metadata:kMDItemWhereFroms file` |
| Spotlight | `mdfind "query"`, `mdls file` |

## Rules

1. **Read-only, or you will corrupt something.** Live apps hold write locks and cache
   in memory. Copy the file first if you need to be sure:
   `cp chat.db /tmp/ && sqlite3 /tmp/chat.db ...`
2. **Schemas change between macOS releases.** A query that works on 15 can return an
   empty set on 16. Check `.schema` before trusting a column name.
3. **Full Disk Access is required and it is a big grant.** It gives the process
   everything, including other apps' data and the TCC database itself. Grant it to a
   terminal you control, and understand that means anything that terminal runs.
4. **`defaults` is cached.** `cfprefsd` can return a stale value right after a GUI
   change. `killall cfprefsd` if you need certainty.

## Why this is worth the effort

"Summarize what she said this week" through layer 5 is twenty screenshots of a scrolling
Messages window, a minute of latency, and a summary of whatever happened to be visible.
Through layer 1 it is one query, exact, in milliseconds, over the complete history.

Reach for a database before you reach for a screen.
