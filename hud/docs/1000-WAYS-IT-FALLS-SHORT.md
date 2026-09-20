# 1000 ways this generative UI is not yet useful

Written against the working build, not against an idea of it. Everything below
is a thing you cannot do, a thing that is wrong, or a thing that is right by
accident. Nothing here is padding: where a limit is deliberate, it is marked
**(on purpose)** and the reason is given, because a list that cannot tell a
decision from a defect is not an audit.

**Status:** 38 fixed so far, struck through and marked in place. The three
called out as mattering most, accessibility, the transcript privacy hole, and
never speaking first, are done. What remains is listed honestly rather than
quietly closed.

What is left is filed as work rather than left as a list:
[the backlog](BACKLOG.md), and in `bd` at `~/Desktop/2026-Code/.beads`.

The point of writing it down is that a HUD fails quietly. It draws something,
you glance at it, and you never find out what it left out.

---

## 1. Text and typography (1-40)

1. There is no rich text anywhere. A `Text` is one weight, one size, one colour.
2. No bold inside a sentence.
3. No italics.
4. No underline.
5. No strikethrough, so nothing can show a completed or superseded item inline.
6. No inline code style, so a filename in a sentence looks like prose.
7. No links. Nothing on the glass can be clicked through to a source.
8. No footnotes or references.
9. Font size is hard-coded per component; a model cannot ask for bigger.
10. No Dynamic Type support, so system text-size settings are ignored entirely.
11. Someone who needs 20pt text cannot read any of it.
12. Line height is fixed and cannot breathe for dense content.
13. No hyphenation control, so long words break badly at narrow widths.
14. No text alignment control beyond the leading default.
15. No centred text, which a title sometimes wants.
16. No right alignment for numeric columns outside `Table`.
17. Monospaced type is available only inside `File`, not as a `Text` option.
18. No superscript or subscript, so units and footnote markers read wrong.
19. No small caps, though the design leans on caps titles.
20. Letter spacing is fixed at one hand-tuned value per component.
21. No control over truncation: some components clip, some wrap, inconsistently.
22. A `Heading` supports two levels and silently treats everything else as level 2.
23. There is no paragraph spacing control.
24. No lists with custom markers.
25. `List` cannot nest.
26. `List` items cannot themselves be components.
27. No blockquote treatment.
28. No horizontal rule.
29. No text selection on most surfaces, so you cannot copy what you are reading.
30. Copying is only possible from `File` in read mode.
31. No find-in-surface.
32. Emoji render at the system default and break the vertical rhythm.
33. No control over numeral style; tabular figures are on in some places, not others.
34. Currency is never formatted; a model must pass a pre-formatted string.
35. Dates are never formatted; same problem.
36. No relative time ("2h ago") except when a model writes the string itself.
37. Nothing pluralises. "1 items" is possible and nothing prevents it.
38. No text direction handling at all.
39. Long single-word strings can overflow a card horizontally with no ellipsis.
40. Text colour cannot be set per run, only per component.

## 2. Layout (41-85)

41. There are exactly two containers: `Stack` and `Screen`.
42. A grid takes a fixed column count and cannot be responsive.
43. Grid columns are always equal width.
44. No column spanning: a wide item cannot take two cells.
45. No row spanning.
46. No alignment control within a stack beyond the default.
47. No distribution control (space-between, space-around).
48. No spacers, so you cannot push one item to the far edge.
49. No dividers or separators as a component.
50. No padding control on any component.
51. No margin control.
52. `gap` is the only spacing lever and it is in units of 4 points.
53. No nesting limits are enforced, so a deep tree can lay out into nothing.
54. No `maxWidth` or `minWidth` on children.
55. No aspect-ratio control except on `Diagram`.
56. No absolute positioning inside a surface.
57. No overlap or z-ordering inside a surface.
58. No sticky headers in a long surface.
59. Scrolling only appears when content exceeds the height cap, and cannot be asked for.
60. A scrolling surface has no visible scrollbar, so there is no cue that more exists.
61. No horizontal scrolling anywhere, so a wide table is simply cut.
62. `Table` has no minimum column width, so a narrow surface crushes it.
63. Surface width is a single number; there is no auto-sizing to content.
64. Surface height is capped at the screen and cannot be set explicitly.
65. The height cap is computed once at open and does not react to a resolution change.
66. Regions are nine fixed positions; there is nothing between them.
67. No percentage or coordinate placement for surfaces.
68. Two surfaces in the same region stack downward and cannot be arranged otherwise.
69. Stacking order within a region is by arrival, not by importance.
70. A surface cannot be pinned above another.
71. There is no way to group surfaces so they move together.
72. No tabs, so related panels must be separate surfaces or one long one.
73. No collapsing or expanding sections.
74. No accordion.
75. Nothing can be minimised to a title bar.
76. The twelve-surface cap is arbitrary and evicts the oldest without warning.
77. Eviction is silent: nothing tells you a panel was dropped.
78. Dragging a surface is not persisted; it returns on the next open.
79. There is no snapping when dragging.
80. Surfaces can be dragged off-screen and there is no way to recall them except clearing.
81. Surfaces cannot be resized by hand at all.
82. There is no way to reset a surface's position without closing it.
83. The layout does not react to the Dock being hidden or moved mid-session.
84. Menu bar height is assumed from the visible frame and not re-read.
85. Nothing reflows when a surface's content grows; the panel jumps.

## 3. Charts that do not exist (86-130)

86. No line chart with more than one series.
87. No axes, ever, even when a reader genuinely needs to read a value **(on purpose: a HUD is glanced at, and the number is printed beside the shape. It is still a limit.)**
88. No gridlines.
89. No tick labels.
90. No legends, so a multi-series chart is impossible by construction.
91. No scatter plot.
92. No bubble chart.
93. No stacked bars.
94. No grouped bars.
95. No diverging bars, so nothing can show above and below a baseline.
96. No negative values in `Bars` at all; a negative scales to a strange length.
97. No histogram.
98. No box plot.
99. No candlestick.
100. No area chart distinct from `Sparkline`.
101. No step chart.
102. No pie chart **(on purpose: a pie is worse than bars at every size, and worst at this one.)**
103. No donut with multiple segments; `Ring` is one value only.
104. No gauge with a needle.
105. No heatmap.
106. No calendar heatmap.
107. No treemap.
108. No sunburst.
109. No Sankey.
110. No chord diagram.
111. No network or force graph.
112. No map of any kind.
113. No geographic anything.
114. No timeline with a real time axis; `Events` is an ordered list.
115. No Gantt.
116. No burndown.
117. No waterfall.
118. No funnel.
119. No radar or spider.
120. No parallel coordinates.
121. No violin plot.
122. No error bars.
123. No confidence bands.
124. No trend line or regression overlay.
125. No moving average.
126. No annotations on a chart (a marker at a date, a threshold line).
127. No reference line, even though thresholds exist for colour.
128. No target or goal indicator.
129. No sparkline variants (win/loss, bar sparkline).
130. No small multiples.

