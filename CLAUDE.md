# Claude Global Instructions

<!--
  CUSTOMIZATION POINT: Session opener
  The section below is an example of a personal ritual that runs at the start of every response.
  Replace it with whatever grounds YOUR workflow: a mantra, a checklist, a design principle, or delete it entirely.
  The hook in settings.json that triggers this is also optional. See settings/README.md.
-->

## SESSION OPENER (CUSTOMIZABLE)

> **This is the author's personal example.** Caleb opens every session with prayer. You should replace this section with whatever centers your work, or remove it entirely.

**Before responding to anything, the FIRST WORDS must be a session opener. This could be:**

- A prayer, meditation, or intention
- A design principle reminder ("Ship quality, not quantity")
- A project-specific checklist
- Whatever grounds your workflow

### Example: prayer opener (author's default)

> Father, I'm building something real today. Let the ideas be clear, the execution clean, and the work point back to You. Guard my time and focus. Amen.

The key: make it specific to the moment, not generic filler. If you use this pattern, vary it each time.

---

## MVP & UI Design — MANDATORY STANDARDS

**Every single UI, MVP, web app, dashboard, landing page, or component must look like a funded startup's product page. No exceptions. If it looks like a CS homework submission, it is wrong and must be rebuilt.**

---

## TECH STACK — ALWAYS USE THESE

### React / Next.js projects

- Tailwind CSS (always)
- shadcn/ui components (always — never build raw buttons, inputs, dialogs from scratch)
- Lucide React icons (always)
- `next/font` with Geist or Inter (always)
- Framer Motion for animations when there's interactivity

### Vanilla HTML (no framework)

- Tailwind CDN (`<script src="https://cdn.tailwindcss.com"></script>`)
- Google Fonts: Inter (`<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet">`)
- Lucide CDN for icons
- Never write raw CSS for layout — Tailwind only

### Vue / Nuxt

- Tailwind CSS + Headless UI + Heroicons

---

## VISUAL DESIGN — MANDATORY

### Color

- **Default palette**: slate/zinc/gray neutrals + one vibrant accent (indigo, violet, blue, emerald, or rose)
- Background: `#0a0a0a` or `zinc-950` — never pure `#000000` or `#ffffff`
- Text primary: `white` or `zinc-50`
- Text muted: `zinc-400` or `zinc-500`
- Accent: `indigo-500` / `indigo-600` as default — change to match brand
- Never use default browser blue links

### Typography

- Font: Inter or Geist — NEVER system fonts, NEVER Times New Roman
- Hero headline: `text-5xl md:text-7xl font-bold tracking-tight`
- Section heading: `text-3xl md:text-4xl font-semibold tracking-tight`
- Body: `text-base text-zinc-300 leading-relaxed`
- Caption/label: `text-sm text-zinc-500`
- Always use `antialiased` on body

### Backgrounds — pick one, never flat black

- Radial gradient: `bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-indigo-900/20 via-zinc-950 to-zinc-950`
- Mesh: layered radial gradients at different positions
- Dot grid: `bg-dot-pattern` or SVG dot overlay
- Grain texture: subtle noise overlay at low opacity
- Glassmorphism panels: `bg-white/5 backdrop-blur-md border border-white/10`

### Spacing & Layout

- Always responsive: design mobile-first
- Use `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8` for page containers
- Section padding: `py-20 md:py-32`
- Card padding: `p-6` or `p-8`
- Consistent gap: `gap-4`, `gap-6`, `gap-8` — never arbitrary values
- Grid layouts: `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6`

### Cards & Surfaces

```
bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-xl
hover:border-zinc-700 transition-all duration-200
```

Glassmorphism variant:

```
bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-6
```

### Buttons

Primary:

```
bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700
text-white font-semibold px-6 py-2.5 rounded-xl
transition-all duration-200 shadow-lg shadow-indigo-500/25
cursor-pointer
```

Secondary:

```
bg-zinc-800 hover:bg-zinc-700 border border-zinc-700
text-zinc-100 font-medium px-6 py-2.5 rounded-xl
transition-all duration-200 cursor-pointer
```

