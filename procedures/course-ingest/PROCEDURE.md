# course-ingest

A whole term read out of a school's Blackboard Ultra and written down twice: as
a ledger that answers questions, and as calendar events that interrupt.

Run it:

```
course-ingest --school acc --signin                      # once, a human signs in
course-ingest --school example --calendar "Fall 2026"    # every time after
course-ingest --school example --calendar "Fall 2026" --dry-run
```

It writes `~/coursework/.ingest/<school>/`: `deliverables.json` (every dated
graded item, each with the gradebook column or syllabus sentence it came from),
`raw/` (the untouched API payloads), `docs/` (every document body and every link
found in one, per course), `files/` (attachments, usually the syllabus), and
`report.json`. With `--calendar` it also puts each dated item on a calendar of
its own.

## The shape of the problem

A syllabus is a contract that states every date the student will be judged on.
Nobody reads it twice. An LMS holds the same dates in a form a machine can read,
but only the ones the instructor has created a column for, which on day one is
a fraction of the term. Neither source is the semester.

So this procedure reads both and keeps them apart. Gradebook columns carry exact
timestamps and go in automatically. Anything only the syllabus knows goes in
`~/coursework/ingest-extra.json` by hand, quoting the sentence. Every row in
`deliverables.json` says which it was.

On the first ACC run, 2026-09-21: the gradebook held 37 dated columns across
three courses. The syllabi held 24 more deadlines that had no column yet. A
calendar built from the gradebook alone would have been missing eleven of twelve
discussions in one course, one of its four homeworks, and every mid-week
deadline in the term.

## Getting in

The LMS is behind the school's SSO, so a person signs in once and the cookie jar
is kept. Four routes were tried on this machine first and all four are closed.
They are recorded because each one costs half an hour to rediscover.

| Route | What happens |
| ----- | ------------ |
| `chrome-js` against the real Chrome | Needs View > Developer > Allow JavaScript from Apple Events. The toggle does not flip from an accessibility press or from keyboard menu navigation. Reported success, pref unchanged, twice, in two separate sessions. |
| Chrome's AppleScript `save` | **Segfaults Chrome.** Version 153.0.8010.50, crash reports 2026-09-21 13:15:28 and 13:21:38, `NSScriptCommand` to `CFStringCompare` on a null. It takes the user's browser down with it. Never call it. |
| Reading Chrome's cookie store | Off limits, and rightly. |
| Playwright on a copy of the Chrome profile | Playwright's default args include `--use-mock-keychain`, which swaps Chrome's real encryption key for a dummy. Every cookie on disk fails to decrypt and the profile looks signed out. `ignoreDefaultArgs: ['--use-mock-keychain']` fixes that, but a second Chrome cannot share a live `user-data-dir` anyway. |

What works is a browser of this procedure's own, signed in once by hand.

**It has to be `storageState`, not a persistent profile directory.** Blackboard's
session cookie is a session cookie, so Chromium never flushes it to disk and a
profile directory comes back signed out on the next run. `storageState` dumps the
live cookie jar. The state file is mode 0600 at
`~/.config/course-ingest/<school>.state.json`.

## The API

Ultra is a single-page app painted from JSON endpoints that are not documented
and differ between Blackboard releases, so the first pass drives the real UI and
records every `/learn/api` call with its response. Guessing URLs is worse than
slow: a wrong one returns 404 HTML that parses as "no assignments".

The prefix is `/learn/api/v1`. **Not** `/learn/api/public/v1`: the public REST
API wants an OAuth app and answers a browser session with
`{"status":401,"message":"API request is not authenticated."}`.

| Endpoint | Carries |
| -------- | ------- |
| `/learn/api/v1/users/me` | the internal user id every other call needs |
| `/learn/api/v1/users/{id}/memberships?expand=course...&limit=10000` | every enrolled course, with its internal `_NNNNNN_1` id |
| `/learn/api/v1/courses/{id}/gradebook/columns?...` | **the deadlines.** `dueDate`, `columnName`, `possible`, `gradebookCategory.title` |
| `/learn/api/v1/courses/{id}/contents?expand=body&recursive=true` | the content tree, and attachment urls under `contentDetail.*.file.permanentUrl` |
| `/learn/api/v1/courses/{id}/contents/{contentId}` | `body.rawText`. The listing above does **not** return document bodies; only a per-item GET does, and there is no batch form |
| `/learn/api/v1/courses/{id}/announcements?limit=100` | where instructors restate the rules that matter |
| `/learn/api/v1/courses/{id}/memberships?...` | role `P` is the instructor |
| `/learn/api/v1/calendars/calendarItems?since=&until=` | anything dated from any source |

Open a course's `/ultra/courses/{id}/cl/outline` before reading it. The content
tree is only warm after the app's own screen has asked for it.

## What to read for, not just what to read

Downloading the syllabus is the part that looks like the work. The work is four
questions, and getting any of them wrong costs more than a missed file.

1. **What does this course allow?** Quote it, do not summarize. Both ACC courses
   ban AI outright and one of them names Claude in its banned list alongside
   Google Translate and Grammarly. An unrecorded policy is a ban.
2. **Where is work actually submitted?** Spanish grades almost nothing on
   Blackboard: quizzes, tests, homework, the final exam and the final project
   are all on VHL Central, and Blackboard only mirrors the dates. Submitting in
   the right system is what earns the grade.
3. **Is the deadline on the card the real deadline?** In Anthropology it is not.
   Discussions close Sunday at 11:59 and Blackboard dates the column to the
   close, but the initial post is due Wednesday and a Sunday post earns no more
   than half. One gradebook column, two deadlines, and the one the LMS shows is
   the one that is already too late.
4. **What does the syllabus have that the gradebook does not?** Count them. If
   the syllabus says twelve discussions and the gradebook has one, the other
   eleven are the job.

## Traps

- **`mac calendar list` prints starts in UTC.** A deadline at 23:59 local is the
  next day in UTC. Comparing raw date prefixes matched nothing, so the second
  run added a second copy of all 61 events. Both sides convert to the local day
  before comparing. The symptom is silent and it destroys trust in the calendar
  faster than having no calendar.
- **Calendar.app times out on first touch.** Creating a calendar through
  AppleScript returns `AppleEvent timed out (-1712)` while doing nothing, if the
  app was not already running. Activate it first, wrap in `with timeout of 120
  seconds`.
- **A dry run must read the existing events.** Skipping that read made
  `--dry-run` promise 61 additions when 61 were already there. A preview that
  differs from the run is not worth reading.
- **Duplicate gradebook columns are real.** Spanish has two "Quiz, Ch. 6"
  columns on different days, one a linked assessment and one manual. Do not
  dedupe them away; surface them as a question.
- **The syllabus and the LMS will disagree.** Spanish's own course calendar puts
  quizzes on five Sundays the gradebook does not use. The calendar carries the
  gradebook date, because that is what the LMS enforces, and the conflict is
  written into the ledger's `open_questions` rather than resolved by guessing.

## Origin

Built 2026-09-21, the morning two ACC courses opened, from the request to read
the courses, learn how each instructor runs their class, and put every graded
deadline on Apple Calendar.
