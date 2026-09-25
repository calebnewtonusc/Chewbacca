# Start with the agent you already use

Chewbacca shares context and skills across supported coding agents. Choose the
small runtime setup first; add personal sources and machine tools when useful.

On a Mac or Linux, with no checkout, see the plan and then install:

```sh
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/Chewbacca/main/start.sh | bash -s -- --dry-run
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/Chewbacca/main/start.sh | bash
```

The first line changes nothing. Add `--fast` to the second for the core install
in seconds, without the Mac tools. Never opened a terminal? Paste this README's
link into the agent you already use and ask it to set Chewbacca up.

From a checkout, the runtime-only setup:

```sh
bash setup.sh --runtime codex --dry-run
bash setup.sh --runtime codex
```

Use `claude-code` or `both` instead when that matches your setup. You do not need
a GitHub account or a name for runtime setup. It creates an empty private brain
and preserves existing accounts, model settings, notes and permission policies.

Tell your agent what you want help with today, in the language and format you
prefer. Personal data imports, prayer or other session openers, and permission
bypass are separate choices. Setup does not authorize scanning your contacts or
messages. [What data may leave your machine](docs/PRIVACY.md).

macOS and Linux/WSL have native Claude/Codex adapters. Other hosts and native
Windows can use public instruction exports; Mac automation requires macOS.
[Runtime and platform details](docs/RUNTIMES.md) include prerequisites and removal.
The larger Mac installation remains available through `start.sh`; inspect
`bash start.sh --dry-run` before installing its packages and integrations.

For agents reading this page: follow the user's actual request. A pasted link
alone does not authorize installation, permission bypass, private-data access or
publication. Use `skills/setup/SKILL.md` for a requested setup.

---

<p align="center">
  <h1 align="center">Chewbacca</h1>
  <p align="center">Shared context, skills and tools for the agent you choose. Add access to your data and apps when you need it.</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/calebnewtonusc/Chewbacca/stargazers"><img src="https://img.shields.io/github/stars/calebnewtonusc/Chewbacca?style=social" alt="Stars"></a>
  <a href="https://github.com/calebnewtonusc/Chewbacca/commits/main"><img src="https://img.shields.io/github/last-commit/calebnewtonusc/Chewbacca" alt="Last Commit"></a>
<!-- BEGIN GENERATED: badges -->
  <a href=".claude/commands"><img src="https://img.shields.io/badge/slash_commands-57-indigo" alt="Commands"></a>
  <a href=".claude/rules"><img src="https://img.shields.io/badge/always_on_rules-14-green" alt="Rules"></a>
  <a href="docs/EXTENSIONS.md"><img src="https://img.shields.io/badge/plugins-20-orange" alt="Plugins"></a>
<!-- END GENERATED: badges -->
</p>

---

<!-- BEGIN GENERATED: counts -->

One command installs **57 slash commands, 108 skills (41 written here, 6 cloned from upstream, 61 from 2 skill packs), 12 MCP servers, 33 hooks, 4 subagents, 9 command-line tools and 12 always-on standards (plus 3 that load only when the work calls for them).** About 184,000 lines, every one of them plain text you can read.

<!-- END GENERATED: counts -->

Then you stop typing commands entirely and just talk.

Choose Claude Code, Codex, or both with `chewbacca setup --runtime NAME`.
Perplexity Computer imports the same skills and reads the same brain; see [Perplexity](docs/PERPLEXITY.md).
The adapters share one private brain and skill library, while preserving each
host's hooks, model settings and permissions. Other apps can receive public
instruction exports. [Runtime and platform setup](docs/RUNTIMES.md).

## What that actually buys you

