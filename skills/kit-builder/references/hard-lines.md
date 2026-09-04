# Writing rule 4, the hard line

**Every kit needs one thing it refuses to do, named explicitly, with what it does
instead.** Write it before any other file, because it shapes all of them.

A kit without one will eventually do real damage, because the domains worth building kits
for are exactly the domains where a confident wrong answer is expensive: law, medicine,
money, immigration status, somebody's degree.

## The shape

Three parts, always:

1. **What it will not do**, stated flatly.
2. **What it does instead**, which must be substantial. A hard line that leaves the kit
   useless is a kit nobody opens.
3. **Who actually decides**, named. Never leave somebody at a wall with no door.

## Worked examples

**apply-kit.** Will not write a sentence you submit to an org that bans AI. Instead it
interviews you, argues the weak side of your argument back at you, tells you your third
paragraph is where your essay actually starts, quizzes you for the interview, and counts
your words. That is most of the value and none of it is a sentence you did not write.

**accommodations-kit.** Will not diagnose, will not reason about medication, will not tell
anybody what they are entitled to, will not draft anything for a clinician to sign, and
will not advise on whether to disclose to an employer. Instead it helps somebody describe
their own functioning accurately, in their own words, to bring to their own appointment.
When something looks like a rights violation it says so and names who adjudicates: the
campus grievance process, OCR, the EEOC, an attorney.

The clinician-letter line is the sharpest one and it generalizes: **never draft a document
for a third party to sign under their own professional judgment.** That is fraud, and
beyond being wrong it destroys the credibility of everything else the person submitted.

## Domain patterns

**Legal-adjacent** (immigration, disputes, tenant, employment): never say "you are
entitled to X" or "they are legally required to Y." Say what the published policy says,
with a source and a date, and name who determines the rest. Never draft anything
threatening legal action, which usually makes things worse at the level where the problem
actually gets solved.

**Medical** (diagnosis, caregiving, appeals, med changes): never diagnose, never suggest a
diagnosis, never say a diagnosis is wrong, never reason about dosing. The kit organizes,
tracks, and prepares questions. The medical team decides, always, and the kit says so
where somebody will read it.

**Money** (benefits, debt, taxes, fundraising): never state a threshold, a rate, or a
deadline from memory. These change annually and a wrong one is expensive. Source and date
every figure, and re-verify at the start of every cycle.

**Anything with a filing deadline** (EEOC, OCR, appeals, immigration): never state the
number of days from memory. Get it from the source, the same day, and put it in
`PROGRESS.md` where `deadline.sh` sees it. These deadlines are short, easy to miss, and
missing one ends the option permanently.

## The test for a good hard line

Read it and ask: **if the agent followed this exactly, would the kit still be worth
opening?** If no, the line is drawn wrong. It should remove the dangerous capability and
leave the useful one, not remove the point of the tool.
