// Read every course: the gradebook, the content tree, the document bodies and
// the attached files.
import { api } from './session.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const COLS = 'isExcludedFromCourseUserActivity=true&expand=associatedRubrics,collectExternalSubmissions&includeInvisible=false';

export const stripHtml = (html) => html
  .replace(/<br\s*\/?>/gi, '\n')
  .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, '\n')
  .replace(/<li[^>]*>/gi, '  - ')
  .replace(/<[^>]+>/g, '')
  .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/\n{3,}/g, '\n\n').trim();

export async function courses(page, host, userId) {
  const r = await api(page, host,
    `/learn/api/v1/users/${userId}/memberships?expand=course.effectiveAvailability,course.permissions,courseRole&includeCount=true&limit=10000`);
  return (r.json?.results ?? []).map((m) => m.course).filter(Boolean);
}

export async function readCourse(page, host, c, out) {
  mkdirSync(`${out}/raw`, { recursive: true });
  mkdirSync(`${out}/docs`, { recursive: true });
  mkdirSync(`${out}/files`, { recursive: true });

  // Open the outline first. Ultra is a single-page app and the content tree is
  // only warm after its own screen has asked for it.
  await page.goto(`https://${host}/ultra/courses/${c.id}/cl/outline`, { waitUntil: 'domcontentloaded' }).catch(() => {});
  await page.waitForTimeout(7000);

  const bundle = {};
  for (const [k, path] of Object.entries({
    course: `/learn/api/v1/courses/${c.id}`,
    columns: `/learn/api/v1/courses/${c.id}/gradebook/columns?${COLS}`,
    contents: `/learn/api/v1/courses/${c.id}/contents?expand=body&recursive=true`,
    announcements: `/learn/api/v1/courses/${c.id}/announcements?limit=100`,
    memberships: `/learn/api/v1/courses/${c.id}/memberships?isExcludedFromCourseUserActivity=true&limit=10000`,
  })) bundle[k] = await api(page, host, path);

  writeFileSync(`${out}/raw/course-${c.courseId}.json`, JSON.stringify(bundle, null, 2));
  writeFileSync(`${out}/raw/outline-${c.courseId}.txt`,
    await page.evaluate(() => document.body.innerText).catch(() => ''));

  return bundle;
}

// The prose: policies, instructions, links. The content listing does NOT
// return document bodies, only a per-item GET does, so this costs one request
// per item and there is no batch form.
export async function readProse(page, host, ctx, c, bundle, out) {
  const items = bundle.contents.json?.results ?? [];
  const lines = [`# ${c.courseId}  ${c.name}`, ''];
  const files = [];

  for (const it of items) {
    const handler = (it.contentHandler ?? '').replace('resource/x-bb-', '');
    if (['document', 'folder', 'lesson', 'courselink', 'asmt-test-link'].includes(handler)) {
      const r = await api(page, host, `/learn/api/v1/courses/${c.id}/contents/${it.id}`);
      const raw = r.json?.body?.rawText ?? '';
      const desc = it.description ? stripHtml(it.description) : '';
      const text = raw ? stripHtml(raw) : '';
      if (text || desc) {
        lines.push(`\n----- [${handler}] ${it.title}  (${it.id})`);
        if (desc) lines.push(desc);
        if (text) lines.push(text);
      }
      // A syllabus is routinely a link out to Google Docs rather than a file.
      for (const m of raw.matchAll(/href="([^"]+)"[^>]*>([^<]*)/g)) {
        lines.push(`      LINK: ${m[2].trim()} -> ${m[1].replace(/&amp;/g, '&')}`);
      }
    }
    for (const v of Object.values(it.contentDetail ?? {})) {
      const f = v?.file;
      if (!f?.permanentUrl) continue;
      const res = await ctx.request.get(`https://${host}${f.permanentUrl}`);
      if (!res.ok()) continue;
      const name = `${c.courseId}__${f.fileName}`.replace(/[/\\]/g, '_');
      writeFileSync(`${out}/files/${name}`, await res.body());
      files.push(name);
    }
  }
  writeFileSync(`${out}/docs/${c.courseId}.txt`, lines.join('\n'));
  return { chars: lines.join('\n').length, files };
}
