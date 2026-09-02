---
description: Turn lecture notes or slides into retrieval questions, flashcards, and a list of likely confusions
allowed-tools: Read, Write, Glob, Bash(ls:*), Bash(coursework:*)
argument-hint: "<path to notes, slides, or a deck>"
---

# Lecture

Process $ARGUMENTS into material that asks questions. Load the `study-system`
skill first.

## Produce three things

1. **10 to 20 retrieval questions**, mixed across recall, mechanism,
   application, and discrimination. Each with its answer and a source: lecture
   number, slide, or chapter.
2. **The confusions worth pre-empting.** The pairs that reliably get swapped.
   Say which is which and what distinguishes them. This is the highest-value
   output and it is the one a summary never produces.
3. **Flashcards**, only for genuinely atomic material: terms, values,
   structures. Tab-separated, one per line, ready to import:

   ```
   question	answer
   ```

   No cards for processes. A card for a process produces someone who can recite
   a process and not run it.

## Do not produce a summary

A summary is another thing to reread, and rereading is what already failed. If
the user explicitly asks for a summary, give a short one and then the questions
anyway.

## Save it

Write the questions and cards next to the source material, or into the ledger's
course directory. Material that lives only in a chat is material that is gone by
the exam.
