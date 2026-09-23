# Jev orchestration across Chewbacca runtimes

Chewbacca's shared decision code and evidence belong below the host adapter. The
user keeps their chosen model. CLI, MCP and native app integrations must expose
actual capabilities; an instruction file alone cannot make a browser execute a
local command. Existing features stay available until a replacement passes their
contracts. Disabled lifecycle hooks stay disabled.

## Choose work by capability

| Responsibility | Owner | Evidence required |
|---|---|---|
| Plan unfamiliar work, generate prose/code, resolve complex ambiguity | User-selected generative model | Accepted artifact and independent checks |
| Classify supplied evidence, rank observed alternatives, apply a semantic rubric | Optional Jev call | Versioned state/rubric, valid typed response, held-out task outcomes |
| Arithmetic, joins, identity, dependencies, permissions, budgets, output shape | Deterministic code | Exact tests and explicit constraints |
| Read or change an application | Supported host tool | Fresh observation, authorized action, observed postcondition |
| Improve future choices | Private evidence and offline policy evaluation | Failed as well as successful attempts, provenance, later reuse and transfer tests |

TypeSafe documents Choice, Noul and Score as text-input decision primitives.
Question IDs do not convey meaning; state the complete question in instructions.
Choice is relative to its candidates; include no-fit when needed. Noul estimates
a proposition, not a degree; Score is an ordinal rubric expectation, not a physical
quantity. Never infer calibration from a returned confidence field. Keep the full
distribution and resolved model. Consult the current [API](https://docs.typesafe.ai/api),
[confidence guide](https://docs.typesafe.ai/confidence) and
[model limits](https://docs.typesafe.ai/models) before relying on a service contract.

## Model the computation as a dependency graph

Put prerequisites before their consumers. Batch independent questions sharing one
state; only start dependent stages after required results are available. For shared
state token length S and question lengths q_i, separate requests repeat roughly
`n*S + sum(q_i)` input tokens; a batch uses `S + sum(q_i)`, before envelope overhead.
Questions still cost tokens. Parallel answering does not let one question see
another answer. A byte cap is not a tokenizer or proof that a request fits.

A useful UI pattern asks the operation and a target for each possible operation
in one batch, with each target question explicitly conditioned on that operation.
Code consumes only the selected operation's compatible target. Do not combine an
independent flat action and target and assume the pair is valid. The observed
control set, allowed edges and current state remain deterministic constraints.
[Source implementation](https://github.com/browser-use/jev-ultrafast/blob/1231850a0bf1a0c0341fe408ef1668dbbfdfac46/jev_ultrafast/model.py).

A different pattern is stage-by-stage selection followed by placement, with
mutually exclusive resources represented as one choice and a final structural
validator. This is preferable when a later question needs the selected set.
[json-render](https://github.com/vercel-labs/json-render). These are existing public
patterns, not exclusive inventions or benchmarks reproduced by Chewbacca.

## Optimize consequences, then measure them

For class probabilities p and an explicit action-by-outcome loss matrix L,
`risk(a) = sum_y p(y)*L(a,y)`. Include abstention. Minimize risk over eligible actions,
then apply any separate policy floor. A probability maximum need not minimize loss.
For uniform wrong loss C and abstention cost A, the boundary reduces to
`p_max >= 1-A/C`. Both rules depend on defensible losses and relevant calibration;
exact arithmetic cannot repair wrong probabilities or business assumptions.
[Cost-sensitive learning, Elkan 2001](https://cseweb.ucsd.edu/~elkan/rescale.pdf).

The decision lab supports an optional loss matrix and preserves its original
scalar policy. Use a fixed labeled baseline, freeze the rubric before evaluation,
and reserve calls before making them. Five synthetic cases test integration only.
They cannot establish domain calibration or a production improvement.

Measure accepted tasks per total cost, elapsed task time, severe-error rate,
coverage, human repair and recovery. Include parent-model orchestration tokens,
observation, requests, retries, fallbacks and unresolved assignments. Do not compare
one fast Jev call with an entire slower baseline workflow. Keep dollars, tokens,
latency and business losses separate unless an explicit conversion is justified.

## Learn without erasing the evidence

Keep source text or retrievable references when reducing context; do not silently
keep completion narration while removing its supporting tools. Context pruning must
preserve constraints and support recovery of a previously unimportant detail.
Reported failures in [fast-jev-compaction issue65](https://github.com/tamaratran/fast-jev-compaction/issues/65)
and [issue56](https://github.com/tamaratran/fast-jev-compaction/issues/56) motivate this
test; their reported incidents are not measurements of Chewbacca.

Use observed transition evidence for execution-path planning. Semantic beam search
is a search heuristic; its relevance scores are not measured transition success.
Graph limits and search budgets must remain explicit. Offline contextual-bandit
updates need verified rewards and holdouts. Model class probabilities are not the
logging policy's action-selection probabilities; never substitute them in an
importance-weighted estimator. A deterministic policy has no counterfactual support
for unchosen actions. [Swaminathan and Joachims 2015](https://proceedings.mlr.press/v37/swaminathan15.pdf).

Private advantage comes from authorized, isolated outcome data and tested procedures.
Raw customer messages, credentials and private UI contents never belong in public
recipes. Local storage does not mean cloud inference stays on device: explicit Jev
requests transmit their supplied state to the provider. Encryption at rest, retrieval,
model training, confidential inference and cross-user isolation are distinct claims.

## Preserve capabilities during refactoring

1. Inventory commands, skills, exports and installed-only additions before changing
   their shared implementation. Preserve CLI/API signatures and valid response fields.
2. Pin regression cases for current supported behavior, including retry, consent,
   private-data boundaries, environment overrides and missing-provider fallbacks.
3. Add adversarial cases that reproduce the actual defect. Record pre-existing
   failures separately; do not lower assertions just to obtain a green result.
4. Compare whole-workflow quality and cost on the same frozen tasks, five live rows
   per batch. Keep original working paths until replacements pass. A local unit suite
   is necessary evidence, not proof that every native host works.
5. Keep runtime adapters thin. Test Claude, Codex and generic exports independently.
   Native execution support must be checked in each actual host; disclose gaps.

Current tools are `jev` (explicit typed API/skill routing), `decision-lab` (bounded
experiments), `ux-decision` (advisory current-state selection), `ux-policy` (observed
route planning and offline reward updates), and `clay-review` (five-record snapshot
verification). Existing people/coursework MCP remains read-only. These tools do not
install themselves into every host, train Jev weights, execute recommended UI actions,
or establish universal software mastery. See [decision standards](DECISION-STANDARDS.md).
