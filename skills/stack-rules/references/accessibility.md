# Accessibility Rules

## Semantic HTML First

Use the right element for the job:

```tsx
<nav aria-label="Main navigation">...</nav>
<header>, <main>, <footer>, <aside>, <section>

// One h1 per page, hierarchical h2-h6
<h1>Page Title</h1>
<h2>Section</h2>

// Button: triggers action. Link: navigates.
<button onClick={handleSubmit}>Submit</button>
<a href="/about">About</a>
```

## Interactive Elements

All interactive elements must be keyboard accessible:

```tsx
// Always use real <button>, never div with onClick
<button
  onClick={handleClick}
  className="focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-zinc-950"
  aria-label="Close dialog"
>
  <X className="w-4 h-4" />
</button>
```

Never remove focus styles. Make them visible.

## Images and Icons

```tsx
// Meaningful images — descriptive alt
<Image src="/hero.jpg" alt="Team working at a whiteboard" />

// Decorative — empty alt
<Image src="/wave.svg" alt="" />

// Icon-only buttons — aria-label required
<button aria-label="Delete post">
  <Trash2 className="w-4 h-4" />
</button>

// Icon alongside text — mark icon as decorative
<button>
  <Trash2 className="w-4 h-4" aria-hidden="true" />
  Delete post
</button>
```

## Forms

```tsx
<label htmlFor="email" className="text-sm text-zinc-400">
  Email address
</label>
<input
  id="email"
  type="email"
  autoComplete="email"
  aria-required="true"
  aria-describedby="email-error"
/>
{error && (
  <p id="email-error" role="alert" className="text-sm text-red-400">
    {error}
  </p>
)}
```

## Color Contrast (WCAG AA)

- Normal text: 4.5:1 minimum
- Large text (18px+ or 14px+ bold): 3:1
- UI components and icons: 3:1

The design system zinc/indigo palette meets these ratios. Verify custom colors at webaim.org/resources/contrastchecker.

## Skip Navigation

First child of body:

```tsx
<a
  href="#main-content"
  className="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-50 focus:px-4 focus:py-2 focus:bg-indigo-600 focus:text-white focus:rounded-lg"
>
  Skip to main content
</a>
```

## ARIA Roles and States

```tsx
// Loading
<div role="status" aria-label="Loading">
  <div className="animate-pulse ..." />
</div>

// Dialog
<div role="dialog" aria-modal="true" aria-labelledby="dialog-title">
  <h2 id="dialog-title">Confirm Delete</h2>
</div>

// Expandable
<button aria-expanded={isOpen} aria-controls="panel-id">Toggle</button>
<div id="panel-id" hidden={!isOpen}>...</div>
```

## Reduced Motion

```tsx
import { useReducedMotion } from "framer-motion";

function AnimatedCard() {
  const shouldReduceMotion = useReducedMotion();
  return (
    <motion.div
      initial={shouldReduceMotion ? {} : { opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
    />
  );
}
```

## Never Do These

- Never remove `outline` without a visible focus alternative
- Never rely solely on color to convey meaning
- Never autoplay video or audio
- Never use `tabIndex` values greater than 0
- Never build a modal that doesn't trap focus
- Never use placeholder text as a label substitute
