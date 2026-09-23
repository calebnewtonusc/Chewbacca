#!/usr/bin/env node
// course-ingest: read a Blackboard Ultra term into data, and put its graded
// deadlines on Apple Calendar.
//
//   course-ingest --host lms.example.edu --school example --calendar "Fall 2026"
//   course-ingest --school example --signin            # first run, or when the session dies
//   course-ingest --school example --dry-run           # read and report, write nothing
//
// The split is deliberate and it is the rule in review-discipline.md: reading
// creates nothing. --dry-run prints exactly the events a real run would add,
// and a real run adds exactly those. A preview that is not the work is not
// worth reading.
import { open, signedIn, api } from './lib/session.mjs';
import { courses as listCourses, readCourse, readProse } from './lib/read.mjs';
import { write as writeCalendar, clear as clearCalendar } from './lib/calendar.mjs';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const argv = process.argv.slice(2);
const flag = (n, d = null) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : (argv[i + 1]?.startsWith('--') ? true : argv[i + 1]); };
const has  = (n) => argv.includes(`--${n}`);
const expand = (p) => p.replace(/^~/, homedir());

// The school is the user's, so it never defaults in this file. The first run
// names it and ~/.chewbacca/course-ingest.json remembers it.
const localPath = expand('~/.chewbacca/course-ingest.json');
const local = existsSync(localPath) ? JSON.parse(readFileSync(localPath, 'utf8')) : {};

const cfg = {
  host: flag('host', local.host ?? null),
  school: flag('school', local.school ?? null),
  calendar: flag('calendar'),
  courses: (flag('courses', '') || '').split(',').map((s) => s.trim()).filter(Boolean),
  since: flag('since') ?? new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10),
  until: flag('until') ?? new Date(Date.now() + 180 * 864e5).toISOString().slice(0, 10),
  out: expand(flag('out', '~/coursework/.ingest')),
  headed: has('headed') || has('signin'),
};
const dryRun = has('dry-run');
if (!cfg.host || !cfg.school) {
  console.error('Which school? Run once with --host <Blackboard Ultra hostname> --school <short name>.');
  process.exit(2);
}
if (local.host !== cfg.host || local.school !== cfg.school) {
  mkdirSync(expand('~/.chewbacca'), { recursive: true });
  writeFileSync(localPath, JSON.stringify({ host: cfg.host, school: cfg.school }, null, 2) + '\n', { mode: 0o600 });
}
cfg.out = `${cfg.out}/${cfg.school}`;
for (const d of ['raw', 'docs', 'files']) mkdirSync(`${cfg.out}/${d}`, { recursive: true });

const s = await open(cfg, { fresh: has('signin') });

if (has('signin')) {
  await s.page.goto(`https://${cfg.host}/ultra/stream`, { waitUntil: 'domcontentloaded' });
  process.stdout.write('Sign in in the window that opened');
  const deadline = Date.now() + 300000;
  while (Date.now() < deadline) {
    await s.page.waitForTimeout(2000);
    const ok = await s.page.evaluate(() => !document.querySelector('input[type="password"]') &&
      location.pathname.startsWith('/ultra')).catch(() => false);
    if (ok) { await s.save(); console.log('\nSIGNED IN, session saved.'); await s.close(); process.exit(0); }
    process.stdout.write('.');
  }
  console.log('\nTimed out, not signed in.'); await s.close(); process.exit(1);
}

if (!(await signedIn(s.page, cfg.host))) {
  console.error(`Not signed in. Run: course-ingest --school ${cfg.school} --signin`);
  await s.close(); process.exit(1);
}

const me = (await api(s.page, cfg.host, '/learn/api/v1/users/me')).json;
let all = await listCourses(s.page, cfg.host, me.id);
if (cfg.courses.length) {
  all = all.filter((c) => cfg.courses.some((want) => (c.courseId + ' ' + c.name).toUpperCase().includes(want.toUpperCase())));
}
writeFileSync(`${cfg.out}/raw/courses.json`, JSON.stringify(all, null, 2));
console.log(`${all.length} course(s) as ${me.userName ?? me.id}`);

const deliverables = [];
const report = [];

for (const c of all) {
  const bundle = await readCourse(s.page, cfg.host, c, cfg.out);
  const prose = await readProse(s.page, cfg.host, s.ctx, c, bundle, cfg.out);
  const cols = bundle.columns.json?.results ?? [];
  const dated = cols.filter((x) => x.dueDate && !/^Participation and Attendance Grade$/i.test(x.columnName ?? ''));
  const short = (c.courseId.match(/[A-Z]{3,4}[- ]?\d{4}/) ?? [c.courseId])[0].replace('-', ' ');

  for (const col of dated) {
    deliverables.push({
      course: short,
      name: (col.columnName ?? col.effectiveColumnName ?? '?').replace(/\s+/g, ' ').trim(),
      due: col.dueDate,
      type: (col.gradebookCategory?.title ?? '').replace('.name', '').toLowerCase() || 'graded',
      points: col.possible,
      source: `${cfg.host} gradebook column ${col.id}, read ${new Date().toISOString().slice(0, 10)}`,
      url: `https://${cfg.host}/ultra/courses/${c.id}/outline`,
    });
  }
  report.push({ course: short, name: c.name, columns: cols.length, dated: dated.length,
                contents: bundle.contents.json?.results?.length ?? 0,
                prose: prose.chars, files: prose.files });
  console.log(`  ${short.padEnd(10)} ${String(dated.length).padStart(3)} dated of ${String(cols.length).padStart(3)} columns, ` +
              `${report.at(-1).contents} content items, ${prose.chars} chars prose, ${prose.files.length} file(s)`);
}

// Deadlines the gradebook cannot know, kept by hand per course and merged
// here. Instructors routinely create a term's columns a week at a time, so a
// calendar built from the gradebook alone silently stops in October.
const extraPath = `${expand('~/coursework')}/ingest-extra.json`;
if (existsSync(extraPath)) {
  const extra = JSON.parse(readFileSync(extraPath, 'utf8'));
  for (const [course, items] of Object.entries(extra)) {
    if (course.startsWith('_')) continue;
    for (const it of items) deliverables.push({ course, ...it, due: new Date(it.due).toISOString() });
  }
  console.log(`  + ${Object.values(extra).filter(Array.isArray).flat().length} hand-kept item(s) from ingest-extra.json`);
}

deliverables.sort((a, b) => a.due.localeCompare(b.due) || a.course.localeCompare(b.course));
writeFileSync(`${cfg.out}/deliverables.json`, JSON.stringify(deliverables, null, 2));
writeFileSync(`${cfg.out}/report.json`, JSON.stringify({ at: new Date().toISOString(), cfg, report }, null, 2));

if (has('clear-calendar') && cfg.calendar && !dryRun) clearCalendar(cfg.calendar);

if (cfg.calendar) {
  const r = writeCalendar(deliverables, { calendar: cfg.calendar, since: cfg.since, until: cfg.until, dryRun });
  console.log(`\n${dryRun ? 'dry run: ' : ''}calendar "${cfg.calendar}": ${r.added} added, ${r.kept} already there, ${r.undated} undated, ${r.total} total`);
} else {
  console.log(`\n${deliverables.length} dated item(s). No --calendar given, so nothing was written.`);
}

await s.save();
await s.close();