Ghost:

```
hover:bg-white/5 text-zinc-400 hover:text-white
px-4 py-2 rounded-lg transition-all duration-200 cursor-pointer
```

### Navigation — SCROLL-AWARE (MANDATORY ON ALL PROJECTS)

**Every project must use a scroll-aware navbar with this exact behavior:**

- Hidden / transparent at the very top of the page (y = 0)
- Slides down and becomes visible after scrolling past ~80px
- Hides again when the user scrolls within ~200px of the bottom of the page
- Smooth `transition: transform 0.3s ease, opacity 0.3s ease`

**Logic (useScrollNav hook — copy this pattern every time):**

```tsx
"use client";
import { useEffect, useState } from "react";

export function useScrollNav() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      const scrollY = window.scrollY;
      const docHeight = document.documentElement.scrollHeight;
      const winHeight = window.innerHeight;
      const nearBottom = scrollY + winHeight >= docHeight - 200;
      setVisible(scrollY > 80 && !nearBottom);
    };
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return visible;
}
```

**Apply to the nav element:**

```tsx
const visible = useScrollNav();
// ...
<nav
  className="fixed top-0 left-0 right-0 z-50 backdrop-blur-md bg-zinc-950/80 border-b border-zinc-800/50"
  style={{
    transform: visible ? "translateY(0)" : "translateY(-100%)",
    opacity: visible ? 1 : 0,
    transition: "transform 0.3s ease, opacity 0.3s ease",
  }}
>
```

**Never use a static always-visible sticky navbar.** This pattern is mandatory on every project.

**Vanilla HTML equivalent (no React — use this for plain HTML projects):**

```html
<nav
  id="navbar"
  style="position:fixed;top:0;left:0;right:0;z-index:50;backdrop-filter:blur(12px);background:rgba(10,10,10,0.85);border-bottom:1px solid rgba(255,255,255,0.08);transform:translateY(-100%);opacity:0;transition:transform 0.3s ease,opacity 0.3s ease;"
>
  <!-- nav content -->
</nav>
<script>
  (function () {
    var nav = document.getElementById("navbar");
    window.addEventListener(
      "scroll",
      function () {
        var scrollY = window.scrollY;
        var nearBottom =
          scrollY + window.innerHeight >=
          document.documentElement.scrollHeight - 200;
        var visible = scrollY > 80 && !nearBottom;
        nav.style.transform = visible ? "translateY(0)" : "translateY(-100%)";
        nav.style.opacity = visible ? "1" : "0";
      },
      { passive: true },
    );
  })();
</script>
```

### Form Inputs

```
bg-zinc-900 border border-zinc-700 rounded-xl px-4 py-2.5
text-white placeholder-zinc-500
focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent
transition-all duration-200 w-full
```

### Badges / Pills

```
inline-flex items-center gap-1.5 px-3 py-1 rounded-full
text-xs font-medium bg-indigo-500/10 text-indigo-400 border border-indigo-500/20
```

---

## INTERACTIVITY — ALL OF THESE ARE REQUIRED

- Every button: hover state + active state + `cursor-pointer` + `transition-all duration-200`
- Every card that's clickable: `hover:scale-[1.02]` or `hover:border-zinc-600`
- Every link: color change on hover
- Loading states: skeleton loaders (animate-pulse) — never blank white space
- Empty states: illustrated message with CTA — never just "No data"
- Error states: friendly message with retry — never raw error strings
- Smooth page transitions where applicable

---

## ICONS — ALWAYS REAL ICONS

- Use Lucide React / Lucide CDN — always
- Size: `w-4 h-4` (inline), `w-5 h-5` (buttons), `w-6 h-6` (feature icons), `w-8 h-8` or `w-10 h-10` (hero icons)
- Feature icons: wrap in colored rounded square: `p-2.5 bg-indigo-500/10 rounded-xl text-indigo-400`
- Never use emoji as functional icons
- Never use text characters as icons (→, ×, ✓)

---

