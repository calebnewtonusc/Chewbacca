# Roadmap

[1000.md](1000.md) lists every known gap. This says which ones are next and
why, so nobody has to read a thousand lines to find out.

Ordered by how much they change for the person using it, not by effort.

## Next

**Merge instead of overwrite on install.** Setup writes `~/.claude/CLAUDE.md`.
Anyone who already has one loses it. Items 15, 836, 837.

**A `--minimal` profile.** The standards and the skills without the Mac
automation, for a work machine or someone who does not want Full Disk Access.
Items 13, 675.

**Signed installs.** A checksum and a pinned release, so `curl | bash` stops
being a leap of faith. Items 1, 2, 529.

**Trigger accuracy.** `chewbacca evals` checks structure and vocabulary. It
cannot yet tell you that a skill fired when it should not have, which is the
more expensive failure. Items 147, 148, 167.

## After that

**One store, not two.** Memory and the second brain both hold durable facts
about you, with different rules and no arbitration. Item 368.

**Redaction before content reaches a model.** Nothing currently distinguishes
data that may leave the machine from data that must not. Items 549, 550, 551.

**Portability.** The standards, skills and commands are platform-neutral and
are welded to a macOS installer. Splitting them would multiply the audience.
Items 671-680.

**A view that is not a terminal.** 1,165 people and half a million messages
are readable only by asking an agent a question. Items 271, 272, 397.

## Deliberately not doing

**A daemon.** "Nothing is left running" is the difference between this and
every alternative. Item 971 stays a moonshot.

**Windows.** Half the value is macOS automation. A port would be a different
project wearing this one's name.

**Telemetry.** No account, no server, nowhere to send it. That means growth
questions get answered by asking people, which is slower and correct.

## How to argue with this

Open an issue naming the item number. A case that some item deep in the list
matters more than these is a good issue, and the list is numbered so that
argument is cheap to make.
