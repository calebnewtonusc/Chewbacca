# Interface

Researched 2026-09-20 from Wathan and Schoger's _Refactoring UI_, Brad Frost's
_Atomic Design_, and the component taxonomy shadcn/ui and Radix actually ship.
Rules only, each one falsifiable. Vibes were left out on purpose.

This file exists because of a latency problem, not a taste problem. Caleb's
diagnosis: **"right now it's laggy because it's needed to every time
recalibrate how to make something."** The cost is the model re-deriving the
method per request. So the method is written down once, here, and every later
session inherits it. Same trick as `demo-video.md`, applied to pixels.

## The system decisions, made once

**Design in grayscale first, add color last.** Refactoring UI's opening move.
Forcing hierarchy through spacing, contrast and typography before color means
color never becomes the crutch holding a weak layout together. A layout that
only reads once it is colored is a broken layout.

**Constrained scales, never arbitrary values.** Spacing is
`4 8 12 16 24 32 48 64 96`. Type is a fixed ramp. Shadows are a fixed set of
five. The argument is not neatness: picking from eight options is a decision a
generator makes correctly every time, and picking from infinite pixels is a
decision it makes differently every time. **A constrained scale is what makes
output reproducible rather than merely nice.**

**Hierarchy comes from size, weight and color, not position.** Three levers,
applied deliberately. De-emphasize by lowering contrast before you shrink
something, because small low-contrast text is unreadable while normal-size
low-contrast text is merely secondary.

**Start with too much white space, then remove.** Cramped is the default
failure of generated UI, because whitespace is the one thing a text model does
not feel. Overshoot deliberately and pull back.

**Details last.** Icons, shadows, micro-interactions and gradients come after
layout and hierarchy work. A generator that reaches for a gradient before the
spacing scale is hiding.

## Composition: the part that makes presets possible

Atomic Design is the assembly grammar, and it is what Caleb means by "giving it
understanding of how to piece things together."

| Stage | What it is | Examples |
| --- | --- | --- |
| **Atom** | Cannot be broken down further without losing function | button, input, label, badge, icon, avatar |
| **Molecule** | A few atoms bonded into one functional unit | search field (label + input + button), stat tile, form row |
| **Organism** | A distinct section of interface | header, sidebar, data table, card grid, settings panel |
| **Template** | Page layout with placeholder content, showing structure | dashboard shell, detail view, wizard |
| **Page** | A template with real content | the actual thing shipped |

Frost's line is the reason this works: atoms "combine together to form
molecules, which further combine to form organisms," which lets you "quickly
shift between abstract and concrete."

**The operational consequence: a preset is stored at the level it is reused
at.** A button is an atom and gets one definition. A dashboard is a template
and gets one definition that names the organisms it holds. **"A user interface
nested three layers down" is a template referencing organisms referencing
molecules**, and it is cheap to generate only because the lower three levels
were never re-derived.

**Templates carry placeholder content that is honest about size.** Frost is
explicit that a template must show "image sizes and character lengths for
headings and text passages." A template built around a 12-character heading
breaks on a real 60-character one, and that break surfaces at the worst moment.

## Rules for generated interfaces specifically

**One theme, locked, across everything constructed.** Caleb: "keep it the same
theme." Tokens are defined once and referenced, never re-chosen per artifact.
A generator that picks a new accent per page produces a pile of demos rather
than a product.

**Every async surface needs loading, empty and error, or it is not done.**
This is already `ABSOLUTE PROHIBITIONS` in `CLAUDE.md`, and it is the single
most common thing missing from a generated dashboard, because the happy path is
the only one in the prompt.

**Real data, or the design is untested.** A populated table and an empty one
are different designs. Generate with representative content, including the long
string and the zero state.

**Name the component before building it.** If the thing being asked for has a
name in the taxonomy, the preset is loaded rather than invented. Inventing a
bespoke variant of a component that already exists is the recalibration this
file is written to prevent.

## When the brief contradicts these

The usual ask is "make it pop", "add a gradient", or "fill the space". Those
are details-first and cramped-by-default, the two named failures above. Say
which rule it breaks, in one line. Build the version with the scale and the
hierarchy. Offer the literal version separately if it is still wanted.
Silently delivering either one is wrong.
