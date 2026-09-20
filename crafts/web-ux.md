# Web UI and UX

Researched 2026-09-20 across four passes: the award corpus, the product-UX
canon, motion craft read out of shipped library source, and the constraint
systems that stop a page looking generated. Rules only. Full sourcing and the
74 extracted design systems live in `calebnewtonusc/ux-engine`.

## The one that governs the rest

**The generated look is not bad taste. It is an empty deny list.** Every
recognizable system is recognizable because of a short list of things it will
not do, and in the strongest cases that list is executable: Shopify Polaris
bans hex and all 25 length units in stylelint, Atlassian bans `<button>` and
`placeholder` in ESLint, GOV.UK bans pasted hex values in Sass. A library that
only says what to use reproduces the median. **The forbidding is the signal.**

Bugatti is the reference case: no accent colour, no radius between 0 and a
pill, no display weight above 400. Three refusals, and they are most of what
makes a page read as Bugatti rather than as every other generated page.

**So before writing a line: pick a system and name what it forbids.**
`ux-pick "austere luxury dark"` returns one with its refusals. Then load only
that system.

## Motion

**Match motion to frequency. This is the best single rule found.**

| Seen | Motion |
|---|---|
| 100+ times a day (shortcuts, palette) | **none** |
| Tens of times a day (hover, list nav) | reduced |
| Occasional (modal, drawer, toast) | standard |
| Rare or first-time | delight |

Raycast ships no open/close animation. That is correct, not lazy. Apple:
"generally avoid adding motion to UI interactions that occur frequently."

**Duration.** Under 300ms for anything the user triggers and waits on. 400 to
500ms for a large surface crossing a long distance. Hover 50-150ms, button
press 100-160ms with `scale(0.97)`, tooltip 125-200ms, dropdown 150-250ms,
modal 200-500ms. Stagger list items 30-80ms, never more. Material's ceiling is
400ms; the people who publish 300ms ship drawers at 500ms.

**Exits are faster than entrances.** Material: 195ms out, 225ms in. Leaving
should not cost the user time.

**Animate `transform` and `opacity`. Nothing else.** Animating width, height,
margin, padding, top or left is a performance bug. Ban `transition: all`.

**Never `scale(0)`.** Nothing in the real world appears from nothing. Start at
`scale(0.9)` to `scale(0.97)` with `opacity: 0`. Popovers and dropdowns scale
from their trigger via `transform-origin`; modals are the exception and stay
centred.

**Use CSS transitions, not `@keyframes`, for anything triggered rapidly.**
Transitions retarget mid-flight; keyframes restart from zero.

**Springs:** start at 100% damping, zero overshoot. Add bounce only when the
driving gesture carried momentum. Apple's Music app uses 100% damping on tap
and 80% on swipe. Keep bounce 0.1 to 0.3 and use none in most UI.

**Reduced motion means reduced, not removed.** The spec says "removes, reduces,
or replaces." Keep opacity and colour, drop transforms. Prefer shortening
durations to `animation: none`, because some sites rely on animation events.
Gate every hover behind `@media (hover: hover) and (pointer: fine)`.

## Speed

100ms is instantaneous, 1s is the limit of uninterrupted thought, 10s is the
limit of attention (Miller 1968, via Nielsen). Budget **50ms** of the 100 for
your own handling. Hold INP at or below **200ms** at p75. Produce each frame in
**10ms**, not 16.

**Measure the percentage of interactions under 100ms, not percentile latency.**
Percentiles hide the shape of the distribution. Bucket into <50, <100, <1000,
>1000 and optimize the tail. Use `performance.now()`, not `new Date()`.

**The best loading state is none.** Sync in the background. Otherwise: show
**nothing** under 2s, a spinner or skeleton from 2 to 10s, a percent-done bar
above 10s. Never render an empty list before data arrives, or you flash "No
results" (Raycast names this their most common extension bug).

## Type

Body prose at `max-width: 65ch`. 45ch floor, 80ch ceiling, 50ch on narrow.
Bringhurst says 66 characters is ideal; Baymard measured that lines over 80
characters were **skipped 41% more often**.

**The larger the font, the tighter the line height.** Body 1.5-1.7, captions
1.3-1.4, headings 1.1-1.3, display 1.0-1.2.

**At least 1.25x between type steps.** Everything crammed between 14 and 18px
is a flat hierarchy and reads as generated.

**Inter is now itself a tell**, along with Geist, Manrope, Space Grotesk and
Plus Jakarta Sans. Swapping one default for a newer default buys nothing.

WCAG 1.4.12 is testable: the layout must survive line height 1.5x, paragraph
spacing 2x, letter spacing 0.12x and word spacing 0.16x. Apply all four and
check nothing clips.

## Colour

**Few semantic roles, not few hex values.** GOV.UK ships 10 functional colours
total. Radix ships 12 steps each with one assigned job. The slop signature is
the opposite: many hues, no roles, chosen per component.

Prefer **OKLCH**. HSL is built on screen geometry, so equal lightness across
hues does not look equally bright and every ramp needs hand-correction.

