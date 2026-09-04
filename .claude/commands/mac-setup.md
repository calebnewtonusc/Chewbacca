---
description: Set up Mac control from scratch, including walking the user through permissions
---

Set up this Mac so I can control it.

1. Run `chewie doctor`. If `chewie` is not on PATH, run `install.sh` from this repo first.
2. Report exactly what is missing.
3. For each missing grant, walk the user through it **one toggle at a time**. Do not
   list all of them at once. Tell them the exact app name `chewie doctor` printed, and
   remind them to quit and relaunch that app afterwards, because the grant does not
   apply until it restarts.
4. Re-run `chewie doctor` after each one.
5. When everything is green, do not summarize what you installed. Prove it works: run
   `chewie see` on whatever app is frontmost and tell them one true thing about what
   is actually on their screen.