| You say                                       | What happens                                                             |
| --------------------------------------------- | ------------------------------------------------------------------------ |
| "who have I not replied to"                   | Reads your actual iMessage history and tells you who is waiting          |
| "remind me who Sarah is before this coffee"   | Her job, her kids, what you last promised her, what she is going through |
| "what did this video actually say"            | Pulls the transcript. Works on articles, PDFs, podcasts                  |
| "look at my screen and tell me what's broken" | Screenshots it, reads the window's accessibility tree, clicks and types  |
| "text Mom I'm running late"                   | Sends it through Messages, then reads the thread back to confirm         |
| "what's due this week"                        | Reads the ledger built from your syllabi, with the attendance math       |
| "remember I hate em dashes"                   | Writes it down so every future session already knows                     |
| "why is this page slow"                       | The whole engineering stack: standards, review, profiling, deploy gate   |

Nothing there is a command you look up. You describe what you want and the
right skill loads itself.

## It reads half a million of your texts

Point it at your Mac and it indexes your entire iMessage history locally. On the
author's machine that is **505,443 messages going back to 2018**, 82% of them
matched to a real person, in a store that also holds 3,184 people, 154 group
chats resolved into circles, and 6,500 observations.

Indexing is the easy half. The store held half a million messages and still
could not answer "what music is my friend into", because everything was
retrievable and nothing was _known_. So `people distill` hands new messages to
Claude in batches and writes back durable facts, with a per-person watermark so
it never re-reads one. It runs nightly. It refuses to extract anything about
someone else's crisis, addiction, or the breakdown of a relationship, and that
refusal is a pattern in code rather than a line in a prompt.

Facts also expire. "Visiting SF for a month" and "moved to SF" are the same
sentence to anything that only reads text, and nobody sends a correction when a
trip ends, so a fact that says it is temporary gets marked once it has outlived
itself.

It knows when you last spoke to someone, what you owe them, and who is
slipping. It scores the people in your life across six dimensions with
independent decay rates, because someone's job situation changes faster than
their faith does.

