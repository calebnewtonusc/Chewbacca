"use client";

// app/dashboard/error.tsx: Next.js error boundary
// Must be a Client Component. Catches errors in route segment.

import { useEffect } from "react";
import { AlertCircle, RefreshCw } from "lucide-react";

interface ErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function Error({ error, reset }: ErrorProps) {
  useEffect(() => {
    // Log to error reporting service (Sentry, etc.)
    console.error("[Route Error]", error);
  }, [error]);

  return (
    <main className="min-h-screen bg-zinc-950 flex items-center justify-center">
      <div className="flex flex-col items-center justify-center py-20 text-center max-w-md mx-auto px-4">
        {/* Icon */}
        <div className="p-4 bg-red-500/10 rounded-2xl border border-red-500/20 mb-6">
          <AlertCircle className="w-8 h-8 text-red-400" />
        </div>

        {/* Message */}
        <h2 className="text-xl font-semibold text-white mb-3">
          Something went wrong
        </h2>
        <p className="text-zinc-400 text-sm leading-relaxed mb-8">
          {process.env.NODE_ENV === "development"
            ? error.message
            : "An unexpected error occurred. Please try again."}
        </p>

        {/* Retry */}
        <button
          onClick={reset}
          className="flex items-center gap-2 bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 text-zinc-100 font-medium px-6 py-2.5 rounded-xl transition-all duration-200 cursor-pointer"
        >
          <RefreshCw className="w-4 h-4" />
          Try again
        </button>
      </div>
    </main>
  );
}
