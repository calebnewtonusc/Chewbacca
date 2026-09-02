# Component Rules

## Always Use shadcn/ui: Never Build Primitives From Scratch

Before writing any UI component, check if shadcn/ui has it:

```bash
npx shadcn@latest add button
npx shadcn@latest add dialog
npx shadcn@latest add input
npx shadcn@latest add select
npx shadcn@latest add card
npx shadcn@latest add toast
npx shadcn@latest add dropdown-menu
npx shadcn@latest add tabs
npx shadcn@latest add badge
npx shadcn@latest add skeleton
```

Only build custom components for things shadcn/ui doesn't cover.

## Component File Structure

```ts
// 1. Imports
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";

// 2. Types
interface UserCardProps {
  user: User;
  onEdit?: (id: string) => void;
}

// 3. Component
export function UserCard({ user, onEdit }: UserCardProps) {
  // 4. State and hooks at top
  const [isExpanded, setIsExpanded] = useState(false);

  // 5. Derived values
  const displayName = user.firstName + " " + user.lastName;

  // 6. Handlers
  const handleEdit = () => onEdit?.(user.id);

  // 7. Early returns for loading/error/empty
  if (!user) return null;

  // 8. Render
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6">
      {/* ... */}
    </div>
  );
}
```

## Skeleton Loaders: Required for Every Async Component

Never show blank space while loading. Every component that fetches data needs a skeleton:

```tsx
export function UserCardSkeleton() {
  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 animate-pulse">
      <div className="h-4 bg-zinc-800 rounded w-3/4 mb-3" />
      <div className="h-3 bg-zinc-800 rounded w-1/2" />
    </div>
  );
}
```

## Empty States: Required for Every List Component

Never show nothing when a list is empty:

```tsx
export function EmptyState({ title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <div className="p-4 bg-zinc-800/50 rounded-2xl mb-4">
        <InboxIcon className="w-8 h-8 text-zinc-500" />
      </div>
      <h3 className="text-lg font-semibold text-zinc-200 mb-2">{title}</h3>
      <p className="text-zinc-500 text-sm max-w-sm mb-6">{description}</p>
      {action && <Button onClick={action.onClick}>{action.label}</Button>}
    </div>
  );
}
```

## Error States

```tsx
export function ErrorMessage({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="p-3 bg-red-500/10 rounded-xl mb-4">
        <AlertCircle className="w-6 h-6 text-red-400" />
      </div>
      <p className="text-zinc-400 text-sm mb-4">{message}</p>
      {onRetry && (
        <Button variant="outline" onClick={onRetry} size="sm">
          Try again
        </Button>
      )}
    </div>
  );
}
```

## Toast Notifications

Use shadcn/ui `useToast`, never build custom toast:

```tsx
import { useToast } from "@/hooks/use-toast";

const { toast } = useToast();

// Success
toast({ title: "Saved!", description: "Your changes have been saved." });

// Error
toast({ title: "Error", description: err.message, variant: "destructive" });
```

## Modal / Dialog Pattern

```tsx
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

<Dialog>
  <DialogTrigger asChild>
    <Button>Open</Button>
  </DialogTrigger>
  <DialogContent className="bg-zinc-900 border-zinc-800">
    <DialogHeader>
      <DialogTitle>Title</DialogTitle>
    </DialogHeader>
    {/* content */}
  </DialogContent>
</Dialog>;
```

## Icons: Lucide React Only

```tsx
import { Loader2, Check, X, ChevronRight, ArrowRight } from "lucide-react";

// Loading spinner
<Loader2 className="w-4 h-4 animate-spin" />

// Feature icon with colored bubble
<div className="p-2.5 bg-indigo-500/10 rounded-xl">
  <Zap className="w-5 h-5 text-indigo-400" />
</div>
```

Never use emoji as icons. Never use text characters (→, ×) as icons.

## Component Composition

Prefer composition over props drilling:

```tsx
// Bad: prop drilling
<Card title="..." description="..." footer="..." icon="..." />

// Good: composition
<Card>
  <Card.Header>
    <Card.Icon><Zap /></Card.Icon>
    <Card.Title>Title</Card.Title>
  </Card.Header>
  <Card.Body>Description</Card.Body>
  <Card.Footer>...</Card.Footer>
</Card>
```

## Never Do These

- Never build a custom button, input, dialog, select, or dropdown, use shadcn/ui
- Never use inline styles: Tailwind only
- Never render `null` on error, show an error state
- Never render nothing on empty, show an empty state
- Never forget loading state on any async component
- Never put business logic inside JSX, extract to handlers or hooks
