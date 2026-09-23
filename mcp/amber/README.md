# amber-mcp

Amber's contacts over MCP. It's Karthik's deliverable 3 from
[docs/AMBER-LOCAL.md](../../docs/AMBER-LOCAL.md): attach it to Claude, ChatGPT or
Perplexity, hand it a contact list, and the people land deduplicated in one
person's Amber on their own machine. The plan for the other three deliverables
is in [docs/AMBER-PLAN.md](../../docs/AMBER-PLAN.md).

## What it does

| Tool              | What it does                                                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `preview_import`  | Reads a file (CSV, TSV, vCard, JSON, PDF) or a short inline list and reports new, already known, duplicates and rejects. Writes nothing. |
| `apply_import`    | Saves exactly what one preview reported. Refuses if the store changed since.                                                             |
| `undo_import`     | Removes the people one import added and clears the fields it filled. Nothing else.                                                       |
| `search_contacts` | Name, company, title, email or notes.                                                                                                    |
| `amber_summary`   | Count, top companies, import history.                                                                                                    |

Duplicates match on email, LinkedIn, phone (last ten digits), or name plus
company with legal suffixes stripped. A name alone never matches, because two
John Smiths are two people. An import fills blank fields and never overwrites
one.

## Where the data lives

`~/.amber/users/<user>/contacts.db`. The file is mode 0600 and its directory 0700. The user is fixed when the server starts (`AMBER_USER`, default the macOS
account), and no tool takes a user argument, so one process can only ever
reach one person's contacts.

## What it will not do

- **Read files outside the import folders.** `file` must resolve inside
  `~/Downloads`, `~/Documents` or `~/Desktop` (or `AMBER_IMPORT_DIRS`), have a
  `.csv`, `.tsv`, `.vcf`, `.json` or `.pdf` extension, and sit in no hidden
  folder. The path comes from a model, and a document can steer a model into
  asking for `~/.ssh`.
- **Answer a web page.** Over HTTP, every request needs the bearer token in
  `~/.amber/users/<user>/token` (mode 0600). Host must be localhost, which stops
  DNS rebinding. A browser Origin is refused unless it is listed in
  `AMBER_ALLOWED_ORIGINS`.

## Run it

Zero dependencies. It needs Node 22.5+, plus `pdftotext` (`brew install
poppler`) for PDFs.

```sh
mcp/amber/amber-mcp                # stdio: Claude Desktop, Claude Code, Codex
mcp/amber/amber-mcp --http 7789    # HTTP on 127.0.0.1 only, for browser clients
```

Claude Desktop, in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "amber": { "command": "/path/to/Chewbacca/mcp/amber/amber-mcp" }
  }
}
```

## Limits worth knowing before the demo

- **A 10,000-row list has to come in as a file.** A model can't emit ten
  thousand contacts as tool arguments, since that is roughly 400k output
  tokens. Inline rows are for short lists the model read itself.
- **PDFs are read line by line.** A table with one contact per line reads
  correctly. A PDF laid out as cards or multi-line blocks won't, which is why
  the preview flags every PDF import to be checked before applying.
- **Browser clients** (Perplexity, ChatGPT on the web) need the HTTP transport
  plus a tunnel or a connector, and can't read a local file path. Claude Desktop
  and Claude Code work today.

## Tests

```sh
python3 tests/test_amber_mcp.py
```

The tests put 10,000 rows through preview and apply: 8,500 people, 1,500
duplicates in three different formats, and 50 rows with no way to reach anyone.
Each step takes about 0.1s. They also cover isolation between users, stale
previews, undo, vCard and PDF.

Built with Chewbacca
