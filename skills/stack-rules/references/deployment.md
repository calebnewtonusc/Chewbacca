# Deployment Rules

## Default Deploy Target: Vercel

All Next.js projects deploy to Vercel. Use the `/deploy` command.

```bash
vercel --prod
```

- Never deploy without running typecheck + lint first
- Never deploy with `.env` leaked into source
- Always confirm the preview URL before promoting to production

## vercel.json Baseline

```json
{
  "framework": "nextjs",
  "buildCommand": "npm run build",
  "devCommand": "npm run dev",
  "installCommand": "npm install"
}
```

## Environment Variables

Set in Vercel dashboard, not hardcoded. Three environments:

- `Development`: local dev, optional
- `Preview`: PRs and branch deploys
- `Production`: main branch only

Never put production secrets in Preview environments if they're not safe to expose.

## Pre-Deploy Checklist

Before every production deploy:

1. `npm run build` passes locally (catches type errors Vercel will catch)
2. `npm run lint` passes with zero warnings
3. No `.env` files staged in git
4. No `console.log` debug statements in critical paths
5. No hardcoded localhost URLs
6. No `TODO: fix before deploy` comments

## Branch Strategy

- `main`: production, always deployable
- Feature branches → Vercel preview deployments automatically
- Never merge to main without a passing preview deploy

## Domain Setup

After first deploy:

1. Add custom domain in Vercel dashboard
2. Update DNS (CNAME to `cname.vercel-dns.com`)
3. Enable HTTPS (automatic)
4. Set `NEXT_PUBLIC_APP_URL` to the production URL

## GitHub Integration

Always push to GitHub first, then let Vercel deploy from the repo:

```bash
git push origin main
# Vercel auto-deploys from the push
```

Never use `vercel deploy` from local for production — always go through GitHub.

## Build Optimization

- Use `next/image` for all images — never `<img>`
- Use `next/font` for fonts — never Google Fonts CDN link in Next.js
- Enable ISR or SSG where data doesn't change per request
- Use `generateStaticParams` for dynamic routes with known values

## Post-Deploy Verification

After every deploy:

1. Open the production URL and verify it loads
2. Check the Vercel dashboard for build errors
3. Test the primary user flow manually
4. Check Vercel Function logs for runtime errors

## Never Do These

- Never deploy from a dirty git working tree
- Never skip the build check locally
- Never hardcode the Vercel project ID or org ID
- Never put secrets in `next.config.ts` `env` block (they get bundled into client JS)
