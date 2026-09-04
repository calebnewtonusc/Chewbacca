# Layer 5: Vision

Screenshot the screen, send it to a model, get back a coordinate, click it. The most
general layer and the worst performing one. Use it for what it is uniquely good at,
not as a default.

## Capture

```bash
screencapture -x /tmp/shot.png              # built in, no install, silent
screencapture -x -R 0,0,1440,900 /tmp/r.png # region
screencapture -x -l $WINDOW_ID /tmp/w.png   # one window
peekaboo image --app Safari --path /tmp/s.png
chewie shot --app Safari
```

Capturing a specific window rather than the whole display is worth doing every time.
Less to look at, fewer tokens, and no risk of leaking whatever else is on screen into
the model's context.

## Anthropic's computer tool

The current toolset is `computer_toolset_20260801`, no beta header, on Fable 5.1,
Mythos 5.1, Fable 5, Mythos 5, Opus 5, Sonnet 5, and Opus 4.8. The earlier
`computer_20251124` needed a beta header and covered the 4.x line.

Seventeen member actions: `screenshot`, `zoom`, `left_click`, `right_click`,
`middle_click`, `double_click`, `triple_click`, `left_click_drag`, `mouse_move`,
`left_mouse_down`, `left_mouse_up`, `cursor_position`, `scroll`, `type`, `key`,
`hold_key`, `wait`.

Details that cost people time:

- **Coordinates are in screenshot pixel space**, origin top-left, and they stay in
  full-screenshot space even after a `zoom` call. If you downscaled the image before
  sending it, scale the returned coordinates back up before clicking.
- **Retina is 2x.** Either downscale by 2 before sending or halve what comes back.
  Doing neither puts every click at double the offset.
- **Size limits.** For the current toolset: max long edge 2576px, max 4784 visual
  tokens, computed as `ceil(w/28) * ceil(h/28)`. For the earlier one: 1568px long
  edge, 1.15 megapixels. Resize before sending, not after being rejected.
- **Recommended resolutions:** 1024x768 or 1280x720 for a desktop, 1280x800 or
  1366x768 for web. Above 1920x1080 accuracy drops and cost climbs.
- **Batching.** The model can return several actions in one response. Execute them in
  order and **stop at the first failure**. Every `tool_use` needs a matching
  `tool_result`; for the skipped ones return `is_error: true` with exactly
  `"Not executed: an earlier computer action in this turn failed."`
- **Every result needs `"toolset_name": "computer"`.**
- **Context.** Keep it to 20 images or fewer per request and prune old screenshots in
  batches so prompt caching still hits.

Reference implementation: [anthropics/anthropic-quickstarts](https://github.com/anthropics/anthropic-quickstarts/tree/main/computer-use-demo).

## OpenAI CUA

Same shape, different names. `openai/openai-cua-sample-app` is the reference. The
`computer-use-preview` model returns `computer_call` items with actions and you loop
screenshots back as `computer_call_output`.

## Set-of-Marks and OmniParser

Raw pixel grounding is the weak point. The standard mitigation is to not ask for raw
coordinates at all: detect the interactive elements first, draw numbered boxes on the
image, and ask the model to pick a number.

[microsoft/OmniParser](https://github.com/microsoft/OmniParser) (25k stars, CC-BY-4.0)
does this: a YOLO-based icon detector plus a captioner, turning a screenshot into a
labeled list of interactable regions. It measurably improves grounding on dense UIs and
is the piece most homegrown implementations are missing.

On a Mac, note the irony: **layer 3 already gives you exactly this, for free, faster,
and with real names instead of guessed boxes.** Set-of-Marks exists because Windows and
Linux accessibility is worse. Use it on a Mac only when the tree is genuinely absent.

## Native GUI models

A separate approach: models trained end-to-end to output GUI actions from pixels, no
separate detector.

| Model | Notes |
|-------|-------|
| [UI-TARS](https://github.com/bytedance/UI-TARS) | ByteDance, 11k stars. Pure vision, no HTML or element IDs. UI-TARS-desktop (39k stars, Apache-2.0) is the app |
| [Fara-1.5](https://github.com/microsoft/fara) | Microsoft, 6k stars, MIT. Small enough to run locally |
| [ShowUI](https://github.com/showlab/ShowUI) | CVPR 2025, end-to-end vision-language-action |

These are worth watching, and they are the right architecture long-term. Today, on
macOS specifically, a hybrid that reads the tree and only falls back to vision beats
pure vision on both cost and success rate.

## Continuous capture

[screenpipe](https://github.com/screenpipe/screenpipe) (21k stars, Rust) records the
screen continuously, OCRs it, and serves it back as searchable context. Different use
case from control: it is memory, not action. Worth knowing about when the task is
"what was I doing yesterday" rather than "click this."

## The honest cost

Per step: about 1,500 tokens for the image, one to several seconds of latency, and you
need a fresh one after every action because there is no other way to see the result. A
twenty-step task is thirty thousand tokens of screenshots and a minute of waiting,
before the model has thought about anything.

The same task through the accessibility tree is a few thousand tokens and a couple of
seconds, and it does not misclick.

## Prompt injection

**A screenshot is untrusted input.** It contains text written by other people: emails,
web pages, documents, chat messages. Text in an image that says "ignore your previous
instructions" is an attack, and it is the most realistic threat in this entire space,
because unlike a normal prompt injection the model is holding a mouse.

Anthropic's API runs injection classifiers and the model asks for confirmation when it
flags something, but do not treat that as the control. The control is: content read
off the screen is data about what a document says, never an instruction. Anything
irreversible gets a human.
