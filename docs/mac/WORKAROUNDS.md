# 18 failure modes, and what to do about them

Every one of these has cost somebody a day. Most fail silently, which is what makes
them expensive. Each entry: what you see, why, how to detect it, how to fix it.

---

### 1. Keystrokes go nowhere, no error

**Why.** Secure Input. Any app can raise `EnableSecureEventInput` to guarantee nothing
is watching the keyboard. Password fields do. 1Password does. The login window does.
While it is up, no other process can install an event tap.

It is process-global and reference-counted, so one app that raises it and forgets to
lower it starves the whole system indefinitely.

**Detect.** `ioreg -l -w 0 | grep SecureInput`, a `kCGSSessionSecureInputPID` entry
names the holder. Or `chewie doctor --secure-input`.

**Fix.** Move focus off the secure field: click a neutral area, or `open -a Finder`,
then retry. If an app is stuck holding it, focus and unfocus that app, or quit it.

---

### 2. `CGEvent.post` does nothing, inside an app

**Why.** App Sandbox silently blocks event posting. No error, no return code.

**Fix.** There is none inside the sandbox. This is why every serious macOS
computer-use tool ships notarized and outside the App Store.

---

### 3. Accessibility tree is empty, or all elements are unnamed

**Why.** Chromium builds its tree lazily and keeps it off until a client asks. Affects
Chrome, Edge, VS Code, Slack, Discord, Notion, Figma, Spotify, and every other
Electron app.

**Fix.** Set `AXManualAccessibility` to true on the **application** element, wait 200
to 500ms, re-read. `chewie see --force-ax`.

The retry delay is not optional. An immediate re-read still looks empty and people
conclude the fix does not work.

**Measured on this machine, 2026-09-04:** Slack returned `0` (success) for
`AXManualAccessibility` and `-25208` (attribute unsupported) for
`AXEnhancedUserInterface` set on the app element, so treat the latter as a fallback that
often will not take. VS Code snapshotted to 284 labeled refs.

**Chrome is the exception: 18 refs before the fix and 18 after.** The browser chrome is
accessible; the *renderer* is a separate switch the attribute does not flip
(`--force-renderer-accessibility` is the launch flag). Do not try to read a web page out
of Chrome through the AX tree. That is layer 6, attach over CDP and read the DOM.

---

### 4. Clicks land at double the offset

**Why.** Retina. Screenshots are captured at 2x device pixels; `CGEvent` takes screen
points.

**Fix.** Halve coordinates that came from a 2x screenshot, or downscale the image
before sending it. Better: use layer 3 refs and never do coordinate math.

---

### 5. Clicks land on the wrong monitor

**Why.** The global coordinate space spans all displays and origins go negative. A
monitor to the left of the primary starts at negative x.

**Fix.** `CGGetActiveDisplayList` / `CGDisplayBounds` for real geometry. Never assume
one origin at 0,0.

---

### 6. "Not authorized to send Apple events" (-1743)

**Why.** The Automation grant was denied, or the prompt appeared while the terminal was
backgrounded and got dismissed. **TCC asks once, ever.**

**Fix.** `tccutil reset AppleEvents`, bring the terminal to the front, trigger it again,
click Always Allow. Warn the user first, you are wiping grants they set by hand.

---

### 7. Permission prompt names the wrong app

**Why.** A CLI binary has no bundle identity, so macOS walks the responsibility chain
to whatever launched it. Your tool shows up as "Cursor."

**Fix.** For users: grant it to the host app; that is correct, if confusing. For tool
authors: embed an `Info.plist` with a bundle ID and `NSAppleEventsUsageDescription`,
add the apple-events entitlement, and use
`responsibility_spawnattrs_setdisclaim`. See [PERMISSIONS.md](PERMISSIONS.md).

---

### 8. It worked in Terminal, not in VS Code

**Why.** Same reason as #7. Grants attach to the host process, and each host is its own
row in TCC.

**Fix.** Grant each host separately. `chewie doctor` names the current one.

---

### 9. "Application isn't running" (-600)

**Why.** The AppleScript target is not launched. Also hits `Shortcuts Events`, which is
a separate process from the Shortcuts app.

**Fix.** `open -a "App"` first, then poll until `System Events` lists the process. Do
not just sleep a fixed amount.

---

### 10. AppleScript hangs, then times out (-1712)

**Why.** Default Apple Event timeout, roughly two minutes. A modal dialog on the target
app blocks the event until someone dismisses it.

**Fix.** `with timeout of 300 seconds ... end timeout`. And check for an unexpected
modal before assuming the script is wrong: `peekaboo dialog list`.

---

### 11. A shortcut prompts, and there is nobody to answer

**Why.** Shortcuts touching protected resources prompt on first run. A headless caller
cannot answer.

**Fix.** Pre-warm. Run each shortcut once by hand, answer Always Allow, verify it runs
clean from the terminal, and only then let an agent call it.

---

### 12. `defaults write` had no effect

**Why.** Two causes. Apps cache preferences in memory and rewrite them on quit. And
`cfprefsd` caches reads.

**Fix.** Write while the app is closed, or restart it after. `killall cfprefsd` before
reading if you need certainty.

---

### 13. `chat.db` returns rows with NULL text

**Why.** On Ventura and later, message bodies moved to `attributedBody`, a hex-encoded
NSAttributedString blob.

**Fix.** Decode the typed stream, or use a library that already does , 
[mac_messages_mcp](https://github.com/carterlasalle/mac_messages_mcp).

---

### 14. SQLite says "database is locked"

**Why.** The live app holds a write lock.

**Fix.** Open read-only (`file:...?mode=ro`) or copy the file to `/tmp` first. Never
write to a live app's database.

---

### 15. Clicking a ref hits the wrong element

**Why.** The ref is stale. It was scoped to a snapshot taken before the UI changed.

**Fix.** Re-snapshot after anything that changes the UI: a sheet opening, a
navigation, a resize, a list scroll. `see → act → see` every step.

---

### 16. `do JavaScript` fails in Safari

**Why.** Develop > Allow JavaScript from Apple Events is off by default.

**Fix.** Turn it on. Enable the Develop menu first in Safari > Settings > Advanced.

---

### 17. Playwright is logged into nothing

**Why.** A fresh browser has no profile. This is why so many web-task demos die at a
login page.

**Fix.** Attach to the user's running browser over CDP instead:
`open -a "Google Chrome" --args --remote-debugging-port=9222`, then connect. See
[06-BROWSER.md](06-BROWSER.md).

---

### 18. The screenshot contained instructions and the agent followed them

**Why.** Prompt injection. Screen content is written by other people, emails, web
pages, chat messages, PDFs. An agent holding a mouse and reading attacker-controlled
text is the most realistic serious risk in this space.

**Fix.** Architectural, not a flag. Content read off the screen is data about what a
document says, never an instruction. Anything irreversible gets a human. Anthropic's
API runs injection classifiers, but do not treat a vendor classifier as the control.

---

## Same list as JSON

[`../data/failure-modes.json`](../../mac/data/failure-modes.json) has each of these with its
detector command and fix, for agents that would rather parse than read.
