---
description: Generate and deliver the morning operator brief
---

Run the Chewbacca operator brief.

1. Gather the raw state:
   ```bash
   chewie brief --json
   ```
   That returns today's calendar (layer 1), the texts waiting on a reply (chat.db
   with the attributedBody decoder), and recent inbox email (bounded AppleScript).

2. Triage it. This is the part only judgment can do, so do it honestly:
   - **Urgent**: a direct question from a real person, a deadline today, a
     time-sensitive request, a reply someone is visibly waiting on.
   - **Noise**: newsletters, receipts, automated mail, reactions, closed threads.
     Do not dress these up as action items.
   - Cross-reference: an email AND a text from the same person about the same thing
     is one item, not two.

3. Write the brief in his voice, short, no preamble. Structure:
   - Today's calendar with any conflicts called out
   - What genuinely needs a reply, most time-sensitive first, with who and what
   - Anything with a hard deadline
   - A suggested order for the first two hours

4. Deliver it. Default: print it. If he has said to text it, use a confirm-gated
   send_text to himself. Never send anything outbound to other people from the brief.

Be strict about urgency. A brief that lists 40 things is a brief he stops reading.
Twelve real ones beat forty padded ones. If nothing is actually urgent, say that.
