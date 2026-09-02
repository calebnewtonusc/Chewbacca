// app/not-found.tsx: Global 404 page

import Link from "next/link";
import { ArrowLeft, SearchX } from "lucide-react";

export default function NotFound() {
  return (
    <main className="min-h-screen bg-zinc-950 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-zinc-900 via-zinc-950 to-zinc-950 flex items-center justify-center">
      <div className="flex flex-col items-center justify-center text-center px-4">
        {/* 404 number */}
        <p className="text-9xl font-black bg-gradient-to-r from-zinc-700 to-zinc-800 bg-clip-text text-transparent mb-4 leading-none select-none">
          404
        </p>

        {/* Icon */}
        <div className="p-4 bg-zinc-800/50 rounded-2xl border border-zinc-700/50 mb-6">
          <SearchX className="w-8 h-8 text-zinc-500" />
        </div>

        {/* Message */}
        <h1 className="text-2xl font-bold text-white mb-3">Page not found</h1>
        <p className="text-zinc-400 text-sm leading-relaxed max-w-sm mb-8">
          The page you&apos;re looking for doesn&apos;t exist or has been moved.
        </p>

        {/* Back home */}
        <Link
          href="/"
          className="flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold px-6 py-2.5 rounded-xl transition-all duration-200 shadow-lg shadow-indigo-500/25 cursor-pointer"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to home
        </Link>
      </div>
    </main>
  );
}
