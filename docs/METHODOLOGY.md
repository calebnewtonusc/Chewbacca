# Vibe Coding Methodology

How to actually vibe code. Not theory. The real workflow.

---

## What Vibe Coding Is

Vibe coding is AI-assisted development where you describe what you want in natural language and an AI agent (Claude Code, Cursor, etc.) writes the implementation. You steer with intent, not syntax.

The key insight: **the bottleneck shifts from typing code to giving clear instructions.** The developer who writes the best prompts ships the best product.

---

## The D1 Workflow

This is the specific workflow this repo implements.

### 1. Context Engineering (before you write a single prompt)

The quality of AI output is directly proportional to the quality of context you provide. This is why `CLAUDE.md` and rules files exist.

**What context engineering looks like:**

- A `CLAUDE.md` at project root that defines your design system, tech stack, and conventions
- Rules files (`.claude/rules/`) that auto-inject domain knowledge based on file type
- A second brain system that loads your identity, current projects, and priorities every session
- Slash commands that encode multi-step workflows into single triggers

**Why it matters:**
Without context, Claude writes generic code. With context, it writes code that looks like YOUR team wrote it. Same model, completely different output.

### 2. Prompt-First Development

Instead of opening a code editor and typing, you open Claude Code and describe:

```
Build a dashboard that shows my Todoist tasks grouped by sprint label,
with priority color coding and a completion percentage bar for each group.
Use the design system from CLAUDE.md.
```

Claude reads your `CLAUDE.md`, rules, and templates, then generates a complete implementation that matches your stack and visual standards.

### 3. Iterative Refinement

Vibe coding is not "generate once and ship." The loop is:

1. **Prompt** the initial implementation
2. **Review** the output (does it match intent?)
3. **Refine** with specific feedback ("make the cards glassmorphism, add skeleton loading states")
4. **Audit** with `/audit` or `/review` commands
5. **Ship** with `/push` or `/deploy`

Each iteration is faster than hand-coding because you're operating at the intent level, not the syntax level.

### 4. Parallel Execution

When a task has independent sub-parts, split them across agents:

- One agent builds the UI while another writes the API route
- One agent researches the codebase while another scaffolds boilerplate
- One agent writes tests while another implements the feature

The `claude-squad` pattern (multiple headless Claude instances) is the highest-throughput mode.

---

## The Five Principles

### 1. Context Over Prompts

A mediocre prompt with excellent context produces better output than an excellent prompt with no context. Invest in `CLAUDE.md`, rules files, and templates before you start prompting.

### 2. Specificity Over Abstraction

"Build a landing page" produces AI slop. "Build a landing page for a health data platform targeting 25-35 year old professionals, dark mode, glassmorphism cards, scroll-aware navbar, with sections for: hero with product screenshot, 3 feature cards, pricing table, and CTA" produces a real product page.

### 3. Audit Everything

AI-generated code needs review just like human code. The `/audit`, `/review`, and `/ship` commands exist because generated code can have subtle bugs, security issues, or design flaws that look fine at first glance.

### 4. Ship Incrementally

Don't generate an entire app in one prompt. Build feature by feature, page by page. Each increment gets reviewed and committed before moving on. This is how you maintain quality.

### 5. Own the Architecture

The AI writes the code. You own the decisions. You choose the stack, the data model, the user flow, the deployment target. Vibe coding is about delegation, not abdication.

---

## Common Anti-Patterns

### The "Generate Everything" Trap

Prompting for an entire app at once. The output will be shallow and generic. Build incrementally.

### The "No Context" Trap

Using Claude Code without a `CLAUDE.md` or rules files. You'll spend more time correcting output than you save.

### The "No Review" Trap

Shipping AI-generated code without reading it. You'll accumulate bugs, security issues, and tech debt fast.

### The "Copy-Paste" Trap

Generating code in a chat window and pasting it into your editor. Use Claude Code directly in your project so it has full codebase context.

### The "One Tool" Trap

Only using one AI tool. Claude Code for architecture and complex features, v0 for quick UI prototypes, Cursor for inline edits. Each tool has a sweet spot.

---

## Measuring Vibe Coding Effectiveness

Track these to know if your setup is working:

- **Time from idea to deployed feature**: should decrease over time
- **Prompts per feature**: fewer prompts = better context engineering
- **Audit findings per generation**: fewer findings = better rules files
- **Revert rate**: how often you undo AI-generated changes

---

## Further Reading

- [ECOSYSTEM.md](../ECOSYSTEM.md) for tools and repos in the space
- [docs/CLOUDFLARE.md](CLOUDFLARE.md) for D1-specific patterns
- [docs/PROMPTS.md](PROMPTS.md) for example prompts
- [docs/SYSTEM-PROMPTS.md](SYSTEM-PROMPTS.md) for writing the prompt that governs an agent across sessions
