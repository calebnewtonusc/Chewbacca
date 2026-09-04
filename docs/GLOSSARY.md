# Glossary

Words this kit uses in a specific way. It invented some of them, which is not
an excuse for never defining them.

**Always-on standard.** A rule file imported by `CLAUDE.md`, so it is in context
before you type. Nine of them. Costs tokens on every session, which is why the
list is short and the rest load on demand.

**Task-specific rule.** A rule that loads only when the work calls for it: the
design system when a UI file is open, the deploy gate when shipping. Three of
them. `chewbacca context` shows which is which.

**Skill.** A folder with a `SKILL.md` whose `description` decides when it loads.
The model reads descriptions to route, so the description is the interface and
the body is the content. 78 installed.

**Kit.** A repo you live inside for weeks while an agent walks you through a
process you have never done and will not do again for years. Applications,
appeals, accommodations. A skill fires once; a kit holds state across sessions.
The seven-property test is in the `kit-builder` skill.

**Hook.** A script the harness runs at a fixed moment: session start, after a
write, on stop. Eight of them. They are timed and logged now: `chewbacca log`.

**Slash command.** A prompt file you invoke by typing `/name`. 57 of them, and
the kit's own argument is that you should rarely need one.

**Subagent.** A separate agent with its own context and tool set, spawned for a
bounded job. Four here: reviewer, debugger, explorer, context keeper.

**MCP server.** An external tool provider the agent can call. Twelve are
registered by default. Their tool schemas cost context whether used or not.

**Layer.** One of seven ways to control the Mac, ordered by cost. AppleScript
and a database read are cheap; a screenshot is the last resort. `mac-control`
routes between them.

**The ledger.** `~/coursework`, a machine-readable version of your syllabi.
The source of truth for dates. Nothing in the kit is allowed to guess one.

**The second brain.** Your context repo, usually `~/second-brain`. Markdown
about you: who you are, what you are working on, who you work with.

**The people store.** `~/.chewbacca/people/people.db`, SQLite. Everyone you
know, what you know about them, and when you last spoke.

**Profile.** Which install this machine got: personal, student, or developer.
Doctor uses it to avoid warning about things your profile never installed.

**Doctor.** `chewbacca doctor`. Asserts the install actually works, because
every early bug in this kit failed silently.

**Bypass mode.** `defaultMode: bypassPermissions`, so tool calls do not prompt.
The single biggest decision in the repo. See [THREAT-MODEL.md](THREAT-MODEL.md).
