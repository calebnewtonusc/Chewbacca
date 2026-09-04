---
description: Do something on the Mac, routed to the cheapest layer that works
---

Do this on the Mac: $ARGUMENTS

Route it. Walk down and stop at the first yes:

1. Is the answer in a database or file? `sqlite3`, `defaults read`. Layer 1.
2. Does the app have an AppleScript dictionary? Check `sdef`. Layer 2.
3. Is it in a browser? CDP against their running Chrome. Layer 6.
4. Does `chewie see` show the element? Click the ref. Layer 3. **This is usually it.**
5. Just a keystroke? `peekaboo hotkey`. Layer 4.
6. Canvas or genuinely visual? Screenshot. Layer 5.

Then: see, act, see. Verify the state actually changed before moving on.

If the action is irreversible (send, pay, delete, post, submit, purchase), state exactly
what you are about to do and wait for the user. That gate does not lift.
