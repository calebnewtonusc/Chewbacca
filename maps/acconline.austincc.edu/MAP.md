# acconline.austincc.edu (Blackboard Ultra, Austin Community College)

Read on 2026-09-25 from the person's own Chrome history while they clicked
through all three Fall 2026 courses (35 visits, `web-record show` rebuilds it).
Every address below was visited, none was guessed. `bb` opens any of them by
name; this file is what it is built on.

## Go by address, not by clicking

Ultra is a single-page app with slow panels. An address loads the page in one
step, where clicking there takes three to five. Open the address; use `ux-do`
or `jev-browse` only for what is inside the page.

## Blackboard-wide

| Page | Address |
|---|---|
| Activity stream (home) | `/ultra/stream` |
| Course list | `/ultra/course` |
| Calendar, all courses | `/ultra/calendar` |

Signing in lands on `/?new_loc=%2Fultra%2Fstream` and redirects to the stream.

## Inside a course (`{c}` is the internal id, like `_974077_1`)

| Tab | Address | Page title |
|---|---|---|
| Content | `/ultra/courses/{c}/outline` | Content / <course> |
| Discussions | `/ultra/courses/{c}/engagement` | Discussions / <course> |
| Gradebook | `/ultra/courses/{c}/grades` | Gradebook / <course> |
| Messages | `/ultra/courses/{c}/messages` | Messages / <course> |
| Announcements | `/ultra/courses/{c}/announcements` | Announcements / <course> |
| Calendar | `/ultra/courses/{c}/calendar` | Calendar / <course> |
| Groups | `/ultra/courses/{c}/groups/enrollments` | Groups / <course> |
| Achievements | `/ultra/courses/{c}/achievements` | Achievements / <course> |

Course ids live in `~/coursework/courses/*.yml` as `blackboard_internal_id`.
course-ingest's notes use `/cl/outline`; the app itself went to `/outline`.

## Items

| Content handler | Address | Seen |
|---|---|---|
| `x-bb-asmt-test-link` (homework, papers, tests) | `/ultra/courses/{c}/assessment/{item}/overview?courseId={c}` | yes |
| `x-bb-folder` | `/ultra/courses/{c}/document/{item}?view=content&state=view` | yes |
| `x-bb-document`, `x-bb-lesson`, `x-bb-file` | same route as a folder | not yet |
| `x-bb-courselink` (discussions) | the course's Discussions page | the item's own address not yet |
| `x-bb-externallink` | the link's own url | n/a |

Item ids and handlers come from course-ingest's last read,
`~/coursework/.ingest/acc/raw/course-*.json`. A new item appears after the next
`course-ingest --school acc` run.

## Mistakes already made here

- AppleScript reached a Playwright copy of Chrome with zero windows while the
  person used the real one, so a recorder built on it saw nothing. Read
  Chrome's History file, and open pages with Chrome's binary plus
  `--profile-directory`, which both reach the real profile.
- Spanish grades almost nothing here; its work is on VHL Central. Opening the
  Spanish gradebook is not where a Spanish grade is.
- The course-ingest session (`~/.config/course-ingest/acc.state.json`) had
  expired on 2026-09-25; a headless read needs `course-ingest --school acc --signin`.

## Hard line

Navigation only. Both courses ban AI for the work, so nothing here writes,
posts, or submits.
