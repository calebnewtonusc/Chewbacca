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
s "<text>" [step=true]                                     say one line on the pill (subtitle); a step is a tool call
w "<text>" [done=true]                                     the written answer, for the conversation panel
q <n>                                                      how many requests are waiting
t "<text>" state=running|waiting|done                      the terminal strip under the pill; `t off` hides it
```

Nothing appears until `r`. Send `c` and `>` in any order: a child may arrive
before its parent.

**Send `r` as soon as the Screen exists, not at the end.** Children that arrive
after the root still land, so a stream that gets cut off has drawn something.
Putting `r` last means a long answer that ran out draws nothing at all.

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

## How a request reaches you

You do not poll. A person asks for something by pressing Option-Space and typing,
by holding the talk key (the globe, or a right-hand modifier chosen from the
menu) and speaking, or by typing into the conversation panel, and the display
sends it up the socket:

```
h "show me my week"
h "show me my week" via=typed
```

`via=typed` means they typed it. Answer a typed request in writing and do not
read it aloud: they chose not to speak, usually because they cannot hear or be
heard where they are.

The talk key itself goes up too, the moment it moves:

```
k down
k up
```

`k down` means they are about to speak. Whatever the voice is saying stops
there, and a run in flight goes quiet for the rest of its answer, which still
reaches the panel. The words that follow as `h` replace that run rather than
wait behind it; a typed request while a run is in flight still queues.

Two quick presses of the talk key are the way out: the display closes the
panel, shuts the microphone, sends `e stop run` for a run in flight and then
`x`, and clears the glass. On `x`, stop talking and show nothing afterwards.

The recogniser is handed the names in `~/.bob/names.txt` (written by `hud
listen` from Messages and Contacts) and `~/.bob/vocabulary.txt` (the person's
own, one word or phrase per line) on every press, so a name is heard as the
name and not the nearest common word. "Sound when heard" in the menu adds a
short tone on release, off by default.

Stay connected to receive it. Answer by drawing, not by writing prose back down
the socket: nothing reads prose there.

What they said is drawn on the pill at the bottom of the screen first, in
quotes, and held there for a second before `h` goes up, so pressing the key
again takes it back instead of sending it. To the person the pill is the
"hyper bar": that is what the voice calls it, and it is where a long answer
is said to be.

The pill is also where you speak. `s "<text>"` puts one line under the panels:
a breadcrumb while you work, the answer when you are done.

```
s "Reading your calendar"
s "Friday 3pm is free. Sagar has been texted."
```

A spoken reply is one to two sentences and at most 140 characters, because the
pill holds two lines of 13 point text at 440 points wide and a panel has less
room than an ear. Lead with the answer; the panel carries the rest. `q <n>` is
how many requests are waiting behind the one in flight, shown as a badge on the
pill, and `q 0` clears it.

The rest of a full answer goes to the conversation panel, which the pill opens
when clicked: every request and every answer of the session, selectable, with a
field to type the next request. A long answer, a summary or a recap, is not
read aloud at all: the voice says one line, "All the info on the Civil War is
ready for you in the hyper bar", and the answer is written here for reading.
The voice knows the person: `hud-listen` appends a digest of the second brain
to its prompt before every run, and keeps every question and answer in
`superassistant/questions.jsonl` (see `superassistant/README.md`).
The panel's header has the switch for that, "Speech off for long answers", on
by default; off, every answer is read out in full. The display sends it to
whoever is listening as `e prefer voice long=written|spoken`, on every change
and again right after a client's `listen`. `w "<text>"` is the answer so far, the whole
text rather than a delta, and `w "<text>" done=true` closes it. Send it at each
sentence as the answer is written, so the panel fills as the voice reads. Prose
with Markdown: paragraphs, headings, bullet and numbered lists, quotes, rules,
pipe tables, and fenced code with its language and a copy button.

`s "<text>" step=true` is a tool call in words. It goes on the pill like any
`s`, and the panel keeps it on the open answer: the live line under the answer
while it is being done, with the clock, and afterwards a folded list of what
was done and how long it took. A plain `s` is a line of the answer and is not
kept, because the answer's text is already there.

Each answer in the panel has copy, read aloud and ask-again buttons; a request
has edit and copy. Read aloud goes up the socket as
`e say turn text="<answer>"`, for whoever owns the voice to speak.

## Pointing

Holding Option-Command and dragging outlines a region, and on release the
display sends its coordinates up the socket:

```
g 420 260 380 90
```

That is deixis, and it is what makes a fragment work. "Why is this failing" while
pointing at a stack trace carries more precise context than a paragraph of
typing. When a request arrives shortly after a region, the two belong together
and the request's "this" means whatever is in that rectangle.

The display sends coordinates, not pixels. It has no screen recording permission
and asking for one so it can crop a rectangle it already knows the bounds of
would be a poor trade. Look at the region yourself if you need to see it.

## Finding out when you got it wrong

Send `listen` and the display talks back. It answers with its version
immediately, and after that anything you send that it could not use comes back
as a problem:

```
v! "bobhud/1 verbs=c,>,d,r,@,-,p,s,q,m,u,b,listen"
! "`c` needs an id and a type"
```

Without subscribing you get silence, and silence means nothing at all: a
misspelled component and a perfect one look identical. If you are writing
something new, subscribe while you develop it.

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

## Dictation

Hold Control, then the talk key, and talk: the words are typed at the caret of
whatever app is in front, as they are spoken. A word goes in once it has
survived one revision of the recogniser, so the text does not shiver. On
release a local whisper.cpp server (`~/.bob/whisper/`, 127.0.0.1:8178, started
by the display at launch) reads the whole sentence again with the person's
vocabulary as its prompt and corrects it in place, but only if the same app is
still in front and no key has been pressed since.

Nothing about it goes up the socket and no model reads it: the talk key without
Control asks the assistant, and with Control it types. Do not draw anything for
it and do not type on the person's behalf.

It needs macOS Accessibility for BobHUD, to post key events. A rebuild can leave
that switch on and the app untrusted, because macOS stores a code requirement
and an ad-hoc signature names only the binary's hash; that happened on
2026-09-21 (granted at 05:13:59, rebuilt at 13:40:12). `bin/lib/axgrant.py`
names that state and `hud/scripts/signing-identity.sh` ends it by signing with a
certificate that outlives the build. `dictation` and `whisper` lines in
`log show --predicate 'subsystem == "bob.hud"'` say what each turn did.

## Guiding a person

A mark says "look at this" to somebody who knows the screen. A guide says
"press this" to somebody who does not: a ring around the control, a bubble
that says what to do in words, and a slow pulse so the eye finds it.

```
m guide 724 70 30 30 label="Click Sign in" tone=guide life=120
```

`tone=guide` is the whole difference. A guide is the one mark that answers a
click: when the person presses inside its rectangle, or on the ring around it,
the display takes it down and sends

```
e hit guide label="Click Sign in"
```

so whoever is guiding can look at the screen again and show the next step.
Nothing on the glass takes the click itself; it reaches the app underneath as
it always did.

`bin/hud-guide` does the finding: `hud-guide list` reads the front window's
controls through the accessibility tree, `find "sign in"` matches by name,
`show elem_12 --say "Click Sign in"` sends the line above, `clear` takes it
down. One bubble at a time, by design: re-sending `guide` moves it, and a
person following along wants the next step, not a trail. The voice's rules
for guiding, one step, their words, their hands, are in `bin/hud-agent.md`
under "Showing them where".

## Playing music

"Play Blinding Lights", "play some Drake", "pause", "skip", "what's playing",
"turn it up": the bridge reads these itself and drives the player, so nothing
waits on the model. `bin/hud-music` is the same code as a command:

```bash
hud-music play "fred again"      # Spotify by name, or YouTube audio without keys
hud-music pause | resume | next | previous | again | stop | shuffle
hud-music volume up              # or down, or a number
hud-music now                    # what is on, in a sentence
hud-music status                 # which players are ready, and why not
```

Spotify plays whatever its own search puts at the top for the words, misheard
or not: a headless browser (`pip3 install playwright && playwright install
chromium-headless-shell`, once) reads the top result off Spotify's web player,
about 1.5 s, and the desktop app plays it. With keys in `~/.bob/spotify.json`
(`hud-music setup`, a free developer app's client id and secret) it is one
API search instead. Without either, Deezer, Wikidata, MusicBrainz and
Spotify's public embed pages find the URI for anything well known, and a
guess they are not sure of goes to the model, which works out the name and
plays it with `hud-music play --anyway`.
"On YouTube" plays the first result through `ffplay` with no window, a few
seconds in, and so does any request when Spotify is not installed. "Stop" on
its own pauses the music when the voice is idle; "stop the music" always does.

## Panels that take themselves down

`@ toast at=top life=6` closes after six seconds. Use it for something the person
does not need to dismiss: a build finishing, a file saved, a reminder that stops
being true.

Leave `life` off for anything they will read or act on. A panel that vanishes
mid-sentence is a bug they will blame on you.

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

You can only draw these. There is no HTML and no styling prop, and anything not
listed here is dropped silently by the renderer, so a panel using it is simply
missing that piece and nothing tells you.

Props are JSON and the parser splits on whitespace, so write arrays with no
spaces inside them: `points=[31,28,44]`, not `points=[31, 28, 44]`.

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