## 4. Charts that exist but are thin (131-175)

131. `Sparkline` takes bare numbers with no timestamps, so gaps in time are invisible.
132. A weekend and a weekday are the same width in a `Sparkline`.
133. Missing data cannot be expressed; there is no null in the points array.
134. A flat series is drawn at mid-height by a special case, which is honest but silent.
135. `Sparkline` has no minimum or maximum labels.
136. No indication of the range being shown.
137. The `value` label is whatever string the model passes; nothing checks it matches the data.
138. A model can pass points that contradict the printed value and nothing notices.
139. `Bars` scales to the largest bar, so the absolute magnitude is invisible.
140. `Bars` has no axis, so two `Bars` on one panel are not comparable to each other.
141. `Bars` cannot sort itself; order is whatever arrives.
142. No "other" bucket for a long tail.
143. No limit on row count, so forty rows render forty tiny rows.
144. `Bars` labels truncate with no tooltip to recover them.
145. `Ring` shows one value and cannot show progress against a changing target.
146. `Ring` has no tick marks.
147. `Ring` cannot show over-100% (a value above 1 clamps silently).
148. `Ring` colour does not change with thresholds unless thresholds are given.
149. `Metric` has no delta or change indicator, despite that being the most common need.
150. `Metric` has no sparkline beside it.
151. `Metric` cannot show a target.
152. `Metric` units are a separate string with no formatting logic.
153. `Metric` thresholds only support ascending crossings; nothing handles "below X is bad".
154. Thresholds cannot colour a background, only the number.
155. `Table` cannot sort.
156. `Table` cannot filter.
157. `Table` cannot paginate.
158. `Table` has no row limit, so a hundred rows overflow the height cap and scroll invisibly.
159. `Table` cells cannot be formatted, coloured, or aligned per column.
160. `Table` has no totals row.
161. `Table` cannot highlight a row.
162. `Table` columns cannot be hidden.
163. `Table` has no zebra striping or row hover.
164. `Events` cannot group by day.
165. `Events` has no relative time; the model writes the string.
166. `Events` cannot collapse a long list.
167. `Events` `accent` is boolean, so there is one level of emphasis and no more.
168. `Events` cannot show duration, only an instant.
169. `Status` has three levels and no fourth for "in progress".
170. `Status` cannot carry an action.
171. Nothing supports a loading state distinct from empty.
172. Nothing supports an empty state with an explanation.
173. An empty `Bars` or `Events` renders as nothing, not as "none".
174. No component can say "this data is stale, last read at X".
175. No component shows its own provenance.

## 5. Diagrams (176-225)

176. ~~Coordinates outside 0 to 1 are drawn off-canvas and silently vanish; the model does this.~~ **FIXED** (clamped to the unit square)
177. ~~Nothing clamps or warns on out-of-range coordinates.~~ **FIXED** (clamped rather than dropped)
178. No curved edges; every line is straight.
179. No bezier or spline routing.
180. No orthogonal or elbow routing, so a dense graph is a bowl of spaghetti.
181. No automatic layout at all; the model computes every coordinate by hand.
182. There is no force-directed, hierarchical, or layered layout to fall back on.
183. Overlapping nodes are the model's problem and it gets them wrong regularly.
184. Edges do not attach to node borders; they end wherever the coordinates say.
185. An arrow can end inside a node and look like it stopped short.
186. No edge labels except a free `label` positioned by hand.
187. An edge label does not move when the edge does.
188. No self-loops.
189. No multi-edges between the same pair.
190. No directed-both arrows.
191. Arrowheads are a fixed size regardless of stroke width or scale.
192. No arrowhead styles (open, diamond, circle).
193. No dashed styles beyond one dash pattern.
194. No line caps or joins control.
195. Node labels do not wrap; a long one overflows its box.
196. Node labels do not shrink to fit.
197. Node size is given, not computed from the label.
198. No node icons or images.
199. No node shapes beyond a rounded rectangle and a circle.
200. No diamond, hexagon, cylinder, or any flowchart vocabulary.
201. No grouping or subgraph boxes.
202. No swimlanes.
203. No nesting: a node cannot contain a diagram.
204. Diagrams are not interactive; you cannot click a node.
205. Diagrams cannot report which node was clicked.
206. No hover states.
207. No tooltips.
208. No zoom or pan.
209. A large diagram simply gets smaller until it is unreadable.
210. No minimum legible size guard.
211. The 400-part cap is silent: part 401 disappears with no warning.
212. No text in a diagram can be selected or copied.
213. Diagram colours are limited to the four tones.
214. No gradient fills.
215. No opacity control per part.
216. No layering control; parts draw in array order and that is the only lever.
217. Morphing pairs parts by index, so inserting one at the front makes everything animate to the wrong place.
218. There is no stable identity for a part across updates.
219. A changed part count animates from padded zeros, which can look like a part flying in from the corner.
220. No animation control: duration and curve are fixed.
221. No way to disable the morph for a diagram that should just cut.
222. No stagger or sequencing of an entrance.
223. Nothing can be drawn progressively (a line that traces itself).
224. The bloom pass doubles the draw cost of every stroke and cannot be turned off.
225. No export: you cannot get a diagram out as SVG or an image.

## 6. Files (226-270)

226. `File` takes a path and nothing else; there is no way to show a buffer you already have.
227. No way to show a remote file or a URL.
228. PDFs have no page navigation control; `page` is set once by the model.
229. No page number display, so you cannot tell where you are.
230. No PDF search.
231. No PDF text selection.
232. No PDF annotation.
233. No PDF thumbnails or outline.
234. Images cannot be zoomed.
235. Images cannot be panned.
236. No image rotation.
237. No EXIF or metadata display.
238. Animated GIFs do not animate.
239. No video support at all.
240. No audio support.
241. Text files get no syntax highlighting.
242. No line numbers.
243. No word wrap toggle.
244. Markdown is shown as raw text, not rendered, which for a notes-heavy user is the common case.
245. CSV is shown as raw text rather than as a `Table`.
246. JSON is not pretty-printed or folded.
247. The 8MB cap is silent past the message; there is no partial load.
248. No streaming or tailing of a growing file.
249. No file watching: an edited file does not refresh on screen.
250. Editing has no undo or redo.
251. Editing has no find and replace.
252. No autosave; an unsaved edit is lost when the surface closes.
253. Closing a surface with unsaved edits warns nobody.
254. Save has no conflict detection: if the file changed on disk, your version wins silently.
255. Save has no backup of the previous contents.
256. Save is all-or-nothing with no diff shown.
257. The editor is a plain `TextEditor` with no code affordances.
258. No tab or indent handling.
259. No bracket matching.
260. Encoding is assumed UTF-8; anything else falls through to "not text".
261. Line endings are not normalised or reported.
262. A file with no read permission reports "not on disk", which is wrong and misleading.
263. A directory path reports "not on disk" rather than offering a listing.
264. Symlinks are followed with no indication.
265. `~` is expanded but no other shell syntax is, and nothing says so.
266. Relative paths resolve against the app's working directory, which is not the user's.
267. No recent-files or reopen.
268. Two `File` components pointed at the same path do not share state.
269. There is no indication a file is being edited elsewhere.
270. No way to save-as or export to a new path.

