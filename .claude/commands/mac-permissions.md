---
description: Fix a macOS permission problem
---

Diagnose the permission problem: $ARGUMENTS

Load the `mac-permissions` skill. Work in this order:

1. `chewie doctor` for current state
2. Identify which bucket is actually involved. They are separate: Accessibility,
   Screen Recording, Automation, Full Disk Access, Input Monitoring.
3. Check whether the symptom is even TCC. Silent keystroke failure is Secure Input.
   -600 is the app not running. -1728 is a wrong object.
4. If a prompt was dismissed once, it never returns. `tccutil reset <bucket>` and
   trigger again with the terminal in the foreground. **Warn the user before any
   reset**, since it wipes grants they set by hand.

Never claim you can grant a permission programmatically. You cannot. There is no API,
`tccutil` only removes, and the TCC database is SIP-protected.
