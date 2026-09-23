# Evidence-bound UX policy

`bin/ux-policy` adds offline graph optimization and a small, real learning rule to
`ux-learning`. It proposes actions; it cannot click, spend credits, send messages,
activate hooks, modify a map, or promote a procedure. A caller must supply the
current permitted action set. Neither a map nor Jev output grants permission.

This is an adaptation of established algorithms, not a claim of a novel or
proprietary algorithm. Private, permissioned outcome data and tested domain
procedures may become a differentiated asset. They stay outside the public repo.
Synthetic tests establish mechanics only: real Clay transfer is unproven.

## Graph planner

```sh
bin/ux-policy plan path/to/map.json --store /private/receipts \
  --start table --goal editor --permit open-editor --min-trials 10
```

`--min-trials` is an explicit operator choice, not a claim that 10 observations
establish competence. The planner reuses `ux-learning status`: only receipts for
the exact package ID, revision and SHA-256 are counted; current evidence bytes
must match; reused evidence does not multiply observations. The receipt's supplied
success label is not independently authenticated by its file hash.

Dijkstra minimizes the sum of declared nonnegative edge costs over edges that:

- appear in the caller's permitted set;
- are observed and not forbidden;
- meet the explicit minimum sample count and have at least one success.

All other edges are excluded, even if they appear shorter or were rewarded in a
past policy. Insufficient evidence returns an inspection fallback with no route.
Permission to suggest an edge is not permission to execute it on a current screen.

For each edge, the output includes a Wilson 95% interval. With observed success
fraction p, n trials and z = 1.959963984540054, its lower limit is:

```
L = (p + z²/(2n) - z sqrt(p(1-p)/n + z²/(4n²))) / (1 + z²/n)
```

Intervals are descriptive unless independent representative trials are justified.
`--independent-retries` explicitly opts into the stronger assumption that attempts
are independent, stationary Bernoulli trials, every failure returns to the same
state, and each attempt has constant cost c. Under that model E[cost] = c/p; the
planner uses c/L as a conservative plug-in cost. The Wilson bounds are pointwise edge intervals, not simultaneous 95%
confidence bounds for all edges or a confidence guarantee for the whole path. Do not use this model for destructive, state-changing,
rate-limited, or correlated retries. The tool never performs retries.

Cost units are the map's units. A relative-effort label is not measured latency.
Tie-breaking is deterministic lexicographic edge order; no random seed is needed.

## Contextual bandit replay

Each categorical context has one sample mean per eligible action. For observed
verifier success s in {0,1}, nonnegative cost c, explicit cost scale C > 0 and
penalty weight w in [0,1], the bounded reward is:

```
r = s - w min(c/C, 1)       # -1 <= r <= 1
n <- n + 1
Q(context, action) <- Q + (r - Q)/n
```

This is an offline categorical contextual bandit: a one-step reinforcement
learning problem. It does not learn a multi-step value function, infer unseen
outcomes, generalize between contexts, or explore live systems. The planner and
bandit are separate proposals; the tool does not claim a combined optimal policy.
Recommendations greedily maximize observed mean reward among currently permitted,
observed, non-forbidden arms meeting `--min-trials`. They abstain when the best
mean reward is zero or negative: under this explicit reward definition, taking
no action has zero cost and zero reward. This is an objective-derived baseline,
not an empirically calibrated threshold. Unknown contexts abstain.
Unknown or undersampled arms are reported as unassessed, not assigned invented
success priors. Mean ranking has no uncertainty guarantee and may overfit.

Create a private JSON replay with exactly this shape (use the actual map hash):

```json
{
  "schema_version": 1,
  "binding": {
    "package_id": "demo",
    "revision": "1",
    "package_sha256": "ACTUAL_SHA256_OF_MAP_BYTES"
  },
  "reward": {"cost_weight": 0.5, "cost_scale": 10},
  "events": [{
    "id": "trial-001",
    "context": "editor-text-selected",
    "action": "replace-selected-text",
    "eligible": ["replace-selected-text", "clear-and-type"],
    "success": true,
    "cost": 2,
    "evidence_path": "trial-001-verifier.json",
    "evidence_sha256": "ACTUAL_SHA256_OF_EVIDENCE_BYTES"
  }]
}
```

The numbers illustrate the schema; they are not calibrated product settings.
Cost and scale must use the same unit, chosen before comparing policies. A trusted
verifier must generate the success label; this CLI checks supplied evidence
integrity but does not prove the label true. Context names must distinguish
material UI conditions. Evidence should capture the before state, action and
observed postcondition, with secrets and personal data minimized.

```sh
bin/ux-policy train map.json --state /private/policy.json --replay training.json
bin/ux-policy recommend map.json --state /private/policy.json \
  --context editor-text-selected --permit replace-selected-text \
  --permit clear-and-type --min-trials 10
bin/ux-policy evaluate map.json --state /private/policy.json \
  --replay holdout.json --min-trials 10
```

Train incrementally with new event IDs and new evidence. Duplicate IDs or reused
evidence are rejected, including across batches. State is private JSON written
atomically with owner-only permissions. A stable adjacent lock refuses concurrent writers explicitly; retry the rejected
training call after the other writer finishes. Verified event payloads and absolute
evidence paths persist privately. Every load rechecks evidence bytes and rebuilds
means and counts, rejecting changed or missing evidence and inconsistent state. Changed map bytes, revision, or reward settings require
an explicitly new state path; there is no silent reset or cross-version reuse.
The ledger permits basic consistency checks, not cryptographic authentication
against a person who can modify the local state.

Evaluation refuses overlap with training by event ID or evidence hash, never
updates the policy, and reports only outcomes where the recommended action equals
the logged action. This action-matched replay is **not an unbiased policy value**
when logging is selective. No propensity scores or counterfactual rewards are
fabricated. Meaningful superiority claims require a prospectively designed,
budget-matched comparison, sufficient coverage, and separately verified outcomes.
Freeze contexts, rewards and thresholds before the held-out evaluation; repeated
holdout tuning invalidates the claim of a fresh holdout.

## Verified scope

`python3 -m unittest discover -s tests -p test_ux_policy.py -v` tests that failures
change a later process's recommendation, masks remain binding, low evidence
abstains, repeated evidence cannot create trials, map changes invalidate policies,
and held-out evaluation does not train. It also tests real receipt-store evidence
revalidation. These are synthetic deterministic fixtures. They do not establish
real-world success rates, economic benefit, mastery, or fresh-session Clay transfer.
