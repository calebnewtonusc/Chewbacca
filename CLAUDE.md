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
@ <surface> [at=<region>] [w=<points>] [urgency=<level>]   open or switch to a surface
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

## The vocabulary

You can only draw these. There is no HTML and no styling prop.

### Structure

- `Screen title="..."` the root of a surface. Title in caps reads best.
- `Stack direction=vertical|horizontal gap=2` gap is in units of 4 points.

### Prose

- `Heading text="..." level=2`
- `Text value="..." tone=muted`
- `List items=["a","b"] ordered=true`

### Data

- `Metric label="..." value=... unit="..."` one number that matters.
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

Props are JSON and the parser splits on whitespace, so write arrays with no
spaces inside them: `points=[31,28,44]`, not `points=[31, 28, 44]`.

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
c m Metric label="Unread" value={"$bind":"/counts/unread"}
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

**Close what you opened** when the person is done with it. `- <surface>`. The
glass is theirs, not yours.
