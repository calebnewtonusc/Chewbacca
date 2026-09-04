# Plynn, vendored

This directory is a fork of **[Plynn](https://github.com/31Carlton7/plynn)** by
**Carlton Aikins**, MIT licensed. His `LICENSE` is kept beside this file and
covers everything here, including our changes, which are derivative of his work.

## Why it lives in this repo instead of being installed

It used to be installed: `bin/install-plynn.sh` cloned his repository and applied
`patches/plynn-macos15.patch` at install time. That broke twice in a single day.
Once because upstream pushed a commit touching `scripts/Info.plist` and the patch
silently stopped applying, so every macOS 15 install bailed out with "upstream
has moved" and nobody noticed. Once because four commits of our own work landed
in the fork and never made it back into the patch, so people installing the kit
got a Plynn without them.

A patch against a moving target is a second copy of the truth that nobody looks
at until it is wrong. The source is 98 files and 2.7MB. Carrying it is cheaper
than keeping a diff honest.

## What we changed

**It runs on macOS 15.** Upstream declares macOS 26. Every dependency supports 14
or lower, and only three features actually needed 26, each with a fallback
already in the code: FoundationModels polish becomes Qwen3-4B via MLX,
SpeechAnalyzer becomes Parakeet, Liquid Glass becomes `.ultraThinMaterial`.
Dropping the deployment target is what fixes loading, because the linker then
weak-links those frameworks and missing symbols resolve to null instead of
aborting in dyld. Sparkle's background check is off, since an upstream release
built for 26 would replace a working install with one that cannot launch.

**Chewie.** Say "Chewie" at the front of a dictation, or hold left Option instead
of fn, and it goes to Claude Code with your own CLIs, skills and second brain
rather than being typed out. Answers are shown on the pill and copied, never
pasted: a reply to a question is not dictated text. Small talk is answered on the
warm local model, and a held-warm Claude session takes a real answer from about
26 seconds to about 5.

**No setup window.** This kit already grants the permissions and downloads the
model, so a wizard on launch asks for work that is done. Anything genuinely
missing is named on the pill instead, and the window is still there behind the
menu item.

## Sending changes upstream

The macOS 15 work is generally useful and belongs to Carlton if he wants it.
Chewie is specific to this kit and does not. Keep them separable: the port
touches availability gating and the manifest, Chewie is `ChewieRouter.swift` plus
its call sites in `main.swift`.