## PAGE SECTIONS — HOW TO BUILD THEM

### Hero Section

- Full viewport height or at least 80vh
- Large bold headline with gradient text accent: `bg-gradient-to-r from-white to-zinc-400 bg-clip-text text-transparent`
- Muted subtitle, 1-2 sentences max
- 1-2 CTA buttons (primary + secondary)
- Subtle animated background (gradient, particles, or grid)
- Optional: floating UI mockup or screenshot

### Feature Grid

- 3-column grid on desktop, 1-col mobile
- Each card: icon in colored bubble + heading + description
- Consistent card height

### Pricing

- 3-tier layout, center card highlighted with border + shadow
- "Most popular" badge on center
- Feature checklist with checkmark icons

### Stats/Numbers

- Large numbers with gradient treatment
- Short label below
- Horizontal row, centered

### Testimonials

- Card grid with avatar, quote, name, title
- Star ratings if applicable

### CTA Section

- Full-width, centered
- Gradient background or bordered box
- One clear headline + one button

### Footer

- Multi-column links
- Logo + tagline left
- Social icons right
- Copyright bar at bottom
- `border-t border-zinc-800`

---

## ANIMATIONS (when using React/Framer Motion)

```jsx
// Fade up on scroll
initial={{ opacity: 0, y: 20 }}
animate={{ opacity: 1, y: 0 }}
transition={{ duration: 0.5, ease: "easeOut" }}

// Stagger children
variants={{ container: { staggerChildren: 0.1 } }}

// Hover scale
whileHover={{ scale: 1.02 }}
whileTap={{ scale: 0.98 }}
```

---

## ABSOLUTE PROHIBITIONS

- NO Times New Roman or system serif fonts
- NO flat gray or white backgrounds without treatment
- NO raw `<button>` without styling
- NO `<a>` tags with default browser blue
- NO layout that breaks on mobile
- NO placeholder content like "Lorem ipsum" in MVPs
- NO components without hover states
- NO hardcoded pixel widths for layout
- NO inline styles (use Tailwind classes)
- NO missing loading/empty/error states in data-driven UIs
- NO shipping without checking mobile view
- **NO EM DASHES (--) anywhere, ever. In code comments, copy, documentation, chat responses, anywhere. Use a colon, period, or comma instead.**
- **NO EMOJIS anywhere, ever. Not in copy, not in code, not in commit messages.**

---

## AI SLOP CHECK -- MANDATORY SELF-AUDIT BEFORE SHIPPING

Before shipping any output (UI, code, copy, documentation), run this self-check:

### What is AI slop?

Generic, template-thinking output that could have been produced for anyone. The kind of thing that looks "fine" but has no soul, no specificity, no real design thinking behind it.

### The self-audit (run after every iteration)

**Copy check:**

- Is any text generic enough to be on a thousand other sites? ("Transform your workflow with AI-powered insights") -- rewrite with specificity
- Does every headline communicate exactly what THIS product does? If not, rewrite it
- Are there any filler phrases like "Streamline your", "Powerful", "Seamless", "Leverage", "Cutting-edge", "State-of-the-art"? Delete them
- Are there em dashes? Replace them

**Design check:**

- Is this the same 3-column icon + heading + description card grid used for every section? Vary the layout
- Does every section look identical to the last? Each section must have a distinct visual identity
- Is the background just flat black? Add gradient treatment
- Do the cards disappear into the background? Add visible borders/backgrounds

**Code check:**

- Are there `any` types? Fix them
- Are there unused imports? Remove them
- Are there `console.log` statements? Remove them
- Is there commented-out code? Remove it
- Are there TODO comments that weren't addressed? Address them or create a task

**UX check (run after every design iteration):**

Every iteration must pass ALL of these before moving on:

