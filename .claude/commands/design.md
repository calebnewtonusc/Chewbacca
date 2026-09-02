---
description: Build a UI from description using the full visual system + deep UX law enforcement
allowed-tools: Bash(npm:*), Bash(npx:*), Read, Write, Edit, Glob
argument-hint: "<UI description, be specific about the content, context, and user goal>"
---

# Design

Build `$ARGUMENTS` using the full design system. UX laws are not decorations, they are enforced at every decision.

---

## Phase 1: Content-First Analysis

Before touching any code, answer these questions:

1. **What is the user's single goal on this screen?** Name it in one verb phrase.
2. **What is the primary content type?** (list, form, detail view, dashboard, marketing, etc.)
3. **What content-native format best expresses it?**
   - iMessage quotes → iMessage bubble UI, not generic quote cards
   - Stats/numbers → massive bold gradient typography, not tables
   - Timeline/story → editorial magazine spread, not alternating cards
   - Progress/achievement → visual tracker with clear completion signal
   - Pricing → 3-tier with one visually distinct "recommended" option
4. **What is the emotional tone?** (urgent / calm / celebratory / professional)

Never apply a template before answering these. The design must emerge from the content.

---

## Phase 2: UX Law Pre-Flight

Run this checklist BEFORE designing a single component. Every law must be satisfied in the final output.

### Information Architecture

**Hick's Law**: Decision time grows with options.

- How many choices are visible at once? More than 5-7 primary options → chunk them or use progressive disclosure.
- Navigation: max 5-7 top-level items. If more, group them.
- Dropdowns: max 7 items before search is required.

**Miller's Law**: Working memory holds 7 ± 2 items.

- List items visible at once: limit to 5-9 before pagination or infinite scroll.
- Form fields per section: group into semantic chunks of 3-5, never show 12 fields at once.

**Choice Overload**: Too many parallel options kill decisions.

- Pricing pages: max 3 tiers. Highlight one with Von Restorff Effect.
- Feature lists: progressive disclosure (show 3-5, reveal more on demand).

### Layout and Visual Hierarchy

**Law of Proximity**: Elements placed close together are assumed related.

- Related fields must be visually closer to each other than to unrelated fields.
- Label-to-input gap: `mb-1.5` or `mb-2`. Section-to-section gap: `mb-8` or `mb-12`.
- Never put unrelated items at equal spacing.

**Law of Common Region**: Shared border or background = perceived group.

- Use cards (`bg-zinc-900 border border-zinc-800 rounded-2xl`) to group related content.
- Use dividers (`border-t border-zinc-800`) to separate sections, not whitespace alone.

**Law of Similarity**: Elements that look alike are assumed to behave alike.

- All interactive elements (buttons, links, inputs) must look visually distinct from static content.
- Primary CTAs: always `bg-indigo-600`. Never use the same color for non-interactive elements.
- Links: always `text-indigo-400 hover:text-indigo-300`. Never unstyled.

**Serial Position Effect**: First and last items are best remembered.

- Primary CTA: place at the top or bottom of the viewport, not buried in the middle.
- Navigation: most important action at start or end, never in the center of a list.
- Feature lists: lead with the strongest feature, end with the second strongest.

**Von Restorff Effect**: The different element is the remembered element.

- One and only one primary button per screen section. Everything else is secondary or ghost.
- One pricing tier highlighted. If all tiers are highlighted, none are.
- Use sparingly: a badge, a glow, a border accent. Overuse = noise.

### Interaction Design

**Fitts's Law**: Larger targets closer to attention are easier to hit.

- Primary CTA: minimum `px-6 py-3` (44px+ tap target). Never a tiny button far from content.
- Mobile: bottom sheet CTAs, not top-right. Thumbs reach the bottom.
- Icon-only buttons: minimum `w-10 h-10` click area even if icon is `w-5 h-5`.

**Doherty Threshold**: Response must appear within 400ms to maintain flow.

- Every button that triggers an async action: show loading state immediately.
- Use `isLoading` + `<Loader2 className="animate-spin" />` on submit buttons.
- Skeleton loaders: appear instantly, before any data arrives.

**Goal-Gradient Effect**: Motivation accelerates near completion.

- Multi-step forms: always show a `<progress>` or step indicator ("Step 2 of 4").
- Upload flows: show percentage. Never an indeterminate spinner for file operations.
- Onboarding: show checkmarks as steps complete. Name how many remain.

**Zeigarnik Effect**: Incomplete tasks are remembered better than finished ones.

- Show "resume where you left off" CTAs for abandoned flows (draft saved, profile incomplete).
- Progress badges on incomplete profile sections drive completion.
- "You're 80% done with your setup" is more compelling than a blank dashboard.

### Cognitive Load

