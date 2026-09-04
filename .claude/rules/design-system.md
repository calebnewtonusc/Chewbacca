# Design system

Loads when a UI file is open. This used to live in CLAUDE.md, so a shell script
session and a Swift session both paid for the Framer Motion rules before either
one started. Roughly 4,000 tokens on every session with no use for a line of it.

Applies to `.tsx`, `.jsx`, `.css`, `.html`, `.vue`, `.svelte`, and any task that
is visibly about how something looks.

## MVP & UI Design: MANDATORY STANDARDS

**Every single UI, MVP, web app, dashboard, landing page, or component must look like a funded startup's product page. No exceptions. If it looks like a CS homework submission, it is wrong and must be rebuilt.**

---

## TECH STACK: ALWAYS USE THESE

### React / Next.js projects

- Tailwind CSS (always)
- shadcn/ui components (always, never build raw buttons, inputs, dialogs from scratch)
- Lucide React icons (always)
- `next/font` with Geist or Inter (always)
- Framer Motion for animations when there's interactivity

### Vanilla HTML (no framework)

- Tailwind CDN (`<script src="https://cdn.tailwindcss.com"></script>`)
- Google Fonts: Inter (`<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet">`)
- Lucide CDN for icons
- Never write raw CSS for layout: Tailwind only

### Vue / Nuxt

- Tailwind CSS + Headless UI + Heroicons

---

## VISUAL DESIGN: MANDATORY

### Color

- **Default palette**: slate/zinc/gray neutrals + one vibrant accent (indigo, violet, blue, emerald, or rose)
- Background: `#0a0a0a` or `zinc-950`, never pure `#000000` or `#ffffff`
- Text primary: `white` or `zinc-50`
- Text muted: `zinc-400` or `zinc-500`
- Accent: `indigo-500` / `indigo-600` as default, change to match brand
- Never use default browser blue links

### Typography

- Font: Inter or Geist, never system fonts, never Times New Roman
- Hero headline: `text-5xl md:text-7xl font-bold tracking-tight`
- Section heading: `text-3xl md:text-4xl font-semibold tracking-tight`
- Body: `text-base text-zinc-300 leading-relaxed`
- Caption/label: `text-sm text-zinc-500`
- Always use `antialiased` on body

### Backgrounds: pick one, never flat black

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
- Consistent gap: `gap-4`, `gap-6`, `gap-8`, never arbitrary values
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

### Navigation: SCROLL-AWARE (MANDATORY ON ALL PROJECTS)

**Every project must use a scroll-aware navbar with this exact behavior:**

- Hidden / transparent at the very top of the page (y = 0)
- Slides down and becomes visible after scrolling past ~80px
- Hides again when the user scrolls within ~200px of the bottom of the page
- Smooth `transition: transform 0.3s ease, opacity 0.3s ease`

**Logic (useScrollNav hook, copy this pattern every time):**

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

**Vanilla HTML equivalent (no React, use this for plain HTML projects):**

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

## INTERACTIVITY: ALL OF THESE ARE REQUIRED

- Every button: hover state + active state + `cursor-pointer` + `transition-all duration-200`
- Every card that's clickable: `hover:scale-[1.02]` or `hover:border-zinc-600`
- Every link: color change on hover
- Loading states: skeleton loaders (animate-pulse), never blank white space
- Empty states: illustrated message with CTA, never just "No data"
- Error states: friendly message with retry, never raw error strings
- Smooth page transitions where applicable

---

## ICONS: ALWAYS REAL ICONS

- Use Lucide React / Lucide CDN, always
- Size: `w-4 h-4` (inline), `w-5 h-5` (buttons), `w-6 h-6` (feature icons), `w-8 h-8` or `w-10 h-10` (hero icons)
- Feature icons: wrap in colored rounded square: `p-2.5 bg-indigo-500/10 rounded-xl text-indigo-400`
- Never use emoji as functional icons
- Never use text characters as icons (→, ×, ✓)

---

## PAGE SECTIONS: HOW TO BUILD THEM

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


## IMAGES: ALWAYS INCLUDE ON PERSONAL SITES

**Every tribute page, person page, or profile site must include real photos of the actual person.**

- Ask the user for the photos, or point at a directory they nominate
- Check Contacts for profile photos
- Ask the user if needed, but never ship a person's page without their face on it
- Photo treatment: `rounded-2xl overflow-hidden border border-white/10` with gradient overlay at bottom
- Include floating stat cards overlapping the photo for depth

## iMESSAGE QUOTES: DESIGN AS iMESSAGE BUBBLES

When the content is iMessage texts/quotes, render them as iMessage-style chat bubbles, not generic quote cards.

- Outgoing (you): right-aligned, `bg-blue-500` bubble, white text
- Incoming (other person): left-aligned, `bg-zinc-800` bubble, white text
- Include timestamp, avatar initial, context label below
- This directly expresses the content instead of generic template thinking

## CONTENT-FIRST DESIGN: ALWAYS

Before writing any component, name what the content IS and pick a design that directly expresses it:

- iMessage quotes → iMessage bubble UI
- Stats/numbers → massive bold gradient typography
- Timeline → editorial magazine spread, not alternating card template
- Tribute site → photo-first, emotional, personal, not SaaS landing page

---
