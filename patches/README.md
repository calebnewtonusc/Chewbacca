# Patches

Patches against third-party source live here. Right now there are none.

## plynn-macos15.patch (removed 2026-09-04)

Plynn is no longer patched at install time. **It is vendored at `plynn/`**, and
`bin/install-plynn.sh` builds that directly. See `plynn/NOTICE.md`.

The patch was removed because it broke twice in one day. Once when upstream
pushed a commit touching `scripts/Info.plist`, after which it silently stopped
applying and every macOS 15 install bailed out with "upstream has moved" without
anyone noticing. Once when four commits of our own landed in the fork and never
made it back into the patch, so people installing the kit got a Plynn missing
all of them.

The lesson worth keeping: **a patch against a moving target is a second copy of
the truth that nobody looks at until it is already wrong.** Vendor it, or track
upstream properly. A diff maintained by hand is neither.
