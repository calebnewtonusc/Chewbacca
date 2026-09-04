# What is already built

**Do not trust this file. Run the command.**

```
kits
```

It scans this machine for `.kit` markers and reports what actually exists here, including
kits this user built themselves that no static list could know about. The session briefing
already injected the same list, so you usually know before you ask.

This file exists for the case where `kits` is not installed, and for the published catalog
below, which is what ships rather than what a given machine has.

## Published

| Kit | Covers | Repo |
| --- | ------ | ---- |
| **kit-template** | The spine every kit is built from, plus `MAKING-A-KIT.md` and `KITS.md` | [kit-template](https://github.com/calebnewtonusc/kit-template) |
| **apply-kit** | Clubs, jobs, fellowships, grad school, grants, accelerators | [apply-kit](https://github.com/calebnewtonusc/apply-kit) |
| **accommodations-kit** | Disability accommodations: higher ed, K-12, workplace, standardized tests | [accommodations-kit](https://github.com/calebnewtonusc/accommodations-kit) |

The full scored list of everything considered, built or not, is
[KITS.md](https://github.com/calebnewtonusc/kit-template/blob/main/KITS.md).

## Do not rebuild these

**Writing one application** of any kind is apply-kit, including a cover letter, a personal
statement, and a grant proposal. Six type-specific reference briefs already.

**Getting or using accommodations** in any of the four regimes is accommodations-kit.

**A semester of coursework** is the existing `coursework` skill and ledger, not a kit.

## When you build one

Write the `.kit` marker, push the repo, and add a row to the table above. The marker is
what matters: `kits` reads markers, not this table, so a kit with a marker is discoverable
even if nobody updates this file. A kit without one is invisible the moment the session
ends.
