// Put deadlines on Apple Calendar, idempotently.
//
// Re-running must not duplicate. The ingest gets run again every time an
// instructor moves a date, so this matches on title plus LOCAL day. The local
// part is not a detail: `mac calendar list` prints starts in UTC, and a
// deadline at 23:59 local is the next day in UTC, so comparing raw prefixes
// matches nothing and a second run silently doubles the whole semester.
//
// Nothing lands on a personal calendar. Everything goes on a calendar of its
// own, so it can be hidden in one click and cleared in one command.
import { execFileSync } from 'node:child_process';

const MAC = `${process.env.HOME}/.local/bin/mac`;
const sh = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8' });

const pad = (n) => String(n).padStart(2, '0');
const stamp = (iso) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const day = (iso) => stamp(iso).slice(0, 10);

function ensure(name) {
  if (sh(MAC, ['calendar', 'calendars']).includes(name)) return;
  // Calendar.app can take longer than osascript's default to wake up, and the
  // timeout is reported as an error even though nothing went wrong.
  sh('/usr/bin/osascript', ['-e', 'tell application "Calendar" to activate']);
  sh('/usr/bin/osascript', ['-e',
    `with timeout of 120 seconds
       tell application "Calendar" to make new calendar at end of calendars with properties {name:"${name}"}
     end timeout`]);
}

function have(name, since, until) {
  try {
    const items = JSON.parse(sh(MAC, ['calendar', 'list', '--from', since, '--to', until, '--calendar', name, '--json']));
    return new Set(items.map((e) => `${e.title}|${day(e.start)}`));
  } catch { return new Set(); }
}

export function write(items, { calendar, since, until, dryRun = false }) {
  if (!dryRun) ensure(calendar);
  // Read the existing events even on a dry run. Skipping it made --dry-run
  // claim it would add all 61 events when 61 were already there, which is the
  // one thing a preview must never do: say something different from the run.
  const existing = have(calendar, since, until);
  let added = 0, kept = 0, undated = 0;

  for (const it of items) {
    if (!it.due) { undated++; continue; }
    const title = `${it.course}: ${it.name}`;
    if (existing.has(`${title}|${day(it.due)}`)) { kept++; continue; }
    const notes = [it.type && `Type: ${it.type}`, it.points != null && `Points: ${it.points}`,
                   it.where && `Submit on: ${it.where}`, it.url && `Link: ${it.url}`,
                   it.source && `Source: ${it.source}`].filter(Boolean).join('\n');
    if (dryRun) { added++; continue; }
    sh(MAC, ['calendar', 'add', title, '--at', stamp(it.due), '--calendar', calendar,
             '--notes', notes, '--duration', '15m']);
    added++;
  }
  return { added, kept, undated, total: items.length };
}

export function clear(calendar) {
  sh('/usr/bin/osascript', ['-e',
    `with timeout of 300 seconds
       tell application "Calendar" to tell calendar "${calendar}" to delete every event
     end timeout`]);
}
