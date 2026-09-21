# Reading a term out of the LMS

A syllabus PDF handed over by the student is the slow path, and it only ever
covers the courses they remembered to hand over. If the school runs Blackboard
Ultra, the whole term can be read directly: every enrolled course, every
gradebook column with its exact due timestamp, every document body, and the
syllabus file itself.

This procedure already exists. Run it rather than rebuilding it.

```
course-ingest --school acc --signin                      # once, a human signs in
course-ingest --school acc --calendar "Fall 2026"    # every time after
course-ingest --school acc --calendar "Fall 2026" --dry-run
node ~/Chewbacca/procedures/course-ingest/verify.mjs acc
```

Full doctrine, the endpoint map, and the four routes into a signed-in session
that do not work, in `~/Chewbacca/procedures/course-ingest/PROCEDURE.md`. Read
it before touching any of this.

## What the LMS cannot tell you

The gradebook only holds columns an instructor has already created. On day one
that is a fraction of the term, and it stays a fraction all semester in courses
where the instructor builds a week at a time. **Count the syllabus against the
gradebook every run.** If the syllabus says twelve discussions and Blackboard
has one, the other eleven are the work, and they go in
`~/coursework/ingest-extra.json` quoting the sentence they came from.

The LMS also cannot express more than one deadline per column. That matters
more than it sounds. A discussion whose column is dated to its Sunday close can
have an initial post due Wednesday, worth half credit after. The date on the
card is the one that is already too late.

## The four questions

Reading the files is the part that looks like the work. These are the work.

1. **What does this course allow?** Quote it into `policies.ai`, do not
   summarize a ban into "be careful". An unrecorded policy is a ban.
2. **Where is work actually submitted?** A language course can grade almost
   nothing on the LMS and mirror only the dates from the publisher's platform.
   Submitting in the wrong system costs the grade.
3. **Is the deadline on the card the real deadline?** See above.
4. **What does the syllabus have that the gradebook does not?**

## When the two sources disagree

They will. Put the LMS date on the calendar, because that is the one the LMS
enforces, and write the conflict into the course's `open_questions` so it
becomes something to ask the instructor rather than something to guess at.
Never average them, never pick the later one.

## After a run

- `coursework check` must parse every deliverable the run produced.
- Re-run the ingest. It must add zero. A second run that adds anything means
  the dedupe is broken, and a doubled calendar is worse than no calendar.
- Read back what landed. A script's success message is not evidence.
