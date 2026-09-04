# Security

## Reporting vulnerabilities

If you find a security issue (leaked credentials, injection vulnerability, etc.), open a GitHub issue or email the maintainer directly.

## Known issue: historical token in git history

A Todoist API token was previously committed to command files and has since been removed from all files. However, it remains in git history.

### If you forked before April 2026

The token `f0126e...` in older commits was the maintainer's Todoist token.
Treat it as live until this line says otherwise: do not assume it is dead,
and do not use it. It grants access to one person's task list and nothing
in your fork depends on it. Delete it from any fork's history you control.

### For the maintainer: cleaning git history

To fully remove the token from history, run BFG Repo Cleaner:

```bash
# Install BFG
brew install bfg

# Clone a bare copy
git clone --mirror https://github.com/calebnewtonusc/Chewbacca.git

# Create a file with the secret to remove
echo "<the-leaked-token-string>" > secrets.txt

# Run BFG
bfg --replace-text secrets.txt Chewbacca.git

# Clean up and push
cd Chewbacca.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push
```

Then rotate the Todoist token at https://todoist.com/app/settings/integrations/developer.

## Best practices enforced by this repo

- `PreToolUse` hook warns before writing to `.env` files
- `/push` command scans diffs for secret patterns before committing
- `/audit` command greps for hardcoded tokens in source files
- `settings.json` uses env vars (`$TODOIST_API_TOKEN`), never inline tokens
- `.gitignore` template excludes `.env`, `.dev.vars`, and credential files
- CI workflow checks for leaked secret patterns on every push
