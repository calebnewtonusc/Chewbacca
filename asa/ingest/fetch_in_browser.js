// Runs inside a signed-in Thinkific tab. The session cookie never leaves the
// browser: same-origin fetch carries it, and only lesson metadata comes back.
//
// Thinkific paginates nothing here but rate-limits hard on bursts, so the
// per-content loop is serial with a small gap. A 60-lesson course takes about
// a minute, which is cheaper than being throttled into a retry storm.
async () => {
  const slug = location.pathname.match(/\/courses\/take\/([^/]+)/)?.[1];
  if (!slug) return { error: "not on a course page", href: location.href };

  const j = async (u) => {
    const r = await fetch(u, {
      credentials: "include",
      headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
    });
    if (!r.ok) throw new Error(u + " -> " + r.status);
    return r.json();
  };

  const course = await j(`/api/course_player/v2/courses/${slug}`);
  const contents = course.contents || [];
  const details = [];
  const failed = [];

  for (const c of contents) {
    try {
      details.push(await j(`/api/course_player/v2/course_contents/${c.id}`));
    } catch (e) {
      failed.push({ id: c.id, name: c.name, error: String(e) });
    }
    await new Promise((r) => setTimeout(r, 120));
  }

  return { slug, course, details, failed, fetchedAt: new Date().toISOString() };
};
