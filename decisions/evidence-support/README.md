# Synthetic evidence-support smoke

These five repository-authored cases use invented entities. Labels and reasons
were frozen before provider calls in `labels.jsonl`. The state sent to Jev contains
only a source excerpt and proposed claim. The labels remain separate.

This is a connectivity, response-validation and abstention demonstration. It is
not a blind real-world benchmark: the question describes the failure categories
used to design these examples. `split: heldout` exercises the reporting path; it
does not create independent sampling. The all-supported literal-overlap baseline
is deliberately simple and is **not Chewbacca's production baseline**. Beating it
would not establish superiority to an agent or actual Clay workflow.

Run from repository root, using existing credentials only:

```sh
bin/decision-lab validate --registry decisions/evidence-support/registry.json
bin/decision-lab run --registry decisions/evidence-support/registry.json --examples decisions/evidence-support/examples.jsonl --ledger /absolute/private/path/jev-evidence-smoke.jsonl --live
```

The registry binds the existing `jev-latest` setting. No setup, authentication
change or model override is required or performed. Maximum five calls, 2.5-second
transport timeout each, no retries. The wrapper may abstain on transport failure;
that is an observed result, not a reason to silently increase the budget.
The lab uses Gavin's `ask_result` to preserve supplied resolved model and validated
token counts. Missing metadata stays unknown. Actual monetary cost remains unknown
unless separately verified; token counts alone do not establish cost.

After independently checking `labels.jsonl`, join each label to the matching
ledger decision using `join_outcome` and the exact label-file digest. Record the
real verifier identity and evidence path. `bin/decision-lab report` then compares
paired outcomes. Reports must retain their synthetic-smoke scope; no promotion,
accuracy generalization, cost-saving or mastery claim is warranted.
