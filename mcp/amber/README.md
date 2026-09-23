# amber-mcp

Amber's contacts over MCP. Attach it to Claude, ChatGPT or Perplexity, hand it a
contact list, and the people land deduplicated in one person's Amber on their
own machine. Per-person roots come from `bin/amber-user`, and the redaction
layer for model calls is `bin/amber-redact`.

## What it does

| Tool              | What it does                                                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `preview_import`  | Reads a file (CSV, TSV, vCard, JSON, PDF) or a short inline list and reports new, already known, duplicates and rejects. Writes nothing. |
| `apply_import`    | Saves exactly what one preview reported. Refuses if the store changed since.                                                             |
| `undo_import`     | Removes the people one import added and clears the fields it filled. Nothing else.                                                       |
| `search_contacts` | Name, company, title, email or notes.                                                                                                    |
| `amber_summary`   | Count, top companies, import history.                                                                                                    |
| `hello`           | Whose Amber this is, what they have told it about themselves, and what is due today. Chat apps call it first and greet the person by name. |
| `remember`        | Saves a fact about a person, or about the user ("me"), to their own people store, so a later conversation knows it.                      |
| `recall`          | What the user told it before: everything about one person, or keywords across everyone.                                                  |

Duplicates match on email, LinkedIn, phone (last ten digits), or name plus
company with legal suffixes stripped. A name alone never matches, because two
John Smiths are two people. An import fills blank fields and never overwrites
one.

## Where the data lives

`~/.chewbacca/users/<user>/contacts.db`, and what `remember` saves goes to
`~/.chewbacca/users/<user>/people/`, the same people store `bin/people` runs. The file is mode 0600 and its directory 0700. The user is fixed when the server starts (`AMBER_USER`, default the macOS
account), and no tool takes a user argument, so one process can only ever
reach one person's contacts.

## What it will not do

- **Read files outside the import folders.** `file` must resolve inside
  `~/Downloads`, `~/Documents` or `~/Desktop` (or `AMBER_IMPORT_DIRS`), have a
  `.csv`, `.tsv`, `.vcf`, `.json` or `.pdf` extension, and sit in no hidden
  folder. The path comes from a model, and a document can steer a model into
  asking for `~/.ssh`.
- **Answer a web page.** Over HTTP, every request needs the bearer token in
  `~/.chewbacca/users/<user>/token` (mode 0600). Host must be localhost, which stops
  DNS rebinding. A browser Origin is refused unless it is listed in
  `AMBER_ALLOWED_ORIGINS`.

## Run it

Zero dependencies. It needs Node 22.5+, plus `pdftotext` (`brew install
poppler`) for PDFs.

```sh
mcp/amber/amber-mcp                # stdio: Claude Desktop, Claude Code, Codex
mcp/amber/amber-mcp --http 7789    # HTTP on 127.0.0.1 only, for browser clients
```

To add it to Claude Desktop and Claude Code in one step (each config is backed
up to `*.before-amber` first):

```sh
mcp/amber/amber-mcp install
```

A walkthrough for showing it to someone is in [DEMO.md](DEMO.md).

## Where it runs, and what gets built next

- **Claude Desktop, Claude Code:** `amber-mcp install` adds it.
- **Perplexity for Mac:** works today. Perplexity's Mac app runs local
  connectors through its PerplexityXPC helper. `install` prints the command
  to paste under Settings, Connectors, Add Connector.
- **ChatGPT:** it only talks to remote HTTPS servers, and OpenAI's Secure MCP
  Tunnel client reaches one running on your Mac. Next to build: point that
  tunnel at `amber-mcp --http`, then add the OAuth ChatGPT expects in front of
  the bearer token.
- **Ten thousand rows come in as a file path, not as rows in the chat.** One
  contact is about 40 tokens, so 10,000 is roughly 400k tokens of tool input.
  The file path gets around that entirely.
- **PDFs are read one line at a time.** Tables read correctly. Card layouts
  are next, using the model's own reading of the page. The preview flags every
  PDF import until then.

## Tests

```sh
python3 tests/test_amber_mcp.py
```

The tests put 10,000 rows through preview and apply: 8,500 people, 1,500
duplicates in three different formats, and 50 rows with no way to reach anyone.
Each step takes about 0.1s. They also cover isolation between users, stale
previews, undo, vCard and PDF.

Built with Chewbacca
