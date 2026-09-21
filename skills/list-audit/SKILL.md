---
name: list-audit
description: Check a purchased, scraped or inherited contact list before anyone builds a sequence on it. Use when a lead list, investor list, prospect file, CSV export or enriched dataset arrives, when someone says they bought a list or paid for data, before writing outbound copy or scoring rules against a file, and when a campaign is bouncing or the personalization is coming out wrong. Also use before quoting how many contacts a file contains.
license: MIT
requires: [list-audit]
---

# Auditing a contact list

```bash
list-audit contacts.csv                # the report
list-audit contacts.csv --grades A,B   # what counts as usable
list-audit contacts.csv --json         # for a pipeline
```

Columns are auto-detected, the file is read once, and nothing but counters is
held, so a 200 MB file is fine. It takes about twenty seconds per million rows.

## The number on the invoice is not the number you have

The row count is what the seller quotes and the only figure anyone repeats. It is
almost never the number you can send to. The first audit this was built from:
**1,039,715 rows sold, 81,460 actually usable, 7.8 percent.** The rest were
organizations with no human attached, rows with no email, or graded junk.

Report the usable number before anyone plans against the row count. Someone will
have already said the big number out loud, and the longer that goes uncorrected
the more work gets built on it.

## What it looks for, and why each one earns its place

**Rows with no person.** A list can be nearly half organization records with no
contact on them. Those are not leads, they are a research queue.

**The company cell holding an image or a URL.** Scrapers drop attachment links
into the wrong column. The email is usually still good, so the row looks fine
until `{{company}}` renders an Airtable URL in front of a prospect.

**The NaN strip.** Somebody cleans pandas `NaN` values with a global
find-and-replace on the literal substring `nan`, and it eats the same three
letters everywhere else, so `Financial` becomes `Ficial` and `Fernandez` becomes
`Ferdez`. Sector damage costs you filter accuracy, but name damage sends an email
that opens "Hi Ferdo", which is the one field the recipient checks first.

**A LinkedIn column that belongs to someone else.** The worst one, because the
column looks populated. On the first file audited, roughly **thirty thousand rows
carried a stranger's profile**, including Ben Horowitz's row pointing at an
unrelated person next to his real a16z address.

## Triangulate rather than sampling

A slug that shares no token with the name is only a flag. Vanity URLs, married
names and transliterations land there legitimately, so the raw percentage is an
upper bound and quoting it as an error rate is wrong.

Cross-check the third field instead. If the **email** corroborates the name and
the **LinkedIn** does not, LinkedIn is the wrong field, and you have a real rate
without opening a browser or hand-checking a hundred profiles. That turned an
"18.5 percent, needs a sample audit" into "71 percent of flagged rows are
confirmed wrong" in one pass.

The general move: when one field is suspect, verify it against a second
independent field on the same row before reaching for manual review.

## Say it plainly, and say it early

The person who bought the file is going to hear this from you or from a bounce
rate. From you is better, and it is not an attack on their purchase. Lead with
what they do have, then the defects, then the one that blocks sending.

Check sector and geography coverage against the campaigns the list is meant to
serve, because coverage decides which of them are workable at all. On the first
audit, four of eight portfolio companies fit the file and three could not be
worked off it regardless of how good the messaging got. That is a targeting
finding, not a data finding, and it changes the plan more than any defect does.

**Never score a list before auditing it.** Scoring a file with these defects
produces confident garbage and hides the damage under a grade.
