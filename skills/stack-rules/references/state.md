# State Management Rules

## State Hierarchy: Choose the Lowest Level That Works

1. **Server state** (DB/API data) → React Query or SWR
2. **URL state** (filters, tabs, pagination) → `useSearchParams` / router
3. **Local component state** → `useState`
4. **Shared UI state** (modals, toasts, sidebar) → Zustand or React Context
5. **Form state** → React Hook Form
6. **Global app state** → Zustand (rarely needed)

Never reach for Zustand when `useState` is sufficient. Never reach for Context when URL params work better.

## Server State: React Query

For any data that lives in a database or external API:

```ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";

// Fetch
const {
  data: posts,
  isLoading,
  error,
} = useQuery({
  queryKey: ["posts", { userId, page }],
  queryFn: () => fetchPosts({ userId, page }),
  staleTime: 5 * 60 * 1000, // 5 minutes
});

// Mutate with optimistic update
const queryClient = useQueryClient();
const { mutate: deletePost } = useMutation({
  mutationFn: (id: string) => api.delete(`/posts/${id}`),
  onMutate: async (id) => {
    await queryClient.cancelQueries({ queryKey: ["posts"] });
    const previous = queryClient.getQueryData(["posts"]);
    queryClient.setQueryData(["posts"], (old: Post[]) =>
      old.filter((p) => p.id !== id),
    );
    return { previous };
  },
  onError: (err, id, context) => {
    queryClient.setQueryData(["posts"], context?.previous);
  },
  onSettled: () => queryClient.invalidateQueries({ queryKey: ["posts"] }),
});
```

## URL State: Filters and Pagination

```ts
import { useRouter, useSearchParams } from "next/navigation";

function FilterBar() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const setFilter = (key: string, value: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set(key, value);
    router.push(`?${params.toString()}`);
  };
}
```

Use URL state for: tab selection, sort order, filter values, page number, search query. This makes pages shareable and back-button-friendly.

## Local Component State

```ts
// Simple toggle
const [isOpen, setIsOpen] = useState(false);

// Loading state for async operations
const [isPending, startTransition] = useTransition();

// Derived state, compute from existing state, don't store separately
const filteredPosts = useMemo(
  () => posts.filter((p) => p.status === activeFilter),
  [posts, activeFilter],
);
```

Never store derived state, compute it. Never duplicate server state in local state.

## Shared UI State: Zustand

For UI state shared across unrelated components (modals, toasts, sidebar):

```ts
import { create } from "zustand";

interface UIStore {
  isSidebarOpen: boolean;
  openSidebar: () => void;
  closeSidebar: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  isSidebarOpen: false,
  openSidebar: () => set({ isSidebarOpen: true }),
  closeSidebar: () => set({ isSidebarOpen: false }),
}));
```

## Form State: React Hook Form

```ts
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

type FormData = z.infer<typeof schema>;

function LoginForm() {
  const { register, handleSubmit, formState: { errors, isSubmitting } } =
    useForm<FormData>({ resolver: zodResolver(schema) });

  const onSubmit = async (data: FormData) => { /* ... */ };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("email")} />
      {errors.email && <p>{errors.email.message}</p>}
    </form>
  );
}
```

## Loading and Error States

Every async operation needs all three states handled:

```tsx
if (isLoading) return <Skeleton />;
if (error) return <ErrorMessage message={error.message} onRetry={refetch} />;
if (!data || data.length === 0) return <EmptyState />;
return <DataList data={data} />;
```

Never show blank white space or raw error strings.

## Never Do These

- Never store server state in Zustand, use React Query
- Never use Context for high-frequency updates (it rerenders all consumers)
- Never store derived values in state, compute them with useMemo
- Never mutate state directly, always use setter functions
- Never put async logic in useState setters