## 7. Controls and input (271-320)

271. There are four controls: button, field, select, checkbox. That is the whole vocabulary.
272. No multi-line text area.
273. No number input with steppers.
274. No slider.
275. No date picker.
276. No time picker.
277. No colour picker.
278. No file picker.
279. No radio group; `Select` is the only single-choice control.
280. No multi-select.
281. No combo box with typeahead.
282. No search field with results.
283. No toggle switch distinct from a checkbox.
284. No segmented control.
285. No stepper.
286. No rating input.
287. No tag or token input.
288. `Field` has no validation.
289. `Field` has no input mask or format hint.
290. `Field` has no character count or limit.
291. `Field` cannot be marked required.
292. `Field` has no error state.
293. Nothing shows a validation message.
294. `Select` options are strings only; no value/label distinction.
295. `Select` cannot be searched.
296. `Select` cannot group options.
297. `Select` cannot be disabled.
298. No control can be disabled or read-only.
299. No control has a loading state.
300. `Button` has one variant beyond default and no destructive style.
301. `Button` cannot show a spinner while its action runs.
302. `Button` gives no feedback that its action was received.
303. Actions are fire-and-forget; nothing can report success or failure back to the button.
304. There is no confirmation for a destructive action.
305. No undo for anything a control does.
306. No form concept: controls are independent and nothing validates them together.
307. No submit-on-enter across a group.
308. No tab order between controls.
309. Keyboard focus is not visible on most controls.
310. You cannot reach a control by keyboard from outside the surface.
311. There is no keyboard shortcut to focus a surface.
312. Nothing supports drag and drop.
313. Nothing accepts a pasted image or file.
314. No right-click or context menu anywhere.
315. No double-click behaviour.
316. No gestures beyond drag-to-move.
317. No pinch or scroll-to-zoom on anything.
318. Controls write locally then emit; if nobody is listening the local write is a lie that looks like success.
319. There is no way to make a control read-only until an agent confirms.
320. Nothing debounces: typing in a bound `Field` emits an event per keystroke.

## 8. Interaction and behaviour (321-365)

321. A surface cannot be scrolled unless the pointer is over it, because the glass is click-through elsewhere.
322. The pointer-tracking that enables that runs on every mouse move for the whole session.
323. There is no way to make a surface permanently interactive.
324. There is no way to make one permanently inert.
325. Clicking the glass does not bring the app forward, which is right, but means keyboard input never reaches a surface unless it takes focus.
326. A text field in a surface steals the caret from the app underneath when clicked.
327. There is no way to type into a surface without losing your place in the app below.
328. Escape clears everything, with no undo and no confirmation.
329. Escape is a global monitor, so it fires from any app and cannot be scoped.
330. There is no per-surface dismiss keyboard shortcut.
331. The close button appears only on hover, so a trackpad user must find it.
332. There is no keyboard way to close one surface.
333. Dragging is the only positioning gesture and it has no modifier for constrained movement.
334. There is no way to bring a specific surface to the front by keyboard.
335. Surfaces do not respond to the app underneath moving or resizing.
336. Nothing anchors to a window, so a "note on this document" moves when the document does not.
337. No accessibility-tree anchoring, so markers are absolute and go stale immediately.
338. A marker does not follow a scrolling document.
339. A marker does not disappear when the thing it marked goes away.
340. Marker decay is time-based, which is a proxy for relevance and often wrong.
341. There is no way to pin a marker to a window rather than the screen.
342. The reticle captures coordinates only; nothing identifies what is under them.
343. The reticle cannot select an element, only a rectangle.
344. Pointing at something gives no visual confirmation of what was understood.
345. There is no hover-to-identify mode.
346. Nothing highlights on hover.
347. There are no tooltips anywhere in the system.
348. There is no help or discoverability surface; the vocabulary lives in a file.
349. Nothing tells a new user the hotkeys exist.
350. The menu bar item is the only affordance and it is easy to miss.
351. There is no onboarding of any kind.
352. There is no settings UI; everything is a constant in source.
353. You cannot change the accent colour.
354. You cannot change the corner radius or density.
355. You cannot change where the ring lives.
356. You cannot change the hotkeys.
357. Option-Space may collide with an existing shortcut and there is no way to move it.
358. There is no conflict detection for hotkeys.
359. Holding the globe key is the only push-to-talk and it cannot be rebound.
360. Nothing indicates the display is running except the menu bar item.
361. There is no sound, ever, for anything.
362. There is no haptic feedback.
363. There is no notification integration.
364. Nothing reaches you when the display is hidden except a `critical` surface.
365. `critical` is honoured only at draw time; a surface that becomes critical later does not resurface.

## 9. State, data, and bindings (366-415)

366. The data model is a single JSON object per surface with no schema.
367. Nothing validates a bound value's type against what the component expects.
368. A string bound into `Sparkline`'s points renders nothing and reports nothing.
369. `$count`, `$sum` and `$avg` are the entire expression language.
370. No filtering in a computed value beyond one equality.
371. No arithmetic between two pointers.
372. No formatting in a computed value.
373. No conditional rendering: a component cannot appear only when a value is set.
374. No `if` or `unless` at all.
375. No loops: a model must emit one component per row by hand.
376. A ten-row list is ten `c` lines, which is the single biggest token cost in practice.
377. No templates or repeaters.
378. No component reuse; the same shape must be re-declared each time.
379. Data updates replace whole values; there is no array append.
380. There is no way to push one row onto a table without resending all rows.
381. No patch semantics beyond setting a pointer.
382. No transactional update: a multi-line change paints intermediate states.
383. No batching, so a stream of `d` lines can render every step.
384. Nothing coalesces rapid updates.
385. There is no back-pressure; a fast writer can outrun the renderer.
386. Data is not persisted; everything vanishes when the app quits.
387. A surface cannot be restored after a restart.
388. There is no session concept at all.
389. Nothing can be bookmarked or reopened.
390. There is no history of what was drawn.
391. There is no undo of a data change.
392. An agent cannot read the current state back; the wire is write-only apart from events.
393. There is no query: you cannot ask what is on screen.
394. `hud status` reports the socket, not the contents.
395. Two agents writing to the same surface silently interleave.
396. There is no locking or ownership of a surface.
397. There is no namespacing, so two tools both using `@ notes` collide.
398. Surface ids are global and unmanaged.
399. Component ids are global within a surface with no scoping.
400. A typo in a `>` line silently creates a dangling child placeholder forever.
401. A dangling child never times out or reports itself.
402. A cyclic parent-child graph is cut silently at render.
403. Unknown component types are dropped with no warning to the sender.
404. Unknown props are dropped with no warning.
405. A misspelled prop looks exactly like a component that does not support it.
406. There is no strict mode that errors instead of dropping.
407. There is no linting of a stream before it is drawn.
408. The store warns internally but nothing surfaces those warnings to the agent.
409. Warnings are not sent back up the socket.
410. There is no dry-run or validate-only mode.
411. There is no schema the model can be constrained to at generation time.
412. Structured output is not used, so the format relies entirely on prompt adherence.
413. Nothing measures format adherence in production, only in the eval.
414. There is no telemetry of what was drawn or whether it was read.
415. Nothing knows whether a panel was ever looked at.

