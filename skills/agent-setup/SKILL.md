---
name: agent-setup
description: "Finish the parts of this kit's install that need a browser or a permission dialog: screen and accessibility grants, provider keys, any step behind a web console, and verification. Use after setup.sh, when doctor.sh reports a tool installed but unusable, or when the user says to finish setting something up themselves."
license: MIT
requires: [chewbacca]
---

# Agent setup

`setup.sh` installs binaries. It cannot tick a checkbox in System Settings,
click through a consent screen, or fill in a web console that has no API. This
skill is how you finish those, so the user does not have to.

Work through the checks first, do only what is actually missing, and end by
running `./doctor.sh`.

## Before touching the GUI: is a person using this machine?

Driving the mouse, the keyboard, or the browser while someone is mid-task will
interrupt them and can capture what they are typing. **Check first, every time:**

```bash
peekaboo list apps --json | head -40      # what is frontmost
```

Stop and ask if the frontmost window is a login page, a password field, a
payment form, a video call, or anything you did not open. Say which window you
saw and offer to continue when they are done. Never screenshot to find out
whether it is safe: that is the capture you are trying to avoid. `peekaboo list`
gives you titles without pixels.

Prefer, in this order:

1. A CLI or an API. Always.
2. `chrome-js`, which reads and clicks through JavaScript. Deterministic, and it
   never captures the screen.
3. `peekaboo click` on a specific labeled element.
4. Screenshots, only when you must see a layout you cannot query.

## 1. Screen Recording and Accessibility

```bash
peekaboo permissions
```

Both must read Granted. If not, these are TCC grants and no CLI can set them:
they need a real click in System Settings. Open the exact panes for the user and
tell them which app to tick (the terminal or editor running you, not peekaboo):

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Say `BLOCKED: grant Screen Recording and Accessibility` and move on to the rest.
Come back and re-run `peekaboo permissions` when they say it is done.

If permissions read Granted but capture still fails, it is the Bridge, not TCC.
See [docs/MACOS-TOOLS.md](../../docs/MACOS-TOOLS.md); the kit's `peekaboo`
wrapper already forces local execution.

## 2. Provider API keys

Check what exists before asking for anything:

```bash
for k in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY; do
  [ -n "${!k:-}" ] && echo "$k set" || echo "$k missing"
done
```

Nothing here is blocked on a key:

- `summarize` runs on the local Claude CLI with `--cli claude`.
- `mac-use` falls back to the same CLI when no key is set.

Both cost more per call than a provider key and both inherit the user's
`~/.claude/CLAUDE.md`, so a preamble the instructions ask for lands in the
output. Mention that once. Do not ask for a key the user has not offered.

## 3. A step that lives behind a web console

Some tools need a credential that only a web console issues, and consoles rarely
have an API. `chrome-js` drives one through JavaScript. Read the page between
every step rather than assuming the last click landed.

```bash
chrome-js --check                         # which profiles allow JS, and the account on each
chrome-js --list                          # every tab Chrome exposes
chrome-js --open "<url>" --profile Default --match "<url-part>" --text
chrome-js --match "<url-part>" --click "Next"
chrome-js --match "<url-part>" --eval "document.title"
```

Four things that will cost you an hour each if you do not know them:

- **"Allow JavaScript from Apple Events" is per Chrome profile**, not per
  browser. A window in a profile without it fails every call with the same
  opaque error. `chrome-js --check` prints the state of each profile.
- **Chrome exposes one AppleScript-visible instance.** Windows belonging to
  other profiles or other user-data-dirs are invisible, so a tab can appear to
  vanish between two calls. Always pass `--profile`, and confirm with `--list`.
- **Open the console in the profile whose account owns the resource.** Landing
  in the wrong account gives a permissions page that reads like a broken
  project and is really a wrong-account problem.
- **Angular and Polymer ignore `el.value = x`.** Go through the native setter
  and dispatch the events, or the framework never sees the change:

  ```javascript
  var d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value");
  d.set.call(el, value);
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
  ```

  Dropdowns are usually a `mat-select` or `[role="combobox"]`: click it, wait,
  then click the `[role="option"]` you want. Chip fields commit on a synthetic
  Enter `KeyboardEvent`.

A consent screen granting access to someone's own account is theirs to approve.
Get it to the point of one click, hand them the URL, say
`BLOCKED: approve the consent screen`, and verify after they do.

## 4. Verify and report

```bash
./doctor.sh
```

Report what you finished, what is still blocked and why, and what it costs the
user to unblock it. A step you skipped is a fact they need, not a failure to
hide. Never report a tool as working because it installed; report it as working
because you ran it.
