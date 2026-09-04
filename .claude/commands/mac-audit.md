---
description: Audit what an agent can currently reach on this Mac, and what that means
---

Audit the current control surface.

1. `chewie doctor` for grants and tools.
2. `claude mcp list` for registered servers, and note which of them can act on the Mac.
3. State plainly what an agent can currently do with those grants. Accessibility plus
   Screen Recording is functionally total control of the session: read every pixel,
   click every button, type into anything. Full Disk Access adds every file.
4. Name the specific risks that apply here, not generic ones:
   - Which grants are on a general-purpose app rather than a terminal the user controls
   - Whether anything long-running or internet-driven is running on the host rather
     than in a VM
   - Whether any automation reads content written by other people (email, web, chat),
     which is the prompt injection surface
5. Recommend the smallest change that reduces the risk without breaking what they use.

Be honest and specific. Do not pad it, and do not moralize.