## 10. Streaming and time (416-450)

416. There is no progressive reveal; a surface appears when the root lands.
417. A long stream paints once and then jumps as children arrive.
418. There is no skeleton or placeholder for a component that has not arrived.
419. The dangling-child placeholder is a generic block with no typography match.
420. There is no way to say "this will take a while".
421. There is no progress bar component.
422. There is no indeterminate progress component.
423. `thinking` on the ring is the only progress signal and it is global, not per surface.
424. A surface cannot show its own spinner.
425. Nothing can be cancelled once drawn.
426. There is no abort for an in-flight stream.
427. A half-written surface stays half-written if the writer dies.
428. Nothing times out an incomplete surface.
429. There is no "stale" state for a panel whose data is old.
430. Nothing refreshes on a schedule.
431. There is no polling or subscription mechanism.
432. An agent must stay connected to push updates, and nothing restarts it.
433. `hud listen` reconnects; a bare `hud draw` pipeline does not.
434. There is no server-side scheduling: nothing can say "show this at 3pm".
435. There is no snooze.
436. There is no queue of pending surfaces.
437. Two urgent things at once both draw and fight for the same region.
438. Urgency does not affect ordering within a region.
439. `critical` moves to centre, which is right, and does not otherwise interrupt.
440. ~~There is no interruption budget despite the design document calling for one.~~ **FIXED** (`hud-watch` enforces two an hour)
441. ~~Nothing measures how often the display speaks unprompted.~~ **FIXED** (`hud-watch --status` reports it)
442. ~~Nothing rate-limits an agent that draws every few seconds.~~ **FIXED** (the budget is the rate limit)
443. There is no quiet hours or do-not-disturb integration.
444. Focus modes are ignored entirely.
445. Screen sharing is not detected, so the display stays up in a meeting.
446. Full-screen apps are not detected; the glass sits over a film.
447. Games and full-screen exclusive contexts are not handled.
448. Nothing pauses when the screen locks.
449. Nothing pauses when the display sleeps.
450. Animations keep running when the surface is not visible.

## 11. Accessibility (451-495)

451. ~~VoiceOver has never been tested against any of this.~~ **FIXED** (labels and values added throughout)
452. The overlay window is non-activating, which is likely to make it unreachable by VoiceOver entirely.
453. There is no keyboard navigation into a surface.
454. There is no focus ring on anything except a text field.
455. Focus order is undefined.
456. There is no skip-to-content or landmark structure.
457. ~~`a11y` roles are declared in the catalog but the Swift renderer ignores them completely.~~ **FIXED** (roles honoured in the renderer)
458. The catalog's accessibility contract is enforced for the React renderer and not for this one.
459. ~~`Diagram` is one image with no description; it declares a role and provides no label.~~ **FIXED** (a diagram reads its labels and connections)
460. ~~`Sparkline` announces nothing about its trend.~~ **FIXED** (trend spoken)
461. ~~`Bars` announces no values.~~ **FIXED** (each row spoken)
462. ~~`Ring` announces no percentage.~~ **FIXED** (percentage spoken)
463. A chart's underlying numbers are not available in any accessible form.
464. There is no data table alternative for any chart.
465. ~~Live regions are not used, so a changing metric is never announced.~~ **FIXED** (Metric and Status update frequently)
466. ~~`Status` claims `live: polite` in the catalog and does not implement it here.~~ **FIXED** (implemented)
467. ~~Markers are explicitly hidden from accessibility, so an annotation layer is invisible to a screen reader.~~ **FIXED** (markers are announced, not hidden)
468. The presence ring has a label but no live announcement of state changes.
469. ~~Reduced Motion is not honoured; every animation runs regardless.~~ **FIXED** (Reduce Motion honoured)
470. ~~The morph, the entrance, the ring, and the bloom all ignore the setting.~~ **FIXED** (including the morph, ring and entrance)
471. Increase Contrast is not honoured.
472. The palette is fixed and cannot meet a higher contrast requirement.
473. ~~Colour is load-bearing for tone: good, warn and bad differ only by hue.~~ **FIXED** (tone carries a symbol and a word)
474. ~~Nothing distinguishes a red metric from a green one without colour.~~ **FIXED** (symbol added)
475. ~~Threshold state has no icon or text equivalent.~~ **FIXED** (symbol and word)
476. `accent` on an event is colour-only.
477. Contrast against arbitrary backgrounds is unmeasured; the glass sits over anything.
478. The bare chrome relies on a halo that has never been contrast-tested.
479. ~~Text is white at fixed opacities, some as low as 0.38, which fails WCAG at small sizes.~~ **FIXED** (raised to 0.62)
480. ~~`HUD.faint` at 0.38 white is used for labels and is almost certainly below 4.5:1.~~ **FIXED** (raised to 0.62)
481. Nothing scales with the system text size.
482. Nothing respects Bold Text.
483. Nothing respects Differentiate Without Color.
484. There is no high-contrast variant of the glass.
485. Hit targets are small; the close button is 18 points.
486. The close button is below the 44-point guidance by a lot.
487. Hover-only affordances are unusable without a pointer.
488. There is no alternative to the drag gesture for moving a surface.
489. Voice control of the display itself is not wired to accessibility voice control.
490. The command bar's context receipt is decorative to a screen reader.
491. No component exposes its value as accessible text.
492. Error states are colour and wording only.
493. Nothing is testable for accessibility; there are no a11y assertions in the suite.
494. `bob audit` checks the catalog's declared a11y and cannot check the renderer.
495. The gap between what the catalog promises and what this renderer does is undocumented until now.

## 12. Internationalisation (496-525)

