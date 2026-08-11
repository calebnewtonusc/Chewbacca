---
paths:
  - "**/*.tsx"
  - "**/*.ts"
  - "**/*.html"
  - "**/*.md"
---

# Writing Rules

These apply to ALL text output: UI copy, documentation, code comments, commit messages, chat responses.

---

## EM DASHES ARE BANNED

Never use em dashes (--) anywhere. Not in copy. Not in code comments. Not in documentation. Not in chat.

Use a colon, period, or comma instead.

```
WRONG: "A powerful tool -- built for developers."
RIGHT: "A powerful tool built for developers."

WRONG: "Authentication failed -- check your API key."
RIGHT: "Authentication failed. Check your API key."

WRONG: "The result -- if successful -- will be cached."
RIGHT: "The result, if successful, will be cached."
```

## EMOJIS ARE BANNED

Never use emojis anywhere. Not in UI copy. Not in commit messages. Not in README files. Not in responses.

```
WRONG: "🚀 Deploy in seconds"
RIGHT: "Deploy in seconds"

WRONG: "feat: add dashboard ✨"
RIGHT: "feat: add dashboard"
```

---

## AI SLOP IS BANNED

Run this check before outputting any copy or documentation.

### Banned phrases (always rewrite these)

These phrases signal generic template thinking. Delete them on sight:

- "Transform your workflow"
- "Powerful" (as a standalone adjective)
- "Seamless" / "seamlessly"
- "Leverage" (as a verb for software features)
- "Cutting-edge"
- "State-of-the-art"
- "Game-changing"
- "Revolutionary"
- "Innovative"
- "Next-generation"
- "Robust"
- "Scalable" (unless in a technical context)
- "Best-in-class"
- "World-class"
- "Streamline your"
- "Empower your team"
- "At your fingertips"
- "Take it to the next level"
- "The future of X"
- "Built for X" (without specifics)
- "Supercharge your"

### What good copy looks like instead

Every headline and description must answer: what does THIS product do, for WHOM, that produces WHAT specific result?

```
WRONG: "Powerful project management for modern teams"
RIGHT: "One place for every PR, deploy, and deploy failure"

WRONG: "Seamlessly connect your workflow"
RIGHT: "Draft, review, and merge without switching tabs"

WRONG: "Leverage AI to transform your business"
RIGHT: "Tell Claude what to build. Get working code in 30 seconds."
```

### Specificity test

Before writing any headline, ask: could this headline appear on a competitor's site unchanged?

If yes, it is not specific enough. Rewrite it.

---

## COPY TONE

- Direct: say the thing, not the thing around the thing
- Present tense: "Claude builds the component" not "Claude will build the component"
- Active voice: "You create the project" not "The project is created"
- Short sentences: max 20 words before a period
- No hedging: "might", "could potentially", "it's possible that" -- cut these

---

## HEADINGS

- Sentence case by default ("Build faster today" not "Build Faster Today")
- Title case only for product names and formal titles
- Never all caps for body headings
- Hero headlines: bold claim about what the product does or the outcome it produces

---

## ERROR MESSAGES

Error messages are copy too. They must be:

- Specific ("Invalid email address" not "Validation failed")
- Actionable ("Enter a valid email like name@example.com" not just "Error")
- Human ("Something went wrong -- we're on it" is wrong because em dash AND vague)
- Never raw technical strings to the user ("PGRST116: not found" must never be user-facing)
