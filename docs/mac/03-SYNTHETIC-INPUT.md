# Layer 4: Synthetic input

Making the machine believe a human pressed a key or clicked a mouse. This is the layer
that actually touches things when the layers below cannot.

## The API

`CGEventCreateMouseEvent`, `CGEventCreateKeyboardEvent`, `CGEventPost`. Events posted
to `kCGHIDEventTap` are indistinguishable from hardware input.

```bash
cliclick c:412,208          # click
cliclick dc:412,208         # double click
cliclick rc:412,208         # right click
cliclick m:412,208          # move only
cliclick t:"hello world"    # type
cliclick kd:cmd t:s ku:cmd  # cmd+s
cliclick w:500 c:100,100    # wait 500ms then click
cliclick dd:100,100 du:400,400  # drag

peekaboo click --coords 412,208
peekaboo type "hello"
peekaboo hotkey cmd+shift+4
peekaboo scroll down --amount 5
peekaboo drag --from 100,100 --to 400,400
```

## The three silent failures

Every one of these fails with no error. That is what makes them expensive.

### 1. Secure Input

macOS has a system-wide flag, `EnableSecureEventInput`, that any app can raise when it
wants to guarantee nothing is watching the keyboard. Password fields raise it. 1Password
raises it. The login window raises it. **While it is up, no other process can install
an event tap, and synthetic keystrokes do not arrive.**

It is a process-global, reference-counted flag, so a single app that raises it and
forgets to lower it starves everything else on the system indefinitely. This is the
actual cause of "my hotkeys randomly stopped working" bug reports going back a decade.

Detect it:

```bash
ioreg -l -w 0 | grep SecureInput
# any "kCGSSessionSecureInputPID" entry names the PID holding it
```

`chewie doctor --secure-input` prints the offending process name.

Fix it: move focus off the secure field. Click a neutral area, or `open -a Finder`, then
retry. If a specific app is stuck holding it, the app has to be focused and unfocused,
or quit.

### 2. App Sandbox

`CGEvent.post()` is **silently blocked inside the App Sandbox**. No error, no return
code, nothing happens. Apple does not document this clearly, and it is a recurring
source of "works in development, broken in the App Store build" reports.

Practical consequence: any Mac agent distributed through the App Store cannot use this
layer. That is why every serious computer-use tool for macOS ships outside the store,
notarized and directly downloaded.

### 3. Missing Accessibility

Without the Accessibility grant, event posting fails quietly. `AXIsProcessTrusted()`
tells you before you try:

```bash
chewie doctor
agent-desktop permissions
peekaboo permissions
```

## Coordinates: points, not pixels

`CGEvent` takes **screen points**. Screenshots come back in **device pixels**. On a
Retina display those differ by a factor of 2.

If a vision model looked at a 2x screenshot and said "click 824, 416," the real click
is at 412, 208. Getting this wrong puts every click at twice the offset from the
top-left, which looks like the model being bad at grounding when it is really your
math.

This whole class of bug disappears if you use layer 3 refs instead of coordinates.

## Multiple displays

The global coordinate space spans all displays, and origins can be negative, a
monitor to the left of the primary starts at a negative x. `CGGetActiveDisplayList` and
`CGDisplayBounds` give you the real geometry. Assuming a single origin at 0,0 is a
common cause of clicks landing on the wrong screen.

## Being a decent citizen

This layer takes the user's mouse. If they are sitting at the machine, that is rude at
best and destructive at worst.

- Park the cursor somewhere harmless after a drag.
- Do not automate while the user is actively typing.
- Prefer layer 3, which acts on background windows without stealing focus.
- For anything long-running, use a VM. See [07-SANDBOX.md](07-SANDBOX.md).

## Alternatives to typing

Typing character-by-character is slow and every character is a chance for a dropped
event. For anything longer than a few words, use the clipboard:

```bash
printf '%s' "$LONG_TEXT" | pbcopy
peekaboo paste    # sets clipboard, cmd+V, restores the previous clipboard
```

`peekaboo paste` restoring the old clipboard matters more than it sounds. Silently
eating what the user had copied is the kind of small hostility that makes people
uninstall things.

Better still, when the app supports it: set the value directly through the
accessibility tree and skip input entirely.

```bash
agent-desktop type @s8f3k2p9:e4 "hello"
peekaboo set-value --value "hello"
```

## Permission

**Accessibility**. Same grant as layer 3. Note that macOS keeps Accessibility, Input
Monitoring, and Screen Recording in separate TCC buckets, having one does not give
you the others.
