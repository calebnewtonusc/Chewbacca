---
paths:
  - "projects/**/*.tsx"
  - "projects/**/*.ts"
  - "projects/**/*.html"
  - "projects/**/*.css"
---

# Design Rules

## The Standard

Every UI must look like a funded startup product page or a polished Dribbble shot. If it looks like a CS homework submission, it is wrong and must be rebuilt. The bar is Base44 quality at minimum.

## Content-First Design

Before writing any component, name what the content IS and pick a design that expresses that content directly.

- iMessage quotes → render as iMessage bubble UI, not generic quote cards
- Personal timeline → editorial magazine spread with personality
- Stats/numbers → massive bold typography with gradient treatment
- Tribute/person site → photo-first, emotional, personal

Every section must look visually distinct from every other section on the page.

## Tech Stack (always)

**React / Next.js:**

- Tailwind CSS (always)
- shadcn/ui (always — never build raw buttons, inputs, dialogs from scratch)
- Lucide React icons (always)
- `next/font` with Geist or Inter (always)
- Framer Motion for animations when there is interactivity

**Vanilla HTML:**

- Tailwind CDN
- Google Fonts: Inter
- Lucide CDN for icons
- Never write raw CSS for layout

## Color

- Background: `#0a0a0a` or `zinc-950` — never pure `#000000` or `#ffffff`
- Text primary: `white` or `zinc-50`
- Text muted: `zinc-400` or `zinc-500`
- Accent: `indigo-500` / `indigo-600` as default
- Never use default browser blue links

## Cards: must be visible

- Minimum background: `rgba(255,255,255,0.06)` or solid `zinc-900` / `zinc-800`
- Never use `rgba(255,255,255,0.025)` — it is invisible on dark backgrounds
- Border: `border border-zinc-800` or `border border-white/10`
- Hover: `hover:border-zinc-700` or `hover:border-white/20`
- Every clickable card: `transition-all duration-200 cursor-pointer`

## Typography

- Font: Inter or Geist — NEVER system fonts, NEVER Times New Roman
- Hero headline: `text-5xl md:text-7xl font-bold tracking-tight`
- Section heading: `text-3xl md:text-4xl font-semibold tracking-tight`
- Body: `text-base text-zinc-300 leading-relaxed`
- Always use `antialiased` on body

## Images

- **Always include real photos on personal and tribute sites**: use actual images, never placeholders
- Real people deserve real photos. Never ship a person's page without their face on it
- Photo treatment: `rounded-2xl overflow-hidden` with subtle gradient overlay at bottom
- Photo frame: `border border-white/10` with `box-shadow: 0 32px 80px rgba(0,0,0,0.6)`
- Floating stat cards overlapping the photo add depth and personality

## Marquee / Ticker

Include a scrolling identity-tag marquee strip on tribute and landing pages between Hero and the first content section. It signals personality immediately and breaks the monotony of section stacking.

## Backgrounds: never flat black

- Radial gradient: `radial-gradient(ellipse at top, rgba(indigo/blue, 0.2), transparent)`
- Dot grid: `background-image: radial-gradient(circle, rgba(255,255,255,0.055) 1px, transparent 1px); background-size: 32px 32px`
- Mesh: layered radial gradients at different positions
- Glassmorphism panels: `bg-white/5 backdrop-blur-md border border-white/10`

## Buttons

Primary: `bg-indigo-600 hover:bg-indigo-500 text-white font-semibold px-6 py-2.5 rounded-xl transition-all duration-200 shadow-lg shadow-indigo-500/25 cursor-pointer`

Secondary: `bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 text-zinc-100 font-medium px-6 py-2.5 rounded-xl transition-all duration-200 cursor-pointer`

## Absolute Prohibitions

- NO Times New Roman or system serif fonts
- NO flat gray or white backgrounds without treatment
- NO raw `<button>` without styling
- NO `<a>` tags with default browser blue
- NO layout that breaks on mobile
- NO placeholder content like "Lorem ipsum" in MVPs
- NO components without hover states
- NO glass cards where the glass effect is imperceptible
- NO generic 3-column card grid for every single section — vary layouts
- NO centered heading + subtitle + grid repeated for every section
- NO shipping a tribute/person site without a real photo of the person
- NO inline styles (use Tailwind classes)
- NO em dashes anywhere ever
- NO emojis anywhere ever

## Before Shipping Any UI

Ask: "Does this look like it could be a real YC-backed startup product page or a polished Dribbble shot?"

If no — redesign it.

## Scroll-Aware Navbar (Mandatory)

Every project uses a scroll-aware navbar:

- Hidden at the top (y = 0)
- Slides in after scrolling 80px
- Hides again within 200px of the bottom

```tsx
function useScrollNav() {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const handle = () => {
      const scrollY = window.scrollY;
      const nearBottom =
        scrollY + window.innerHeight >=
        document.documentElement.scrollHeight - 200;
      setVisible(scrollY > 80 && !nearBottom);
    };
    window.addEventListener("scroll", handle, { passive: true });
    return () => window.removeEventListener("scroll", handle);
  }, []);
  return visible;
}
```

Apply with: `style={{ transform: visible ? "translateY(0)" : "translateY(-100%)", opacity: visible ? 1 : 0, transition: "transform 0.3s ease, opacity 0.3s ease" }}`

Never use a static always-visible sticky navbar.

**Vanilla HTML equivalent (plain HTML projects — no React):**

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
