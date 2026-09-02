// app/dashboard/page.tsx: Server Component shell
// Replace with your actual page name and content

import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Dashboard | YourApp",
  description: "Manage your YourApp dashboard",
};

// Data fetching at the page level (Server Component)
async function getData() {
  // const data = await fetch("...", { next: { revalidate: 60 } });
  // return data.json();
  return { items: [] };
}

export default async function DashboardPage() {
  const { items } = await getData();

  return (
    <main id="main-content" className="min-h-screen bg-zinc-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Page header */}
        <div className="mb-10">
          <h1 className="text-3xl font-bold text-white tracking-tight">
            Dashboard
          </h1>
          <p className="text-zinc-400 mt-2">
            Overview of your account and activity.
          </p>
        </div>

        {/* Page content */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {items.length === 0 ? (
            <div className="col-span-3 flex flex-col items-center justify-center py-20 text-center">
              <p className="text-zinc-500 text-sm">Nothing here yet.</p>
            </div>
          ) : (
            items.map((item: { id: string; name: string }) => (
              <div
                key={item.id}
                className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6"
              >
                {item.name}
              </div>
            ))
          )}
        </div>
      </div>
    </main>
  );
}
