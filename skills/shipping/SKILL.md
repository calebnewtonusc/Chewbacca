---
name: shipping
description: "Get a change safely out the door. Use when the user says ship it, is this ready, push this, deploy this, put it live, run the tests, write tests for this, or asks whether something is safe to release. Also use before any deploy to production, when a build or deploy fails, and at the end of a work session to commit and push what was done."
requires: [git]
---

# Shipping

The gate exists because the expensive failures are boring: a secret committed, a
type error nobody ran, a deploy from a dirty tree.

## Before anything else, check for secrets

This runs first because it is the only step that cannot be undone after the fact.
A key pushed to a public repo is compromised the moment it lands, and deleting
the commit does not recall it.

```sh
git diff --cached --name-only | grep -E '^\.env|\.env\.' && echo "STOP: .env staged"
git diff --cached | grep '^+' | grep -iE '(sk-ant|sk-[a-z0-9]{20}|api[_-]?key|secret|password|token)=' \
  | grep -viE 'example|placeholder|your_|process\.env\.|os\.environ' | head
```

If a real secret appears: stop, unstage it, tell the user plainly, and do not
continue. Do not offer to "be careful" with it.

## The gate

Detect the project rather than assuming. `package.json` means Node,
`pyproject.toml` or `requirements.txt` means Python, and both means run both.

Run typecheck, lint, and tests, in that order, because a type error makes lint
output noise and a lint failure makes a test run a waste of time. Use the
project's own scripts (`npm run typecheck`) before reaching for a global tool,
since a project pins its versions for a reason and a different major version
locally lets CI-only failures through.

**Report what actually happened.** If tests fail, show the output. If a step was
skipped because the script does not exist, say which. "Quality gate passed" after
a skipped test run is the single most damaging sentence available here, because
it is believed.

## Writing tests

When asked to write tests, cover the case that was actually broken, not the happy
path that already worked. A test that passes before and after the fix pins
nothing. Mirror the suite's existing harness and helpers rather than inventing a
parallel mock style in the same file, and name the test after the scenario, not
the implementation.

## Deploying

Before production: the gate passes clean, no `.env` staged, no hardcoded
localhost, no debug logging left in a hot path, environment variables set in the
host dashboard rather than only locally. Check the mobile view at 375px if there
is a UI.

After: open the URL, run the primary flow once, and read the function logs. A
deploy that returned success and a page that renders are different claims.

Many hosts deploy on push. Pushing and then running a deploy command again is how
a double deploy or a rollback race happens, so know which the project does before
doing both.

## Pushing

Commit messages explain why, in prose, like a person wrote them. No bullet-list
changelog for a three-line change, no "enhanced" or "robust".

If on the default branch and the change is not trivial, branch first. Never force
push over a branch someone else may have pulled without saying so out loud.
