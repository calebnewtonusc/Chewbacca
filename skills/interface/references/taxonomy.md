# The component taxonomy

Every interface type, named, so a generator loads instead of invents. Grouped
by the job the component does, because that is how a request arrives ("show me
which ones are overdue") rather than by what it looks like.

Names match shadcn/ui and Radix where they exist, since `CLAUDE.md` already
requires shadcn and never building a primitive from scratch. A name in
**bold** has a shadcn component; the rest are compositions you assemble.

## Atoms

| Job | Components |
| --- | --- |
| Action | **button**, icon button, **toggle**, link |
| Text entry | **input**, **textarea**, **input-otp** |
| Choice | **checkbox**, **radio-group**, **select**, **switch**, **slider** |
| Status | **badge**, dot, **progress**, spinner, **skeleton** |
| Identity | **avatar**, logo, initials |
| Structure | **separator**, **label**, kbd, code |

## Molecules

| Job | Components |
| --- | --- |
| Filtered entry | search field, **combobox**, tag input, date picker (**calendar** + **popover**) |
| One number | stat tile, metric with delta, sparkline card, gauge |
| One record | list row, **card**, media object, comment, notification |
| Guidance | **form** field with label, hint and error; **tooltip**; inline alert |
| Navigation unit | **breadcrumb** crumb, **tabs** trigger, **pagination** control, step |

## Organisms

| Job | Components |
| --- | --- |
| Many records | **table** (sortable, selectable), card grid, kanban, **calendar**, timeline, tree, feed, gallery |
| Navigation | top bar, **sidebar**, **navigation-menu**, **command** palette, **menubar**, footer |
| Focused task | **dialog**, **sheet**, **drawer**, **alert-dialog**, wizard step, inline editor |
| Overview | dashboard header with KPI row, **chart** panel, activity stream, leaderboard |
| Conversation | message thread, composer, transcript, diff view |
| Systemic | **toast** stack, empty state, error boundary, loading shell, onboarding checklist |

## Templates

| Template | Holds | Use when |
| --- | --- | --- |
| **Dashboard** | KPI row, 1-3 chart panels, one table | The question is "how are things going" |
| **Index / list** | Filters, table or card grid, pagination | The question is "which ones" |
| **Detail** | Header with actions, tabbed body, related list | The question is "tell me about this one" |
| **Split / master-detail** | List on the left, detail on the right | Scanning and inspecting in one motion |
| **Wizard** | Progress, one step per screen, back and next | A task with required order |
| **Settings** | Sidebar of sections, grouped forms, save bar | Changing configuration |
| **Feed** | Composer, infinite stream, filters | Time-ordered activity |
| **Console / REPL** | Input, scrollback, status line | Live interaction with a system |
| **Landing** | Hero, proof, features, CTA | Persuading someone who has not signed up |
| **Overlay HUD** | Floating panel, no chrome, transparent ground | Ambient status over other apps |

**Nested three layers down** is a template holding organisms holding molecules.
The dashboard is the only one most requests actually want, and it is the one
most often rebuilt from scratch.

## Choosing, in one pass

1. **What question does the viewer arrive with?** That picks the template from
   the table above.
2. **What is the shape of the data?** The shape picks the component, and this
   mapping is a lookup rather than a judgement call:

   | Shape | Component |
   | --- | --- |
   | One number | stat tile |
   | Many records, shared fields | table |
   | Many records, one dominant image | card grid |
   | Time-ordered | feed or timeline |
   | Hierarchical | tree |
   | Two variables over a range | chart |
3. **What can the viewer do?** Each verb is an atom or a focused-task organism.
   No verb means no buttons, and a read-only surface is allowed to be read-only.
4. **What happens when it is empty, slow or broken?** Three states, always.

Steps 1 to 3 are a lookup. Only step 4 needs thought, and it is the one that
gets skipped.
