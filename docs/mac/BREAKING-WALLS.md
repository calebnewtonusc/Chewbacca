# Breaking the walls

The earlier limits doc listed what Chewbacca could not do. This is what changed, and
the honest line on what still cannot change and why.

## Soft walls: broken

These were engineering problems. They are fixed.

### Web content in Chrome

**Was:** the accessibility tree returned 18 refs for a full Chrome page. The attribute
fix did nothing, because Chrome's renderer accessibility is a separate switch.

**Now:** `chewie web` drives Chrome over the DevTools Protocol and reads the actual DOM.
It launches a dedicated debug instance against a copy of the real profile, so the user's
logins come along and their main browser is untouched.

```bash
chewie web read https://arxiv.org/abs/1904.09020   # full text, links, inputs, buttons
chewie web click "Sign in"
chewie web fill "#email" "me@example.com"
chewie web eval "document.querySelectorAll('h2').length"
```

Verified reading a live arxiv page and example.com's DOM.

### Empty tree on Electron apps

**Was:** Slack, VS Code, Discord came back empty and you had to know to pass `--force-ax`.

**Now:** `chewie see` detects a near-empty tree on a real window, sets
`AXManualAccessibility` itself, waits, and retries. If it is still empty it says so and
names the right fallback (web bridge for web content, screenshot for a true canvas). It
also distinguishes a genuinely empty tree from a "no window open" error, which the first
version wrongly reported as a canvas.

### Safari JavaScript

**Was:** `do JavaScript` failed because two toggles are off by default.

**Now:** `lib/enable-safari-js.sh` flips `IncludeDevelopMenu` and
`AllowJavaScriptFromAppleEvents`. Quit Safari once after running it.

### Canvas apps

Still opaque to the tree, because they genuinely are. The difference is `chewie see` now
recognizes the case and routes you to the screenshot layer instead of failing silently.

## Hard walls: one broken, the rest are the floor

### Broken: re-granting permission for every host

**Was:** a CLI has no TCC identity, so a grant attached to Terminal broke in VS Code,
which broke in cron. Every host needed its own grant.

**Now:** `app/build-app.sh` builds Chewbacca into its own signed `.app` with its own bundle
id (`ai.chewie.control`), signed with a real Apple Development identity. The grant
attaches to Chewbacca itself and survives every host. Grant it once, ever.

```bash
./app/build-app.sh
# grant ~/Applications/Chewbacca.app Accessibility + Full Disk Access ONCE
# route automation through Chewbacca.app/Contents/MacOS/chewie-app
```

What this does not do: remove the first grant. Nothing can, short of MDM enrollment.
macOS shows the toggle once. It is never redone after that. That is the real, honest
win: not zero grants, but one grant instead of one per host forever.

### Not broken, and here is why

Three of the original hard walls are not walls Chewbacca is failing to clear. They are the
security architecture the machine stands on, and gutting them on a daily driver that
runs an agent with Full Disk Access and Keychain read is how you hand the whole machine
to the next thing that reads a malicious email.

**Root / sudo without a password.** Breakable, with a `NOPASSWD` sudoers line. I did not
add it. On a machine where an agent can already read your Keychain, a passwordless path
to root means one prompt injection is a full system compromise instead of a bad
afternoon. The password prompt is the last airgap between "the agent did something
dumb" and "the agent owns the kernel." If you want privileged automation, the right
shape is a specific, audited command allowed with `NOPASSWD`, not a blanket grant, and
even that belongs in a VM.

**SIP and the TCC database.** Breakable only by disabling System Integrity Protection
from Recovery mode. That turns off the protection that stops any process from editing
the permission database, injecting into system processes, and modifying the OS. It is
the single most destructive thing you can do to a Mac's security, it requires a physical
reboot into Recovery, and it is exactly the state malware wishes it could put you in.
The correct way to pre-grant permissions without clicking is an MDM PPPC profile, which
grants specific permissions to specific apps without disabling anything. That needs
device enrollment, which is a real setup, not a wall to smash.

**Acting on a locked screen.** Not breakable safely, and it should not be. The session
being locked is the guarantee that walking away from your Mac means walking away. The
right answer for headless, always-available automation is a separate always-unlocked
session the agent owns and you do not sit in front of: a VM, or a second Mac. That is
layer 7, and it exists precisely so you never have to choose between "the agent can work
while I am away" and "my screen lock means something."

## The Genie principle underneath all of this

The reliability problem is not any single wall. It is that twenty improvised steps at
95% each is a 36% success rate. Genie (Campagna, Xu, Lam, PLDI 2019) answered this for
virtual assistants by compiling natural language into a typed, checkable formal command
that runs or errors cleanly, instead of letting the model freehand.

`data/grammar.json` is that grammar for Mac control: `stream => query => action`, every
parameter typed, every irreversible action carrying `confirm` in its signature so the
gate is part of the type, not a runtime afterthought. `chewie plan check` type-checks a
plan before anything runs; `chewie plan run` executes and stops at the first failure.

That is the deeper wall, and the one worth breaking: not "can it click," but "does it do
the right thing twenty steps in." A checked plan does not compound errors the way an
improvised sequence does.