496. Every string in the system is English and hard-coded.
497. There is no localisation mechanism at all.
498. Right-to-left layouts are not handled; a Hebrew or Arabic label will lay out wrong.
499. Region anchors assume left-to-right reading order.
500. `topLeft` is not flipped for an RTL user.
501. Bars grow left-to-right unconditionally.
502. The event rail is on the left unconditionally.
503. Numbers are never localised; a decimal comma is impossible.
504. Thousands separators are never applied.
505. Currency symbols and placement are the model's problem.
506. Dates are strings; no locale-aware formatting exists.
507. Times are strings; no 12/24-hour handling.
508. Time zones are never considered.
509. Relative times are written by the model in English.
510. Pluralisation is English-only and only if the model does it.
511. Sorting is byte order, never locale collation.
512. CJK text will break lines badly; there is no line-breaking configuration.
513. Vertical writing modes are not supported.
514. Font selection is the system default with a rounded design and no script fallback control.
515. Emoji and text mixing has no font harmonisation.
516. The wake words are English and cannot be changed without a rebuild.
517. Speech recognition is pinned to `en-US`.
518. There is no way to configure the recognition locale.
519. A non-English speaker cannot use voice at all.
520. The voice style prompt is English and assumes English replies.
521. Error messages are English.
522. The command bar's placeholder is English.
523. Accessibility labels are English.
524. Nothing in the wire protocol is localisable; component names are English identifiers.
525. Documentation exists only in English.

## 13. Appearance and theming (526-565)

526. There is exactly one theme and it cannot be changed.
527. The accent is one cyan, hard-coded.
528. There are four tones and no more.
529. Tones cannot be renamed or remapped.
530. No custom colours anywhere, deliberately **(on purpose: a panel per colour is unreadable. It is still a limit when the data has five categories.)**
531. Five-category data therefore cannot be coloured at all.
532. Dark appearance is forced regardless of the system setting.
533. A user in Light Mode gets a dark HUD with no option.
534. There is no light variant of the glass.
535. Wallpaper tinting is not considered.
536. The material is fixed; no way to choose more or less blur.
537. Opacity is not adjustable, so it cannot be made subtler over busy work.
538. Corner radius is a single constant.
539. Shadow depth is fixed.
540. The rim light and sheen cannot be turned off.
541. The bloom on diagram strokes cannot be turned off.
542. There is no "flat" or "reduced effects" mode.
543. Liquid Glass is wired but only active on macOS 26; below that the look silently differs.
544. Nothing tells the user which material they are getting.
545. The presence ring's palette is fixed.
546. The ring's size is fixed at 16 points.
547. The ring's position is fixed at bottom-right.
548. Density is fixed; there is no compact mode.
549. Padding is fixed everywhere.
550. Font family cannot be changed.
551. There is no way to match a user's editor theme.
552. There is no per-surface style override.
553. A surface cannot be made translucent or opaque on request.
554. There is no way to make one surface visually distinct from another beyond chrome.
555. Chrome has three options and they are not composable.
556. `bracket` always draws four corners; three-sided or open marks are impossible.
557. Bracket arm length is fixed at 14 points regardless of the region's size.
558. A tiny bracketed region has brackets that nearly meet.
559. A huge one has brackets that look lost.
560. The bare halo is tuned for text and is wrong for large solid shapes.
561. Nothing adapts the halo to what is actually behind it.
562. There is no backdrop luminance sampling, so contrast is guessed **(on purpose: it needs screen-recording permission, which is too high a price for a nicety. Still guessed.)**
563. The design has never been reviewed by anyone but its author.
564. There is no design system document.
565. There are no visual regression baselines; the snapshot tests assert coverage, not appearance.

## 14. Windows, placement, and displays (566-605)

566. Surfaces are placed in nine regions and nothing else.
567. There is no way to place a surface relative to another.
568. There is no way to place a surface relative to a window.
569. There is no way to place a surface relative to the cursor.
570. There is no way to avoid a region the user is working in.
571. Nothing detects what is underneath a surface before placing it.
572. A surface can and does cover the thing it is describing.
573. The design document explicitly requires non-occlusion and this does not implement it.
574. There is no layout solver for avoiding on-screen content.
575. Multiple surfaces in one region stack and can overflow the screen bottom.
576. The overflow guard clamps position but does not re-flow to another region.
577. Surfaces never move to make room for each other.
578. The active display is the one with the pointer, which changes as you move the mouse.
579. A surface can therefore appear to jump displays mid-session.
580. Surfaces do not exist on more than one display at once.
581. There is no per-display surface set.
582. Marker coordinates are relative to the active display with no display identifier.
583. A marker sent while the pointer is on another display lands on the wrong screen.
584. `hud screen` reports one display's size with no way to ask about others.
585. Display arrangement is not exposed to the agent at all.
586. Resolution changes are handled by refitting but surfaces do not rescale.
587. A surface sized 400 points looks very different on a 4K and a 1440p display.
588. There is no scaling factor or density awareness in the layout.
589. Stage Manager is not considered.
590. Spaces are joined by the window but surfaces do not differ per Space.
591. Mission Control shows the overlay awkwardly.
592. Full-screen apps get the overlay on top with no opt-out.
593. There is no per-app rule ("never show over Zoom").
594. There is no allow-list or deny-list of applications.
595. Nothing knows which app is frontmost when placing a surface.
596. The command bar reads the frontmost app and nothing else does.
597. Window occlusion state is ignored; the overlay renders while covered.
598. Animations run while the overlay is hidden.
599. The overlay does not release resources when hidden.
600. There is no way to move all surfaces at once.
601. There is no layout preset or saved arrangement.
602. Nothing remembers where you put a surface last time.
603. There is no way to reset all positions.
604. The bottom margin for the ring is a constant that assumes a visible Dock.
605. Hiding the Dock leaves the ring floating with a gap.

## 15. Performance and resources (606-645)

