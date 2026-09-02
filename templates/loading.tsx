// app/dashboard/loading.tsx: Next.js automatic loading UI
// Drop this in any route segment to show skeleton while page data loads

export default function Loading() {
  return (
    <main className="min-h-screen bg-zinc-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Header skeleton */}
        <div className="mb-10 animate-pulse">
          <div className="h-8 bg-zinc-800 rounded-lg w-48 mb-3" />
          <div className="h-4 bg-zinc-800 rounded w-72" />
        </div>

        {/* Card grid skeleton */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {Array.from({ length: 6 }).map((_, i) => (
            <CardSkeleton key={i} />
          ))}
        </div>
      </div>
    </main>
  );
}

function CardSkeleton() {
  return (
    <div
      className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 animate-pulse"
      role="status"
      aria-label="Loading"
    >
      <div className="h-10 w-10 bg-zinc-800 rounded-xl mb-4" />
      <div className="h-4 bg-zinc-800 rounded w-3/4 mb-3" />
      <div className="h-3 bg-zinc-800 rounded w-full mb-2" />
      <div className="h-3 bg-zinc-800 rounded w-1/2" />
    </div>
  );
}
