"use client";

// useScrollNav, scroll-aware navbar hook
//
// Behavior:
//   - Returns false at top of page (navbar hidden)
//   - Returns true after scrolling past 80px (navbar visible)
//   - Returns false again when within 200px of page bottom
//
// Usage:
//   const visible = useScrollNav();
//   <nav style={{ transform: visible ? "translateY(0)" : "translateY(-100%)" }}>

import { useEffect, useState } from "react";

export function useScrollNav(threshold = 80, bottomOffset = 200): boolean {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const handle = () => {
      const scrollY = window.scrollY;
      const nearBottom =
        scrollY + window.innerHeight >=
        document.documentElement.scrollHeight - bottomOffset;
      setVisible(scrollY > threshold && !nearBottom);
    };

    window.addEventListener("scroll", handle, { passive: true });
    handle(); // run once on mount to set initial state
    return () => window.removeEventListener("scroll", handle);
  }, [threshold, bottomOffset]);

  return visible;
}

// ─── Example nav component ───────────────────────────────────────────────
//
// export function Navbar() {
//   const visible = useScrollNav();
//   return (
//     <nav
//       className="fixed top-0 left-0 right-0 z-50 backdrop-blur-md bg-zinc-950/80 border-b border-zinc-800/50"
//       style={{
//         transform: visible ? "translateY(0)" : "translateY(-100%)",
//         opacity: visible ? 1 : 0,
//         transition: "transform 0.3s ease, opacity 0.3s ease",
//       }}
//     >
//       ...
//     </nav>
//   );
// }
