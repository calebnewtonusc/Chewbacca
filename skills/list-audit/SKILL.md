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

## Grade plus an email is not a qualified contact

The tool reports two tiers and the second is the real one. A row can carry an A
grade, a working email and still be a name at gmail with no company, no title and
no LinkedIn. Requiring a person, a real company name and a work email domain took
one file from 81,460 "usable" to 27,200 qualified, which is 2.6 percent of what
was bought.

Plan against the qualified number, and say it before anyone builds a target count
on the row count.

## A segment that looks perfect on volume can be the junk

The clearest case: a client's beachhead was US to MENA remittance corridors, and
the file held 50,797 UAE rows with 49,078 emails. On row count it was the single
best fit in the portfolio.

Then the segment got checked on its own: **91 percent had no LinkedIn, 84 percent
were on gmail, hotmail or yahoo, and 48,000 of the 49,078 had `organization` set
to "Unknown" or left blank.** It was tagged as 22,021 "ai" and 26,998 "VC", which
would have made Dubai home to more AI venture firms than the Bay Area.

Before believing any geography or sector block, check three rates inside it:
LinkedIn coverage, free-mailbox share, and blank-organization share. A real
institutional segment fails none of them. Real firms inside a junk block still
survive the qualified gate on their own, so nothing good is lost by distrusting
the block.

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

## Segmenting after the audit

Once a file is audited, subsetting it per campaign is a separate job with three
rules worth keeping.

**Index before querying.** A 220 MB CSV re-read per question wastes minutes a
time. One pass into SQLite takes about 13 seconds per million rows and every
query after is instant. Store the defect findings as columns rather than
repairing them, so a query excludes a defect explicitly instead of a cleaning
step quietly dropping rows nobody counted.

**Score additively and keep the breakdown on the row.** Sector match, the
seller's own grade, firm type, stage fit, geography. A score nobody can explain
is a score nobody trusts the moment a list underperforms, and the breakdown is
what turns "this list is bad" into "the stage filter was wrong".

**Keep the enrichment queue in its own file.** Rows that fit the thesis and have
a LinkedIn but no email are not sendable, they are a vendor spend. Mixing them
into the sendable list is how a campaign reports a bounce rate that is really a
coverage gap. Exclude rows whose LinkedIn is suspect from that queue, since that
is the field the enrichment starts from.

**A thin segment is a sourcing answer, not a tuning problem.** When a campaign
comes back with a few hundred targets and others have thousands, the file does
not cover that thesis. Loosening the gate to hit a nicer number moves the failure
from the list to the reply rate. Say the segment needs another source.

## Segmenting for more than one campaign at once

Two mistakes that only show up when you audit the output rather than the code.

**Score independently and the lists will collide.** Five companies scored
separately against one file produced lists that shared half their rows: of 4,354
contacts, 2,121 were on two or more and 105 were on four. When one sender runs
all the campaigns, that is the same person getting two to four cold emails from
one firm, which costs the relationship and the sending domain at once.

Allocate instead of scoring in parallel. Score every contact against every
campaign and give it to exactly one, and break ties inside a small margin toward
the campaign with the fewest targets so far, so thin segments get first claim on
ambiguous contacts rather than losing all of them to the broadest campaign. Then
verify the lists are disjoint by reading the files back, because "disjoint by
construction" is a claim about code and not about output.

**Never match on terms that describe the audience's own profession.** A fintech
company targeting a list of investors matched on "financial services", "finance"
and "asset management" and took half of every other campaign's contacts, because
in an investor database those describe what the contact *is*, not what it backs.
Narrowed to what the company actually sells into, its list fell from 2,448 to 697
and everyone else got their targets back. The same trap waits for a legal-tech
company matching "legal" against a list of lawyers.

## Learning the taxonomy from the data usually does not work here

Hand-written sector lists will match a minority of the values in a real file,
which makes expanding them from co-occurrence look obvious. It was tried on a
26,000-row pool and made the lists worse: the column held 5,480 distinct strings
polluted with geographies, stage tags and whole sentences, so co-occurrence
surfaced what was common rather than what was related, and every campaign learned
roughly the same additions. A dating app was given biotech and climatetech.
Dropping any term learned by three or more campaigns helped without fixing it.

For cold outbound a wrong-thesis message costs more than a missed contact, so
precision beats recall and curated terms win. Keep the experiment behind a flag
so the conclusion stays checkable instead of becoming folklore.
