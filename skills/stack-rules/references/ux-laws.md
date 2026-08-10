---
paths:
  - "projects/**/*.tsx"
  - "projects/**/*.ts"
  - "projects/**/*.html"
---

# Laws of UX

Apply these when designing any UI, component, or interaction. They are not suggestions — violations are design bugs.

---

## Aesthetic-Usability Effect

Beautiful interfaces are perceived as more usable and users forgive minor friction more readily. Polish matters, but never use it to mask a real usability problem that needs fixing.

## Choice Overload

Too many options in parallel kills decisions and drives abandonment. Limit what is visible at once. Use progressive disclosure, search, and filters to narrow the field before asking users to choose.

## Chunking

Break content into visually distinct groups with clear hierarchy. Users scan, they do not read linearly. Use whitespace and meaningful categories to signal relationships between elements.

## Cognitive Load

Every non-essential element in the UI taxes the user's brain for free. If it does not help them complete their goal, remove it. Organize what remains logically so the least possible effort is required.

## Doherty Threshold

Responses must return in under 400ms to keep users in flow. For anything longer, show a skeleton loader or progress indicator. A wait that looks active feels shorter than one that looks broken.

## Fitts's Law

Make click targets large enough and place important actions where the user's attention already is. Small targets far from focus centers increase errors and frustration. Primary CTAs should never be tiny or far-right on mobile.

## Goal-Gradient Effect

Motivation accelerates as users approach completion. Show progress bars, step counts, and completion percentages in multi-step flows. Making progress visible directly increases completion rates.

## Hick's Law

Decision time grows with the number and complexity of options. Reduce the number of things shown at any moment, especially where speed matters. Reveal complexity progressively, not all at once.

## Jakob's Law

Users spend most of their time on other products and arrive with mental models already built. Follow familiar conventions for nav, forms, icons, and layouts. When you must deviate, help users transition gradually.

## Law of Common Region

Elements inside a shared border or background are perceived as a group. A card, a divider, a tinted background communicates relationship without extra components. One of the cheapest ways to add visual structure.

## Law of Proximity

Elements placed close together are assumed to be related. Use tight spacing within groups and generous spacing between groups. Never let unrelated items sit adjacent at equal spacing.

## Law of Similarity

Elements that look alike are assumed to behave alike. Keep all interactive elements visually consistent and distinct from passive content. Do not style a CTA like body text.

## Miller's Law

The average person holds 7 plus or minus 2 items in working memory at once. Show no more than 5 to 9 items in any list, menu, or navigation. When there is more content, group it.

## Pareto Principle

80% of outcomes come from 20% of causes. Identify the 20% of features users actually use and make those excellent before touching the rest. Do not spread effort evenly across everything.

## Peak-End Rule

People judge an experience by its emotional peak and its ending, not the average. Design your most satisfying moment and nail the final interaction: the success screen, confirmation, or offboarding. Both must land.

## Serial Position Effect

Users best remember the first and last items in a sequence. Middle items fade. Put the primary CTA at the start or end of navigation, not buried in the center. The most important action should not be sandwiched.

## Tesler's Law

Every product has irreducible complexity. The job of design is to absorb that complexity on behalf of the user through smart defaults, pre-filled forms, and sensible flows rather than dumping it in the UI.

## Von Restorff Effect

The one element that looks different from everything else is the one people remember. Use it deliberately: one primary CTA, one highlighted pricing tier, one badge. Use it more than once and you have noise, not signal.

## Zeigarnik Effect

Incomplete tasks are remembered better than finished ones. Surface incomplete states, progress indicators, and pick-up-where-you-left-off prompts to pull users back and drive completion. Abandoned flows are a recoverable UX opportunity.

---

## Quick Reference

| Designing...                | Laws to check                                                       |
| --------------------------- | ------------------------------------------------------------------- |
| Navigation / menus          | Hick's Law, Miller's Law, Serial Position Effect, Jakob's Law       |
| Forms / multi-step flows    | Goal-Gradient Effect, Zeigarnik Effect, Tesler's Law, Chunking      |
| Cards / layout              | Law of Proximity, Law of Common Region, Law of Similarity, Chunking |
| CTAs / buttons              | Fitts's Law, Von Restorff Effect, Serial Position Effect            |
| Loading / async states      | Doherty Threshold, Cognitive Load                                   |
| Onboarding / success states | Peak-End Rule, Aesthetic-Usability Effect                           |
| Pricing / option selection  | Choice Overload, Hick's Law, Von Restorff Effect                    |
