# Deploy gate

Loads before a production deploy and when `/ship` runs. A checklist that matters
at one moment does not belong in the context of every moment.

## DEPLOYMENT CHECKLIST: RUN BEFORE EVERY PRODUCTION DEPLOY

```
PRE-DEPLOY
[ ] npm run build passes locally (zero errors, zero warnings)
[ ] npm run lint passes (zero warnings, not just zero errors)
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
