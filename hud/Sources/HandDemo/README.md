# Hand Demo (Doctor Strange overlay)

This is a demo. It draws the hand skeleton from the built-in camera as a
glowing overlay on the screen, like the spell circles in Doctor Strange.
Good for one recording and not much else.

```bash
cd hud && swift run HandDemo
```

Quit with Cmd-Q.

The production hand gestures live in `KyberKit/HandTracker.swift` and go
through the `onGesture` callback. They do not draw anything on screen. This
target exists so the skeleton is visible on camera for a demo recording.

Two hands are tracked here (for the visual), while production tracks one
(for the 7.56ms frame time).
