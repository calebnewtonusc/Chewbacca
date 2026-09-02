# Grading models

Three models show up, and they are not variations on each other. Using the wrong
math produces a number that feels precise and is meaningless.

## Weighted percentage

Each component has a weight summing to 100, and a score as a percentage.

```
standing  = sum(weight * score / 100 for graded) / sum(weight for graded) * 100
remaining = sum(weight for ungraded)
needed    = (target - earned) / remaining * 100
```

`coursework grade <course> --target 90` does this. Read what it means carefully:
`needed` is the average percentage required across everything left. When it comes
back above 100 the target is gone, and saying so plainly is more useful than
encouragement.

## Points

The course states a total, like 420 points, and each component is worth a
number. Convert to weights by dividing by the total. The ledger accepts `points`
directly and the CLI normalizes.

The trap is a total that does not match the stated denominator. A syllabus that
says "the course grade will be based upon 400 possible points" above a table
summing to 420 is common. Record the table, because that is what gets graded,
and note the discrepancy. Ask rather than silently picking one.

In the ledger, `score` is a percentage unless you also give `max`, in which case
it is raw points out of max. Give `max` whenever you are copying a number off a
returned exam.

## Labor contract

A baseline grade, usually B, guaranteed for completing the minimum labor. The
grade then moves on countable infractions and countable extra work, not on
quality:

- absences past the allowance
- late final drafts
- late or missing ancillary work
- lapses in good-faith effort
- extra revisions completed, each moving the grade up a step

**The CLI refuses to model this**, and that refusal is correct: there is no
average to take. `grading_model: contract` makes `coursework grade` print the
policy instead of a number.

To answer "where do I stand" in a contract course, count. Absences, late essays,
late ancillary items, lapses, each against its own column in the step table,
then sum the steps and subtract from the baseline. Add one step back for each
completed further revision.

Two details that decide outcomes and are always in the fine print:

- **An eraser or amnesty clause**, usable once, on a single infraction, often
  explicitly not on a missing final essay. It is worth one grade step and people
  forget they have it.
- **A hard gate independent of the contract.** Writing programs commonly require
  every essay to be submitted at all to pass, regardless of standing. A student
  can be at a B on the table and still fail by never turning in one paper.

Contract courses are the ones where attendance arithmetic matters most, because
absences convert directly into grade steps with no way to out-perform them
later.

## What to do with a mid-semester estimate

State what is actually known: the fraction of the grade that has been graded so
far, the standing within it, and what remains. A standing computed from 24% of
the grade is a weak signal and should be labeled as one. The useful sentence is
usually not the current number but what the next graded item does to it.
