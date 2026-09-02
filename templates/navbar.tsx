"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

// Scroll-aware navbar, mandatory pattern
// Hidden at top, slides in after 80px scroll, hides near bottom
function useScrollNav() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const handle = () => {
      const scrollY = window.scrollY;
      const nearBottom =
        scrollY + window.innerHeight >=
        document.documentElement.scrollHeight - 200;
      setVisible(scrollY > 80 && !nearBottom);
    };
    window.addEventListener("scroll", handle, { passive: true });
    return () => window.removeEventListener("scroll", handle);
  }, []);

  return visible;
}

const NAV_LINKS = [
  { label: "Features", href: "#features" },
  { label: "Pricing", href: "#pricing" },
  { label: "Docs", href: "/docs" },
];

export function Navbar() {
  const visible = useScrollNav();

  return (
    <nav
      className="fixed top-0 left-0 right-0 z-50 backdrop-blur-md bg-zinc-950/80 border-b border-zinc-800/50"
      style={{
        transform: visible ? "translateY(0)" : "translateY(-100%)",
        opacity: visible ? 1 : 0,
        transition: "transform 0.3s ease, opacity 0.3s ease",
      }}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link
            href="/"
            className="text-white font-bold text-lg tracking-tight hover:text-zinc-300 transition-colors duration-200"
          >
            YourApp
          </Link>

          {/* Nav links */}
          <div className="hidden md:flex items-center gap-6">
            {NAV_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className="text-sm text-zinc-400 hover:text-white transition-colors duration-200"
              >
                {link.label}
              </Link>
            ))}
          </div>

          {/* CTA */}
          <div className="flex items-center gap-3">
            <Link
              href="/login"
              className="text-sm text-zinc-400 hover:text-white transition-colors duration-200"
            >
              Sign in
            </Link>
            <Link
              href="/signup"
              className="bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold px-4 py-2 rounded-lg transition-all duration-200 shadow-lg shadow-indigo-500/25 cursor-pointer"
            >
              Get started
            </Link>
          </div>
        </div>
      </div>
    </nav>
  );
}
