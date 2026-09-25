---
name: jev-browse
description: "Do a narrow task on a website in the user's own Chrome in seconds, with Jev choosing each click and field instead of a model writing selectors. Use for a web task with one clear goal (find, filter, open, fill a search, navigate a web app like Clay, LinkedIn or Google Flights) when speed matters, before falling back to chrome-js or clicking by hand. Stops before any send, submit, pay, delete, sign-in, run or enrich and leaves that press to the person."
license: MIT
requires: [chewbacca]
---

# jev-browse

`jev-browse` wraps [browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast). Each step reads the page into a numbered table of controls. One TypeSafe request picks the operation (click, type, select, scroll, wait, done, blocked) and its target, all in the same round trip. Text for a field comes from the goal: put it in quotes. One quoted string is typed as written with no model call; with several, Jev picks which one goes in which field. There is no text model, no screenshots and no generated selectors.

## When

- A web task with one narrow goal, like "filter this Clay table to Series A SaaS companies in Boston" or "open the Wikipedia article on Gödel's incompleteness theorems".
- Speed matters, and the page is ordinary HTML and ARIA.

## Not when

- The page is canvas, lives in frames or shadow roots, or needs uploads or pop-up tabs. The MVP does not see those. Use `chrome-js`, or `chewie see` and `chewie click`.
- The task needs judgment across many pages. Break it into narrow goals first.
- The task is a send, post, payment, delete or submit. The floor stops the run at that button either way.

## How

```
jev-browse doctor
jev-browse run --url "https://app.clay.com/workspaces/<id>/home" \
  --goal 'Search people for "VP of Sales" in "Boston", stop when results show' --json
```

The `--json` result has a `status`:

- `done`: Jev chose DONE. That is a claim, not proof. Read the page (`chrome-js --match <host> --text`) before you say it worked.
- `yours_to_press`: the run reached a control that sends, submits, pays, deletes, signs in, runs or enriches, and left it alone. `control` names it. Tell the person where it is and ask.
- `blocked`, `timeout`, `failed`: say which, in one line. Then try `chrome-js` or read the window with `chewie see`.

Each `--goal` should be one sentence, one outcome, and name its own stopping point: "Stop when the filtered rows are visible". Every piece of text to type goes in quotes; a typing step with no quoted text stops with `failed` instead of guessing. Repeat `--goal` for an ordered list.

## The floor

The wrapper, not the goal text, refuses any click whose label reads like send, submit, post, publish, pay, buy, book, delete, archive, sign in, apply, invite, share, merge, deploy, run or enrich. A model can ignore a sentence, but it cannot get past this. `--allow-commit` lifts the floor for one run, and only after the person has said yes to that exact press.

## Setup

`jev-browse install` clones jev-ultrafast at a pinned commit into `~/.chewbacca/jev-ultrafast` and runs `uv sync`. Chrome connects over Browser Harness, so allow remote debugging when Chrome asks. It needs one key, `TYPESAFE_API_KEY`, the same one `bin/lib/jev.py` reads from the environment or the login Keychain.

Owned tabs open in the background of the Chrome profile Browser Harness attaches to. For client work, that should be the profile signed in to the client's account.

## After a run

When a site taught you something (a URL, a control's real name, a mistake), add it to `maps/<host>/MAP.md` the same way hud-agent.md asks for any website task.