```
[ ] Hick's Law: No more than 7 options visible at once in menus/nav
[ ] Miller's Law: No more than 9 items in any list before pagination
[ ] Fitts's Law: Primary CTA is 44px+ tap target, prominent location
[ ] Doherty Threshold: Every async action shows feedback within 400ms
[ ] Law of Proximity: Related items grouped, unrelated items separated
[ ] Law of Similarity: Interactive elements look different from static content
[ ] Von Restorff Effect: ONE highlighted CTA per section (not two, not zero)
[ ] Serial Position Effect: Primary action at start or end of navigation
[ ] Goal-Gradient Effect: Multi-step flows show progress
[ ] Cognitive Load: Every element earns its place
[ ] Peak-End Rule: Success state is satisfying, error state is actionable
[ ] Aesthetic-Usability: Full dark design system applied
```

If any box is unchecked -- fix it before continuing to the next section.

---

## THE STANDARD

Before shipping any UI, ask: **"Does this look like it could be a real YC-backed startup's product page or a polished Dribbble shot?"**

If the answer is no — redesign it. The bar is Base44 quality at minimum, ideally better.

---

## Always Do Before Starting Any Work

Run your session opener (see the SESSION OPENER section at the top of this file).

## Always Do When Finishing a Project

**Push to GitHub when done** with any project/feature. Create the repo if it doesn't exist, push to main, and share the URL. Never wait to be asked.

---

## README Footer (CUSTOMIZABLE)

<!--
  CUSTOMIZATION POINT: Replace with your own signature footer, or remove entirely.
  The author uses "All glory to God!" — you should use whatever represents you.
-->

Every README file created or edited should end with a consistent signature footer. Example:

```
Built with D1 Vibe Coding
```

This applies to: new repos, updated READMEs, any markdown file that functions as a README.

---

## IMAGES — ALWAYS INCLUDE ON PERSONAL SITES

**Every tribute page, person page, or profile site must include real photos of the actual person.**

- Scan iMessage attachments for photos (`~/Library/Messages/Attachments/`)
- Check Contacts for profile photos
- Ask the user if needed, but never ship a person's page without their face on it
- Photo treatment: `rounded-2xl overflow-hidden border border-white/10` with gradient overlay at bottom
- Include floating stat cards overlapping the photo for depth

## iMESSAGE QUOTES — DESIGN AS iMESSAGE BUBBLES

When the content is iMessage texts/quotes, render them as iMessage-style chat bubbles, not generic quote cards.

- Outgoing (you): right-aligned, `bg-blue-500` bubble, white text
- Incoming (other person): left-aligned, `bg-zinc-800` bubble, white text
- Include timestamp, avatar initial, context label below
- This directly expresses the content instead of generic template thinking

## CONTENT-FIRST DESIGN — ALWAYS

Before writing any component, name what the content IS and pick a design that directly expresses it:

- iMessage quotes → iMessage bubble UI
- Stats/numbers → massive bold gradient typography
- Timeline → editorial magazine spread, not alternating card template
- Tribute site → photo-first, emotional, personal — not SaaS landing page

---

## MCP TOOLS — ALWAYS HAVE THESE ENABLED

These MCP servers are mandatory for D1-level vibe coding. Each one eliminates a class of friction.

| Server                  | Package                                            | Why It Matters                                                      |
| ----------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| **filesystem**          | `@modelcontextprotocol/server-filesystem`          | Read/write local files directly — no copy-paste needed              |
| **github**              | `@modelcontextprotocol/server-github`              | Create repos, PRs, issues, read code — all from chat                |
| **postgres**            | `@modelcontextprotocol/server-postgres`            | Query production DB directly to debug data issues                   |
| **puppeteer**           | `@modelcontextprotocol/server-puppeteer`           | Screenshot any URL, test UI, scrape data                            |
| **memory**              | `@modelcontextprotocol/server-memory`              | Persist facts across sessions — no re-explaining context            |
| **supabase**            | `mcp-server-supabase`                              | Manage tables, run migrations, check RLS from chat                  |
| **sequential-thinking** | `@modelcontextprotocol/server-sequential-thinking` | Force step-by-step reasoning on complex multi-step problems         |
| **composio**            | Composio MCP URL                                   | GitHub, Gmail, Google Calendar, Todoist, Vercel, Slack — 100+ tools |

