---
name: setup
description: "Install Chewbacca by talking, not by answering a terminal wizard. Use when the user wants to set up this kit, run setup.sh, finish a half-finished install, or add one tool that was skipped. Also use when they ask what the installer is about to change on their machine."
license: MIT
---

# Setting up Chewbacca

`setup.sh` takes every answer as a flag. You ask the questions here, in
conversation, then run it once. The terminal is where you run commands, not
where the user fills in a form.

Never tell them to run `setup.sh` themselves and answer prompts. There are no
prompts.

## 0. Check the machine before asking anything

Assume nothing is installed. This kit is aimed at people whose Mac has Claude
on it and not much else, and macOS ships only bash, curl, and stubs at
`/usr/bin/git` and `/usr/bin/python3` that do nothing until the Command Line
Tools are installed.

```bash
./bin/bootstrap.sh --check
```

Read the result back in plain words. If anything is missing, run it for real:

```bash
./bin/bootstrap.sh
```

It installs the Command Line Tools, Homebrew, gh, node, jq, uv, and the claude
CLI. Three things it cannot do alone, and you should not pretend otherwise:

- **The Command Line Tools dialog.** A window opens with an Install button.
  Tell them to click it and say you will wait. Re-run bootstrap after.
- **The Homebrew password prompt.** Homebrew writes outside their account, so
  it asks for their login password. Say that plainly before it appears, or a
  password prompt out of nowhere reads like something has gone wrong.
- **`gh auth login`.** It opens a browser and needs their GitHub account. If
  they do not have one, that is a real fork in the road: say so, because two
  repos get created and pushed.

Do not start the questions until bootstrap says Ready. Answers collected
against a machine that then fails prerequisites are answers you have to ask
for twice.

## 1. Ask only what is needed

One question at a time, in plain language. Do not dump the whole list at once.

| Ask                      | Flag                               | If they skip it                                  |
| ------------------------ | ---------------------------------- | ------------------------------------------------ |
| First name               | `--name`                           | Required. It names their context repo.           |
| Where should repos live  | `--repo-dir`                       | `~/dev`                                          |
| GitHub username          | `--github-user`                    | Taken from whoever `gh` is logged in as          |
| Anthropic API key        | `--anthropic-key`                  | Not written. Claude Code's own login still works |
| GitHub token             | `--github-token`                   | Not written                                      |
| Todoist token            | `--todoist-token`                  | Not written                                      |
| Composio MCP URL and key | `--composio-url`, `--composio-key` | Composio not wired                               |

Say plainly that keys are optional and that each one written lands in
`~/.claude/settings.json` in plain text. Someone who does not need Composio
should not be handed a Composio question to feel bad about.

## 2. Ask the two consequential ones separately

These change how Claude behaves on the whole machine. Both default to off. Ask
each as its own question and take a plain no for an answer.

**Permission prompts.** `--bypass-permissions` stops Claude asking before it
runs a shell command or writes a file. It applies to every project, and it is
written to three separate files, so undoing it is not one edit. Ask directly:
should Claude stop asking permission before it acts? Leave it off unless they
say yes. Do not sell it.

**Session opener.** `--session-opener prayer` makes every reply begin with a
prayer. This is the author's own practice. It is off unless someone asks for
it, and it is not a default anyone inherits by installing a coding tool.

## 3. Confirm before you run anything

Show the exact command, then a plain-language summary of what changes:

- which repos get created and where
- which credentials get written, by name, or "none"
- whether Claude will ask permission afterwards
- that the editor and desktop app are configured too

`--dry-run` prints this without touching anything. Use it when they hesitate.

## 4. Run it

Either pass flags:

```bash
./setup.sh --name Jane --repo-dir ~/dev --github-user janedoe
```

or write the answers to a file, which is better when a key is involved because
the value never lands in shell history:

```bash
cat > setup.answers.json <<'JSON'
{
  "name": "Jane",
  "repo_dir": "~/dev",
  "github_user": "janedoe",
  "anthropic_key": "sk-ant-...",
  "bypass_permissions": false,
  "session_opener": "none"
}
JSON
./setup.sh --answers setup.answers.json
```

Delete the answers file afterwards if it held a key, and say that you did.

## 5. Read the output back to them

Run `./doctor.sh` and translate it. A warning is not a failure. Name what is
missing, what it costs them, and the one command that fixes it.

Re-running is safe. One section at a time:

```bash
./setup.sh --only tools     # a tool arrived after the first run, like uv
./setup.sh --only plugins   # the claude CLI was missing at the time
./setup.sh --only mcp
```

Sections: `prereq repos settings editor desktop mcp rules plugins tools plynn verify`

## 6. Hand off what a script cannot do

Screen Recording, Accessibility, and any consent screen need a real click. The
[agent-setup](../agent-setup) skill covers those. Switch to it once the
install is done rather than leaving a checklist behind.

## What to never do here

- Do not turn on `--bypass-permissions` because it makes your own job easier.
- Do not enable the session opener without being asked.
- Do not read a key out of their environment, keychain, or `gh auth token` and
  pass it in. If they did not give it to you, it does not get written.
- Do not paste a key into a chat message you then echo back.
