---
name: mac-runtime
description: Run a multi-step task on the Mac as a formal plan that is type-checked, executed, verified, and logged - instead of improvising bash step by step. Use for any task with more than two or three steps, anything that ends in an irreversible action (send, pay, post, submit), or anything the user will want to debug afterward. This is Chewbacca's agent runtime.
---

# The Chewbacca runtime: plan, execute, verify, log

For anything longer than a couple of steps, do not freehand a sequence of commands.
Compile the request into one formal plan, check it, run it, and read the trace.

The reason is arithmetic, not style. Twenty improvised steps at 95% reliability each
is a 36% success rate (see `docs/BENCHMARKS.md`). A checked plan that stops at the
first failure and gates every irreversible action does not compound errors that way.
This is the Genie / executable-semantic-parser idea (Campagna, Xu, Lam; Liang):
compile intent into a typed, checkable representation that runs or errors cleanly,
rather than letting the model improvise.

## The grammar

`data/grammar.json` defines the command space: `stream => query* => action*`.

- **stream** - when it runs: `now`, `every`, `on_text`, `on_file`, `on_calendar`
- **query** - reads, no side effects: `texts`, `screen`, `web`, `app_data`, `file`
- **action** - side effects: `click`, `type`, `web_click`, `web_fill`, `remind`,
  `calendar`, `send_text`, `send_email`, `run_shell`

Every parameter is typed. Every irreversible action carries `confirm: true` in its
signature, so the gate is part of the type and cannot be forgotten.

## Write a plan

```json
{
  "stream": { "name": "now" },
  "query":  [{ "name": "texts", "days": 2, "unanswered": true, "direct": true }],
  "action": [{ "name": "remind", "title": "Reply to Chen about Saturday" }]
}
```

## Run it

```bash
chewie plan check plan.json     # type-check only, runs nothing
chewie plan run   plan.json     # execute; confirm-gated actions refuse without --yes
chewie plan run   plan.json --yes
```

`check` catches a missing or mistyped parameter before anything touches the machine.
`run` executes queries then actions in order, stops at the first failure, and writes
a trace.

## Read what happened

```bash
chewie log            # the last run, step by step, with timing
chewie log --runs     # recent runs
chewie log --json     # the raw trace
```

Every step is logged with its status and duration to `~/.chewie/runs/<ts>.jsonl`. When
a task half-worked, this is how you find the step that failed instead of guessing.

## When NOT to use a plan

A single read (`chewie see`, `chewie texts`, `chewie brief`) or a single obvious action does
not need the ceremony. The plan runtime earns its keep on multi-step tasks, on anything
irreversible, and on anything the user will want to audit afterward.

## The end-to-end pattern

The headline example - research leads, draft outreach, stage, confirm - is one plan:

```
now
  => web (query LinkedIn / a directory for companies under 50 employees)
  => web (extract contact emails)
  => send_text (text the user the list)                    [confirm]
  => send_email (staged drafts, one per lead)              [confirm]
```

The two outbound steps are `confirm: true`, so Chewbacca compiles and stages the whole
thing, then stops and shows the user exactly what it will send before a single email
leaves. That gate is in the grammar, not bolted on, which is why it holds even under
"just send them, I trust you."