Config lives at your project root `.mcp.json` or `~/.claude/.mcp.json`.

---

## AGENTIC WORKFLOW — PARALLEL EXECUTION ALWAYS

When a task can be split into independent sub-tasks, always parallelize. Never work sequentially when parallel is possible.

### When to use sub-agents

- **Research + Build**: one agent researches the codebase while another writes boilerplate
- **Multi-file refactors**: split files across agents
- **Build + Test**: one agent builds, one writes tests simultaneously
- **Data + UI**: fetch data shape while building the component

### claude-squad (headless parallel agents)

```bash
# Spin up N headless Claude agents on the same repo
claude-squad --agents 3 --task "implement feature X"
```

### Headless vs interactive mode

- **Interactive** (default): for tasks that need your judgment mid-way
- **Headless** (`--headless`): for well-defined tasks that can run to completion unattended — use for scaffolding, test writing, docs

### Sub-agent patterns

- Give each agent a tight scope: one file, one feature, one concern
- Always merge back to main context and verify before shipping
- Use worktrees (`git worktree add`) for truly isolated parallel work

---

## AI FEATURES — ALWAYS USE VERCEL AI SDK

For any feature involving AI responses, streaming, or structured outputs:

### Streaming responses (mandatory — never buffer AI output)

```typescript
import { streamText } from "ai";
import { anthropic } from "@ai-sdk/anthropic";

export async function POST(req: Request) {
  const { messages } = await req.json();
  const result = streamText({
    model: anthropic("claude-sonnet-4-6"),
    messages,
    system: "You are a helpful assistant.",
  });
  return result.toDataStreamResponse();
}
```

### Client-side streaming hook

```typescript
import { useChat } from "ai/react";

export function ChatUI() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } =
    useChat({
      api: "/api/chat",
    });
  // render messages
}
```

### Structured outputs (use when you need typed JSON back)

```typescript
import { generateObject } from "ai";
import { z } from "zod";

const { object } = await generateObject({
  model: anthropic("claude-sonnet-4-6"),
  schema: z.object({
    title: z.string(),
    tags: z.array(z.string()),
    priority: z.enum(["low", "medium", "high"]),
  }),
  prompt: "Analyze this task and categorize it.",
});
// object is fully typed
```

### Tool calling (give Claude real-world actions)

```typescript
import { streamText, tool } from "ai";
import { z } from "zod";

const result = streamText({
  model: anthropic("claude-sonnet-4-6"),
  tools: {
    searchDatabase: tool({
      description: "Search the product database",
      parameters: z.object({ query: z.string() }),
      execute: async ({ query }) => searchProducts(query),
    }),
  },
  messages,
});
```

### RAG architecture basics

1. **Ingest**: chunk documents → embed with `text-embedding-3-small` → store in Supabase `pgvector`
2. **Retrieve**: embed user query → cosine similarity search → return top K chunks
3. **Generate**: inject chunks into system prompt → stream response

---

## DEBUGGING PROTOCOL — IN THIS ORDER

When something breaks, follow this exact sequence. Do not skip steps.

1. **Read the error exactly.** Copy the full error message. Every word matters — "cannot read property of undefined" and "cannot read property of null" are different bugs.

2. **Identify the file and line number.** Stack traces are maps. Go to the exact line before doing anything else.

3. **Check your assumptions.** What did you expect this variable to be? `console.log` it. Is it what you expected?

4. **Google the specific error.** Search: `[framework] [exact error message] [year]`. Stack Overflow + GitHub Issues find 80% of bugs.

5. **Check the official docs.** API changed? Breaking version? The docs often have a migration guide you missed.

6. **Read the diff.** `git diff` against the last working state. What exactly changed? The bug lives in the diff.

7. **Rubber duck it to Claude.** Paste: (a) the exact error, (b) the relevant code, (c) what you expected vs what happened. Not just "it's broken."

8. **Bisect if needed.** `git bisect` to find the exact commit that broke it. Then read that commit.

**Never:** guess randomly, change multiple things at once, delete and rewrite before understanding why it broke.

