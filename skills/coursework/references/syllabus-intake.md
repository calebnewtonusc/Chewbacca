# Reading a syllabus into the ledger

The output is one `courses/<code>.yml`. The input is the whole syllabus, read
end to end. This takes real attention once and then never again, which is the
entire trade.

## Read all of it

Syllabus PDFs bury the expensive information. The exam schedule is on the last
page. The attendance penalty is in a paragraph after the grading table. The AI
policy is under a heading about academic integrity, three pages after the
section that sounded like it would cover it. Regrade windows and makeup rules
hide inside "Additional Policies".

For a PDF, read every page. For a syllabus that is a spreadsheet, dump every
sheet, not the first one: the roster, the office hours grid, and the assignment
list are usually separate tabs.

Page count is not difficulty. A nine-page syllabus can carry a stricter
attendance rule than a twenty-two-page one.

## Extract in this order

1. **Identity.** Code, full title, units, section number, term.
2. **Meetings.** Every one: lecture, lab, discussion, studio. Days, start and
   end, room, and a `label` so they are distinguishable. Labs and discussion
   sections are separate entries, not a note on the lecture.
3. **People.** Instructor, TA, lab manager, with email and office hours. The lab
   manager is often the one who handles regrades, and their name appears once.
4. **Deliverables.** Every dated thing that carries a grade: projects, drafts,
   quizzes, exams, presentations, portfolios, final documentation. Each gets a
   `due`, a `type`, a `weight` or points value, `status: todo`, and a `source`
   naming the page.
5. **Grading.** The breakdown table, as `weight` percentages or raw `points`.
   Then the letter scale, into `policies.grading`.
6. **Attendance.** The number allowed, the cost of each one after, the tardy
   rule, and the make-up mechanism if one exists. This becomes arithmetic the
   CLI can do.
7. **Policies, quoted.** AI, late work, exams and makeups, regrades. Quote them.
   A summary of a ban reads as a suggestion three weeks later.

## Verbatim, not paraphrased, for the policies

Paraphrase loses the operative clause. "AI is restricted" is useless. "not
permitted for assignments, exams, or other course-related work unless explicitly
authorized by the instructor" tells you there is a door and where it is.

Same for attendance: "you get some absences" versus "two absences with no
explanation, each subsequent absence lowers the final grade by 1/3 of a letter,
three tardies equal an absence, more than 15 minutes late is a full absence".
The second one can be computed against. The first one cannot.

## Every date carries a source

```yaml
- {
    name: "Midterm 1",
    due: 2026-10-02,
    type: exam,
    source: "syllabus p7 lecture schedule",
  }
```

When the date turns out to be wrong, `source` is the difference between fixing a
misreading in ten seconds and re-reading a PDF. When it changes in class, the new
source is "announced in class YYYY-MM-DD", which also records that the PDF and
the ledger now disagree on purpose.

## Watch for the stale header

Syllabi are copied forward year to year. A Fall 2026 syllabus whose schedule
table is titled "Fall 2025" is common and usually harmless: check whether the
weekday names match the dates for the current year. If Aug 26 is a Wednesday in
the table and a Wednesday on the calendar, the dates are current and only the
title is stale. If they do not match, stop and ask, because every date in that
table is suspect.

Also check the "important dates" block at the back. It is frequently pasted from
the previous term and can name the wrong semester while listing the right dates.

## Section numbers matter at the end

Multi-section courses often list two final exam slots, one per section. Record
the one matching the section on the cover page, and note the other in
`notes`. A final documentation deadline three days off is a real way to lose a
project.

## Report the gaps, do not fill them

Syllabi routinely omit: the AI policy, the room, whether the free absences cover
presentation days, and the actual due dates for assignments handled through
prompts posted later in the term. Leave those `null` with a note, and hand the
user the list as questions to ask in class or on the course site. A guessed
value is indistinguishable from a real one once it is in the file, which is why
`coursework check` treats a missing source as an error and a missing AI policy
as the loudest one.

## Then verify

```bash
coursework check
coursework due --days 30
```

Read the output. A course with no meetings will not appear in `today` or `week`
and it will look like a light semester until the day of the exam.
