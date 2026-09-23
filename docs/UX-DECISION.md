# Fresh-observation UX decisions

`chewbacca ux-decision` connects a versioned navigation map, explicit current UI
observations and the Jev decision registry. It recommends an eligible control; the
host's supported UI tool still executes and observes the outcome. This is not an
autonomous browser driver or a replacement for task authorization.

```sh
chewbacca ux-decision learning/clay-navigation/package.json \
  --observation observation.json --goal saved --max-age-seconds 30
```

The example freshness budget is an operator choice, not a measured universal value.
Observations carry `schema_version:1`, a UTC `observed_at` ending in Z, `state_id`,
`permitted_edges`, `controls` (`id`, `role`, `name`, boolean `enabled`), and `bindings`
(`edge_id`, `control_id`). Bindings must come from current observed UI controls,
not a remembered coordinate or invented target. This interface cannot authenticate
what the caller says was visible. Optional `data_class` defaults to `nonpublic`;
use `synthetic` or `public` only for genuinely synthetic/public projections.

Only observed, non-forbidden, explicitly permitted edges from the declared current
state with an enabled bound control and a permitted route to the goal qualify. One
candidate needs no Jev call. Ambiguity without a registry causes abstention. For
semantic selection, pass `--registry registry.json`; its criteria must match the
eligible edge IDs exactly. `--live` explicitly invokes the existing Jev transport;
nonpublic transmission additionally requires `--allow-nonpublic`. Do not send raw
screens, client rows or credentials just because the transport is configured.

The deterministic shortest estimated route is the comparison baseline, not proof
of optimal real-world cost. Jev returns a typed recommendation under the registry's
loss and confidence constraints. It never expands the eligible action set. Save the
result privately, then use `--revalidate result.json` with a current observation
and freshness budget. Changed observation/package hashes, expired state or disabled
controls require a new decision. Revalidation still returns `action_authorized:false`.

Pair verified outcomes with `decision-lab`; use `ux-learning record` for graph
transition evidence. `ux-policy` learns from explicit verified replay events and
provides evidence-constrained routing and offline contextual-bandit recommendations.
Do not count model confidence as an outcome or classify an action as successful
because a click returned. Shared state/context bindings need explicit review; these
commands do not automatically translate arbitrary browser traces into skills.

Current scope: typed recommendation, freshness checks, execution-independent outcome
records, and separate offline policy evaluation. Live browser execution, multi-step
credit assignment and fresh-account transfer remain unverified. Existing lifecycle
hooks stay disabled; nothing here changes runtime/model or permissions.

API contract checked against TypeSafe's official [Choice documentation](https://docs.typesafe.ai/primitives/choice)
and [API reference](https://docs.typesafe.ai/api), 2026-09-23. Their
[citation-check example](https://docs.typesafe.ai/cookbooks/citation_check) motivates
using source excerpts rather than bare URLs for evidence-support judgments. Local
fixtures demonstrate our contract handling, not the vendor's accuracy claims.