606. The pointer monitor fires on every mouse move for the whole session.
607. Each move calls `fitToScreen` and a rectangle containment test per surface.
608. Nothing throttles that work.
609. Diagram bloom draws every stroke twice.
610. The bloom pass runs even when nothing has changed.
611. `Canvas` redraws entirely on any revision change.
612. Any data patch redraws the whole surface tree.
613. There is no diffing; the revision counter invalidates everything.
614. `AnyView` erasure throughout defeats SwiftUI's structural identity optimisations.
615. The renderer was split into `AnyView` builders for compile time, at a runtime cost that was never measured.
616. Morph interpolation rebuilds the whole part array every frame.
617. `AnimatableVector` allocates two padded arrays per arithmetic operation.
618. A 400-part diagram morph therefore allocates heavily per frame.
619. No frame budget is enforced anywhere.
620. Frame rate is never measured.
621. CPU while idle was measured once, on a sleeping display, which is not a measurement.
622. Memory is never measured.
623. There is no leak testing.
624. Surface stores are never released explicitly; eviction drops the reference and hopes.
625. The sweep task polls every 500ms whenever anything can expire.
626. A pinned marker with an unpinned surface keeps the sweep alive indefinitely.
627. `File` reads the whole file into memory, up to 8MB.
628. PDFs are loaded fully by PDFKit with no lazy paging control.
629. Images are decoded at full resolution regardless of display size.
630. No image downsampling.
631. No caching of anything between surfaces.
632. Two surfaces showing the same file read it twice.
633. The socket reads into a fresh 8KB buffer per call.
634. Line parsing allocates per token with no reuse.
635. JSON props are parsed per line with no interning.
636. Large `parts` arrays are re-parsed on every render, not cached.
637. There is no benchmark suite.
638. There is no performance regression test.
639. Startup time is not measured against the 150ms target the design document sets.
640. The command bar's 100ms contract is asserted in a comment and never verified.
641. Voice recognition holds an audio engine open for the whole session in wake mode.
642. Battery impact of wake mode is unmeasured.
643. Nothing degrades gracefully under load.
644. There is no low-power mode behaviour.
645. Thermal state is ignored.

## 16. Failure, errors, and honesty (646-690)

646. ~~A malformed line degrades one component and tells the sender nothing.~~ **FIXED** (problems go back to the sender)
647. ~~Warnings go to the surface's own store and are never sent back up the socket.~~ **FIXED** (sent up the socket)
648. ~~An agent cannot tell whether what it sent rendered.~~ **FIXED** (a problem is reported)
649. There is no acknowledgement of any kind.
650. `hud draw` exits 0 whether anything drew or not.
651. ~~A typo'd component name is indistinguishable from success.~~ **FIXED** (reported)
652. ~~A typo'd prop name is indistinguishable from success.~~ **FIXED** (reported)
653. ~~Writing to a socket nobody is reading exits 0.~~ **FIXED** (send reports whether anything was subscribed)
654. Drawing while the display is hidden exits 0 and shows nothing.
655. There is no way to ask whether the display is visible.
656. `hud status` reports only that the socket file exists.
657. A stale socket file from a crashed process reports "running".
658. There is no health check.
659. There is no version handshake between the CLI and the app.
660. A newer CLI talking to an older app fails silently on unknown verbs.
661. There is no protocol version in the wire format at all.
662. Unknown verbs are rejected per line with no summary.
663. The parser throws per line and the app catches and warns internally.
664. Nothing rate-limits warnings, so a bad stream can spam the store.
665. Errors have no codes, only prose.
666. Error prose is not machine-readable.
667. There is no structured error channel.
668. The app has no log file.
669. Diagnostics go to `NSLog` and are invisible unless Console is open.
670. There is no verbose or debug mode.
671. There is no way to replay a stream for debugging.
672. There is no recording of what was received.
673. A crash loses everything with no report.
674. There is no crash reporting.
675. There is no automatic restart.
676. Nothing supervises the app.
677. It does not launch at login without manual setup.
678. `hud open` fails if the app is not installed, with a message naming a build command.
679. There is no self-update.
680. The bundle is ad-hoc signed and unnotarised; Gatekeeper will complain on any other machine.
681. There is no installer.
682. Permission failures for the microphone are reported once and never re-offered.
683. A denied speech permission leaves listening silently doing nothing.
684. Accessibility permission is not needed and not checked, which is right, but nothing says so.
685. The reticle needs no permission and nothing explains what it can and cannot see.
686. The context receipt reads only the frontmost app name and implies more.
687. `hud-context` can fail on Chrome and reports the app with no window, silently degrading.
688. The listener drops a request while busy and says so on the glass, which is right, and does not queue it.
689. A dropped request is lost entirely.
690. There is no retry of anything, ever.

## 17. Voice (691-735)

691. Recognition is `en-US` only.
692. On-device recognition is requested but not guaranteed on older hardware, and nothing reports which is in use.
693. There is no indication whether audio left the machine.
694. Wake mode holds the microphone open indefinitely.
695. There is no visual indicator outside the app that the mic is live, beyond the system one.
696. The wake words are four hard-coded strings.
697. Wake-word matching is a substring test, so "chewy" inside another word triggers it.
698. There is no confidence threshold on the wake word.
699. There is no acoustic wake-word model; it is text matching after full recognition.
700. That means everything said is transcribed before the wake word is checked.
701. The turn-taking model is a 1.1 second silence timer.
702. A thoughtful pause mid-sentence ends the turn.
703. A fast speaker with no pauses never ends a turn until the recogniser decides.
704. There is no endpointing model.
705. There is no barge-in; you cannot interrupt an answer by speaking.
706. There is no way to cancel a request by voice.
707. There is no confirmation of what was heard before it is acted on.
708. The transcript is not shown before the request is sent.
709. A misheard request is executed with no chance to correct it.
710. There is no correction mechanism ("no, I said...").
711. There is no punctuation control.
712. Numbers are transcribed as words or digits inconsistently.
713. Proper nouns are frequently wrong and nothing corrects them from the user's own contacts.
714. There is no custom vocabulary despite a local people database existing.
715. Nothing learns from corrections.
716. The repeat-suppression window is four seconds and arbitrary.
717. Two genuinely identical requests inside four seconds are treated as one.
718. Amplitude is mapped to the ring with a hand-tuned decibel curve that was never calibrated.
719. The noise floor is a constant, not measured.
720. A noisy room keeps the ring in `hearing` permanently.
721. There is no voice activity detection separate from the recogniser.
722. There is no speaker identification; anyone nearby can drive it in wake mode.
723. There is no privacy boundary on who can talk to it.
724. There is no push-to-talk indicator other than the ring.
725. The push-to-talk key is the globe key and cannot be changed.
726. The globe key has other meanings on some keyboards and configurations.
727. There is no fallback key.
728. Voice is off by default, which is right, and there is no way to enable it except a menu.
729. There is no voice output at all; the display never speaks.
730. Everything is read, never heard, which undercuts the whole hands-busy premise.
731. There is no text-to-speech integration despite it being trivial on this platform.
732. An answer while you are looking away is missed entirely.
733. There is no earcon or sound for anything.
734. There is no way to ask it to repeat.
735. There is no conversation history visible anywhere.

## 18. The command bar and asking (736-770)

