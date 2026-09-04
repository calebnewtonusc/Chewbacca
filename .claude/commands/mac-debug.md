---
description: Debug a failing Mac automation
---

Debug this: $ARGUMENTS

Load the `mac-debug` skill. Match the symptom against `data/failure-modes.json` before
you retry anything.

Do not escalate to a screenshot to route around a failing accessibility read. A failing
layer-3 read almost always means one specific fixable thing, and the screenshot costs
ten times as much and still clicks the wrong element.

Three failures on the same action: stop and report what you tried and what you saw.
