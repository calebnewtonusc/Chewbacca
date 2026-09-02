---
description: Work through an assigned reading against the prompt that will grade it
allowed-tools: Read, Write, Glob, WebFetch, Bash(coursework:*)
argument-hint: "<path or URL> [course code]"
---

# Reading

Load the `study-system` skill and read `references/reading.md`.

## Step 1: find out what it is for

A graded response, a discussion, an exam chapter, or a problem set. That decides
how to read it. If there is an assignment prompt, read the prompt first: it turns
the reading into a search, which is faster and better.

## Step 2: read at the right depth

- **Textbook chapter for an exam:** structure first, then section by section,
  closing the book after each and saying what it said. Figures are content.
- **Paper:** pass 1 is title, abstract, figures, conclusion. Pass 2 is intro and
  results against the claim. Pass 3 is methods, only if the result matters
  enough to check how it was made.
- **Essay or argument for a response:** the central claim in the user's own
  words, the reasoning behind it, whether it holds, and who would disagree.

## Step 3: hand back what the assignment needs

Annotations with page numbers, so the quote does not have to be hunted later.
The four things a response usually wants: the claim, the evidence and whether it
holds, the connection to what the class has been arguing about, and the critique.

## Before drafting anything submitted

```bash
coursework policy <course> ai
```

State what the course allows before writing a word of the response. In a course
that bans AI, help them read and then stay out of the writing. In a course that
requires disclosure, draft the disclosure with them at the same time.
