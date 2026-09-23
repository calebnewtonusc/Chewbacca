# Portable UX learning format, version 1

`bin/ux-learning` uses Python's standard library and runs from a fresh checkout.
It validates maps, suggests routes, and records explicitly supplied local evidence.
It never executes action text, clicks, runs a campaign, promotes a lesson, or
changes agent hooks. Run it from the repository root:

```sh
python3 bin/ux-learning validate learning/clay-navigation/package.json
python3 bin/ux-learning route learning/clay-navigation/package.json --start start-state --goal goal-state
python3 bin/ux-learning record learning/clay-navigation/package.json --receipt receipt.json --store /path/to/private/ux-store
python3 bin/ux-learning status learning/clay-navigation/package.json --store /path/to/private/ux-store
```

Use actual state IDs from the map. The launcher resolves its implementation relative
to the checkout, so it does not require a particular username or installation.
Relative package paths resolve from the caller's working directory. The store is
explicit and private; do not place receipts, screenshots, or its SQLite database
in a distributable lesson directory.

## Package

All keys below are required except `notes`. Unknown fields, duplicate JSON keys,
unsupported schema versions, duplicate IDs, and invalid endpoints are rejected.

```json
{
  "schema_version": 1,
  "package_id": "example-navigation",
  "revision": "1",
  "title": "Example navigation",
  "cost_unit": "relative_effort",
  "notes": "Costs are supplied estimates.",
  "states": [
    {"id": "start", "label": "Import dialog visible"},
    {"id": "selected", "label": "File selected"}
  ],
  "edges": [
    {
      "id": "choose-file",
      "from": "start",
      "to": "selected",
      "action": "Choose <CSV_PATH> in the native picker",
      "postcondition": "Expected filename is shown",
      "status": "documented",
      "cost": 1,
      "forbidden": false
    }
  ]
}
```

IDs and revision strings use letters, digits, dots, underscores, and hyphens,
starting with a letter or digit. Revision is an opaque label, not an ordered
number: a receipt must match it exactly. Schema version is the integer `1`.
`cost_unit` is `relative_effort` or `seconds` for the entire package. Every cost
is a finite, nonnegative number, never a boolean. Costs are supplied planning
estimates, not success probabilities or measurements certified by this tool.

`observed` records the map author's evidence-backed assertion; `documented`
means a transition has not been locally demonstrated. Neither is authenticated
by the validator. An edge can be marked `forbidden` regardless of its status.
Use placeholders for local files, customer identifiers, and account details.
Do not distribute absolute local paths or private evidence. Validation rejects
paths and URLs in IDs but is **not a privacy scrubber** of natural-language text;
review every distributed field.

## Routes

Routes follow directed edges with lowest summed estimated cost. By default only
`observed` edges qualify. `--include-documented` explicitly admits documented
edges and reports `tentative: true` when used. `--exclude-edge EDGE_ID` is
repeatable. Forbidden edges are always excluded; no override exists. Unknown
start, goal, and excluded-edge IDs are errors. A start equal to its goal returns
an empty route. Unreachable goals return `reachable: false`, not a forced path.

The search settles each state at most once, so zero-cost cycles terminate and
returned routes are simple. Routes are planning suggestions, not permission or
current-screen verification. Only IDs and estimates are returned; action text
remains data. Live operators must recheck the visible state and postconditions.

## Private receipt

```json
{
  "schema_version": 1,
  "id": "attempt-001",
  "package_id": "example-navigation",
  "revision": "1",
  "edge_id": "choose-file",
  "outcome": "success",
  "observed_at": "2026-01-01T10:30:00Z",
  "evidence_path": "evidence/screenshot.png",
  "evidence_sha256": "<64 lowercase hexadecimal characters>"
}
```

All fields are required, with no extras. `observed_at` must be valid UTC RFC3339
ending in `Z` and cannot be in the future. Outcome is `success` or `failure`.
Evidence must be a readable regular local file. Relative evidence paths resolve
against the receipt file's directory. Absolute private paths are allowed here.
Supply the SHA-256 explicitly: the recorder compares it with the bytes it reads.
It rejects a missing file or wrong digest; it cannot detect fabricated evidence
whose supplied hash matches. A hash establishes integrity, not who observed an
action or whether a screenshot proves a postcondition.

The private SQLite store retains the normalized receipt and the SHA-256 of the
**exact package bytes**, in a transaction. Identical receipt IDs are idempotent;
changing their contents or package bytes under the same package/revision/ID is
an error. Reusing an evidence hash for the same edge with conflicting outcomes
is rejected. Give revised maps a new revision. There is no automatic migration
or promotion across revisions. Unknown schema versions fail closed.

## Status and limits

Status is read-only and does not create a missing store. It counts receipts for
the exact package ID, revision, and package hash only, after rechecking local
evidence bytes. Missing or changed evidence is excluded and reported. Multiple
receipt IDs sharing an edge and evidence hash count once. Separate files with
different hashes may still represent correlated trials; this tool cannot prove
independence or prevent an author from fabricating records.

Each edge reports attempts, successes, failures, and a descriptive 95% Wilson
interval. With no attempts the interval is null. With zero successes readiness
is `not-demonstrated`; any successes yield at most `observed-success`.
`mastery` is always `not-assessed`. Intervals assume independent Bernoulli trials
and do not establish generalization across accounts, UI versions, tasks, or users.
Use independently specified holdout tasks and review before making a competence
claim. No sample-size threshold silently certifies mastery.

The store is locally trusted, not tamper-proof or independently authenticated.
New database files use owner-only permissions; existing directory permissions
remain the operator's responsibility. Deleting or archiving the private store
removes local receipt history without altering the published map. Recording
never edits a source package or exports private evidence.

Validation:

```sh
python3 -m unittest discover -s tests -p test_ux_learning.py -v
```
