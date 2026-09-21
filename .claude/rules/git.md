---
paths:
  - "**/*"
---

# Git Rules

**Never commit Co-Authored-By lines.** No AI attribution in commit messages.

**Stage by filename, never `git add -A` or `git add .`** prevents accidentally committing `.env` files, large binaries, or unrelated changes.

**Branch naming:**

- `fix/{issue-or-slug}` for bug fixes
- `feat/{feature-slug}` for new features
- `chore/{description}` for maintenance, dependency updates

**Commit message format:**

- `fix: {what was broken and how it was fixed}`
- `feat: {what new capability was added}`
- `chore: {maintenance task}`
- Reference issue numbers: `fix: resolve null crash on profile load (#42)`

**Never amend published commits.** Create a new commit instead.

**Resolve conflicts by understanding them.** Don't `git checkout --ours/--theirs` blindly. Read both sides.

<!--
  CUSTOMIZATION POINT: Add repo-specific rules here.
  Example: "org-name/repo requires PRs. Never push directly to main."
  Example: "Personal repos (your-username/*) can be pushed to main directly."
-->

## Always `git commit -- <paths>`, never a bare `git commit`

**`git commit` commits the entire index, not the files you just added.**
Staging by filename is careful and insufficient: if another session already
staged its work, a bare commit swallows it.

This happened twice in one day in this repo. The second time, a handoff note
had warned about the first in writing, and the very next commit did it again:
`a99042a`, about `methods/`, absorbed `README.md`, `setup.sh` and
`SHA256SUMS.txt` from a parallel session.

```bash
git add bin/thing tests/thing.sh
git commit -- bin/thing tests/thing.sh     # only these, whatever else is staged
```

Check before committing when any doubt exists:

```bash
git diff --cached --name-only
```

`.githooks/pre-commit` prints the staged list on every commit and refuses when
the index holds files far older than the newest one. Enable it with
`git config core.hooksPath .githooks`. It is a backstop: it cannot catch a
file a build step regenerated seconds ago.
