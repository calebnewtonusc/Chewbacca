# Bounded Clay review replay

`chewbacca clay-review` is a deterministic, read-only verifier for explicit official
Clay CLI export snapshots. It does not read the browser, enrich records, contact an
API, send a campaign or authenticate source claims. It returns held candidates for
human review; it never returns send approval.

```sh
chewbacca clay-review --columns columns.json --rows rows.json --manifest review.json
```

The manifest freezes one to five source row IDs, their expected campaign and SHA-256
of each exact, independently reviewed `Briefing Summary` string, expected full name,
and the source company templates:

```json
{"schema_version":1,"sender_signature":"Alex Example\nExample Company","template_signoff":"Alex","rows":[{"row_id":"example-row","campaign":"Example","full_name":"Pat Example","brief_sha256":"<64 lowercase hex characters>","first_touch_draft":"Hi [First name],\n\nCompany description.\n\nAlex","followup_draft":"Following up on the brief."}]}
```

Obtain snapshots through the supported read-only Clay interface. Review the actual
brief before freezing its digest. Hashing whatever is currently in a row without
checking it does not prove a correct join. Column and row snapshots use the official
CLI's `data` arrays, field IDs, `cells`, `status`, `value` and optional boolean
`isStale`. Duplicate column names/IDs or row IDs are errors. Missing required cells,
unfinished actions, stale values, blocked research, wrong campaign/brief version,
failed QA, partial evidence URLs, missing complete copy, unresolved placeholders or
wrong sender signature exclude a candidate. The exact assembled first touch and
follow-up are reconstructed from the pinned templates and investor opening;
recipient or body drift is excluded. Rich raw response objects are rejected rather
than interpreted with an invented schema; the current CLI exposes action markers,
not full provider objects, so raw/extracted source truth is not authenticated. Every exported candidate stays HOLD.

The command emits input hashes, exclusion reasons and only current candidate copy.
Keep output private: it can contain client/investor information. It does not claim a
snapshot is still current in Clay or confirm citations, financial claims, legal
eligibility, verified addresses, suppressions or mailbox readiness. Obtain a fresh
snapshot for an actual handoff. Sender identity and the literal template signoff are required manifest configuration.
The five-row limit is a deliberate workflow constraint, not a learned performance threshold.

This compiles the previously manual stale-result correction into an executable
check. Regression fixtures are synthetic; a replay of an owned snapshot establishes
behavior on that snapshot, not transfer to other accounts or improved outreach.
