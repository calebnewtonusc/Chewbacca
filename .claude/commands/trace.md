---
description: Trace a data flow, bug, or feature through a codebase end-to-end — maps every file and function involved
allowed-tools: Read, Glob, Grep, Bash(git log:*)
argument-hint: "<symptom, feature name, or data path to trace>"
---

# Trace

Trace the flow of `$ARGUMENTS` through the codebase. Map every file and function involved, identify where data transforms or could break, and report the full chain.

## Step 1: Identify the flow type

Determine which category applies:
- **HTTP request**: from route definition → middleware → handler → DB → response
- **Data mutation**: from UI action → API call → validation → DB write → side effects
- **Background job/agent**: from trigger → queue → worker → output/notification
- **Auth flow**: from token → middleware → user resolution → authorization check
- **Event/webhook**: from inbound payload → validation → processing → response

## Step 2: Find the entry point

Search for the entry point related to `$ARGUMENTS`:
```
grep -rn "{keyword}" src/ --include="*.ts" --include="*.js" --include="*.py" -l
```

Read the most likely entry point file in full.

## Step 3: Trace the chain

Follow the code path step by step:
1. Read each function in the chain
2. Note where data **changes shape** (transforms, parses, validates)
3. Note **failure points** — where could data be lost, malformed, or misrouted?
4. Identify **ownership boundaries** — where does one module hand off to another?

## Step 4: Report the chain

```
Entry: {file:line} — {function name}
  ↓ {transform or action}
  {file:line} — {function name}
  ↓ {transform or action}
  ...
Exit: {file:line} — {where the data ends up / what is returned}
```

Then list:
- **Data transforms**: how the data changes shape at each step
- **Failure points**: where it could break and what the failure mode would be
- **Findings**: any bugs, missing validation, or suspicious patterns
- **Recommendation**: what to fix or investigate further

Be specific about file paths and line numbers. Never report a finding without verifying the actual code.
