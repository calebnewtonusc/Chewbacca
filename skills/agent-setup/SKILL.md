---
name: agent-setup
description: "Finish the parts of this kit's install that need a browser or a permission dialog: Google OAuth for gog, screen and accessibility grants, provider keys, and verification. Use after setup.sh, when doctor.sh reports a tool installed but unusable, or when the user says to finish setting something up themselves."
license: MIT
---

# Agent setup

`setup.sh` installs binaries. It cannot click a consent screen, tick a checkbox
in System Settings, or create a Google Cloud OAuth client. This skill is how you
finish those, so the user does not have to.

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

## 3. Google OAuth for gog

`gog` needs a Desktop OAuth client from a Google Cloud project. This is the
longest step and most of it is scriptable.

### The parts that are pure CLI

```bash
gcloud auth list                                   # is there a usable account
gcloud config set account <their-google-account>
gcloud projects list                               # reuse a project if one fits
gcloud projects create <id> --name="gogcli"        # or make one

gcloud services enable gmail.googleapis.com calendar-json.googleapis.com \
  drive.googleapis.com docs.googleapis.com sheets.googleapis.com \
  tasks.googleapis.com people.googleapis.com contacts.googleapis.com \
  --project <id>
```

### The parts behind the console

Use `chrome-js`. Confirm the profile first, because the account signed into
Chrome must own the project, and JS-from-Apple-Events is a **per-profile**
setting:

```bash
chrome-js --check          # which profiles allow JS, and which account each is
```

Pick the profile whose account owns the project. If it is disabled, that is one
menu click the user has to make: View > Developer > Allow JavaScript from Apple
Events, in a window of that profile.

Open the console **in that profile**, or you will land in whichever account
Chrome used last and get a permissions error that looks like a project problem:

```bash
chrome-js --open "https://console.cloud.google.com/auth/overview/create?project=<id>" \
          --profile Default --match "auth/overview" --text
```

Then walk the wizard. Read the page between every step rather than assuming it
advanced. Selectors confirmed against the Google Auth Platform wizard:

| Step                | What to do                                                                             |
| ------------------- | -------------------------------------------------------------------------------------- |
| App Information     | `input[formcontrolname="displayName"]`, then the `userSupportEmail` combobox           |
| Audience            | the radio whose wrapper text starts with `External` (`Internal` needs a Workspace org) |
| Contact Information | the emails chip field, committed with an Enter key event                               |
| Finish              | tick the policy checkbox, `Continue`, then `Create`                                    |

Angular ignores a plain `el.value = x`. Set it through the native setter and
dispatch the events:

```javascript
var d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value");
d.set.call(el, value);
el.dispatchEvent(new Event("input", { bubbles: true }));
el.dispatchEvent(new Event("change", { bubbles: true }));
```

Then create the client itself at
`https://console.cloud.google.com/auth/clients/create?project=<id>`: open the
`typeControl` combobox, pick `Desktop app`, name it, `Create`, then click
`Download JSON` in the dialog that follows. It lands in `~/Downloads`.

```bash
gog auth credentials set ~/Downloads/client_secret_*.json
gog auth add <their-account> --services gmail,calendar,drive,docs,sheets,tasks,contacts,people
```

That last command opens a consent page and waits. It is the one step where the
user clicks Allow, because it is their account being granted to. Hand them the
URL it prints, say `BLOCKED: approve the gog consent screen`, and verify after:

```bash
gog auth list && gog gmail search 'newer_than:1d' --max 1 --json
```

An External app in Testing may need the account on the test-user list first, at
`https://console.cloud.google.com/auth/audience?project=<id>`.

## 4. Verify and report

```bash
./doctor.sh
```

Report what you finished, what is still blocked and why, and what it costs the
user to unblock it. A step you skipped is a fact they need, not a failure to
hide. Never report a tool as working because it installed; report it as working
because you ran it.