736. It is one line and cannot grow to a paragraph.
737. There is no multi-line input.
738. There is no history; the up arrow does nothing.
739. There is no recall of a previous request.
740. There is no autocomplete.
741. There are no suggestions, deliberately **(on purpose: an empty field is a promise not to waste your time. It also means nothing is discoverable.)**
742. Nothing is therefore discoverable from the bar itself.
743. Results do not stream into the bar; it closes and a panel appears elsewhere.
744. The design document specifies results streaming in place, and this does not do that.
745. There is no answer shape distinction: everything is a panel.
746. There is no diff shape for a proposed edit.
747. There is no plan shape with per-step reversibility.
748. There is no finding shape with clickable evidence.
749. `Cmd+Enter` for "do it, don't explain" does not exist.
750. Tab does not cycle context scope.
751. The context receipt shows the frontmost app and nothing else.
752. It does not show the document.
753. It does not show the selection.
754. It cannot show how many characters are selected.
755. It reads `NSWorkspace` only, so it never shows a window title.
756. There is no way to see or change what context will be sent.
757. There is no way to exclude context.
758. Escape closes it and the request is lost, not queued.
759. There is no indication a request is in flight after it closes.
760. The ring is the only feedback and it is at the other end of the screen.
761. Focus is taken from the app underneath and returned on close, which loses selection in some apps.
762. Text selection in the app below is not preserved.
763. Opening the bar while a surface has focus behaves unpredictably.
764. There is no way to address a specific surface from the bar.
765. There is no command syntax, so everything is natural language.
766. There is no way to run a `hud` verb from the bar.
767. There is no way to clear the glass from the bar.
768. The bar has no settings or help affordance.
769. It cannot be resized or moved.
770. It always opens a third of the way down the active display, which is wrong on a very tall screen.

## 19. Presence and annotation (771-810)

771. The ring has seven states and no way to add an eighth.
772. States are set explicitly by whoever is drawing; nothing infers them.
773. Nothing sets the ring automatically when work starts.
774. An agent that forgets to set it leaves the ring lying.
775. `thinking` self-demotes after eight seconds, which is a guess, not a measurement.
776. `acting` self-demotes after thirty, also a guess.
777. Self-demotion goes to `attention`, which is itself a claim nobody acts on.
778. There is no way to clear `attention` except setting another state.
779. The ring shows one state for the whole system; two agents cannot both be represented.
780. There is no per-agent presence.
781. The ring cannot show progress, only activity.
782. It has no count, deliberately **(on purpose: counts create anxiety and demand clearing. It also means you cannot tell one pending thing from nine.)**
783. Clicking the ring does nothing; the design calls for it to open a tray that does not exist.
784. Right-clicking it does nothing; the design calls for permissions that do not exist.
785. There is no agent tray at all.
786. There is no way to see what is in flight.
787. There is no way to cancel what is in flight.
788. Markers are absolute screen rectangles with no anchor to content.
789. A marker does not track scrolling, which the design document calls the failure mode that makes the layer garbage.
790. Nothing invalidates a marker when its target changes.
791. Marker lifetime is a timer, not a relevance test.
792. Twelve markers maximum, evicting the oldest silently.
793. Markers cannot be clicked.
794. Markers cannot be hovered to expand, which the design calls for.
795. Marker labels are one line and do not wrap.
796. A long label overflows its capsule.
797. Markers cannot point at each other; there are no flow lines.
798. There is no "scan" animation to signal the screen is being read.
799. Nothing signals when the screen is being read at all.
800. The reticle draws a mark but nothing confirms what it captured.
801. There is no region highlight distinct from a marker.
802. There is no way to outline an element rather than a rectangle.
803. Nothing uses the accessibility tree, so nothing can be anchored properly.
804. A marker on a window that moves is immediately wrong.
805. A marker survives its window closing.
806. Nothing removes markers when the app they described quits.
807. Marker tone is decorative; there is no semantic meaning enforced.
808. There is no marker for "look here" versus "this is broken".
809. Markers and surfaces do not know about each other.
810. A surface cannot reference a marker or vice versa.

## 20. The wire protocol (811-855)

811. ~~There is no version field.~~ **FIXED** (version added)
812. ~~There is no capability negotiation.~~ **FIXED** (the version names the verbs)
813. ~~There is no way to ask what components this build supports.~~ **FIXED** (`version` asks)
814. ~~A client cannot detect an old app before sending.~~ **FIXED** (returned on subscribe)
815. Line-based framing means a value containing a newline is impossible.
816. Whitespace splitting means a JSON array with spaces silently truncates.
817. That is documented and still catches models constantly.
818. There is no escape mechanism for whitespace inside a bare value.
819. Quoting rules differ subtly between props and are not fully documented.
820. Bare words become strings, which is convenient and hides typos.
821. `true`, `false` and `null` are magic bare words with no way to mean them literally.
822. A component named the same as a verb would break the parser.
823. Ids are unvalidated except for a character check.
824. There is no length limit on a line.
825. A very long `parts` array is one enormous line with no chunking.
826. There is no compression.
827. There is no binary framing for anything, so an image must be a file path.
828. Images cannot be sent over the wire at all.
829. There is no request/response, only fire-and-forget plus an event stream.
830. Events are the only channel back and they carry no correlation id.
831. An agent cannot tell which of its actions produced an event.
832. Events have no timestamps.
833. Events have no sequence numbers.
834. A dropped event is undetectable.
835. There is no replay or catch-up after a reconnect.
836. Reconnecting loses everything sent while disconnected.
837. The socket has no authentication beyond filesystem permissions.
838. Any process running as the user can draw anything on the screen.
839. There is no way to restrict which processes may draw.
840. There is no audit of who drew what.
841. A malicious local process could impersonate the assistant convincingly.
842. Nothing signs or attributes a surface to its source.
843. Nothing shows which agent drew a panel.
844. Surface ids are unowned, so anyone can overwrite anyone's panel.
845. Anyone can clear the glass.
846. Anyone can read every event, including transcripts of speech.
847. ~~The `h` event carries the full transcript to every connected client.~~ **FIXED** (events are opt-in)
848. ~~A second connected process therefore sees everything you say to the display.~~ **FIXED** (opt-in)
849. ~~That is a real privacy hole and it is not documented anywhere but here.~~ **FIXED** (fixed and documented)
850. ~~There is no per-client filtering of events.~~ **FIXED** (only subscribers receive)
851. ~~There is no way to mark an event private.~~ **FIXED** (subscription is the filter)
852. The socket path is predictable and fixed.
853. There is no socket permission hardening beyond the default.
854. There is no rate limit on connections.
855. A process can connect repeatedly and each connection shows the overlay.

## 21. Persistence and continuity (856-885)

