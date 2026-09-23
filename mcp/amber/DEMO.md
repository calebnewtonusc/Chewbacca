# Amber contacts demo

A three-minute walkthrough for Karthik. It shows deliverable 3 working, plus
the on-device, one-person-per-store shape behind deliverables 1 and 2.

## Before the call

1. Run `mcp/amber/amber-mcp install`, then quit and reopen Claude Desktop.
2. Put a real contact export in `~/Downloads`, such as a CSV from LinkedIn,
   Google Contacts or a Clay table. Messy is better, because duplicates and
   blank rows are the point of the demo.

## The walkthrough

1. **"Add the contacts in Downloads/<file>.csv to Amber."** Claude calls the
   preview and reads out the numbers: new, already known, duplicates
   collapsed, rejected. Point out that nothing has been saved yet.
2. **"Looks right, save them."** The apply step saves exactly what the preview
   showed.
3. **"How many people do I know at <firm>?"** The answer includes the firm's
   "LLC" spelling, because firms are matched by name with legal suffixes
   stripped.
4. **"Undo that import."** Everything it added is gone, and nothing else is
   touched.
5. Show `~/.chewbacca/users/<you>/contacts.db`. It's one file on this Mac,
   readable only by you. A second person gets their own folder, and no tool
   can reach across.

## What to say plainly

- Ten thousand rows arrive as a file, not pasted into chat. A model can't
  write out that many contacts as tool input. Previewing and saving 10,000
  rows each take about 0.1s in the test.
- Perplexity and ChatGPT on the web need a hosted connector first. Claude
  Desktop and Claude Code work today.
- The redaction boundary (PAPILLON) and per-user profiles are in
  [docs/AMBER-PLAN.md](../../docs/AMBER-PLAN.md), not in this demo.

Built with Chewbacca
