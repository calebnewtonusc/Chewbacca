# The work left on the display

Tracked in `bd` at `~/Desktop/2026-Code/.beads`, which is where it should be
worked from. This file is the durable copy, because that database sits in a
repo with no remote and would not survive the disk.

Every issue comes from [1000 ways it falls short](1000-WAYS-IT-FALLS-SHORT.md)
and cites the item numbers it closes. Forty-four of the thousand are already
struck through there; these cover the rest that is worth doing.

Seven of the thousand are marked deliberate and are not here. A few cannot be
fixed by writing code: item 999 is that nobody but its author has ever used it,
and the only fix for that is somebody else using it.

Regenerate after any change with the script in the commit that added this file.


## P1 — correctness and trust

### HUD: UI tests that drive the real app

`bd_2026-Code-jii`

Nothing tests the overlay window, click-through, scroll pass-through, the hotkeys, the command bar or the reticle. Click-through has broken twice and was caught only by using it. Items 886-899.

**Done when:** A UI test target launches the app, draws a surface, and asserts click-through and scroll pass-through behaviour.

### HUD: anchor markers to content rather than to screen coordinates

`bd_2026-Code-j3m`

Markers are absolute rectangles. They do not follow scrolling, do not invalidate when their target changes, and survive the window they described closing. The design document names stale anchors as the thing that makes an annotation layer garbage. Items 337-341, 788-791, 803-806.

**Done when:** A marker anchors to an accessibility element where one exists, tracks scroll and window movement, and removes itself rather than pointing at the wrong place.

### HUD: confirm VoiceOver can reach the overlay at all

`bd_2026-Code-gp6`

The overlay is a non-activating panel, which may make every surface unreachable to VoiceOver no matter how good the labels are. All the a11y work done so far assumes it is reachable and nobody has checked. Items 451-452.

**Done when:** VoiceOver is turned on and driven through a drawn surface by hand. The result is written down either way: if it cannot reach it, that is a finding worth more than the labels.

### HUD: detect screen sharing and full-screen apps

`bd_2026-Code-5wa`

Screen sharing is not detected, so the display stays up in a meeting, and full-screen apps get the overlay on top with no opt-out. There is no per-app rule. Items 445-447, 592-594.

**Done when:** An active screen share hides the layer automatically. A per-app deny list exists.

### HUD: implement the accessibility contract for containers and controls

`bd_2026-Code-apw`

Screen, Stack, Heading, Text, List, Button, Field, Select and Checkbox still declare a11y in the catalog and get nothing in the Swift renderer. Charts, Metric, Status, Diagram and markers were done on 2026-09-05; these were not.

Audit items 452-458, 463-464, 481-495 in hud/docs/1000-WAYS-IT-FALLS-SHORT.md.

**Done when:** Every component in src/hud/catalog.ts has its declared role and name source honoured by the Swift renderer. A test reads the catalog and asserts each one is covered, so adding a component without a11y fails CI.

### HUD: keyboard navigation into and around a surface

`bd_2026-Code-yw6`

There is no way to reach a control by keyboard, no focus ring on most things, and no defined focus order. A surface with a button is usable only with a pointer. Items 308-311, 453-456, 487-488.

**Done when:** A surface can be focused by keyboard, its controls tabbed through in a defined order with a visible ring, and dismissed without the mouse.

### HUD: make file editing safe

`bd_2026-Code-vz4`

Editing has no undo, no autosave, and no conflict detection: if the file changed on disk your version wins silently. Closing a surface with unsaved edits warns nobody. Items 250-256.

**Done when:** Editing detects a changed file before writing, keeps a backup, warns on close with unsaved changes, and supports undo.

### HUD: stop covering the thing being described

`bd_2026-Code-0l9`

Surfaces are placed in nine fixed regions with no knowledge of what is underneath, so a panel routinely covers the content it is about. The design document calls non-occlusion a hard rule and this does not implement it. Items 571-577.

**Done when:** Placement considers what is on screen and offsets to free space. A surface never fully covers the window it is describing.

### HUD: surface ownership and namespacing

`bd_2026-Code-9rl`

Surface ids are global and unowned. Any process running as the user can overwrite any panel, clear the glass, or impersonate the assistant convincingly, and nothing attributes a surface to its source. Items 395-399, 838-845.

**Done when:** A connection can claim a namespace, surfaces it draws are attributed, and another connection cannot silently overwrite them.


## P2 — capability

### HUD: Bars cannot show negative values or a shared scale

`bd_2026-Code-8wl`

Bars scales to its own largest value, so two Bars on one panel are not comparable, and a negative value scales to a strange length. Items 139-144.

**Done when:** Bars supports negatives around a baseline, an optional shared or absolute scale, sorting, and an other bucket for a long tail.

