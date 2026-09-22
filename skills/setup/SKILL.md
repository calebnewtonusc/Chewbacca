---
name: setup
description: "Install or repair Chewbacca for the agent and platform the person actually uses. Use for a first install, a partial setup, selecting a runtime, or explaining what setup changes."
license: MIT
---

# Set up Chewbacca

Give the person a working first task while preserving their accounts, permissions,
existing instructions and personal choices.

## Start with the requested outcome and installed runtime

Read `docs/RUNTIMES.md`. From the checkout, inspect without changing anything:

```sh
python3 tools/agent_runtime.py plan --runtime auto
```

If they named an agent, select it explicitly. If none is detected, explain the
supported choices. Do not install Claude, require a GitHub account, or ask for API
keys merely because this kit historically used them. A desktop app may be present
without its CLI; a missing CLI is not evidence of a missing account.

For an existing supported agent, preview and install its adapter:

```sh
bash setup.sh --runtime codex --dry-run
bash setup.sh --runtime codex
```

Use `claude-code` or `both` when that matches the request. `--brain-dir PATH`
selects an existing private brain. `--name NAME` is optional and initializes only
an empty identity file. Without a name, leave identity unknown. Never infer a
person's identity from a username, home-directory path, device owner or git author.
Never replace their existing notes with starter templates.

The runtime installer creates blank private context, links skills and installs
native instructions and hooks. It does not import contacts, messages, calendar,
email or files, change permission policies, select an account, or publish a repo.
Read back its result: missing dependencies, preserved conflicts and untrusted
hooks are separate conditions. Configure only what the user requested.

## Choose additional setup only when it is useful

The full Mac bootstrap is a separate path for people who need the Mac toolkit.
Inspect `bin/bootstrap.sh --check` and preview the chosen profile first. Explain
package downloads and any OS dialogs before running a full install.

- `personal`: personal assistance without GitHub repositories.
- `student`: personal setup plus coursework tools.
- `developer`: the larger toolkit, including GitHub operations.
- `portable`: the shared configuration portions of the historical installer.

A repository creation or push requires authorization for that action; wanting a
coding assistant is not enough. Use runtime-only setup when that is sufficient.
Native Windows currently gets instruction exports; shell hooks run in WSL.
Never promise that Mac automation works on Linux or Windows.

## Learn preferences through useful work

Start with one concrete question if the goal is not known: "What would you like
help with today?" Use the answer before collecting more context. A short answer,
a pasted example, a file they select, or a skipped question are all acceptable.

Use their chosen language, name and pronouns. Adapt the amount of detail and the
format when they ask; do not infer disability, religion, profession or technical
ability. Instructions should also make sense without color or a screenshot.

Session openers are optional. Prayer, gratitude and none are supported by the
full installer; none is the default. Never impose the author's beliefs or style.
Permission bypass is a separate explicit choice, and it does not authorize
sending messages, reading unrelated private sources or publishing work.

## Connect one authorized source at a time

Read `skills/your-data/SKILL.md` and `docs/PRIVACY.md` before importing personal
sources. Ask which source is useful for the current goal unless already stated.
Existing OS permission is capability, not consent to import everything.

Describe where selected content may be sent: the active model provider, a
connected service, or a local store. Do not promise local-only processing because
a database is stored locally. Never ask someone to paste a secret into chat;
prefer the provider's supported sign-in flow.

For a blocked OS or account step, finish the authorized preparation, explain the
specific capability needed, and hand over only the host-owned consent action.
Do not change trust databases or work around a denied control surface.

## Verify the actual first task

Use a harmless task tied to the person's goal. On a blank setup, read the new
context files and verify that the host discovers the instructions and skills.
A command-line adapter test does not prove the host dispatched its hooks. Review
native hook activation and test both a refusal and an allowed operation before
claiming enforcement. Never spend model quota merely to label setup healthy.

`chewbacca agent status --runtime NAME` describes the integration. The full
`chewbacca doctor` also checks optional Mac tools; distinguish an irrelevant
optional tool from a failure of the selected runtime. Report partial installation
accurately, with one concrete next action only when the host requires the person.

`chewbacca agent remove --runtime NAME` reverses recorded adapter changes while
preserving later edits and the shared brain. `chewbacca uninstall` handles the
historical full toolkit; neither is a promise to erase every external dependency.

## Examples and failure cases

A Codex user on Linux asks for help with a repo: install the Codex adapter, leave
Mac tools and Claude untouched, and verify native discovery.

A person on a family Mac asks for reminders: leave the account owner's name out
of their identity, establish the intended reminder, and request only the relevant
app access. Do not scan Contacts to make the greeting seem personal.

An existing Claude user adds Codex: connect the same brain, preserve their opener
and permissions, and report any conflicting skill names or required hook review.