---

## DEPLOYMENT CHECKLIST — RUN BEFORE EVERY PRODUCTION DEPLOY

```
PRE-DEPLOY
[ ] npm run build passes locally (zero errors, zero warnings)
[ ] npm run lint passes (zero warnings — not just zero errors)
[ ] npm run typecheck passes (tsc --noEmit clean)
[ ] No .env files staged in git
[ ] No hardcoded localhost URLs (grep -r "localhost" src/)
[ ] No console.log in critical paths (grep -r "console.log" src/)
[ ] All env vars set in Vercel dashboard
[ ] NEXT_PUBLIC_APP_URL points to production domain

UI CHECK
[ ] Hero section renders correctly on mobile (375px width)
[ ] No layout overflow on any screen size
[ ] All images have alt text
[ ] No broken links
[ ] Scroll-aware navbar works (hidden at top, appears at 80px)
[ ] All CTAs link to correct destinations

PERFORMANCE
[ ] Lighthouse score above 90 on production URL
[ ] No route over 150KB first load JS
[ ] All above-the-fold images have priority={true}

POST-DEPLOY
[ ] Open production URL and verify it loads
[ ] Test primary user flow end-to-end
[ ] Check Vercel Function logs for runtime errors
[ ] Check Vercel Speed Insights (first day)
```

---

## MEMORY PROTOCOL — CLAUDE UPDATES CONTEXT AUTOMATICALLY

**You never manually update context files. Claude does it, silently, as work happens.**

This relies on the second brain system created by `setup.sh`. See [second-brain/README.md](second-brain/README.md).

### Which file to update and when

| What happened                                          | File to update                                           |
| ------------------------------------------------------ | -------------------------------------------------------- |
| New job, consulting role starts or ends                | `{name}-context/NOW.md` + `{name}-context/MEMORY.md`     |
| Project ships, goes live, changes URL, or dies         | `{name}-context/NOW.md`                                  |
| Project's CI/deploy breaks or gets fixed               | `{name}-context/NOW.md` (update "Things Broken" section) |
| New collaborator joins a project                       | `{name}-context/PEOPLE.md`                               |
| Preference stated, feedback given, behavior correction | `.claude/projects/.../memory/feedback_*.md`              |
| New tool, hook, MCP server, or infrastructure change   | `{name}-context/SYSTEM.md`                               |
| Life event or major identity shift                     | `{name}-context/YOU.md`                                  |
| New API key, service credential, or endpoint           | `{name}-context/SYSTEM.md`                               |
| Stack preference changes                               | `{name}-context/STACK.md`                                |
| New person in your network or collaborator context     | `{name}-context/PEOPLE.md`                               |

> Replace `{name}` with your name from `setup.sh` (e.g., `john-context`).

### How to update

1. Write the file with the updated content (PostToolUse hook auto-commits and auto-pushes)
2. No need to announce it unless asked
3. Updates happen inline during conversation, not at the end as a "memory dump"

### Context file structure (`{name}-context/`)

| File        | What It Contains                                                   | Update Frequency                   |
| ----------- | ------------------------------------------------------------------ | ---------------------------------- |
| `YOU.md`    | Identity, education, background, personality, goals                | Monthly or after major life events |
| `NOW.md`    | Current jobs, active projects with URLs, priorities, broken things | When anything changes              |
| `PEOPLE.md` | Collaborators, family, professional network                        | When relationships change          |
| `SYSTEM.md` | Hooks, commands, MCP, APIs, infrastructure                         | When infrastructure changes        |
| `STACK.md`  | Tech stack, design system, code standards                          | When stack preferences change      |

### Granular session memory (`.claude/projects/.../memory/`)

Use the auto-memory system for granular learnings:

- `feedback_*.md` — specific behavioral guidance
- `project_*.md` — project-specific facts
- `user_*.md` — facts about your preferences and identity
- `reference_*.md` — pointers to external systems

The MEMORY.md index in that directory must stay current. When adding a new memory file, add a one-line pointer to MEMORY.md immediately.
