---
description: Deploy current project to Vercel, auto-detects project, runs quality gate, deploys
allowed-tools: Bash(vercel:*), Bash(git:*), Bash(gh:*), Bash(pnpm:*), Bash(npm:*), Bash(npx:*), Bash(ls:*), Read, Glob
argument-hint: "[--prod] [project-path]"
---

# Deploy

Deploy current project to Vercel. Runs quality gate first, never ships broken code.

## Step 1: Detect project

If $ARGUMENTS has a path, use it. Otherwise use current directory.

```bash
ls package.json 2>/dev/null && echo "found" || echo "no package.json"
cat vercel.json 2>/dev/null || echo "no vercel.json"
```

## Step 2: Quality gate

```bash
npm run typecheck 2>/dev/null || npx tsc --noEmit
npm run lint 2>/dev/null || npx eslint . --max-warnings 0
```

If either fails, stop and report the errors. Do not deploy broken code.

## Step 3: Ensure clean git state

```bash
git status --short
git diff --stat HEAD
```

Commit any uncommitted changes first:

```bash
git add {changed files by name}
git commit -m "chore: pre-deploy cleanup"
```

## Step 4: Deploy

Preview deploy (default):

```bash
vercel --yes 2>&1
```

Production deploy (if $ARGUMENTS contains --prod):

**Never run `vercel --prod` from local.** Push to `main` and let Vercel auto-deploy from GitHub:

```bash
git push origin main
```

Then open the Vercel dashboard to confirm the deployment triggered.

## Step 5: Report

Show the deployment URL. Report whether it's preview or production.
If it's the first deploy, link the project in Vercel dashboard.