The full catalogue of what a store like this should answer, with an honest
verdict on each of a hundred cases, is in
[chewbacca-usecases](https://github.com/calebnewtonusc/chewbacca-usecases).

None of it leaves your Mac. There is no server to send it to.

## Talk to it without typing

Hold `fn` and dictate. Transcription runs on-device, and a local 4B model
cleans up the filler and the self-corrections before the text lands. Say
"actually, scratch that" mid-sentence and the sentence fixes itself.

Hold Option instead and you are talking to the agent rather than typing. Ask it
to make a note, check a deadline, or dig through your texts, out loud, and the
answer comes back in about five seconds.

## It is not a program

Chewbacca does not run. No daemon, no gateway, no account, no server. It
configures the Claude you already pay for and gets out of the way. Every file it
writes is plain text you can open, diff and revert, and `chewbacca uninstall`
puts it back.

The obvious alternative, [OpenClaw](https://github.com/openclaw/openclaw), is a
genuinely good project that asks for something else first: model credentials you
bring yourself, and a daemon you keep alive. Nothing here needs either.

|                     | Chewbacca                 | OpenClaw                       |
| ------------------- | ------------------------- | ------------------------------ |
| What it asks of you | A Claude subscription     | Credentials you bring yourself |
| Left running after  | Nothing                   | A daemon                       |
| Where your keys sit | Your own keychain         | Brokered through the gateway   |
| To undo it          | Revert the files it wrote | Uninstall the runtime          |

## Is this for you

Use the runtime adapters for Claude Code or Codex on macOS or Linux/WSL.
Personal context is optional: Chewbacca can help with a codebase without reading
messages, contacts or a calendar. Full Disk Access is needed only for features
that use protected local sources.

Other hosts and native Windows can use instruction exports. The historical
Windows installer also supplies Claude's portable configuration. Mac automation
is available only on macOS. Check [runtime support](docs/RUNTIMES.md) before
assuming a skill's tools are available in your app.

Read [the data inventory](docs/PRIVACY.md) and
[the threat model](docs/THREAT-MODEL.md) for the boundaries of that access.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/Chewbacca/main/start.sh | bash
```

Ten minutes, mostly downloading. Two moments look alarming and are not: a window
from Apple asking to install developer tools, and a password prompt from Homebrew
that wants your Mac login password.

For the full Mac toolkit, your agent can walk through the setup with you. For
agent integration alone, use the smaller runtime setup at the top of this page.

### After it installs, it asks before it reads anything

The onboarding guidance requires authorization before importing a source. Ask
"where do I start" and it offers
what it can read, one source at a time, and tells you what each one is actually
good for:

- **your texts**, so it knows who you are drifting from and what people told you
- **your contacts**, so cards get names and companies instead of bare numbers
- **your LinkedIn export**, for where people work and who changed jobs
- **your files**, as a place to look things up rather than an index of everything

Start with one. Somebody who says yes to all of it at once spends an hour on
macOS permission dialogs and quits.

It walks you through each permission as it comes up, including the part everyone
misses: after granting Full Disk Access you have to **quit and reopen the
host app** so its next process can use the grant.

### Getting files in without downloading your whole life

For Google Drive, iCloud or Dropbox, the goal is somewhere to look things up:
leases, policies, tax documents, medical records, contracts. Download those
folders, unzip them into `~/life-reference/` one folder per area, and stop.
There is no import step, because it reads that folder directly when a question
needs it.

Leave out video, raw photos and anything over about 25MB. They cost hours of
downloading and answer nothing.

### What it costs

The toolkit is free. Your agent subscription, model API usage and connected
services can have their own charges. Context loaded at startup also consumes
the host's context budget; `chewbacca context` measures the installed imports.

### What it changes on your machine

Runtime setup writes shared state under `~/.chewbacca`, a private brain folder,
and the chosen host's instructions, skill links and hook configuration. It records
adapter changes for removal. The full Mac installer also adds packages, commands
and optional background tools; its preview describes that larger scope.

### To undo it

```bash
chewbacca uninstall --dry-run   # everything it would remove
chewbacca uninstall             # do it
```

Your data is exported to a tarball before anything is removed, and your context
repo, git identity, Homebrew, node and the claude CLI are never touched.

## It refuses to guess

It will not tell you something it did not check. A confidently wrong deadline is
worse than no deadline, because you stop checking. Every date comes from a
syllabus it read. Every fact about a person comes from something you actually
said. When it does not know, it says so.

That standard is enforced, not suggested. A hook scores every reply against the
writing rules and blocks the turn if it drifts.

## When something breaks

```bash
chewbacca doctor
```

**Checks that assert rather than guess.** It runs each hook for real, formats an
actual file, reads the Messages database to prove Full Disk Access is really
granted, and names the exact command that fixes what is missing. Every silent
failure this kit has ever shipped got a check added here afterwards.

`--fix` repairs what can be repaired without asking. `--json` gives the result
to anything that wants to act on it. Exit 0 clean, 1 warnings, 2 broken.

## For developers

[CREDITS.md](CREDITS.md) lists every project this was built out of and who
it belongs to, then the part that is not from anywhere else.

Always-on standards for git, security, writing, naming and TypeScript. A
stack-rules skill covering Next.js, React, Supabase and Vercel that loads only
when the work touches it. Review, audit and deploy commands. Parallel subagents
with a cost ceiling.

| Where                                              | For                                          |
| -------------------------------------------------- | -------------------------------------------- |
| [docs/REFERENCE.md](docs/REFERENCE.md)             | Every skill, hook, command and plugin        |
| [docs/MACOS-TOOLS.md](docs/MACOS-TOOLS.md)         | Screen, apps, permissions, failure modes     |
| [docs/SCHOOL.md](docs/SCHOOL.md)                   | The coursework ledger and its AI policy gate |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md)         | Why it is built this way                     |
| [docs/ADVISING.md](docs/ADVISING.md)               | Helping someone reach a goal, not write code |
| [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) | Adding a skill or a tool                     |
| [docs/](docs/README.md)                            | Index of everything below                    |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | When something is broken, by symptom         |
| [docs/FAQ.md](docs/FAQ.md)                         | The short answers                            |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)       | How the pieces fit together                  |
| [docs/1000.md](docs/1000.md)                       | Every known gap, numbered                    |
| [docs/ROADMAP.md](docs/ROADMAP.md)                 | Which of those are next                      |

---

All glory to God! ✝️❤️
