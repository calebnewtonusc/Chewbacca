---
name: hud
description: Draw live interfaces on the screen over everything else, with no browser and no window. Use when the user asks to see something rather than be told it, says show me, put that on screen, pull up, or asks for a dashboard, chart, diagram, or status display. Also use to update or animate something already on screen, and to take it down when they are done.
license: MIT
requires: [hud]
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
hud demo                   # put one of everything on screen
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

Send `r` as soon as the Screen exists rather than at the end. Children that
arrive after the root still land, so a stream that gets cut off has drawn
something instead of nothing.

```
@ <surface> [at=region] [w=points] [urgency=level] [chrome=kind]
c <id> <Type> prop=value ...
> <parent> <child> ...
d /pointer <json>
r <id>
- <surface>
listen                             ask to receive events on this connection
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

Anything not listed here is dropped silently by the renderer, so the panel will
just be missing that piece and nothing will tell you. Write arrays with no
spaces inside them.

<!-- generated: components -->

### Structure

- **Screen** The root of a surface. Exactly one per surface, and every other component hangs off it. A short title in caps reads best at a glance.

  ```
  c s Screen title="RELATIONSHIPS"
  ```

- **Stack** Groups components. Vertical by default; use grid with cols for several small numbers, because four metrics in a column waste the height of a panel that is already capped. Gap is in units of 4 points.

  ```
  c row Stack direction=grid cols=2 gap=3
  ```

### Prose

- **Heading** A label over a section. Use it when one panel holds two unrelated groups; a panel with one group already has its Screen title.

  ```
  c h Heading text="Needs a reply" level=2
  ```

- **Text** A sentence. Reach for it last: a heads-up display is glanced at, and prose is the thing a glance cannot do. Never use it to describe a chart that is already on the panel.

  ```
  c t Text value="Nothing is overdue." tone=muted
  ```

- **List** Plain bullets. Prefer Events when the items happened at times, and Bars when they have magnitudes worth comparing.

  ```
  c l List items=["Bring the charger","Print the form"]
  ```

### Data

- **Metric** One number that matters. Give it thresholds and it colours itself when the value crosses one, which is the difference between a number read at a glance and a number that has to be read.

  ```
  c m Metric label="Unread" value=12
  ```

  ```
  c o Metric label="Overdue" value=4 thresholds=[{"at":1,"tone":"bad"}]
  ```

- **Table** Rows with several fields each. Use it when the person needs to compare across columns; if there is one number per row, Bars says it faster.

  ```
  c tb Table columns=[{"field":"name","label":"Name"},{"field":"due","label":"Due"}] rows=[{"name":"Origin Story","due":"Sep 9"}]
  ```

- **Status** One line about how something went. For an outcome, not for standing state: a panel that permanently says everything is fine is a panel nobody reads.

  ```
  c st Status message="Deploy finished" level=success
  ```

### Dashboard

- **Sparkline** A trend. Six to thirty points: fewer is noise and more is a smear. Always pass value, because nobody reads an exact number off a 34-point chart, so the drawing carries the shape and the text carries the number.

  ```
  c sp Sparkline label="Messages this week" points=[31,28,44,39,58,52,71] value="71"
  ```

- **Bars** Ranked rows, scaled against the largest rather than against zero, so four values within ten percent of each other still read as different. Horizontal because the labels are words. `display` is what gets printed; `value` only sets the length.

  ```
  c b Bars caption="Time since last reply" rows=[{"label":"Sagar","value":2,"display":"2h"},{"label":"Ava","value":31,"display":"1d"}]
  ```

- **Ring** A proportion, and only ever a proportion: value runs 0 to 1 and the thing must have a real ceiling. A ring around an unbounded number is decoration, and decoration costs the same attention as information while carrying none.

  ```
  c r Ring label="Attendance" value=0.82 caption="82%"
  ```

- **Events** Things that happened or are about to, most recent or soonest first. Set accent on the one that matters; setting it on all of them sets it on none.

  ```
  c e Events caption="Due" items=[{"time":"Sep 9","text":"Origin Story","accent":true}]
  ```

### Anything else

- **Diagram** Reach for this whenever the answer is a shape rather than a number: how things connect, what flows into what, the parts of a system, a hierarchy. Draw it out of nodes and arrows in a unit square where x and y run 0 to 1, and label the nodes. Lay a sequence left to right along y=0.5, and a hierarchy top down from y=0.2, so that two drawings of the same thing come out the same way and somebody can recognise a diagram they have seen before instead of reading it again from scratch. The drawing is the entire answer: do not put a written version of it beside the diagram, because a panel that says the same thing twice has wasted the one glance it gets. Not for anything Bars or Events already says.

  ```
  c d Diagram aspect=2.4 parts=[{"t":"node","x":0.2,"y":0.5,"w":0.22,"h":0.3,"label":"Model"},{"t":"arrow","x":0.32,"y":0.5,"x2":0.68,"y2":0.5},{"t":"node","x":0.8,"y":0.5,"w":0.22,"h":0.3,"label":"Glass"}]
  ```

  ```
  c d2 Diagram aspect=2 parts=[{"t":"node","x":0.5,"y":0.2,"w":0.3,"h":0.24,"label":"Request"},{"t":"arrow","x":0.44,"y":0.32,"x2":0.22,"y2":0.62},{"t":"arrow","x":0.56,"y":0.32,"x2":0.78,"y2":0.62},{"t":"node","x":0.18,"y":0.76,"w":0.28,"h":0.24,"label":"Cache","tone":"good"},{"t":"node","x":0.82,"y":0.76,"w":0.28,"h":0.24,"label":"Model","tone":"warn"}]
  ```

- **File** Shows an actual file: a PDF through the system's PDF engine, an image as an image, anything that decodes as text as text. Use it when the person names a document, instead of describing the document back to them. `editable` on a text file gives a real editor whose save overwrites that exact path.

  ```
  c f File path="~/Downloads/resume.pdf"
  ```

### Controls

- **Button** A press that sends an action back up the socket. Only add one when there is something for it to do; a button nobody is listening for is a promise the panel cannot keep.

  ```
  c go Button label="Send it" action=send variant=primary
  ```

- **Field** A text input bound to a pointer in the panel's own data. It writes locally the moment it is typed in, so it responds at typing speed whether or not anything is still listening.

  ```
  c n Field label="Note" bind=/draft/note
  ```

- **Select** One of a fixed set. Use it wherever the answer is a known list, because a text field that must match one of five strings is a trap.

  ```
  c s Select label="Status" bind=/draft/status options=["Todo","Done"]
  ```

- **Checkbox** A yes or no, bound to a pointer. Use it for a state the person toggles, not for a list of things to tick off: several checkboxes in a row is a form, and a heads-up display is a bad place to fill in a form.

  ```
  c c Checkbox label="Urgent" bind=/draft/urgent
  ```

<!-- /generated -->

## Marking the screen

A panel sits *beside* the work. A mark sits **on** it.

```
m <id> <x> <y> <w> <h> [label="..."] [tone=bad] [life=30]
u [<id>]
```

Coordinates are **points with a top-left origin**, and points are not pixels: a
Retina screenshot reports twice the number you want. Run `hud screen` to get the
size before you place anything.

```bash
hud draw <<'EOF'
m bug 420 260 380 90 label="This is the one failing" tone=bad
EOF
```

Marks decay. The default life is twelve seconds, `life=0` pins one, and re-sending
the same id with a new rectangle moves it rather than leaving a trail. That is
deliberate and it is the rule that makes the layer trustworthy: a mark that
outlives what it described is worse than no mark, because the person learns to
disbelieve all of them.

Twelve marks maximum. Past a dozen the screen is not annotated, it is hatched.

## Panels that take themselves down

`@ toast at=top life=6` closes after six seconds. Use it for something the person
does not need to dismiss: a build finishing, a file saved, a reminder that stops
being true.

Leave `life` off for anything they will read or act on. A panel that vanishes
mid-sentence is a bug they will blame on you.

## Pointing

Holding Option-Command and dragging outlines a region on screen, and the display
sends `g <x> <y> <w> <h>` when it is released. If a request arrives shortly
after, its "this" or "that" means whatever is in that rectangle. `hud listen`
attaches it to the prompt for thirty seconds and then forgets it, because
pointing at something and asking about it a minute later is a coincidence rather
than a reference.

The display sends coordinates, never pixels. Look at the region yourself if you
need to see it.

## Hearing them

The display can listen. It is off until the person turns it on from the menu bar
(hold the globe key to talk, or a wake word), and when it hears something it
sends `h "what they said"` back up the socket.

`hud listen` is the loop: it holds a connection open, and when something is said
it asks a model to answer by drawing. Run it in the background of a session where
you want the screen to be answerable out loud.

Recognition is on-device. Do not add anything that ships audio somewhere.

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

**Get the screen size before placing a mark.** `hud screen`. Coordinates are
points, and a Retina screenshot reports twice that. This is the single easiest
way to put a mark in the wrong place.

**Check `hud status` first** if you have not drawn this session, and `hud open`
if it is not running.
