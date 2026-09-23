---
name: jev
description: "Use Chewbacca's Jev integration for cheap typed decisions, semantic skill selection, classification, scoring, and yes/no judgments with TypeSafe. Use when routing or evaluating supplied text can replace a generative-model parsing step."
---

# Jev in Chewbacca

`chewbacca jev` is the installed integration. It uses TypeSafe's official HTTP
API with Python's standard library. The upstream `typesafe-ai` skill explains
question design; read it when installed. Current contracts live at
https://docs.typesafe.ai/llms.txt and https://docs.typesafe.ai/api.

Use Jev for narrow semantic judgments over supplied evidence. Keep prose,
code generation, complex reasoning, permissions, and execution in the agent.
Exact matching and arithmetic stay in code. The existing keyword router is
free; Jev is an optional semantic alternative, not a cost saving against it.

## Use the integration

Run `chewbacca jev status` to check credential availability without networking.
Use `TYPESAFE_API_KEY` from the process environment, or `chewbacca jev auth`
to enter a key privately into macOS Keychain. Never put a key in a prompt,
command argument, repository, example, or log. `auth --stdin` supports a secure
pipe from a secret store. Keys are read only for explicit Jev commands. The explicit CLI also accepts the
existing `TYPESAFE_API_KEY` Keychain service. Within an Amber user root, hosted
evaluation respects the shared consent setting; a stored key does not override it.

For skill selection, pipe the user's task text into `chewbacca jev route`.
It sends that text and installed skill names/descriptions to TypeSafe. It does
not send skill bodies, local paths, or the second brain. Read the suggested
skill and verify it fits before using it. `none` is a valid answer. Returned
confidence is evidence about the distribution, not correctness or permission.

For other decisions, write a JSON request and run
`chewbacca jev evaluate request.json`, or pipe JSON to `chewbacca jev evaluate -`:

```json
{
  "state": "Please sort these support tickets by their product area.",
  "questions": {
    "work": {
      "type": "choice",
      "instructions": "What output does this request ask for?",
      "criteria": {
        "classification": "Assign existing items to categories",
        "generation": "Write new prose or code",
        "other": "Neither category fits"
      }
    },
    "explicit_deadline": {
      "type": "noul",
      "instructions": "Does the request explicitly state a deadline?"
    }
  }
}
```

The default is pinned to `jev-1.13.0`; evaluate accepts an explicit `model`.
Ask independent questions together. IDs carry no meaning to the model, so put
the whole judgment in instructions. Choice takes a map, Score an ordered array
of 2–10 descriptive levels, and Noul returns probability of yes.

Every response includes actual token usage, resolved model, and latency. No
content is cached or logged. Calls have a 15-second transport timeout and a
100 KB local request/response cap; this byte cap is not a token-limit guarantee.
Service token limits still apply. Errors exit 2 without returning a decision.
There are no automatic retries or automatic actions. Handle failures explicitly
with the existing deterministic path or the agent's reasoning.

## Verify before relying on it

`chewbacca jev smoke` makes one paid call using synthetic text and all three
primitives. This proves connectivity and the basic response contract only.
Compare representative labeled cases against the current workflow before
making accuracy or savings claims. Choose thresholds from measured consequences,
not a universal 0.85. Do not turn probabilistic output into an approval gate.

Only explicitly submitted input is uploaded. Never silently sweep private notes,
messages, credentials, or background prompts into evaluation calls.

## Orchestrate and measure

Read [the orchestration playbook](../../docs/JEV-ORCHESTRATION.md) before designing
new decision points. These practices apply across user-selected models and hosts;
they do not establish that every host or integration has been tested. Preserve the
selected runtime/model and disabled lifecycle hooks. This CLI's pinned default is
separate from the shared transport's `TYPESAFE_MODEL` profile; never silently swap
one profile's limits or model for the other.

Batch only independent questions about the same supplied state. A question that
needs another answer belongs in the next step. Keep exact arithmetic, graph
constraints, permissions and deterministic matching in code. Model confidence is
not calibrated correctness, a verified outcome, or permission to act.

For each candidate workflow: declare the objective, budget and failure cost;
compare at least a deterministic baseline and a semantic alternative; record the
private reusable procedure or labeled evidence being created. Freeze the rubric,
model and dataset version before held-out evaluation. Join decisions to actually
verified outcomes, including failures and unknowns; never record intent as success.

Good: classify ambiguous controls, revalidate the observation, then verify the
postcondition independently. Bad: call a high-confidence choice a successful click,
claim savings against free code without measurement, or batch dependent decisions
and assume their answers are mutually consistent. Sanitized recipes can be shared;
private outcome data and credentials cannot. The existing preservation evidence
is in [references/preservation.json](references/preservation.json).
