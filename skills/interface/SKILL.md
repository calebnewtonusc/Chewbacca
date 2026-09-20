---
name: interface
description: "Build any interface by loading a preset instead of re-deriving one: dashboards, tables, forms, detail views, settings, wizards, feeds, HUD panels, landing pages. Use when asked to build, show, visualize, lay out or mock up a screen, dashboard, chart, UI or app, when the user wants to see data rather than be told it, and before generating any UI from a data source."
---

# Interface

Build it by loading, not by inventing.

The problem this exists for, in Caleb's words: **"right now it's laggy because
it's needed to every time recalibrate how to make something."** The cost of
generating a UI is not rendering. It is the model re-deciding, per request,
what a dashboard is, what spacing to use, what a good table looks like and
where the data comes from. All four of those are written down here, once.

## The order, every time

1. **Name the template.** `references/taxonomy.md` has ten. The request is
   almost always one of them, and the one most people mean is Dashboard.
2. **Name the organisms it holds**, from the same file. Stop here if you are
   about to invent a component that already has a name.
3. **Find the data** in `references/data-loaders.md`, and when it is not there
   use `references/discover-data.md` to go find it, appending what you learn
   back into the loaders file so the next session does not repeat the search.
4. **Apply the system**, from [crafts/interface.md](../../crafts/interface.md):
   grayscale first, the constrained scale, hierarchy by size and weight and
   color, too much whitespace then remove, details last.
5. **Build the three states.** Loading, empty, error. This is the step that
   gets skipped, because the prompt only ever describes the happy path.

Steps 1 to 3 are lookups and should cost almost nothing. That is the point.

## One theme, never re-chosen

Caleb: "keep it the same theme." Tokens are defined once per surface and
referenced everywhere. A generator that picks a fresh accent color per artifact
produces a pile of demos rather than a product, and the tell is obvious the
moment two of them sit side by side.

## Where the thing renders

| Surface | Use | Reach it with |
| --- | --- | --- |
| **HUD** | Ambient, live, over other apps, no window | `hud` and the `hud` skill |
| **Local page** | Something to click through or keep open | an HTML file, opened |
| **In the repo** | Part of a product being built | the project's own stack, per `stack-rules` |

Pick the surface before the layout. An overlay HUD and a settings page are
different templates, and building the second one into the first is the common
mistake.

## Reference files

- [references/taxonomy.md](references/taxonomy.md): every component and
  template, named, grouped by the job it does. Read at steps 1 and 2.
- [references/data-loaders.md](references/data-loaders.md): every data source
  already reachable on this machine, and the four shapes any new one arrives
  in. Read at step 3.
- [references/discover-data.md](references/discover-data.md): the procedure for
  a source nothing covers yet, cheapest method first, ending in pixels only as
  a last resort. Read when step 3 misses.
- [crafts/interface.md](../../crafts/interface.md): the researched rules, from
  Refactoring UI and Atomic Design. Read at step 4.

## The hard line

**Never invent a component that has a name in the taxonomy.** A bespoke variant
of a table is the recalibration this skill exists to prevent, it will not match
the next one generated, and nobody asked for it.
