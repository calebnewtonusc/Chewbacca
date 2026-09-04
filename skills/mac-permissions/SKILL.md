---
name: mac-permissions
description: Diagnose and fix macOS permission problems for automation - Accessibility, Screen Recording, Automation/Apple Events, Full Disk Access, TCC. Use when a Mac automation fails silently, when the user gets "not authorized" errors, when setting up Mac control for the first time, or when something worked before and stopped.
---

# macOS permissions

Almost every "my Mac automation broke" is one of five things. Work through them in
order.

## 1. Check state

```bash
chewie doctor
```

Reports each grant, names the exact app that needs it, and lists which tools are on
PATH.

## 2. You cannot grant these from code

Believe this before you spend an hour on it.

- `tccutil` **only resets**. There is no `tccutil grant`.
- The TCC database is SIP-protected. Editing it does not work.
- The only programmatic grant is an **MDM PPPC profile**, requiring an enrolled machine.

Everything else is a human clicking a toggle. Design around that instead of fighting it.

## 3. Grant it to the right app

**The app hosting the agent, not the agent, and not the CLI.** A CLI binary has no
bundle identity, so macOS attributes its requests up the responsibility chain to
whatever `.app` launched it.

Consequences that confuse people:

- The prompt says "Cursor wants to control Finder" when it was your script
- It works in Terminal and silently fails in VS Code, because grants are per host
- Two different tools launched by the same terminal share one grant

`chewie doctor` resolves the outermost `.app` and prints its name.

## 4. The buckets are separate

| Grant | Buys | Needed for |
|-------|------|-----------|
| Accessibility | Read the UI tree, post clicks and keys | Layers 3 and 4 |
| Screen Recording | Screenshots, ScreenCaptureKit | Layer 5 |
| Automation | Apple Events, **per caller-target pair** | Layer 2 |
| Full Disk Access | `~/Library`, other apps' data | Layer 1 |
| Input Monitoring | Observing input (distinct from posting) | Rarely |

Having one gives you none of the others. Automation is per *pair*: controlling Mail and
controlling Safari are two separate grants.

## 5. The prompt only appears once, ever

If the user hit Don't Allow, or the prompt appeared while the terminal was in the
background and got dismissed, **it never comes back**. The automation fails silently
forever. This is the real cause of most "it worked yesterday."

```bash
tccutil reset AppleEvents          # then trigger it again, terminal in the FOREGROUND
tccutil reset Accessibility
tccutil reset All com.example.app
```

**Warn the user before running any reset.** You are deleting grants they clicked
through by hand and they will have to redo every one.

## Error signatures

| Symptom | Meaning |
|---------|---------|
| -1743 "Not authorized to send Apple events" | Automation denied or never asked |
| -600 "Application isn't running" | Not a permission problem. Launch the app |
| -1728 "Can't get..." | Not a permission problem. Wrong object |
| -1712 timeout | Default ~2min Apple Event timeout, often a modal blocking the target |
| errOSASystemError (-1750) | Usually TCC, reported uselessly |
| Keystrokes silently do nothing | Secure Input, or App Sandbox. Not TCC |
| Empty accessibility tree | Missing grant, **or** lazy Electron tree. Check both |

## Walking a human through it

One toggle at a time. Do not list all five.

1. Open System Settings > Privacy & Security > Accessibility
2. Click +, add the app `chewie doctor` named
3. Make sure the toggle is actually ON, not just listed
4. Quit and reopen that app. **The grant does not take effect until relaunch.**
5. `chewie doctor` again

Step 4 is the one everybody skips.

## Say the scope out loud

Accessibility plus Screen Recording is functionally total control of the session: read
every pixel, click every button, type into anything. Full Disk Access adds every file.
That is worth telling the user plainly rather than burying it in an installer.

Two real mitigations: keep grants on a terminal they control rather than a
general-purpose app, and put anything long-running or internet-driven in a VM.

Full detail: `docs/PERMISSIONS.md`.