**Cognitive Load**: Every non-essential element taxes the brain for free.

- Audit: can any element be removed without losing information?
- Remove decorative text that doesn't help the user's goal.
- Remove icons that don't add meaning.
- Empty states: one headline + one CTA. Not three paragraphs of explanation.

**Tesler's Law**: Complexity can't be eliminated, only moved.

- Smart defaults so users don't have to think: pre-fill, suggest, auto-detect.
- Complex decisions should have a "recommended" option pre-selected.
- Never dump form complexity onto the user when it could be a smart default.

### Emotional Design

**Aesthetic-Usability Effect**: Beautiful UI is perceived as more usable.

- Apply the full design system: dark background, Tailwind, shadcn, Inter/Geist, scroll animations.
- Consistent spacing, consistent corner radius, consistent color usage.
- Hover states and transitions on everything interactive.

**Peak-End Rule**: Experience is judged by its peak and its ending.

- Design the success moment: confetti, bold confirmation, clear next step.
- Design the error moment: friendly, specific, actionable, never "Something went wrong."
- Final screen of a flow should feel like an accomplishment, not just text.

**Chunking**: Break content into visually distinct groups.

- Never show a wall of text. Max 3-4 lines before a visual break.
- Feature grids: 3 columns max, each card self-contained.
- Forms: group by semantic meaning (personal info, payment info, preferences) with visible section headers.

---

## Phase 3: Visual System Implementation

### Required stack (always)

```
- Tailwind CSS (all layout and styling)
- shadcn/ui (all interactive primitives, never raw HTML buttons)
- Lucide React (all icons, never emoji)
- Inter or Geist via next/font
- Framer Motion (for scroll animations and transitions)
- Scroll-aware navbar (mandatory on every page)
```

### Color system

```tsx
// Background: never pure black
className = "bg-[#0a0a0a]"; // or bg-zinc-950

// Surface: card
className = "bg-zinc-900 border border-zinc-800 rounded-2xl";

// Text hierarchy
className = "text-white"; // heading
className = "text-zinc-300"; // body
className = "text-zinc-400"; // secondary
className = "text-zinc-500"; // placeholder / caption

// Accent
className = "text-indigo-400"; // active/accent text
className = "bg-indigo-600"; // primary button
className = "bg-indigo-500/10 border border-indigo-500/20"; // accent surface
```

### Scroll animations (mandatory on marketing/landing pages)

```tsx
// Fade up on enter, every section
<motion.div
  initial={{ opacity: 0, y: 24 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true, margin: "-80px" }}
  transition={{ duration: 0.55, ease: [0.16, 1, 0.3, 1] }}
>
```

### Required scroll-aware navbar

```tsx
// Hidden at top, slides in at 80px, hides near bottom of page
// Pattern lives in .claude/snippets/useScrollNav.tsx -- copy it every time
```

### Scroll effects (MANDATORY on every landing/marketing page)

Every section must animate on scroll. Pick the right technique per element:

**CSS scroll-driven (Chrome 115+ / Firefox 110+):**

```css
/* Fade + slide up: default for all content sections */
.reveal {
  animation: reveal-up linear both;
  animation-timeline: view();
  animation-range: entry 0% entry 40%;
}
@keyframes reveal-up {
  from {
    opacity: 0;
    transform: translateY(28px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Scale reveal: cards and feature blocks */
.scale-reveal {
  animation: scale-in linear both;
  animation-timeline: view();
  animation-range: entry 0% cover 40%;
}
@keyframes scale-in {
  from {
    opacity: 0;
    scale: 0.88;
  }
  to {
    opacity: 1;
    scale: 1;
  }
}

/* Curtain clip reveal: hero images */
.curtain-reveal {
  animation: clip-reveal linear both;
  animation-timeline: view();
  animation-range: entry 0% entry 50%;
}
@keyframes clip-reveal {
  from {
    clip-path: inset(0 0 100% 0);
  }
  to {
    clip-path: inset(0 0 0% 0);
  }
}

/* Reading progress bar: always on long-form content */
.progress-bar {
  position: fixed;
  top: 0;
  left: 0;
  height: 2px;
  background: #6366f1;
  transform-origin: left;
  animation: grow-bar linear;
  animation-timeline: scroll(root);
}
@keyframes grow-bar {
  from {
    transform: scaleX(0);
  }
  to {
    transform: scaleX(1);
  }
}
```

**Staggered card grid with IntersectionObserver (broad support):**

```typescript
const observer = new IntersectionObserver(
  (entries) =>
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add("visible");
        observer.unobserve(e.target);
      }
    }),
  { threshold: 0.15 },
);
document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
```