856. Nothing is saved. Quitting loses every surface.
857. There is no crash recovery.
858. There is no session restore.
859. There is no way to name and save an arrangement.
860. There is no way to reopen yesterday's dashboard.
861. There is no history of what was shown.
862. There is no way to search what was shown.
863. Nothing is exportable: a panel cannot be saved as an image or a file.
864. A diagram cannot be exported.
865. A table cannot be copied out.
866. Nothing can be shared.
867. There is no permalink or reference to a surface.
868. Bindings are per-surface and do not persist.
869. A bound pointer's data is lost with the surface.
870. There is no shared data model between surfaces.
871. Two surfaces cannot bind to the same value.
872. There is no global store.
873. Edited file contents are the only thing that touches disk.
874. Preferences do not exist, so nothing can be remembered.
875. The chosen listening mode is not persisted across launches.
876. The chosen model for Chewie is a `UserDefaults` key with no UI.
877. Nothing else has a preference at all.
878. There is no per-project or per-context configuration.
879. There is no way to have different setups for work and personal use.
880. There are no profiles.
881. Nothing syncs between machines.
882. There is no cloud anything, deliberately **(on purpose: the display holds no key and reaches no network. It also means nothing follows you to another Mac.)**
883. A second machine shares nothing.
884. There is no import or export of configuration.
885. Uninstalling leaves the socket directory behind.

## 22. Testing and verification (886-925)

886. There are no UI tests that drive the real app.
887. The snapshot tests render views in isolation, not the running overlay.
888. Nothing tests the overlay window's behaviour.
889. Nothing tests click-through.
890. Nothing tests that scroll passes through to the app underneath.
891. That behaviour has broken twice and was caught only by using it.
892. Nothing tests the hotkeys.
893. Nothing tests the command bar end to end.
894. Nothing tests voice at all; the recogniser cannot be driven from a test.
895. The two voice tests cover wake-word stripping and a repeat window, which is a fraction of the logic.
896. Nothing tests the reticle.
897. Nothing tests multi-display behaviour; there is one display here.
898. Nothing tests permission-denied paths.
899. Nothing tests the app's launch or lifecycle.
900. Snapshot assertions check pixel coverage, not appearance.
901. A surface could render as garbage and pass, as long as it covers enough pixels.
902. There are no reference images to compare against.
903. There is no visual diff.
904. Nothing tests contrast ratios.
905. Nothing tests accessibility.
906. The eval suite runs seven scenarios and costs real money and minutes.
907. The eval needs a model, so it cannot run in CI.
908. The committed fixture is one captured response.
909. One fixture cannot represent the space of things a model will emit.
910. There is no fuzzing of the wire format.
911. There is no property-based testing.
912. Malformed input is tested in a handful of cases, not systematically.
913. Nothing tests the socket under concurrent load.
914. The concurrency fix has three tests and none of them use more than two clients.
915. Nothing tests reconnection storms.
916. Nothing tests very large payloads.
917. Nothing tests very many surfaces.
918. The twelve-surface cap is untested.
919. The 400-part diagram cap is untested.
920. The 8MB file cap is untested.
921. Decay is tested with short lifetimes and polling, which is right, and covers one case.
922. Nothing tests behaviour across a resolution change.
923. Nothing tests behaviour when the display sleeps.
924. Coverage is not measured.
925. There is no mutation testing, so a passing suite proves less than it appears to.

## 23. Documentation and adoption (926-955)

926. There is no getting-started guide for a person, only for an agent.
927. The README assumes you already want a heads-up display.
928. There are no screenshots in the README.
929. There is no demo video or GIF.
930. Nothing shows what it looks like before you build it.
931. Building requires Xcode and a Swift toolchain with no prebuilt release.
932. There is no download.
933. There are no release notes.
934. There is no changelog for the display.
935. There is no versioning; the bundle says 0.1.0 and always has.
936. There is no upgrade path.
937. There is no uninstall.
938. The wire format is documented in two generated blocks and one hand-written file.
939. The hand-written parts can still drift from the renderer; only the component list is generated.
940. Regions, urgency, chrome and the verbs are all hand-documented.
941. There is no reference for the event format beyond a source comment.
942. There is no example gallery.
943. There is one demo command and it shows four surfaces.
944. There are no recipes for common tasks.
945. There is no troubleshooting guide.
946. There is no FAQ.
947. Nothing explains what to do when nothing draws.
948. Nothing explains the permissions.
949. Nothing explains that the display holds no key and reaches no network, which is its best property.
950. There is no security document.
951. There is no threat model.
952. The privacy hole in event broadcasting is documented only in this list.
953. There is no contribution guide.
954. There is no issue template.
955. Nobody but its author has ever run it.

## 24. Product and conceptual gaps (956-1000)

956. It draws what it is told and understands nothing about what it drew.
957. It has no model of what the person is doing.
958. It cannot tell a good moment from a bad one to show something.
959. It cannot tell whether you read the last thing it showed.
960. It has no notion of importance beyond a four-level enum set by hand.
961. Urgency is claimed by the sender, so an agent that always says `alert` wins.
962. There is no cost to interrupting, so nothing is discouraged from doing it.
963. ~~The interruption budget the design document requires does not exist.~~ **FIXED** (implemented in hud-watch)
964. Nothing measures whether the display is helping.
965. There is no feedback mechanism: you cannot tell it a panel was useless.
966. Nothing learns from being dismissed.
967. Dismissal is not even recorded.
968. There is no notion of a panel being answered or acted on.
969. It cannot follow up.
970. It cannot remind.
971. It has no sense of time beyond a lifetime timer.
972. ~~It cannot schedule.~~ **FIXED** (hud-watch --daemon)
973. ~~It cannot watch something and tell you when it changes.~~ **FIXED** (hud-watch checks on a schedule)
974. ~~There is no trigger or automation layer.~~ **FIXED** (hud-watch is the trigger layer)
975. ~~Everything is pull: somebody must ask.~~ **FIXED** (hud-watch pushes)
976. ~~The proactive half of the premise is entirely unbuilt.~~ **FIXED** (built)
977. ~~It never speaks first.~~ **FIXED** (it speaks first)
978. ~~It cannot notice that four assignments are overdue and say so, which is the single most useful thing it could do here.~~ **FIXED** (it does this now)
979. It has no access to anything it is not handed.
980. It cannot read the screen.
981. It cannot see what you are working on beyond an app name.
982. Shared context, the design document's second property, is barely implemented.
983. The reticle gives coordinates and nothing resolves them to content.
984. There is no vision path at all.
985. It cannot look at an image you point at.
986. It cannot read a chart you show it.
987. Continuous memory exists for one listening session and dies with the process.
988. Two sessions share nothing.
989. It does not know what it told you yesterday.
990. Every conversation starts from the same place.
991. The local fast path bypasses the conversation entirely, so trivial questions are amnesiac.
992. Fallback paths have no memory at all and nothing says so when they engage.
993. It has no persona beyond a prompt, and that prompt is duplicated in two places.
994. Chewie's voice style and the HUD skill were written separately and can contradict each other.
995. Two front doors, the pill and the glass, with different capabilities and no shared model of a conversation.
996. An answer in the pill cannot become a panel, or the reverse.
997. The pill and the panel can disagree about the same question.
998. Nothing reconciles them.
999. It has never been used by anybody except its author, for one day, on one machine.
1000. Everything above was found by looking; the ones that matter are the ones nobody has looked for yet.