**Gate on WCAG 2 ratios**: 4.5:1 body, 3:1 large text and UI components. APCA
is exploratory, was removed from WCAG 3 in July 2023, and satisfies no current
regulation.

## Spacing

Dense at the bottom, sparse at the top. Carbon ships 2, 4, 8, 12, 16, 24, 32,
40, 48, 64, 80, 96, 160. Note 40 and 80, so strict 8pt purity is not what real
systems do.

**One gap everywhere is a tell.** Tight inside a group, generous between them.
Spacing inside a component should be less than the spacing around it, so
grouping reads before content does.

**Nested radius is arithmetic: `inner = outer − padding`.**

## Scroll

Native scroll-driven animation is at **87% support** (Chrome 115, Safari 26,
Firefox 159). Gate behind `@supports (animation-timeline: scroll())` and keep
the effect decorative. **Declare `animation-timeline` after the `animation`
shorthand**, which silently resets it otherwise.

**Scroll hijacking:** NN/g found the majority of participants experienced at
least mild disorientation, and some read it as a bug. Never change scroll
direction, never hijack a section with body copy, never on mobile, never above
the fold.

## Command palettes

`Cmd+K`, and the same key closes it. `?` for the shortcut list. One palette,
one key. Every action in the app reachable from it. Show 5 results with the
fifth **intentionally cut off** to signal scroll. Fuzzy match. Score against
title and aliases, taking the max. Do not make the user choose between search
mode and action mode.

**Keep DOM focus on the input** and move assistive-technology focus with
`aria-activedescendant`. Never move real focus to the options.

## Copy and content

Empty states: say which of loading, error or no-data it is; teach something;
offer a direct path to the task. Heading forward-looking, "Create your first
product", never "You haven't added any products yet". **No jokes**, which read
as mockery to someone already stuck.

Errors: adjacent to the source, never colour alone, **preserve the user's
input**, say what to do next. No humor, it goes stale on repeat.

**Never ship an invented stat.** `10k+`, `99.9%`, `24/7` with nothing measured
behind them is a named tell and it is also Caleb's own standing rule.

## The banned list, checkable

`ux-lint <path>` fires on all of these. Run it before calling any UI done.

Indigo and violet Tailwind defaults. The `#6366f1` to `#a855f7` gradient.
Gradient headline text. Glassmorphism. The pulsing status dot. `transition:
all`. `hover:scale-105`. `rounded-2xl` and `3xl`. `shadow-xl` and `2xl`. The
thick coloured left border on list rows. An icon in a 10% tint of itself. One
gap everywhere. Invented stat trios. Emoji section headers. "Empower your
team", "ship smarter", "let's build something together". Giant faint `01 /`
ordinals. A placeholder doing a label's job. Arbitrary inline hex.

## When it must not look generated at all

Clone the constraint of something real and follow it literally. The counter
examples all share a structure: **the constraint is external and stateable**
(a solar power budget, a legibility mandate), **affordances are preserved while
style is abandoned** (links still look like links, which is the whole
difference between brutalist and broken), **hierarchy comes from size and
space, never colour tricks**, and **the subtraction is visible**. A page that
is visibly cheaper reads as a decision; a page that is merely plain reads as an
absence of one.

## If the brief is "make it cool", not "make it usable"

Measured across 33 award winners, 131 JS bundles grepped, in
`calebnewtonusc/ux-engine/research/01-award-corpus.md`.

**The corpus does not say 3D wins. It says one committed mechanism wins.** 3D
is just the most common way to buy one. Igloo wrote an ice-crystal growth
algorithm. The Line Studio made its loader animate on twos. Dropbox turned its
brand guidelines into toys and took Website of the Year, Best UX and a Webby
with **no WebGL at all**. Don't Board Me won on copywriting and a funny 404.

**Pick one mechanism, couple everything to it, skip the rest.**

**The measured stack, which is not the one people assume.** Lenis is on 18 of
23 sites, more common than GSAP itself. Nuxt beats Next 10 to 2. And
**Framer Motion, React Three Fiber and Spline are each on 0 of 32 sites**,
which contradicts `~/.claude/rules/design-system.md` outright. Award work
writes Three.js by hand and drives Lenis from `gsap.ticker` so scroll and
animation share one clock. Normalise scroll to a single 0-1 value and push it
into shader uniforms rather than wiring triggers one at a time.

**Awwwards weights Design 40, Usability 30, Creativity 20, Content 10.** Scores
run 7.45 to 8.25 and nobody cleared 8.3 in three years, so plan to a 7.9.

**Know the price before quoting this section.** No award body publishes a
performance budget, a Core Web Vitals threshold or a WCAG level, and it shows:
only 11 of 23 winners reference `prefers-reduced-motion` at all, 8 of 32 ship
under 60 words of initial HTML (one ships a single word), 13 of 32 have no
`<h1>`, and the largest single bundle is 4.7MB. NN/g found the majority of
users disoriented by scroll hijacking. **Use this section for a campaign
microsite. Do not use it for anything someone has to get work done in.**
