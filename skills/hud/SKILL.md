---
name: hud
description: Draw live interfaces on the screen over everything else, with no browser and no window. Use when the user asks to see something rather than be told it, says show me, put that on screen, pull up, or asks for a dashboard, chart, diagram, or status display. Also use to update or animate something already on screen, and to take it down when they are done.
license: MIT
---

# The display

The user has a transparent layer over their whole screen that you can draw on.
It is click-through everywhere except where something is drawn, so they keep
working underneath it. Panels stay up after you disconnect, which means you can
change one later instead of drawing it again.

```bash
hud status                 # is it running
hud open                   # start it
hud draw                   # Bob Lines on stdin
hud close <surface>        # take one down
```

Reach for this when the answer is a shape rather than a sentence. "How are my
reply times looking" is a chart. "What is due this week" is a list on the glass,
not four paragraphs in a terminal they have to scroll back to.

Do not reach for it to answer a question that is one sentence long. A panel that
says "yes" is worse than saying yes.

## Drawing

```bash
hud draw <<'EOF'
@ people at=topRight w=400
c s Screen title="RELATIONSHIPS"
c a Sparkline label="Messages this week" points=[31,28,44,39,58,52,71] value="71"
c b Bars caption="Time since last reply" rows=[{"label":"Sagar","value":2,"display":"2h"},{"label":"Ava","value":31,"display":"1d"}]
c e Events caption="Needs a reply" items=[{"time":"9:04","text":"Sagar sent the gates","accent":true}]
> s a b e
r s
EOF
```

Every line is one op. Nothing paints until `r`, and `c` and `>` may arrive in
any order, so a child can be sent before its parent.

```
@ <surface> [at=region] [w=points] [urgency=level] [chrome=kind]
c <id> <Type> prop=value ...
> <parent> <child> ...
d /pointer <json>
r <id>
- <surface>
```

Arrays are JSON and the parser splits on whitespace, so write them with no
spaces inside: `points=[31,28,44]`.

## Where, and how loud

`at=` is a region, never a coordinate: `topLeft top topRight left center right
bottomLeft bottom bottomRight`. Put what they asked about where the eye already
is and standing context in a corner. Two or three panels is a workspace, six is
a mess.

`urgency=` is `ambient`, `normal`, `alert`, or `critical`. Only `critical`
appears when the display is hidden. Spend it on a payment failing or a meeting
starting in one minute, never on a task being due next week.

`chrome=` is `card`, `bare`, or `bracket`. **`bare` draws no panel at all**: the
content floats directly on the screen. It is right for a diagram or a figure and
it is the thing this display can do that a window cannot. `bracket` puts corner
marks around a region without covering it.

## Components

Structure: `Screen title="..."`, `Stack direction=vertical|horizontal|grid gap=2`,
where a grid takes `cols` (1 to 4). Four metrics in a column waste a panel's
height; put them in a grid.

Prose: `Heading text="..." level=2`, `Text value="..." tone=muted`,
`List items=["a","b"] ordered=true`.

Data: `Metric label="..." value=... unit="..."`, which with
`thresholds=[{"at":80,"tone":"warn"}]` colours itself when a value crosses a
line (so does `Ring`),
`Table caption="..." columns=[{"field":"name","label":"Name"}] rows=[...]`,
`Status message="..." level=success|warning|error`.

Dashboard, all taking an optional `tone` of `good`, `warn` or `bad`:

- `Sparkline label="..." points=[...] value="71"` a trend. Six to thirty points.
- `Bars caption="..." rows=[{"label":"West","value":42,"display":"42%"}]` ranked
  rows scaled against the largest. `display` is printed, `value` sets length.
- `Ring label="..." value=0.82 caption="82%"` a proportion only. `value` is 0 to
  1. A ring around an unbounded number is decoration.
- `Events caption="..." items=[{"time":"9:04","text":"...","accent":true}]`

Free-form: `Diagram aspect=2.4 parts=[...]`, where each part is a shape in a unit
square. `node` and `box` take `x y w h label`; `line` and `arrow` take
`x y x2 y2` plus `dashed`; `circle` and `dot` take `x y r`; `label` takes
`x y text size`. Use it for a structure or a flow, not to reimplement `Bars`.

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

Controls are live: `Button label="..." action="..."`, `Field label="..."
bind=/pointer`, `Select`, `Checkbox`. A press writes locally and sends an event
back, so it answers whether or not you are still listening.

## Changing something already up

This is the part worth learning, because it is what makes the display feel alive
rather than like a slideshow.

A surface survives your disconnection. Address it again by name and anything you
leave off is kept:

```bash
hud draw <<'EOF'
@ people
c a Sparkline label="Messages this week" points=[31,28,44,39,58,52,88] value="88"
EOF
```

That surface stays in the top right at 400 points wide. The sparkline **changes**
rather than being replaced, and a `Diagram` whose coordinates changed animates
between the two: nodes travel to their new positions.

For anything that updates more than once, bind it and then push data. The
component goes out once and every update after is a single short line:

```bash
hud draw <<'EOF'
@ live at=center w=620 chrome=bare
c s Screen title="BUILD"
c d Diagram aspect=2.2 parts=@/graph
> s d
d /graph [{"t":"node","x":0.2,"y":0.5,"label":"compile"}]
r s
EOF

# later, one line, no component re-sent
printf 'd /graph [{"t":"node","x":0.5,"y":0.5,"label":"compile"}]\n' | hud draw
```

`@/pointer` is the binding. Re-sending a whole component every tick works, costs
far more, and throws away the animation.

## Rules

**Do not narrate the panel.** If you drew the chart, do not also describe it in
the terminal. Say what you put up and where, in one line.

**Do not open a surface per fact.** Related things belong in one panel.

**Close what you opened.** `hud close <name>` when they are done. The screen is
theirs.

**Do not invent components or props.** Anything not listed here is dropped
silently by the renderer, so the panel will just be missing that piece and
nothing will tell you.

**Set the ring.** `p thinking` when you start something slow and `p dormant`
when you are done. It is the only signal the user has that you are alive.

**Check `hud status` first** if you have not drawn this session, and `hud open`
if it is not running.