### HUD: Metric needs a delta, a target and a trend

`bd_2026-Code-6mm`

Metric shows one number. The most common thing anyone wants beside a number is which way it moved, and there is no way to say it. Items 149-153.

**Done when:** Metric supports a delta with direction, an optional target, and an optional inline sparkline. Thresholds work in both directions, not only ascending.

### HUD: Table needs sorting, limits and formatting

`bd_2026-Code-rpq`

Table cannot sort, filter, paginate or limit, has no cell formatting or alignment, no totals row, and no way to highlight a row. A hundred rows overflow the height cap and scroll invisibly. Items 155-163.

**Done when:** Table takes a sort, a row limit with an overflow note, per-column alignment and format, and an optional totals row.

### HUD: a settings surface

`bd_2026-Code-918`

Everything is a constant in source. Hotkeys, accent, ring position, density and listening mode cannot be changed, and Option-Space may collide with an existing shortcut with no way to move it. Items 352-359, 526-548.

**Done when:** A settings window covering hotkeys with conflict detection, appearance, and listening mode, persisted across launches.

### HUD: automatic diagram layout

`bd_2026-Code-100`

A model computes every coordinate by hand and gets overlap wrong regularly. There is no layered, hierarchical or force-directed fallback. This is the single biggest quality problem with diagrams. Items 181-183.

**Done when:** A diagram can be sent as nodes and edges with no coordinates and be laid out by the renderer. Hand-placed coordinates still work.

### HUD: batched and transactional updates

`bd_2026-Code-i4p`

A multi-line change paints intermediate states, nothing coalesces rapid updates, and there is no back-pressure, so a fast writer can outrun the renderer. Items 379-385.

**Done when:** A begin/commit pair applies a group of ops atomically. Rapid updates coalesce to one paint per frame.

### HUD: diagram edge routing and attachment

`bd_2026-Code-c2c`

Edges are straight lines that end wherever the coordinates say, not at a node border, so an arrow can appear to stop short. No curves, no elbows, no edge labels that follow their edge. Items 179-180, 184-188.

**Done when:** Edges attach to node boundaries, support orthogonal and curved routing, and carry labels that move with them.

### HUD: documentation and screenshots for a person

`bd_2026-Code-e44`

The README assumes you already want a heads-up display, has no screenshots, no demo, and no getting-started for anyone who is not an agent. Items 926-947.

**Done when:** Screenshots, a short demo recording, a getting-started page, and a troubleshooting page covering what to do when nothing draws.

### HUD: empty, loading and stale states

`bd_2026-Code-ia3`

An empty Bars or Events renders as nothing, which reads as broken rather than as none. Nothing can say it is loading, and nothing can say its data is old. Items 171-175, 418-424.

**Done when:** Every data component has an empty state that says so, a skeleton while streaming, and a way to mark itself stale with a timestamp.

### HUD: form semantics, validation and disabled states

`bd_2026-Code-efg`

No control can be disabled, marked required, or show an error. Nothing validates. Actions are fire-and-forget with no success or failure path back to the button. Items 288-307, 318-320.

**Done when:** Controls support disabled, required and error states. An action can be acknowledged so a button can show it worked or failed.

### HUD: hit targets are far below the 44 point guidance

`bd_2026-Code-cnr`

The close button is 18 points and only appears on hover. Anyone without fine pointer control cannot dismiss a surface. Items 485-487.

**Done when:** Every interactive target is at least 44 points, or has a keyboard equivalent. Hover-only affordances have a non-hover route.

### HUD: it never speaks out loud

`bd_2026-Code-0sm`

There is no text-to-speech at all. Everything is read, never heard, which undercuts the hands-busy premise: an answer while you are looking away is missed entirely. Items 729-734.

**Done when:** Short answers can be spoken, off by default, with a way to ask it to repeat.

### HUD: let it see the screen

`bd_2026-Code-963`

It cannot read the screen, cannot see what you are working on beyond an app name, and the reticle gives coordinates that nothing resolves to content. Shared context is the design document's second property and is barely implemented. Items 979-986.

**Done when:** A region can be resolved to its content through the accessibility tree, with vision as the fallback, and the cost in permissions stated plainly.

### HUD: measure performance before optimising it

`bd_2026-Code-clo`

Nothing is measured. Frame rate, memory, idle CPU and startup are all unknown, the 150ms and 100ms targets in the design document are asserted in comments, and every redraw invalidates the whole tree. Items 606-645.

**Done when:** A benchmark suite reporting idle CPU, frame time under a morph, memory with twelve surfaces, and command bar open latency. Optimisation happens after, against numbers.

### HUD: memory across sessions

`bd_2026-Code-czr`

