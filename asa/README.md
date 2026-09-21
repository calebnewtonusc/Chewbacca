# asa

The A2A Spring 2026 course (The Uncommon Business, Thinkific) turned into
something Chewbacca can read: 79 transcripts, 108 hours, 1.3 million words,
searchable, with a distilled note per module.

## What is here

| Path           | What it holds                                                  |
| -------------- | -------------------------------------------------------------- |
| `bin/asa`      | Search the corpus. Never loads a whole transcript into context. |
| `ingest/`      | The pipeline. Scan and apply are separate; scan never writes.   |
| `data/`        | Course JSON, downloaded PDFs, the manifest. Local only.         |
| `transcripts/` | One markdown file per session, foldered by module. Local only.  |
| `notes/`       | Distilled notes per module. Original writing, committed.        |
| `skills/asa/`  | The skill that teaches an agent to use this corpus.             |
| `INDEX.md`     | Module and session index with runtimes.                         |

`transcripts/` and `data/` are gitignored. The course is paid material and
the lesson text stays on this machine. What gets committed is the pipeline
and the distilled notes, written from scratch.

## How the ingest works

The course player is behind a login. Two facts make the pipeline cheap:
the lesson JSON names a transcript PDF per workshop, and those PDFs sit on a
public CDN. So only the lesson metadata needs the session, and the bulk
download does not.

Reading that metadata is the awkward part. Chrome on this machine refuses to
enable "Allow JavaScript from Apple Events", so there is no way to run a
same-origin `fetch` in the signed-in tab. `ingest/fetch_via_tab.py` instead
drives a scratch tab to each JSON endpoint and lifts the text off the
clipboard. That borrows the keyboard, so every payload is validated against
the shape its endpoint must return: a grab taken while someone is typing
fails loudly instead of writing garbage.

```bash
python3 ingest/fetch_via_tab.py course           # the course tree
python3 ingest/fetch_via_tab.py contents         # all 128 lessons
python3 ingest/fetch_via_tab.py contents --retry # anything that failed
python3 ingest/downloads.py apply --chat         # PDFs from the CDN
python3 ingest/to_text.py apply                  # PDF to markdown
python3 ingest/build_index.py                    # INDEX.md
```

Thinkific keys its detail endpoints on `contentable_id` and uses a different
path per type (`/api/course_player/v2/lessons/{id}`, `/html_items/{id}`).
The `/course_contents/{id}` path that older integrations use returns 404 on
this school.

`ingest/ingest.py` and `ingest/transcribe.py` are fallbacks for lessons with
no published transcript: Wistia captions first, then whisper over the audio.
79 of 80 videos ship a transcript, so neither has had to run.

## Using it

Load the `asa` skill, or run `bin/asa` directly. Start with `notes/`, which
is a few thousand words per module against a transcript's fifty thousand.
