# Naming Conventions

## Files and Directories

- React components: `PascalCase.tsx` (`UserCard.tsx`, `HeroSection.tsx`)
- Hooks: `camelCase.ts` prefixed with `use` (`useScrollNav.ts`, `useAuth.ts`)
- Utilities: `camelCase.ts` (`formatDate.ts`, `parseQuery.ts`)
- Constants: `SCREAMING_SNAKE_CASE.ts` (`API_ROUTES.ts`) or `camelCase.ts` for module-scope
- Types/interfaces: `PascalCase.ts` (`types.ts`, `schema.ts`)
- API routes: `route.ts` inside descriptive directories (`app/api/users/route.ts`)
- Pages: `page.tsx` inside descriptive directories (`app/dashboard/page.tsx`)
- Layouts: `layout.tsx`
- Server actions: `actions.ts` or `{resource}.actions.ts`

## TypeScript Identifiers

- Variables and functions: `camelCase`
- Classes and types: `PascalCase`
- Enums: `PascalCase` with `PascalCase` members
- Constants: `SCREAMING_SNAKE_CASE` if truly global/config, `camelCase` if local
- Boolean variables: prefix with `is`, `has`, `can`, `should` (`isLoading`, `hasError`, `canEdit`)
- Event handlers: prefix with `handle` (`handleSubmit`, `handleKeyDown`)
- Async functions: use verbs, optionally suffix with `Async` for clarity if needed

## React Components

```ts
// Component name matches filename
export function UserCard({ user }: { user: User }) {}

// Props interface: {ComponentName}Props
interface UserCardProps {
  user: User;
  onEdit?: (id: string) => void;
}

export function UserCard({ user, onEdit }: UserCardProps) {}
```

## Database (Supabase/Postgres)

- Tables: `snake_case`, plural (`users`, `blog_posts`)
- Columns: `snake_case` (`created_at`, `user_id`, `profile_image_url`)
- Indexes: `{table}_{column}_idx` (`posts_user_id_idx`)
- Functions: `snake_case` verbs (`get_user_posts`, `update_profile`)
- Enums: `snake_case` (`post_status`, `user_role`)

## CSS / Tailwind

- Use Tailwind utility classes, no custom class names unless absolutely necessary
- If custom classes are needed: `kebab-case` (`hero-gradient`, `card-hover`)
- CSS custom properties: `--kebab-case` (`--color-accent`, `--font-display`)

## Git

- Branches: `{type}/{slug}` (`feat/user-dashboard`, `fix/auth-redirect`, `chore/update-deps`)
- Commits: `{type}: {description}` in lowercase (`feat: add profile page`, `fix: resolve null crash`)

## API Routes

- Endpoints: `kebab-case` nouns, plural (`/api/users`, `/api/blog-posts`)
- Query params: `camelCase` (`?userId=`, `?pageSize=`)
- JSON body keys: `camelCase`

## Environment Variables

- `SCREAMING_SNAKE_CASE` for all env vars
- Prefix client-safe with `NEXT_PUBLIC_`
- Group related vars with prefix (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`)

## Anti-patterns to Avoid

- No abbreviations unless universally understood (`url`, `id`, `html` are fine; `usr`, `btn`, `cnt` are not)
- No single-letter variables outside of loops (`i`, `j` are fine in for loops)
- No misleading names (`data`, `info`, `stuff`, `thing`, be specific)
- No type names that include the word "type" (`UserType` → just `User`)