Continuous memory exists for one listening session and dies with the process. Two sessions share nothing and it does not know what it told you yesterday. The local fast path and both fallbacks have no memory at all and nothing says so. Items 987-992.

**Done when:** A conversation survives a restart. When a path without memory is used, the reply says so.

### HUD: multi-display correctness

`bd_2026-Code-hue`

The active display follows the pointer, so surfaces appear to jump. Marker coordinates carry no display identifier, so a mark sent while the pointer is elsewhere lands on the wrong screen. Items 578-585.

**Done when:** Surfaces belong to a display and stay there. Marker and region coordinates name their display.

### HUD: reconcile the pill and the glass

`bd_2026-Code-zfk`

Two front doors with different capabilities and no shared model of a conversation. An answer in the pill cannot become a panel or the reverse, and they can disagree about the same question. The voice style and the hud skill were written separately and can contradict each other. Items 993-998.

**Done when:** One prompt source for both surfaces. An answer can move between the pill and the glass.

### HUD: render markdown, CSV and code properly in File

`bd_2026-Code-slu`

Markdown is shown as raw text, which for a notes-heavy user is the common case. CSV is raw text rather than a Table. Code has no highlighting or line numbers. Items 241-246.

**Done when:** File renders markdown, shows CSV as a Table, and highlights code with line numbers.

### HUD: repeaters, so a list is not one line per row

`bd_2026-Code-qsl`

A ten-row list is ten c lines, which is the single biggest token cost in practice. There is no loop, template or component reuse. Items 373-378.

**Done when:** A component can be bound to an array and rendered once per element. Token cost for a twenty-row list drops measurably, verified by bob tokens.

### HUD: report dropped components and props to the sender

`bd_2026-Code-9yi`

Parse failures now go back, but a component the renderer does not know and a prop it does not support are still dropped in silence. From the sender's side that is indistinguishable from success. Items 403-408.

**Done when:** An unknown type or prop produces a problem event naming it. A strict mode exists that refuses rather than drops.

### HUD: restore surfaces across a restart

`bd_2026-Code-5ix`

Nothing is saved. Quitting loses every surface, there is no crash recovery, and dragging a panel is forgotten. Items 856-862, 874-880.

**Done when:** Surfaces and their positions are written to disk and restored on launch, with a way to opt a surface out.

### HUD: signing, notarisation and releases

`bd_2026-Code-85w`

The bundle is ad-hoc signed and unnotarised, so Gatekeeper will refuse it on any other machine. There is no download, no versioning, no release notes and no uninstall. Items 680-681, 931-937.

**Done when:** A notarised, versioned release anyone can download and run, with an uninstall.

### HUD: visual regression baselines

`bd_2026-Code-5d9`

Snapshot tests assert pixel coverage, not appearance. A surface could render as garbage and pass. Items 900-904.

**Done when:** Reference images are committed and compared with a tolerance, with a documented way to update them deliberately.

### HUD: voice needs barge-in, confirmation and correction

`bd_2026-Code-flj`

You cannot interrupt an answer by speaking, cannot cancel by voice, never see what was heard before it is acted on, and have no way to correct a mishearing. Items 705-711.

**Done when:** Speaking interrupts. The transcript is shown before the request goes out, with a moment to cancel or correct.


## P3 — later

### HUD: internationalisation foundation

`bd_2026-Code-79x`

Every string is hard-coded English, RTL layouts break, and no number, date or currency is ever localised. Items 496-525.

**Done when:** Strings move to a catalog, layout mirrors for RTL, and numbers and dates format by locale.

### HUD: make diagrams interactive

`bd_2026-Code-azf`

A diagram cannot be clicked, hovered, zoomed or panned, and cannot report which node was chosen. A large one shrinks until unreadable. Items 204-211.

**Done when:** Clicking a node emits an event naming it. Zoom and pan exist for a diagram larger than its surface.

### HUD: the five most missed chart types

`bd_2026-Code-z0g`

Forty-five chart types do not exist. Rather than adding all of them, pick the five that come up: stacked bars, a real time axis, a scatter, a heatmap and a state timeline. Items 86-130.

**Done when:** Five new components with catalog entries, describes, examples and eval scenarios. Nothing is added without a scenario proving a model picks it correctly.

### HUD: the missing input controls

`bd_2026-Code-5oj`

There are four controls. No text area, number, slider, date, radio, multi-select, or search. A form of any complexity is impossible. Items 271-287.

**Done when:** Add the controls the catalog's own examples imply, each with a catalog entry and an eval scenario.

### HUD: voice beyond en-US

`bd_2026-Code-d4d`

Recognition is pinned to en-US with no way to configure it, so a non-English speaker cannot use voice at all. The wake words are hard-coded English strings. Items 516-520, 691, 696-700.

**Done when:** The recognition locale and the wake words are configurable and persisted.
