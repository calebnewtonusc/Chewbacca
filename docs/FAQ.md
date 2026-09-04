# FAQ

**What is it, in one sentence?**
A configuration for Claude Code that gives it your context, your Mac, and a set
of standards, so you stop explaining yourself every session.

**Does it run something on my machine?**
No daemon, no server, no account. It writes files into `~/.claude` and installs
some command-line tools. `chewbacca uninstall` puts it back.

**What does it cost?**
Nothing beyond the Claude subscription you already have. It does spend context:
`chewbacca context` prints exactly how much loads before you type a word.

**Is my data sent anywhere?**
To Anthropic, as part of the conversation, the same as any Claude Code session.
Nowhere else, unless you registered an MCP server that does. Full inventory in
[PRIVACY.md](PRIVACY.md).

**Why does the README tell an AI to curl-pipe-bash?**
Because most people who open it are pasting the link at Claude. It is a real
security trade and [THREAT-MODEL.md](THREAT-MODEL.md) says so plainly, along
with the clone-and-read alternative.

**Do I have to learn 57 slash commands?**
No. That is the point. You describe what you want and the right skill loads.
The commands exist for when you want to be explicit.

**Does it work on Linux or Windows?**
No. Half of it is macOS automation. The standards and skills would port; the
installer would not. Tracked as items 671-675 in [1000.md](1000.md).

**Will it delete my stuff?**
Permissions default to bypass mode, so tool calls do not prompt. 57 destructive
patterns stay blocked regardless. `chewbacca setup --no-bypass` restores
prompting if that trade is wrong for your machine.

**What if I already have a CLAUDE.md?**
Setup writes to `~/.claude/CLAUDE.md`. Back yours up first. Merging is not
automatic yet, and it should be.

**Can I use only part of it?**
`chewbacca setup --only <section>` installs one piece. A real `--minimal`
profile does not exist yet.

**How do I know it worked?**
`chewbacca doctor`. If it says everything works and it still does not feel
like it, that is a bug in the checks, and worth reporting.

**Who is it for?**
Someone with a Mac and a Claude subscription who wants the assistant to know
their life. The install still needs a terminal, which is the gap between that
ambition and today.

**Is it maintained?**
Check the commit log and [CHANGELOG.md](../CHANGELOG.md). It is one person's
kit, used daily by that person.
