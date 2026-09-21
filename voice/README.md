# hud-voice

The reply, read aloud, with Kokoro on the Neural Engine. One Swift binary
that speaks the same stdin and stdout lines as `bin/hud-speak`, so the bridge
cannot tell which is behind the pipe.

`hud-speak` needs uv, MLX, espeak-ng from Homebrew and a spaCy model, and a
fresh Mac spends a minute installing them before the first word. This needs
nothing installed: FluidAudio's CoreML split of the same 82M model downloads
24 MB on first run into `~/.cache/fluidaudio`.

## Build

```sh
voice/build.sh          # swift build -c release, then ~/.local/bin/hud-voice
HUD_SPEAKER=hud-voice hud-listen --verbose
```

## Measured 2026-09-20, M4 Pro, model on disk

| | hud-speak (Python) | hud-voice (Swift) |
|---|---|---|
| start to ready, warm | 2.3s | 1.6s |
| say to first sound, 3 words | 0.16s | 0.13s to 0.19s |
| say to first sound, 12 words | 0.26s | 0.19s |

The first run of a freshly built binary pays about six seconds more once,
while CoreML compiles the stages for it. A first run on a new Mac downloads
the model first and says so on the pill.

## Protocol

In, one JSON object per line: `{"say": text, "more": true}` cuts off what
was playing and starts this; `{"add": text}` queues behind it; `{"end": true}`
closes the reply so quiet can follow its last sentence; `{"hush": true}` stops
everything. Out: `{"level": 0..1}` twenty times a second while sound plays,
`{"saying": sentence}` before each sentence starts, `{"quiet": true}` when
nothing more is coming, `{"status": text}` while the voice is not ready. The
word `ready` alone means loaded and warm.

`--say "text"` speaks once and exits, `--list` prints the voices, `--voice`,
`--speed` and `--volume` (0 plays silently, for tests) do what they say.
