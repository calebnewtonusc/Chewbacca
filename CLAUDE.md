# Drawing on the screen

You are talking to a heads-up display: one transparent, click-through layer over
everything the person is already doing. You write lines to a Unix socket and
they appear as native panels. There is no browser and no page.

```bash
printf '@ notes at=topRight\nc s Screen title="HELLO"\nr s\n' | nc -U ~/.bob/hud.sock
```

Every line is one op. A line is either complete or invisible, so a half-written
line never draws a half-built panel.

```
@ <surface> [at=<region>] [w=<points>] [urgency=<level>] [chrome=<kind>]
                                                           open or switch to a surface
c <id> <Type> prop=value ...                               create a component
> <parent> <child> <child> ...                             attach children
d /pointer <json>                                          set data
r <id>                                                     name the root, which paints
- <surface>                                                close a surface
```

Nothing appears until `r`. Send `c` and `>` in any order: a child may arrive
before its parent.

## Where things go

`at=` takes a region, never coordinates, because you do not know the size of the
display. `topLeft top topRight left center right bottomLeft bottom bottomRight`.

Several surfaces can be open at once and that is the normal case. Put the thing
being asked about where the eye already is and the standing context in a corner.
Two or three panels is a workspace; six is a mess.

## How loud to be

`urgency=` is `ambient`, `normal` (the default), `alert`, or `critical`.

Only `critical` appears when the person has hidden the HUD, and it defaults to
the centre of the screen. Spend it on something that is genuinely worth
overriding a person who asked for quiet: a payment failing, a deploy breaking,
a meeting starting in one minute. A system that cries wolf gets switched off.

## How much of a window to be

`chrome=` is `card` (the default), `bare`, or `bracket`.

`bare` draws no panel at all. The content sits directly on the screen with a
halo behind it, which is what a heads-up display is actually for and what a
window can never do. Use it for a diagram, a figure, a single line of status.
`bracket` puts four corner marks around a region without covering it.

## Saying it again

A surface stays on the glass after you disconnect, and re-addressing it by name
updates it in place. Anything you leave off is kept:

```
@ notes at=bottomLeft chrome=bare    first time: places it, no panel
@ notes                              later: still bottom left, still bare
```

This is what makes a follow-up work. Send a `c` for a component id that is
already on screen and it changes rather than being replaced, and a `Diagram`
whose coordinates changed **animates between the two**: nodes travel to their
new positions, they do not cut. So "put the socket underneath instead" is one
more `c d Diagram` with different numbers, not a redraw.

Take something down with `- <surface>` when the person is done with it.

## Updating in real time

Bind a prop to the data model and then push data at it. This is the cheap path
and the one to use for anything that changes more than once: the component is
sent once, and every update after that is a single short line.

```
c d Diagram aspect=2.4 parts=@/graph
d /graph [{"t":"node","x":0.2,"y":0.5,"label":"A"}]
d /graph [{"t":"node","x":0.2,"y":0.2,"label":"A"}]
```

The second `d` moves the node. It does not redraw it. The same works for a
`Sparkline`'s points, a `Bars`'s rows, a `Table`'s rows, or any single value:

```
c m Metric label="Unread" value=@/counts/unread
d /counts/unread 12
```

`@/pointer` is the binding. `{"$bind":"/pointer"}` is accepted as well, but the
short form is a third of the tokens and harder to get wrong.

A stream of `d` lines is how a panel tracks something live. Re-sending the whole
component on every tick works and is the wrong instinct: it costs far more
tokens and it throws away the animation.

## The vocabulary

You can only draw these. There is no HTML and no styling prop.

### Structure

- `Screen title="..."` the root of a surface. Title in caps reads best.
- `Stack direction=vertical|horizontal|grid gap=2` gap is in units of 4 points.
  A grid takes `cols` (1 to 4). Four metrics in a column waste the height of a
  panel that is already capped; put them in a grid.

### Prose

- `Heading text="..." level=2`
- `Text value="..." tone=muted`
- `List items=["a","b"] ordered=true`

### Data

- `Metric label="..." value=... unit="..."` one number that matters.
  Takes `thresholds=[{"at":80,"tone":"warn"},{"at":95,"tone":"bad"}]`, and so
  does `Ring`. The last crossed one wins. A number that turns amber on its own
  is read at a glance; a number that is always cyan has to be read.
- `Table caption="..." columns=[{"field":"name","label":"Name"}] rows=[...]`
- `Status message="..." level=success|warning|error`

### Dashboard

Every one of these takes an optional `tone` of `good`, `warn`, or `bad`. Leave it
off and it draws in the house cyan. Do not colour panels for variety: a
dashboard where each chart picked its own colour is harder to read than one
drawn entirely in one, and a person scanning it should be able to assume colour
means something.

- `Sparkline label="..." points=[1,2,3] value="71"` a trend. `value` is written
  out in plain type because nobody reads an exact number off a 34-point chart.
  Six to thirty points. Fewer is noise, more is a smear.
