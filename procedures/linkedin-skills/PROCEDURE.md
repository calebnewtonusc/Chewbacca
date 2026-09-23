# linkedin-skills

List or delete the skills on the signed-in person's LinkedIn profile, in their own Chrome.

```
procedures/linkedin-skills/run.sh list
procedures/linkedin-skills/run.sh delete "Sales" "GitHub"
```

`delete` names every skill it removes and ends by rereading the list, printing `deleted:` or
`STILL THERE:` per name and what is left. There is no "keep only these" mode: a deletion is
public and drops the skill's endorsements, so the names are shown to the person first.

About 6 s a skill. Needs a LinkedIn tab in the signed-in profile with "Allow JavaScript from
Apple Events" on (`chrome-js --check`).

## Origin

2026-09-23, from cutting a profile from 28 skills to 5. The first pass clicked by hand and
took minutes a skill; three fixes, each now a comment in `run.sh`, got it to 6 s:

- after a delete, the edit page ignored `location.href`, so navigation goes through Chrome;
- the edit form renders only when opened by a click from the list, not by loading its URL;
- a clicked confirm is not a deletion, so the list is reread at the end.

Adding a skill is not here yet. The site's controls are in `maps/www.linkedin.com/MAP.md`.
