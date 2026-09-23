# www.linkedin.com

Read on 2026-09-23 in a signed-in Chrome profile, through the accessibility tree
(`chewie see --app "Google Chrome"`), because that profile had JavaScript from
Apple Events off. Nothing was clicked or saved while mapping.

## Go straight to the page

`/in/me/` redirects to the signed-in person's own profile, so no handle lookup is
needed. Every section has a details page under it:

| Want                | Open                                                 |
| ------------------- | ---------------------------------------------------- |
| Skills, all of them | `https://www.linkedin.com/in/me/details/skills/`     |
| Experience          | `https://www.linkedin.com/in/me/details/experience/` |
| Education           | `https://www.linkedin.com/in/me/details/education/`  |
| The profile itself  | `https://www.linkedin.com/in/me/`                    |

Opening the details page directly skips the profile scroll, the "Show all" link
and the ads column, the three things that cost turns when navigating by clicks.

## The skills page

- Top: a link named **Add a skill**, then filter buttons **All**, **Industry
  Knowledge**, **Tools & Technologies**, **Interpersonal Skills**.
- Each row: the skill's name, then a link named **Edit <name> skill**. It opens a
  page, not a dialog: `/in/<handle>/details/skills/edit/forms/<id>/`, with the
  experiences to attach the skill to, **Delete skill** and **Save**.
- Removing (2026-09-23): **Delete skill**, then a confirm with **No thanks** and
  **Delete**. Only the second click removes it. Reload the list to check.
- **Use `procedures/linkedin-skills/run.sh`** to list or delete; it carries the fixes below.
- The edit form renders only when its link is clicked from the list. Loading the edit
  URL directly gives an empty page.
- After a delete, the page ignores `location.href`. Navigate through Chrome
  (AppleScript `set URL of tab`), or every later step acts on a stale page.
- Before a bulk removal, scroll the list until it stops growing and show the whole
  list to the person: a profile that showed 10 skills held 28+ once scrolled.
- The list renders about 10 rows at first and loads the rest on scroll. A read
  of the page that finds 10 skills has not found all of them: scroll, then read
  again, before saying what is there.
- Order is the order skills were added. There is no reorder control on the web
  (checked 2026-09-19): the only way to move one up is to remove it and add it
  again, which drops its endorsements. Say that before doing it.

## Before changing anything

- A profile is public. Adding, removing or editing a skill publishes it, so show
  the exact change and get a yes first, then do all of it in one pass.
- If the person keeps their profile copy somewhere as source (a repo or a note),
  edit the source first and paste from it, so the two never drift.
- LinkedIn may offer to notify the network about a profile change. Default to not
  sharing unless they said to.

## Mistakes already made here

- 2026-09-23: "can you go to my linked in and edit my skills" was routed to the
  browser destination, which can only open a URL, so it opened a Google search
  of the sentence. Fixed in `bin/lib/route.py` (a task on a site goes to the
  assistant). If this happens again, the router regressed.
- 2026-09-23: `chrome-js --open` without `--profile` opened the empty Default
  profile, not the signed-in one. Pick the profile first (see
  `bin/hud-agent.md`, "A task on a website").
- 2026-09-23: a delete loop reported success on a skill that was still there, because it
  clicked on a page that had not navigated. Only a reread of the list proves a deletion.
