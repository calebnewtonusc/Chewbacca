# Scroll Effects Rules

Source: https://prismic.io/blog/css-scroll-effects

**Use these on every project that has a landing page or marketing page. Scroll effects are expected, not optional.**

---

## The Modern Baseline: CSS Scroll-Driven Animations

Chrome 115+ / Firefox 110+. No JS needed for most visual effects.

```css
/* Fade + slide up when element enters viewport */
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

/* Reading progress bar, pure CSS */
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

/* Scale + fade reveal */
.scale-reveal {
  animation: scale-in linear both;
  animation-timeline: view();
  animation-range: entry 0% cover 40%;
}
@keyframes scale-in {
  from {
    opacity: 0;
    scale: 0.85;
  }
  to {
    opacity: 1;
    scale: 1;
  }
}

/* Clip-path curtain reveal for images */
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
```

---

## Intersection Observer Pattern (Broad Browser Support)

Use this as the fallback when `animation-timeline` isn't supported, and as the baseline for all JS-triggered animations.

```ts
// In a React component or useEffect
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        // optionally unobserve after first trigger:
        observer.unobserve(entry.target);
      }
    });
  },
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
  transform: translateY(0);
}
/* Stagger children */
.reveal:nth-child(2) {
  transition-delay: 0.1s;
}
.reveal:nth-child(3) {
  transition-delay: 0.2s;
}
.reveal:nth-child(4) {
  transition-delay: 0.3s;
}
```

---

## Scroll Velocity Skew (Premium Touch)

Makes content feel physically tied to scroll. Use on hero sections or wrappers for a high-end feel.

```ts
function initVelocitySkew(selector: string) {
  let currentSkew = 0;
  let lastY = window.scrollY;

  function loop() {
    const y = window.scrollY;
    const velocity = (y - lastY) * 0.07;
    currentSkew += (velocity - currentSkew) * 0.1; // lerp to 0
    const el = document.querySelector<HTMLElement>(selector);
    if (el) el.style.transform = `skewY(${currentSkew}deg)`;
    lastY = y;
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}
```

---

## Sticky Section Stacking

Cards stack with increasing offsets. Each one lands with a physics feel via CSS spring.

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
.card:nth-child(4) {
  top: 152px;
}
```

---

## Background Color Transitions on Scroll

```ts
const colorStops = ["#0a0a0a", "#0f0f2e", "#1a0a0a", "#0a1a0a"];

window.addEventListener(
  "scroll",
  () => {
    const pct =
      window.scrollY /
      (document.documentElement.scrollHeight - window.innerHeight);
    const idx = Math.floor(pct * (colorStops.length - 1));
    const t = pct * (colorStops.length - 1) - idx;
    // interpolate between colorStops[idx] and colorStops[idx+1]
    document.body.style.backgroundColor = interpolateColor(
      colorStops[idx],
      colorStops[Math.min(idx + 1, colorStops.length - 1)],
      t,
    );
  },
  { passive: true },
);
```

---

## Hero Image Zoom + Blur on Scroll

```ts
const hero = document.querySelector<HTMLElement>(".hero-image");
window.addEventListener(
  "scroll",
  () => {
    const ratio = Math.min(window.scrollY / window.innerHeight, 1);
    if (hero) {
      hero.style.filter = `blur(${ratio * 8}px)`;
      hero.style.transform = `scale(${1 + ratio * 0.15})`;
    }
  },
  { passive: true },
);
```

---

## Highlight Text on Scroll

```ts
const highlights = document.querySelectorAll(".highlight");
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((e) =>
      e.target.classList.toggle("highlighted", e.isIntersecting),
    );
  },
  { threshold: 0.5 },
);
highlights.forEach((el) => observer.observe(el));
```

```css
.highlight {
  background: linear-gradient(transparent 60%, rgba(99, 102, 241, 0.3) 60%);
  background-size: 0% 100%;
  transition: background-size 0.6s ease;
}
.highlight.highlighted {
  background-size: 100% 100%;
}
```

---

## Parallax (CSS-Only)

```css
.parallax-container {
  perspective: 1px;
  height: 100vh;
  overflow-y: auto;
  overflow-x: hidden;
}
.parallax-bg {
  transform-style: preserve-3d;
}
.parallax-bg--back {
  transform: translateZ(-1px) scale(2);
}
.parallax-bg--mid {
  transform: translateZ(-0.5px) scale(1.5);
}
```

---

## AOS (Animate on Scroll): Drop-in Library

When you need broad support with zero custom code, use AOS (~9KB).

```html
<link rel="stylesheet" href="https://unpkg.com/aos@next/dist/aos.css" />
<script src="https://unpkg.com/aos@next/dist/aos.js"></script>
<script>
  AOS.init({ duration: 800, once: true, offset: 80 });
</script>
```

```html
<div data-aos="fade-up" data-aos-delay="100">Card 1</div>
<div data-aos="fade-up" data-aos-delay="200">Card 2</div>
<div data-aos="fade-up" data-aos-delay="300">Card 3</div>
```

Available presets: `fade`, `fade-up`, `fade-down`, `fade-left`, `fade-right`, `flip-left`, `flip-right`, `zoom-in`, `zoom-out`, `slide-up`

---

## Decision Guide

| Goal                                  | Use                                                      |
| ------------------------------------- | -------------------------------------------------------- |
| Simple fade/slide on scroll enter     | CSS `animation-timeline: view()` or IntersectionObserver |
| Stagger grid of cards                 | IntersectionObserver + `nth-child` `transition-delay`    |
| Scroll-speed distortion / luxury feel | JS RAF velocity skew                                     |
| Sticky storytelling sections          | CSS `position: sticky` stacking                          |
| Background color shifts by section    | GSAP ScrollTrigger `onEnter` or JS interpolation         |
| Reading progress bar                  | CSS `animation-timeline: scroll(root)`                   |
| Hero image depth on scroll            | JS scroll listener + `scale` + `blur`                    |
| Broad browser support, zero setup     | AOS library                                              |
| Pinned / scrubbed complex timelines   | GSAP ScrollTrigger (`scrub: 1`, `pin: true`)             |

---

## Never Do These

- Never skip scroll animations on marketing/landing pages, static scrolling looks unfinished
- Never animate `width`, `height`, `top`, `left`, `margin`. GPU only: `transform` and `opacity`
- Never use scroll animations that delay content rendering (don't gate above-the-fold)
- Never leave `will-change: transform` on permanently, only add it just before animation
