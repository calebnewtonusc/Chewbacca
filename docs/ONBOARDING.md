# Onboarding: what the best installers do, and where ours stands

Research and a plan, written 2026-09-23. The goal: someone who has never seen
this repo goes from a link to a working, useful agent in under a minute, and
never sees a surprise.

## What the best ones do

Five products that are known for getting this right, and the one rule each
contributes.

| Product                                                                                                                               | The rule                                                                                                                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Determinate Nix Installer](https://determinate.systems/blog/determinate-nix-installer/)                                              | Show the plan, then act, then keep a receipt. Every change is written to a JSON receipt, and one command undoes all of it. Its authors credit the clean uninstall with adoption: people install what they know they can remove.  |
| [OpenClaw](https://docs.openclaw.ai/start/wizard)                                                                                     | Detect, do not ask. Quick Start is the default and takes defaults for everything it can find. Setup ends with a live test (a real completion through the user's own provider), not a checklist. Re-running never wipes anything. |
| [Wispr Flow](https://docs.wisprflow.ai/articles/3152211871-setup-guide) and [Raycast](https://manual.raycast.com/ai/screen-awareness) | Permissions one card at a time, each explained before the system dialog appears. Each grant is detected live and reveals the next card. If granting needs a relaunch, setup resumes where it stopped.                            |
| [Ollama](https://docs.ollama.com/macos)                                                                                               | Counter-example. A system password prompt with no explanation, on first launch, is the most complained-about part of an otherwise simple install ([issue 15604](https://github.com/ollama/ollama/issues/15604)).                 |
| [rustup](https://rust-lang.github.io/rustup/installation/index.html) and [Homebrew](https://docs.brew.sh/Installation)                | One default path, one keypress. "1) Proceed (default)" is the whole decision for almost everyone, and the customisation is there for the few who want it.                                                                        |

On `curl | bash` trust, [BetterCLI](https://bettercli.org/design/distribution/self-executing-installer/)
and others land on the same split: a tiny bootstrap anyone can read in a
minute, which downloads a pinned, checksummed payload. The fear is not the
pipe. It is running thousands of lines nobody can see, from a URL that can
change between Monday and Friday.

## The rules, extracted

1. **One door.** One command in the first screen of the README, and every doc
   points at it.
2. **Plan, confirm, receipt, undo.** Say exactly what changes, change only
   that, record it, and make removal one command.
3. **Detect, do not ask.** Find the agent, the platform and the tools already
   there. Ask only what cannot be found.
4. **Fast by default, more on request.** The default install is the one that
   takes seconds. Heavier parts arrive when a request needs them.
5. **Permissions at first use, never at install.** Explain first, one at a
   time, detect the grant, deep-link to the exact settings pane.
6. **End on a real success.** The last step does something useful through the
   user's own agent, so the first thing they see working is real.
7. **No surprises.** No window, browser tab, password prompt or charge the
   user was not told about first.
8. **Idempotent.** Running it a second time repairs what is missing and
   leaves everything else, including the user's own edits, as it was.

## Where Chewbacca stands today

Tested 2026-09-23 against a fresh home directory with
`start.sh --dry-run`.

| Rule          | Today                                                                                                                                                                                                                                                                                                                                                                                | Gap                                                                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| One door      | The README opens with `bash setup.sh --runtime codex --dry-run` "from a checkout", never says how to get the checkout, and mentions `start.sh`, `setup.sh` and `install.sh`. `docs/SETUP.md` says to clone and run `install.sh`, which needs `gh`. `start.sh` documents `curl -fsSL https://chewbacca.sh`, but **that domain is not registered**, so the documented one-liner fails. | Three doors, one of them dead.                                                                                                                     |
| Plan and undo | Good. `--dry-run` prints what exists, what installs, every command and directory; `chewbacca uninstall` exists.                                                                                                                                                                                                                                                                      | The plan prints unresolved placeholders (`$CC_DIR`, `$_dest`). No receipt, so uninstall cannot know exactly what this run added.                   |
| Detect        | Good for the agent: Claude Code, Codex or both.                                                                                                                                                                                                                                                                                                                                      | The dry-run still says `claude` is "required, this is a Claude Code kit", which is the exact message that stopped a Codex user in an earlier test. |
| Fast default  | The default is the full install, "about 10 minutes". `--fast` takes seconds.                                                                                                                                                                                                                                                                                                         | The default is the slow path. It also installs Anki, Maccy, Cap and Beads, which have nothing to do with a first session.                          |
| Permissions   | The default promises to "set up Claude to read your calendar, send texts, and see your screen" during install.                                                                                                                                                                                                                                                                       | Asked at install, not at first use.                                                                                                                |
| Real success  | Ends by opening Claude and introducing itself.                                                                                                                                                                                                                                                                                                                                       | No test that the agent actually answered.                                                                                                          |
| No surprises  | Serena's dashboard is patched shut; the password prompt is announced.                                                                                                                                                                                                                                                                                                                | The HUD is ad-hoc signed, so Gatekeeper shows it as unidentified. That reads as malware to a careful person.                                       |

## The plan

### Now (this change)

- The README's first screen becomes one door: preview, then install, with the
  raw GitHub URL that works today. A second door for people who never open a
  terminal: paste one sentence into the agent they already use.
- `start.sh` stops advertising the dead domain.

### Next (small, each a day or less)

- **Flip the default to fast.** The default installs context, skills and hooks
  in seconds. The Mac tools, HUD and voice install when first asked for, with
  one line of explanation and a yes.
- **Drop unrelated apps from the default** (Anki, Maccy, Cap, Beads). Offer
  them in `--full-send` only.
- **Receipt.** `start.sh` and `setup.sh` append every path they create to
  `~/.chewbacca/receipt.json`; `chewbacca uninstall` reads it and removes
  exactly those, and nothing the user made.
- **Live first success.** The last step runs one real question through the
  detected agent ("what can you do for me today?") and prints the answer, with
  the time it took.
- **Fix the plan's placeholders** so every line of the dry-run is a real path.
- **"Required: claude"** becomes "required: an agent (Claude Code or Codex)".

### Needs a decision

- **A short domain.** `curl -fsSL chewbacca.sh | bash` is the premium version of
  the one door, and `chewbacca.sh` is unregistered. Registering it, or serving
  the script from GitHub Pages, costs money or a repo setting, so it is the
  owners' call.
- **A signed, notarized HUD.** An Apple Developer ID removes the "unidentified
  developer" warning and the Accessibility grant loss on every rebuild. It is a
  paid account.
- **A try-it-first mode.** `chewbacca try` runs the people and briefing tools
  against a built-in fictional address book before touching real contacts,
  so the first value needs no permission at all.

## How to know it worked

Time a fresh Mac (or a fresh user account) from the README to the first real
answer. The bar is under 60 seconds on the default path, zero unexplained
dialogs, and `chewbacca uninstall` leaving the home directory as it found it.