- `Bars caption="..." rows=[{"label":"West","value":42,"display":"42%"}]`
  ranked rows, scaled against the largest, not against zero. `display` is what
  gets printed; `value` only sets the length.
- `Ring label="..." value=0.82 caption="82%"` a proportion, and only ever a
  proportion. `value` is 0 to 1. A ring around an unbounded number is
  decoration, and decoration costs the same attention as information.
- `Events caption="..." items=[{"time":"9:04","text":"...","accent":true}]`
  things that happened, most recent first. `accent` marks the one that matters.
  Plain strings are accepted for events with no timestamp.

### Anything else

- `Diagram aspect=2.4 parts=[...]` free-form drawing. Every part is a shape in a
  unit square, so `x` and `y` run 0 to 1 and you never think about pixels.
  `aspect` is width over height.

  | `t`      | fields                                        |
  | -------- | --------------------------------------------- |
  | `node`   | `x` `y` `w` `h` `label`, a labelled box       |
  | `box`    | same, unlabelled                              |
  | `line`   | `x` `y` `x2` `y2`, plus `dashed`              |
  | `arrow`  | same, with a head at `x2,y2`                  |
  | `circle` | `x` `y` `r`, plus `fill`                      |
  | `dot`    | `x` `y` `r`                                   |
  | `label`  | `x` `y` `text` `size`, on its own plate       |

  Every part takes `tone`. Coordinates animate between sends, so changing the
  numbers moves the drawing rather than replacing it.

  This is the escape hatch, and it is geometry rather than code on purpose:
  nothing in a diagram can execute, fetch, or escape. Use it for a structure, a
  flow, a relationship, a layout. Do not use it to reimplement `Bars`.

Props are JSON and the parser splits on whitespace, so write arrays with no
spaces inside them: `points=[31,28,44]`, not `points=[31, 28, 44]`.

### Files

- `File path="~/Downloads/resume.pdf" [page=2] [editable=true]`

  Shows the actual file. PDFs render through the system's own PDF engine,
  images as images, and anything that decodes as text as text. `editable=true`
  on a text file gives a real editor with a save button, and saving overwrites
  that exact path and no other.

  This is the answer to "let's work on my resume, the PDF is in my downloads".
  Put it on screen rather than describing it back to them.

### Presence

```
p thinking
p hearing amp=0.4
p dormant
```

`p` sets the ring in the bottom right corner, which is the one thing always on
the glass. States are `dormant`, `attentive`, `hearing`, `thinking`, `acting`,
`attention`, and `failed`. Each has its own motion, so it is readable without
being looked at.

Set `thinking` when you start work and `dormant` when you finish. A ring left
spinning is worse than no ring: it demotes itself to `attention` after eight
seconds rather than spinning forever, and that is a report of your bug, not a
feature to rely on.

`failed` is the only state that is ever red, and it means an action failed in a
way that may have left something in a bad state. Not "the search returned
nothing".

### Controls

These are live, not pictures. A press writes to the panel's own data model at
once and sends an event back up the socket, so it responds whether or not you
are still listening.

- `Button label="..." action="..." variant=primary`
- `Field label="..." bind=/pointer placeholder="..."`
- `Select label="..." bind=/pointer options=["a","b"]`
- `Checkbox label="..." bind=/pointer`

## Binding

A prop can read from the data model instead of carrying a literal, which is what
lets a number update without rebuilding the component around it.

```
c m Metric label="Unread" value=@/counts/unread
d /counts/unread 12
```

`$count`, `$sum` and `$avg` compute over an array at render time.

## A dashboard

```
@ people at=topRight w=400
c s Screen title="RELATIONSHIPS"
c a Sparkline label="Messages this week" points=[31,28,44,39,58,52,71] value="71"
c b Bars caption="Time since last reply" rows=[{"label":"Sagar","value":2,"display":"2h"},{"label":"Ava","value":31,"display":"1d"}]
c e Events caption="Needs a reply" items=[{"time":"9:04","text":"Sagar sent the gates","accent":true}]
> s a b e
r s
```

## What not to do

**Do not restate the answer in prose above the chart.** The panel is glanced at.
If the sparkline says it, the sentence is noise.

**Do not open a surface per fact.** Related things belong in one panel. Six
panels holding one number each is the failure mode this format makes easy.

**Do not use `Ring` for a number without a ceiling**, or `Sparkline` for
categories. A trend line over four regions is a lie about the data.

**Do not invent components or props.** Anything not on this page is dropped
silently by the renderer, so the panel will simply be missing that piece and you
will not be told.

**Do not redraw when you can change.** Re-send the component with new values and
it moves. Tearing a surface down and rebuilding it throws away the animation and
makes the screen flicker for no reason.

**Close what you opened** when the person is done with it. `- <surface>`. The
glass is theirs, not yours.
