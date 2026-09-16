---
name: repo-health
description: "Find what has rotted in a project. Use when the user asks to clean this up, find dead code, remove unused imports, check my dependencies, whether anything is out of date or vulnerable, what is safe to delete, or asks for an audit of a project or repo. Also use when a repo feels messy, before handing a project to someone else, or when env vars have drifted."
requires: [git]
---

# Repo health

Four kinds of rot, each with a deterministic check. Run the checks, then judge
what the output means: none of these tools is right often enough to act on
blindly.

## Dead code

```sh
npx ts-unused-exports tsconfig.json 2>/dev/null | head -20
npx depcheck 2>/dev/null
grep -rn 'TODO\|FIXME\|HACK\|XXX' --include='*.ts' --include='*.tsx' --include='*.py' . | grep -v node_modules
grep -rn 'console\.log' --include='*.ts' --include='*.tsx' . | grep -v '\.test\.\|\.spec\.\|logger\.'
```

**Confirm before deleting.** An export with no importer may be a public API, a
plugin entry point, or loaded by a string name that no static tool can see. Grep
the name across the whole tree, including config and docs, and check whether the
package's `main` or `exports` points at it. Deleting a genuine entry point breaks
consumers silently and the test suite will not notice.

A `console.log` in a hot path is a real finding. One in a CLI that is meant to
print is not. Read the line before flagging it.

## Dependencies

```sh
npm audit --audit-level=moderate 2>/dev/null || pnpm audit 2>/dev/null
npm outdated 2>/dev/null
```

Treat a vulnerability report as a claim to verify, not an instruction. Ask whether
the vulnerable path is reachable from this code at all: a prototype-pollution
advisory in a build-time dependency is not the same risk as one in a request
handler, and a blanket upgrade to clear a dashboard can break more than it fixes.

Report the count, then name the ones that are actually reachable.

## Environment variables

Compare `.env.example` against `.env`: variables the code reads and the example
never documents, and documented variables nothing reads any more. The first
breaks every new contributor on their first run. **Never print a value**, only a
name.

## Structure

Files over a few hundred lines doing several unrelated things, the same literal
in several files that should be one constant, and local reimplementations of a
helper that already exists in the repo. Grep before keeping any private copy.

## Reporting

Group by what it costs, not by what tool found it. Something that breaks a new
contributor's first run outranks a stale TODO, however many TODOs there are. Say
which findings you confirmed by reading the code and which are a tool's raw
output that still needs a human look.
