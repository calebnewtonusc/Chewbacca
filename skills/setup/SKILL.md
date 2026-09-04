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

## 1. Look before you ask

Most of what the old version of this skill asked for is sitting on the machine
already. Read it instead of asking.

```bash
ls /Applications
defaults read com.apple.dock persistent-apps 2>/dev/null | grep -o '"file-label" = [^;]*'
id -F                       # their real name, from the Mac's own account record
```

Their first name comes from `id -F`. Do not ask for it. Say which name you are
using and let them correct it.

Then read the app list against the table below and **tell them what you found**
rather than asking them to inventory their own life from memory. "I see you have
Notion and Spotify" is a better opening than "do you use a task manager".

| What is installed                                      | What it means               | Setup needed          |
| ------------------------------------------------------ | --------------------------- | --------------------- |
| Calendar, Contacts, Messages, Mail, Notes, Reminders   | Already works through `mac` | A permission click    |
| Notion                                                 | Can be connected            | They sign in, once    |
| Todoist, Linear, Slack, Gmail, Spotify, Google Drive   | Can be connected            | They sign in, once    |
| Anything else                                          | Nothing to do               | None                  |

Apple's apps are the important row. They need no account, no key, and no
signup, and they cover most of what someone actually wants. Lead with those.

## 2. Ask about their life, never about their credentials

The old version of this skill asked nine questions, six of which were API keys
by name: Anthropic, GitHub, Todoist, Composio URL, Composio key. That asks a
person to know what Composio is in order to answer, and being asked for a token
you have never heard of does not read as optional. It reads as a thing you are
failing to have.

**The rule: never say the name of a service they have not said first.**

Ask two or three open questions, in their words:

- "What do you use to keep track of what you need to do?" Not "do you use
  Todoist."
- "Where do you write things down?" Not "do you have Notion."
- "What do you want help with most?" This one decides more than any credential.

Then map their answer yourself:

| They say                          | You wire                          | You say                                        |
| --------------------------------- | --------------------------------- | ---------------------------------------------- |
| "Apple Notes", "Reminders", "the calendar" | Nothing. It already works | "That already works, I can read it right now"  |
| "Notion", "Todoist", "Linear", "Slack" | The connector for that one    | What signing in gets them, then the link       |
| "Paper", "my head", "nothing"     | Nothing                           | Offer their second brain as the answer         |
| "I don't know"                    | Nothing                           | Move on. Ask again in a week when it matters   |

Never present a service they did not name. If they say Notion, set up Notion and
say nothing about the other forty things that were possible.

## 3. Explain anything you cannot make simple

Some things genuinely cannot be made effortless. Those get an explanation before
they happen, not an apology after.

Three of them, and the phrasing matters because each one looks like a failure to
someone who was not warned:

- **A window opens asking to install developer tools.** Say: "Apple is going to
  ask to install some tools. Click Install. It is a big download so it takes a
  few minutes, and I will wait." Otherwise a stalled progress bar reads as a
  crash.
- **A password prompt appears.** Say it before it appears: "This will ask for
  your Mac password. That is Homebrew, which installs software outside your
  account, so macOS makes it ask. It is your normal login password and it does
  not go anywhere." A password box out of nowhere is the scariest moment in the
  whole install.
- **macOS asks whether Claude can see your screen and control your Mac.** Say
  what each grant actually allows and why it is needed for the thing they asked
  for. Do it one toggle at a time, in the moment, not as a checklist at the end.

If they ask what something is, answer in one sentence with no jargon, then move
on. Do not teach them what an MCP server is. They do not need to know and the
kit works either way.

## 4. Ask the two consequential ones separately

These change how Claude behaves on the whole machine. Both default to off. Ask
each as its own question and take a plain no for an answer.

**Permission prompts.** `--bypass-permissions` stops Claude asking before it
runs a shell command or writes a file. It applies to every project, and it is
written to three separate files, so undoing it is not one edit. Ask with a
concrete example rather than in the abstract: "Right now I will ask before I
send a text or change a file. Want me to stop asking?" Leave it off unless they
say yes. Do not sell it.

**Session opener.** Offer it, do not warn about it. Claude can open every reply
with a line they choose, injected on every prompt so it holds across the whole
session and every session after. Two ship with the kit: `prayer`, a prayer to
Jesus Christ specific to the work in front of them, and `gratitude`, one
concrete sentence about something worth being grateful for. Ask which, if
either, and take none for an answer.

It is off by default because it is a surprising thing to inherit from a coding
tool, not because it is an afterthought. Say it can be added any time:

```bash
./setup.sh --only settings --session-opener prayer
```

If they want their own line instead, that is one string in `OPENERS` in
setup.sh, and you can write it with them.

## 5. Confirm before you run anything

Say what changes in their words first, and put the command underneath for
anyone who wants it. Not the reverse.

- what Claude will be able to do afterwards that it cannot do now
- where their second brain lives, as a path they could open in Finder
- whether Claude will ask permission before acting
- that `chewbacca uninstall` reverses all of it

Mention a repo, a credential, or a config file only if one is actually involved.
On the personal profile none of them are, and listing them anyway invents
complexity that is not there.

`--dry-run` prints this without touching anything. Use it when they hesitate.

## 6. Run it

Most installs are one line, because the profile carries the defaults and the
name came from the Mac:

```bash
./setup.sh --profile personal --name Jane
```

Add `--profile student` if they are in school, or `--profile developer` if they
write code and have a GitHub account. Anything else they mentioned gets wired
after this run, one service at a time, as its own small step they can watch.

When a key is genuinely involved, write the answers to a file instead, so the
value never lands in shell history:

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

## 7. Read the output back to them

Run `./doctor.sh` and translate it. A warning is not a failure. Name what is
missing, what it costs them, and the one command that fixes it.

Re-running is safe. One section at a time:

```bash
./setup.sh --only tools     # a tool arrived after the first run, like uv
./setup.sh --only plugins   # the claude CLI was missing at the time
./setup.sh --only mcp
```

Sections: `prereq repos settings editor desktop mcp rules plugins tools plynn verify`

## 8. Hand off what a script cannot do

Screen Recording, Accessibility, and any consent screen need a real click. The
[agent-setup](../agent-setup) skill covers those. Switch to it once the
install is done rather than leaving a checklist behind.

## What to never do here

- Do not turn on `--bypass-permissions` because it makes your own job easier.
- Do not enable the session opener without being asked.
- Do not read a key out of their environment, keychain, or `gh auth token` and
  pass it in. If they did not give it to you, it does not get written.
- **Do not name a service they have not named.** Composio, Todoist, Notion, an
  Anthropic API key: every one of those is a question that assumes knowledge,
  and being asked for a token you have never heard of does not read as optional.
- Do not explain what a hook, an MCP server, a skill, or a subagent is unless
  they ask. The kit works either way, and the words cost them attention they
  should be spending on what it can do.
- Do not hand them a checklist at the end. Anything a script cannot do, walk
  them through in the moment, one step at a time.
- Do not paste a key into a chat message you then echo back.
