# Mathematical, creative, proprietary decisions

These standards apply to every process Chewbacca designs and improves. Scale the
work to the decision: a deterministic edit needs an exact check; an uncertain,
repeated or consequential workflow needs a recorded experiment. They do not enable
hooks, change the selected model, grant permissions or authorize publication.

## Mathematical: choose an appropriate algorithm

Specify the objective, constraints, baseline, budget, failure costs and observable
outcome before choosing machinery. Use algorithms where they improve a decision:

- Exact validation, identity constraints and arithmetic belong in deterministic code.
- Dependency and navigation graphs can expose prerequisites and choose feasible
  routes by observed transition reliability, recovery cost and execution budget.
  A list of edges with guessed weights is a hypothesis, not an optimized policy.
- Cost-sensitive typed Jev decisions can classify uncertain cases or select among
  observed candidates. Evaluate error costs and abstention against a simpler rule;
  confidence is not calibrated probability without evidence.
- For repeated choices with logged actions and verified rewards, evaluate an
  offline or shadow contextual bandit against the fixed policy. Track selection
  bias, exploration support, delayed rewards and drift. A bandit is a restricted
  reinforcement-learning setting, not general learning across arbitrary tasks.
  Never explore irreversible or unauthorized actions to collect a reward.

Do not force a graph, learned model or reinforcement learning onto a problem solved
reliably by a lookup. State assumptions behind optimization, account for dependent
failures, and label guessed parameters. Reserve spend before an attempt; count
failed attempts. Keep unlike cost units separate. Report the denominator, uncertainty
and all assigned outcomes, including abstentions and human interventions.

## Creative: make alternatives compete

Consider the simplest adequate method and at least one materially different method
for substantial decisions. Examples include changing column dependencies instead
of buying a stronger model, reusing verified company evidence instead of researching
it per contact, or changing the state observation instead of retrying a selector.
Choose a bounded test that could reject the favored approach. Reuse existing work
when it wins. Label an idea as existing, adaptation or unverified; novelty alone is
not an outcome. Routine actions need no alternatives ceremony.

## Proprietary: accumulate an authorized advantage

Retain lawful, private, verified assets that can improve subsequent decisions:
observed states, decisions, actions, outcomes, failure corrections, labeled examples,
source provenance and versioned procedures. Record collection and reuse rights,
retention limits and publication scope. Minimize personal data; exclude credentials.
Separate client-specific evidence from sanitized general procedures.

A public API, graph library, prompt or newly written registry is not an exclusive
advantage. The current registry/runtime supplies generic machinery. A private outcome
advantage is a hypothesis until fresh tasks demonstrate improvement attributable
to those assets. Never claim ownership of third-party material or publish client
facts as proof of sophistication.

## The operating loop

1. Retrieve the relevant procedure and its tested boundaries; inspect current state.
2. Define success, severe-error limits, baseline and budget. Select the algorithm
   and competing approach; record what observation would change the choice.
3. Execute within authorization. Jev returns narrow typed recommendations over
   observed candidates; deterministic checks reject invalid or stale outputs.
   Model labels cannot approve sending, spending, publishing or permission changes.
4. Verify postconditions independently of the recommendation. Preserve failures,
   partial execution and actual costs before retrying.
5. Compare with fixed acceptance limits. Update the owning procedure or regression
   test, then test retrieval and application in a fresh session. Promote only the
   scope supported by evidence; retain the last verified version for rollback.

Use `chewbacca decision-lab --help` and `chewbacca ux-decision --help` for the local
experiment and UI-decision interfaces. `chewbacca ux-policy --help` exposes the
graph optimizer and offline bandit; `chewbacca clay-review --help` exposes the
bounded snapshot verifier. Inspect current help and implementation
before selecting options; local records cannot authenticate external observations.
For broader learning tests, see
[learning-transfer](../skills/skill-training/references/learning-transfer.md).
These instructions and tools do not establish global runtime enforcement or mastery.

## A compact decision record

For substantial work, keep one private record containing:

- Objective, constraints, baseline, algorithm and meaningful alternative.
- Budget, consequential error costs, acceptance limits and known uncertainty.
- Evidence references, procedure/model versions, chosen action and verified outcome.
- What changed, reuse/publication rights and the next transfer or retention test.

Link existing evidence instead of duplicating it. A saved record is not a successful
learning event; successful later retrieval and changed behavior must be observed.

For model roles, batching dependencies, evidence preservation and backward-compatible
refactoring, read [Jev orchestration](JEV-ORCHESTRATION.md).
