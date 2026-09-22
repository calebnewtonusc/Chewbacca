# Plynn: retired from the install, kept for what goes into the HUD

Retired 2026-09-21. It is no longer in `setup.sh`'s default sections, no longer
a login item, and not running. The source stays here on purpose.

## Why it was retired

Dictation moved into the HUD, which draws its own pill. Plynn kept running as a
separate app drawing its own, so two indicator systems were live at once and
the one people actually saw was the retired one:

> Secure field, dictation paused

from `Sources/PlynnKit/IndicatorView.swift:267`. Nothing suppressed it, because
nothing was ever written to. Two overlapping systems, one of them invisible in
the code review and very visible on screen.

## What is actually worth taking

Forty files in `Sources/PlynnKit/` against the HUD's two, and most of that is
app scaffolding the HUD already has its own version of. This is the short list
of things the HUD does NOT have and would be better for.

**The dictation quality layer.** This is the real reason to keep the repo.

- `CorrectionLearner.swift` learns from what the user fixes after a
  transcription, so the same mistake stops repeating. The HUD has nothing that
  learns from corrections.
- `PolishGate.swift` and `PolishPrompt.swift` decide when raw speech is worth
  cleaning up and when cleaning it would change the meaning.
- `TranscriptFormatter.swift`, `RulesFormatter.swift`, `LLMFormatter.swift`,
  `AppleFMFormatter.swift`: four formatters at different cost points, from
  deterministic rules to a model call.
- `TextPersonalizer.swift` and `PersonalStore.swift` hold per-person vocabulary,
  which is the difference between a transcript that spells a friend's name right
  and one that does not.

**The context layer, which is what makes dictation feel aimed.**

- `SelectionReader.swift` and `FieldReader.swift` read what is selected and what
  field the cursor is in. The HUD types into the world blind.
- `ContextSnapshot.swift` and `AppCategories.swift` know what app is in front
  and what kind of app it is, so a message to a friend and a commit message can
  be formatted differently.
- `ReferenceResolver.swift` resolves "that", "the last one", "him".

**The safety bit that is the whole reason the pill exists.**

- `SecureInputWatcher.swift` refuses to dictate into a password field. Whatever
  the HUD ends up drawing, it needs this behaviour, and it should be a HUD pill
  rather than a second app's.

**Audio, if the HUD's own path is ever not enough.**

- `StreamingTranscriber.swift`, `Resampler.swift`, `AudioRecorder.swift`,
  `AppleSpeechEngine.swift`, `EngineManager.swift` with an
  `UnavailableSpeechEngine.swift` fallback.

**Meetings, which is a separate product hiding in here.**

- `MeetingRecorder.swift` and `MeetingSummarizer.swift`. Relevant to roadmap
  item 10, an open source Granola.

## What NOT to take

`IndicatorPanel.swift`, `IndicatorView.swift`, `MenuBarIcon.swift`,
`OnboardingWindow.swift`, `SettingsWindow.swift`, `main.swift`. All of it is a
second app's chrome, and the second app is the problem being solved.

`HotkeyMonitor.swift` and `HotkeyTrigger.swift` overlap the HUD's own key
handling. Read them for the edge cases, take the behaviour, not the files.

## If you need it back

    ./setup.sh --only plynn

It is still installed at `/Applications/Plynn.app` and can simply be opened.
It was removed from login items, so nothing starts it on its own.

## Credit

Plynn is by Carlton Aikins, `github.com/31Carlton7/plynn`, MIT. He is at USC
and Caleb has been downstream of his work for months. See `NOTICE.md`.
