---
name: skill-forge
description: Write a new skill, or fix one that is not being obeyed. Use when the user asks for a new skill, says a skill is being ignored or does the wrong thing, wants to turn a repeated task into something reusable, or asks to install a skill someone else wrote. Also use before writing any SKILL.md, because the authoring order matters more than the file.
---

# skill-forge

Most skills fail the same way: somebody wrote the file before they had run
the task. The file then encodes a guess, and the guess is obeyed.

## The order is the whole method

1. **Name the pain, then the problem, then the prompt.** If you cannot say
   what specifically goes wrong today, you are building for a problem nobody
   has. Stop here more often than feels comfortable.
2. **Run it by hand as a plain prompt.** Not once. Until the output is right
   and you know why it is right.
3. **Write the playbook.** Five parts, all of them: the rules, the steps, the
   standards for good output, worked examples, and the never-dos. This is
   prose, not a file format.
4. **Only now write `SKILL.md`**, from the playbook.
5. **Test it against the cases that broke in step 2.**

Skipping from 1 to 4 is the failure this skill exists to prevent.

## Rules for the file itself

**One task per skill.** The test: would you ever run this task on its own? If
no, it is a step, not a skill. Skills that do five things or chain several
events do not get obeyed. Chain narrow skills instead.

**Open with one sentence saying what this is**, above all the detail. Detail
placed above purpose outvotes the purpose.

**Length is a constraint, not a budget.** A long skill stops being followed.
Instructions belong in `SKILL.md`. Facts about a project, a person or a
corpus belong in a referenced file the skill points at.

**Write non-negotiables as prohibitions, not as tone.** "Never invent a
client name" is enforceable. "Be accurate" is not. Anything that goes out
under a real name needs its prohibitions written as hard lines.

**Include the negative examples.** What a wrong answer looks like teaches
more than another right one.

**A human-in-the-loop step is a feature.** A skill that interviews you before
producing is often better than one that one-shots. Do not optimize that away.

## When a chained step keeps returning the same answer

Give it its own turn rather than more instructions. A step folded into a
larger skill collapses toward its own first answer. Splitting it out fixes
what more prompting does not.

## The self-score gate

For anything with a quality bar, make the skill score its own output against
its own rules and refuse to deliver under a threshold. It converts standards
you wrote down into standards that get checked.

## Never install a found skill unopened

A skill from a marketplace or a repo is inspiration, not a dependency. Read
what it actually does first: it runs with your permissions, your files and
your credentials. Prefer `add-skill.sh`, which clones rather than vendors and
prints the declared license before installing, because a badge saying Apache
2.0 can sit on top of a proprietary or AGPL skill that relicenses a project by
contagion.

## Naming and versioning

Kebab-case directory matching the skill name. When a skill is versioned, put
the version at the front of the title, because names truncate from the right
and the one question worth answering at a glance is whether this is current.

## Registry drift is a test, not a paragraph

If skills are listed anywhere, generate the list from the frontmatter and add
a check that fails when it drifts. A hand-maintained index rots, and the rot
is silent.
