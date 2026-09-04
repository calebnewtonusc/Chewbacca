# Permissions: TCC in full

TCC (Transparency, Consent, and Control) is the reason your automation does not work.
Understanding it properly saves more time than any other single thing in this repo.

## The buckets

macOS keeps these in **separate** buckets. Having one does not give you another.

| Grant | Buys you | Layer |
|-------|----------|-------|
| **Accessibility** | Read the AX tree, post synthetic events | 3, 4 |
| **Screen Recording** | Screenshots, window captures, ScreenCaptureKit | 5 |
| **Automation** | Send Apple Events to a specific app | 2 |
| **Full Disk Access** | `~/Library`, other apps' data, the TCC db itself | 1 |
| **Input Monitoring** | Observe input globally (distinct from posting it) | rarely |

Accessibility covers both reading the tree and posting events, so layers 3 and 4 come
together. Screenshots are a separate ask. Apple Events are granted **per caller-target
pair**: "Terminal wants to control Mail" is its own row, and controlling Safari needs
another.

## You cannot grant these from code

This is the single most important fact here and people burn hours before believing it.

- `tccutil` can only **reset**. `tccutil reset Accessibility com.example.app` removes a
  grant. There is no `tccutil grant`.
- The TCC database is SIP-protected. Editing it directly does not work on any supported
  macOS.
- The only programmatic path is an **MDM PPPC profile**, which requires the machine to
  be enrolled in device management. That is how enterprise tools like JumpCloud
  pre-grant Accessibility to their agents.

Everything else is a human clicking a toggle in System Settings. Plan your UX around
that instead of fighting it.

## Which app to grant

**The one hosting your agent, not the agent.** An agent running inside Claude Code in
Ghostty is, to macOS, Ghostty. Grant Ghostty. If you switch to iTerm tomorrow, iTerm
needs its own grant.

```bash
chewie doctor          # prints the exact process name to add
```

Common hosts: Terminal, Ghostty, iTerm2, Warp, Visual Studio Code, Cursor, Claude.

## Why CLI tools break

A command-line binary has no bundle identity. macOS cannot attribute a TCC request to
it, so it walks up the **responsibility chain** to whatever launched it. Consequences:

- The prompt says "Cursor wants to control Finder" when it was your CLI.
- Grants are inherited from the parent, so a tool that works in Terminal fails in
  VS Code until VS Code is granted separately.
- Two different tools launched by the same terminal share one grant, so granting one
  silently grants the other.

**Giving a CLI real identity.** From Peter Steinberger's writeup on the undocumented
parts of this:

Embed an `Info.plist` into the binary's `__TEXT/__info_plist` section:

```swift
linkerSettings: [
    .unsafeFlags([
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", "Sources/Resources/Info.plist"
    ])
]
```

With `CFBundleIdentifier` and `NSAppleEventsUsageDescription` (the string the user
sees in the prompt). Add the entitlement:

```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```

Sign with hardened runtime (`codesign --options runtime --timestamp`) for
distribution, ad-hoc during development.

To make a spawned child responsible for its own permissions instead of inheriting the
parent's chain, there is a private call:

```swift
@_silgen_name("responsibility_spawnattrs_setdisclaim")
func responsibility_spawnattrs_setdisclaim(
    _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32
```

Undocumented and private, so it can break on any macOS release. It is how tools get
their own name in the dialog rather than the terminal's.

Verify your work:

```bash
otool -s __TEXT __info_plist ./mytool        # is the plist embedded
codesign -d --entitlements - ./mytool        # are the entitlements there
tccutil reset AppleEvents com.example.mytool # reset to re-test the prompt
```

## Failure signatures

| Message | Meaning | Fix |
|---------|---------|-----|
| `-1743` "Not authorized to send Apple events" | Automation denied or never asked | Reset, run once interactively, Always Allow |
| `-1728` "Can't get ..." | Object does not exist, not a permission problem | Check the app's dictionary |
| `-600` "Application isn't running" | Target not launched | `open -a "App"` first |
| `-1712` "Apple event timed out" | Default timeout, roughly 2 minutes | Wrap in `with timeout of N seconds` |
| `errOSASystemError` (-1750) | Usually TCC, reported uselessly | Check the grant |
| Silent nothing on keystrokes | Secure Input, or App Sandbox | See [WORKAROUNDS.md](WORKAROUNDS.md) |
| Empty accessibility tree | Missing grant, or lazy Electron tree | `AXIsProcessTrusted()`, then `AXManualAccessibility` |

## Checking state

```bash
chewie doctor
agent-desktop permissions
peekaboo permissions
osascript -e 'tell application "System Events" to get name of first process'  # triggers the AX prompt
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, auth_value FROM access"   # needs Full Disk Access
```

## Resetting to test

```bash
tccutil reset Accessibility
tccutil reset ScreenCapture
tccutil reset AppleEvents
tccutil reset All com.example.app
```

**Warn the user before running any of these.** You are deleting grants they clicked
through by hand, and they will have to redo every one.

## The prompt only appears once

TCC asks once per caller-target pair, ever. If the user hits Don't Allow, or the prompt
appears while the terminal is in the background and gets dismissed, **it never appears
again**. The automation just fails silently forever. This is the actual cause of most
"it worked yesterday" reports.

The fix is `tccutil reset` for that pair, then trigger the request again with the
window in the foreground where the user can see it.

## Scope, honestly

Accessibility plus Screen Recording is, functionally, total control of the user's
session: read every pixel, click every button, type into anything. Full Disk Access
adds every file. That is the deal, and it is worth saying out loud rather than burying
in an installer.

Two mitigations that actually help: keep the grant on a terminal you control rather
than a general-purpose app, and put anything long-running or internet-driven in a VM
([07-SANDBOX.md](07-SANDBOX.md)).
