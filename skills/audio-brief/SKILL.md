---
name: audio-brief
description: Turn a piece of work into something the user can listen to instead of read. Use when they say they want to hear it, listen to it, put it in their ears, or that they will be driving, walking, at the gym, doing laundry, or otherwise away from the screen. Also use when handing over a long analysis they will not sit and read, and when they ask for a voice memo, an audio summary, or a recording of a briefing.
license: MIT
requires: [brief-audio]
---

# Audio brief

Two jobs, and the second one is the hard one. Rendering text to speech is a
command. Writing something worth listening to is the craft, and skipping it
produces a file that is technically audio and practically unlistenable.

## Render it

```bash
brief-audio script.txt                  # -> script.mp3
brief-audio -v am_michael notes.txt     # different voice
echo "some text" | brief-audio -o out.mp3
```

Kokoro-82M, Apache 2.0, local, no API key and no network after the first run
caches the model. First run installs espeak-ng, ffmpeg and a Python 3.12 venv at
`~/.chewbacca/audio-venv`, which takes about a minute. Every run after is faster
than real time.

Voices: `af_heart` (default, highest quality grade), `af_bella`, `af_nicole`,
`af_sarah`, `am_michael`, `am_puck`, `am_adam`, `bf_emma`, `bm_george`.

**Do not reach for a paid TTS API.** That was the first instinct on 2026-09-20
and it was wrong: it needed a key Caleb did not have, so the work stalled on a
credential for something a local Apache-2.0 model does well. If a hosted voice is
ever specifically wanted, that is a deliberate choice, not the default.

## Write it for the ear first

The source analysis is written for eyes that can scan, re-read and skip. None of
that exists in audio. A listener gets what you give them, in the order you give
it, exactly once. Rewrite before rendering. Never pipe a document straight in.

**Front-load the conclusion.** No warm-up. The first sentence is the finding.

**Kill everything visual.** No tables, no bullets, no headers, no URLs, no
markdown, no file paths. A table read aloud is noise. If a table mattered, say
the two numbers that carried it.

**Speak the numbers.** `81,460` becomes "eighty one thousand, four hundred and
sixty". `18.5%` becomes "eighteen and a half percent", or better, "roughly one in
five". `$3K/mo` becomes "three thousand a month". Round hard: precision the
listener cannot write down is wasted.

**Say the headline number twice.** Once in passing, then "let me say that again"
and once slowly. They cannot scroll back.

**Respell anything the voice will mangle.** `a16z` becomes "a sixteen z", `CPG`
becomes "C.P.G." with the periods in, and `NaN` becomes "N-A-N". Check acronyms,
tickers, domain names and anything with digits jammed into letters.

**Signpost every transition.** "First thing." "Second thing, and this is the
interesting one." "Okay, now the dataset." These are filler on the page and load
bearing in audio, because they are the only structure a listener gets.

**Short sentences, because there is no re-reading.** A clause that needs a second
pass is a clause that is lost.

**Say who is who.** "Sam texted you" not "he said". Pronouns drift fast when
nothing is on screen to anchor them.

**Length follows the activity.** Laundry or a walk is four to six minutes, which
is about six hundred to nine hundred words at a hundred and fifty words a minute.
A commute takes more. Check the word count before rendering, not after.

**End on the action, not a recap.** They just heard it.

## The loudness step is not optional

`brief-audio` normalizes to -16 LUFS automatically. That is the podcast standard
and it exists because raw Kokoro output sits near -26 dB mean, which is audible
in headphones in a quiet room and completely gone next to a washing machine or
road noise. If you ever render outside this tool, run the same pass:

```bash
ffmpeg -y -i raw.wav -af "loudnorm=I=-16:TP=-1.5:LRA=11" -codec:a libmp3lame -b:a 128k out.mp3
```

## Deliver it where they will actually play it

Put the file somewhere reachable without a file browser, usually `~/Desktop` or
`~/Downloads`, and say the filename and the runtime in the reply. Keep the script
next to the audio so it can be corrected and re-rendered without rewriting.

## Gotchas that cost real time

- **Python must be 3.12.** torch has no wheels for 3.13 or 3.14, and the system
  Python on this machine is 3.14.
- **`uv pip install --python` wants the venv directory**, not `<venv>/bin/python`.
  That path is a symlink to the uv-managed interpreter, so uv resolves it to the
  real binary and then reports "No virtual environment found".
- **kokoro shells out to `uv pip install` for a spaCy model on first use.** It
  reads `VIRTUAL_ENV`, so rendering from a directory with no `.venv` fails unless
  that variable is exported. `brief-audio` exports it and pre-installs the model.
