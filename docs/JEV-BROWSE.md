# jev-browse

A browser task in your own Chrome, decided by Jev, in seconds. It wraps
[browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast) at a
pinned commit and adds Chewbacca's floor on top.

```
jev-browse install      # clone the pin into ~/.chewbacca/jev-ultrafast, uv sync
jev-browse doctor       # checkout, uv, keys, Chrome over Browser Harness
jev-browse run --url https://en.wikipedia.org/wiki/Main_Page \
  --goal "Open the article about Gödel's incompleteness theorems" --json
```

## What it adds to jev-ultrafast

- **The floor, in code.** Any click whose label reads like send, submit, post,
  pay, buy, book, delete, archive, sign in, apply, invite, share, merge,
  deploy, run or enrich is not executed. The run stops with `yours_to_press`
  and names the control. `--allow-commit` lifts it for one run, after a yes.
- **Keys from the Keychain.** `TYPESAFE_API_KEY` is the same entry
  `bin/lib/jev.py` reads. The text model key is `TEXT_MODEL_API_KEY`, else
  `OPENROUTER_API_KEY`. Nothing goes in argv, the goal or the log.
- **One JSON result** for agents: status, final URL and title, the actions
  taken, the Jev decision count and the elapsed time. A `done` carries a
  `verify` note, because DONE is Jev's claim and not proof.
- **A bounded run.** `--max-seconds` (default 180) on top of jev-ultrafast's
  own 60-action and 120-decision budget.

## Where it sits

The voice's assistant (`bin/hud-agent.md`, "A task on a website") reaches for
it first on a narrow goal, before `site find` and `chrome-js`. The
`jev-browse` skill says when it fits, and what to do when it does not: canvas,
frames, shadow roots, uploads and pop-up tabs are outside jev-ultrafast's MVP.

## Bumping the pin

`JEV_ULTRAFAST_PIN` in `bin/jev-browse`. Read the upstream diff first: this
drives a signed-in browser.
