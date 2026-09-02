# Performance Rules

## Images: Always Use next/image

```tsx
import Image from "next/image";

<Image
  src="/hero.jpg"
  alt="Hero image"
  width={1200}
  height={600}
  priority // use on above-the-fold images
  className="rounded-2xl object-cover"
/>;
```

- Never use raw `<img>` tags in Next.js projects
- Always set `width` and `height` to prevent layout shift
- Use `priority` for above-the-fold images, lazy loading is automatic for the rest
- Use `sizes` prop for responsive images: `sizes="(max-width: 768px) 100vw, 50vw"`

## Fonts: Always Use next/font

```tsx
import { Inter } from "next/font/google";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

export default function RootLayout({ children }) {
  return <html className={inter.variable}>{children}</html>;
}
```

Never use `<link href="fonts.googleapis.com/...">` in Next.js, it bypasses optimization.

## Code Splitting

- Use dynamic imports for large components not needed on initial load:

```tsx
import dynamic from "next/dynamic";

const HeavyChart = dynamic(() => import("@/components/HeavyChart"), {
  loading: () => <div className="animate-pulse bg-zinc-800 rounded-2xl h-64" />,
  ssr: false, // if it uses browser APIs
});
```

- Use `React.lazy` + `Suspense` for client-only heavy components

## Data Fetching

- Prefer Server Components for data fetching, zero JS sent to client
- Use `fetch` with cache control in server components:

```ts
// Cached (static)
const data = await fetch(url, { cache: "force-cache" });

// Revalidate every 60 seconds
const data = await fetch(url, { next: { revalidate: 60 } });

// Never cached (dynamic)
const data = await fetch(url, { cache: "no-store" });
```

- Use React Query or SWR for client-side data that changes:

```ts
const { data, isLoading } = useQuery({
  queryKey: ["posts", userId],
  queryFn: () => fetchPosts(userId),
  staleTime: 5 * 60 * 1000, // 5 minutes
});
```

## Bundle Size

- Never import entire libraries when tree-shaking subsets:

```ts
// Bad
import _ from "lodash";
_.debounce(fn, 300);

// Good
import debounce from "lodash/debounce";
debounce(fn, 300);

// Best: use native equivalents when possible
```

- Regularly check bundle size: `npm run build` shows route sizes
- Flag any route over 100KB first load JS, investigate and optimize

## Rendering Strategy

- Default to Server Components (RSC), no `"use client"` unless needed
- Add `"use client"` only when the component uses: hooks, event handlers, browser APIs
- Keep `"use client"` boundaries as deep in the tree as possible

## Animation Performance

```tsx
// Use transform and opacity: GPU-accelerated
// Never animate: width, height, top, left, margin, padding

// Good
whileHover={{ scale: 1.02 }} // triggers transform

// Bad
whileHover={{ width: "110%" }} // triggers layout recalc
```

Use `will-change: transform` sparingly for elements that animate frequently.

## Database Query Performance

- Always limit query results: `.limit(20)` or pagination
- Never fetch all rows: no `.from("table").select()`without `.limit()` in production
- Use indexes on columns in WHERE/ORDER BY clauses
- Use `.select("col1, col2")`, never `select("*")` in production

## Core Web Vitals Targets

- LCP (Largest Contentful Paint): under 2.5s
- CLS (Cumulative Layout Shift): under 0.1
- INP (Interaction to Next Paint): under 200ms

Run `npx lighthouse` or check Vercel's Speed Insights after every major deploy.

## Never Do These

- Never block the main thread with synchronous heavy computation, use Web Workers
- Never load analytics/tracking scripts before page is interactive
- Never use `useEffect` to fetch data that could be a Server Component
- Never ignore Lighthouse warnings on production routes
