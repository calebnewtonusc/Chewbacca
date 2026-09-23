# Reading a term out of the LMS

A syllabus PDF handed over by the student is the slow path, and it only ever
covers the courses they remembered to hand over. If the school runs Blackboard
Ultra, the whole term can be read directly: every enrolled course, every
gradebook column with its exact due timestamp, every document body, and the
syllabus file itself.

This procedure already exists. Run it rather than rebuilding it.

```
course-ingest --school acc --signin                      # once, a human signs in
course-ingest --school example --calendar "Fall 2026"    # every time after
course-ingest --school example --calendar "Fall 2026" --dry-run
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

---

# D2L Brightspace (Valence)

Blackboard Ultra above is one school's LMS. USC runs **D2L Brightspace**, and
the route in is different enough to be worth writing down. The API is called
Valence. `https://brightspace.usc.edu/d2l/api/versions/` answers without auth;
everything past that needs a session.

The official OAuth route needs an App ID and Key that only the school's D2L
admin issues, so the working route is **the student's own browser cookies**:
`d2lSessionVal` and `d2lSecureSessionVal`, both v10-encrypted, in the Chrome
profile they actually sign in with. Decrypt with PBKDF2-SHA1 over the Chrome
Safe Storage password, then AES-128-CBC with a 16-space IV. They expire, so
re-decrypt every run rather than caching the string.

Use `cryptography`, which is already on the machine. `pycryptodome` will not
install under PEP 668 without `--break-system-packages`, and breaking the system
Python to read a due date is not a trade worth making.

**Do not drive the browser to do this.** Chrome does not expose page content to
the accessibility tree, AppleScript addresses the wrong Chrome instance when
several are running, and the devtools relay shows `about:blank`. An hour went
into learning that on 2026-09-21. Go to the cookies and the API first.

## The endpoints that matter

```
/lp/1.63/enrollments/myenrollments/?orgUnitTypeId=3   every course + org unit id
/le/1.99/{ou}/content/root/                           modules and topic ids
/le/1.99/{ou}/content/topics/{id}                     one topic, incl. its file Url
/le/1.99/{ou}/dropbox/folders/                        assignments, names + due dates
/le/1.99/{ou}/dropbox/folders/{id}/submissions/       SEE BELOW
/le/1.99/{ou}/quizzes/                                quizzes with dates and attempt rules
```

A topic's `Url` is a path under `/content/enforced/{ou}-{section}/`, fetched with
the same cookie header. That is how an assignment prompt PDF comes down the
moment the instructor posts it, which is often mid-class and days before the
student opens it.

Quiz *questions* are instructor-only: `/quizzes/{id}/questions/` returns 403
`Quizzing.ManageQuizzes`. Reading a quiz means opening the attempt in a browser,
and **that consumes an attempt**. Do not.

## Submission status is checkable. Check it.

`/dropbox/folders/{id}/submissions/` works with a student token and returns that
student's own row: submission id, exact `SubmissionDate`, the filename, and the
byte size. An empty array means nothing was ever submitted.

This is the single most useful thing on this list, because "did you turn that
in?" is a question the ledger cannot answer and the student answers from memory.
On 2026-09-21 a `status: todo` essay turned out to have been filed three minutes
before its deadline, and the ancillary self-assessment sitting on the same line
of the syllabus had never been submitted at all. Asking would have surfaced the
first and hidden the second, because he would have thought of the essay.

So: before reporting anything as overdue, and before asking whether something
went in, **read the dropbox**. Write the submission id and timestamp into the
deliverable's `notes` so the claim is checkable later. This is the durable fix
for a ledger drifting out of sync with reality, and it is what
`feedback_two_day_rule` and `feedback_answer_it_before_asking_it` both point at.

**Verifying a submission is not permission to make one.** Reading the dropbox
tells you where things stand; the student submits. The `submit-guard` hook
exists because that line got crossed twice in one night.
