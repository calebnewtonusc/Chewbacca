# Bob HUD

A layer of glass over your whole screen that an AI agent can draw on.

Not a window. Not a browser. One transparent, click-through panel covering the
display, rendering native SwiftUI, that an agent writes to over a Unix socket
while you keep working underneath it.

```bash
printf '@ hi at=topRight\nc s Screen title="HELLO"\nr s\n' | nc -U ~/.bob/hud.sock
```

## Why this exists

Every generative UI system renders to HTML, because HTML is what a model already
knows how to emit and what a browser already knows how to draw. That choice
decides everything downstream: your generated interface lives in a tab, so it
cannot float over your work, cannot mark a region of your screen, cannot show you
a real PDF, and cannot be glanced at while you do something else.

Render the same stream as native views and all of that becomes possible. There is
no bundle, no WebView, no page. The model authors an interface and it appears on
your screen, over whatever you were already doing.

## What it can draw

**Dashboards.** `Sparkline`, `Bars`, `Ring`, `Events`, `Metric`, `Table`,
`Status`, laid out in stacks or a grid. No axes, no gridlines, no legends: the
number is printed beside the shape, so the drawing carries the trend and the text
carries the value. Metrics and rings colour themselves when a value crosses a
threshold you gave them.

**Diagrams.** A free-form vector vocabulary in a unit square: nodes, boxes,
lines, arrows, circles, labels. It is the escape hatch for the case nobody
anticipated, and it is geometry rather than code on purpose. Nothing in a diagram
can execute, fetch, or escape, because none of it is a program.

**Files.** `File path="~/Downloads/resume.pdf"` shows the actual document. PDFs
render through the system's own PDF engine, images as images, text as text, and
editable text writes back to that exact path.

**Marks on the screen itself.** `m bug 420 260 380 90 label="This is the one
failing"` draws corner brackets around a region of your display with a label. Not
a panel near your work: a mark on it. Marks decay, because one that outlives what
it described teaches you to disbelieve all of them.

**Presence.** A ring in the corner with seven states, each with its own motion,
so you can tell whether it is listening, thinking, acting or stuck without
looking directly at it.

**Live controls.** Buttons, fields, selects and checkboxes that write to the
panel's own data model at once and send an event back up the socket, so they
respond at typing speed whether or not an agent is still listening.

## Surfaces are not windows

```
@ figure at=center chrome=bare
```

`chrome=bare` draws no panel at all. The content sits directly on your screen
with a halo behind it for legibility. `bracket` puts corner marks around a region
without covering it. `card` is frosted glass and the default.

## Things change rather than being redrawn

A surface outlives the connection that drew it, so addressing it again by name
updates it in place, and anything you leave off is kept. Send a component with
new numbers and it animates: a metric's digits roll, bars grow, and a diagram's
nodes travel to their new positions rather than cutting.

For anything that updates more than once, bind it and push data:

```
c d Diagram aspect=2.2 parts=@/graph
d /graph [{"t":"node","x":0.2,"y":0.5,"label":"A"}]
d /graph [{"t":"node","x":0.6,"y":0.5,"label":"A"}]
```

The second line moves the node. One line, no component re-sent.

## Talking to it

The display can listen, on-device, and it is off until you turn it on from the
menu bar. Hold the globe key to talk, or enable a wake word. What it hears goes
back up the socket as an event; `hud listen` is the loop that turns that into a
drawing.

## The wire

Every line is one op, and a line is either complete or invisible, so a
half-written line never draws a half-built panel.

```
@ <surface> [at=region] [w=380] [urgency=alert] [chrome=bare] [life=60]
c <id> <Type> prop=value ...
> <parent> <child> ...
d /pointer <json>
r <id>
- <surface>
p <state> [amp=0.4]
m <id> <x> <y> <w> <h> [label="..."] [tone=bad] [life=30]
u [<id>]
```

Nothing paints until `r`. `c` and `>` may arrive in any order, so a child can be
sent before its parent. Anything the renderer does not recognise is dropped
rather than drawn wrong.

## Building it

```bash
swift build
swift test          # 46 tests
./scripts/bundle.sh # produces build/BobHUD.app
```

macOS 14 or later. No dependencies.

## Design notes

The comments in `Sources/BobHUDKit` explain the reasoning rather than the syntax,
and most of them exist because something was wrong first. A few worth knowing:

- The window ignores mouse events by default and only becomes solid where a
  surface actually is. Returning nil from `hitTest` passes clicks through but not
  scroll, which silently ate every scroll on the display.
- `NSHostingView` is a single `NSView`. SwiftUI creates no child views, so a
  `hitTest` that compares against `self` cannot tell a button from a gap.
- A `Canvas` cannot sample what is behind the window, so anything that needs to
  be glass has to be a real view.
- A `View` may conform to `Animatable`, which is what lets a diagram morph: the
  canvas reads its coordinates out of `animatableData` and redraws along the path
  between two drawings instead of cutting between them.

Part of [Bob the Builder](../README.md).

All glory to God! ✝️❤️