```css
.reveal {
  opacity: 0;
  transform: translateY(28px);
  transition:
    opacity 0.65s cubic-bezier(0.16, 1, 0.3, 1),
    transform 0.65s cubic-bezier(0.16, 1, 0.3, 1);
}
.reveal.visible {
  opacity: 1;
  transform: none;
}
.reveal:nth-child(2) {
  transition-delay: 0.1s;
}
.reveal:nth-child(3) {
  transition-delay: 0.2s;
}
```

**Sticky section stacking (feature storytelling):**

```css
.card {
  position: sticky;
  border-radius: 20px;
  transition: transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.card:nth-child(1) {
  top: 80px;
}
.card:nth-child(2) {
  top: 104px;
}
.card:nth-child(3) {
  top: 128px;
}
```

**React/Framer Motion:**

```tsx
<motion.div
  initial={{ opacity: 0, y: 24 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true, margin: "-80px" }}
  transition={{ duration: 0.55, ease: [0.16, 1, 0.3, 1] }}
>
```

| Element               | Effect                       |
| --------------------- | ---------------------------- |
| Section headings      | Fade + slide up              |
| Feature card grids    | Scale reveal + stagger delay |
| Hero images           | Curtain clip-path reveal     |
| Storytelling sections | Sticky stacking              |
| Long content          | Reading progress bar         |
| Hero text             | Framer Motion fade + slide   |

Never ship a landing page without scroll animations. Static scrolling looks unfinished.

---

## Phase 4: Build the Component -- Iterative with Per-Iteration Checks

**After writing EACH section (hero, features, CTA, etc.), before moving to the next section, run the mini-audit below. Do not batch and check at the end.**

```
SECTION COMPLETE: {Section name}
------------------------------------
UX LAWS:
[ ] Hick's Law: options visible at once?
[ ] Von Restorff: one clearly highlighted CTA?
[ ] Fitts's Law: tap targets 44px+?
[ ] Proximity/Similarity: visual grouping correct?
[ ] Peak/Doherty: loading + success states present?

AI SLOP:
[ ] No banned phrases (Powerful, Seamless, Leverage, etc.)?
[ ] No em dashes anywhere?
[ ] No emojis?
[ ] Copy specific to THIS product, not generic?

DESIGN:
[ ] Cards have visible background (not transparent)?
[ ] Hover states on all interactive elements?
[ ] Layout varies from previous section?
------------------------------------
PASS? If any box is unchecked, fix before continuing.
```

Follow Phase 2 laws at every component decision. After writing each section, explicitly cite which UX law it satisfies.

Example annotation format:

```tsx
{
  /* Hick's Law: 3 options max. Von Restorff: center card highlighted. */
}
<div className="grid grid-cols-3 gap-6">
  <PricingCard tier="starter" />
  <PricingCard tier="pro" highlighted /> {/* Single differentiated option */}
  <PricingCard tier="enterprise" />
</div>;
```

---

## Phase 5: UX Law Audit (post-build)

Before finishing, run through the audit:

```
UX LAW AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Hick's Law:          [ ] ≤7 options visible at once in menus/nav
Miller's Law:        [ ] ≤9 items in any list before pagination
Fitts's Law:         [ ] Primary CTA is large (44px+) and prominent
Doherty Threshold:   [ ] Every async action shows loading within 400ms
Law of Proximity:    [ ] Related items visually grouped, unrelated items separated
Law of Similarity:   [ ] Interactive elements look different from static content
Von Restorff Effect: [ ] ONE highlighted CTA per section (not two, not zero)
Serial Position:     [ ] Primary action at start or end, not buried in middle
Goal-Gradient:       [ ] Multi-step flows show progress
Cognitive Load:      [ ] Every element earns its place, nothing decorative
Peak-End Rule:       [ ] Success state is satisfying, error state is helpful
Aesthetic-Usability: [ ] Full dark design system applied, hover states on everything
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VIOLATIONS: {list any}
```

Fix every violation before marking done.

---

## Phase 6: States

Every interactive component must have all three:

**Loading**: skeleton loaders (`animate-pulse bg-zinc-800 rounded`), not spinners alone
**Error**: friendly message + retry button (never raw error strings)
**Empty**: illustrated prompt with CTA (never just "No data found")

---

## Common UX Design Mistakes (never do these)

- Navigation with 9+ items at top level → Hick's Law violation
- Two equally-styled primary buttons next to each other → Von Restorff violation
- 15-field form with no grouping → Cognitive Load + Miller's Law violation
- "Submit" button that does nothing visible for 2 seconds → Doherty Threshold violation
- Success screen with just "Done." and no next step → Peak-End Rule violation
- Icon-only button at 16×16px → Fitts's Law violation
- Progress bar that jumps from 0% to 100% with no intermediate states → Goal-Gradient violation
- Form with all fields at equal visual weight → Law of Similarity + Hierarchy violation
