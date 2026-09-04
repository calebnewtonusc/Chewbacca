# Bob HUD

A floating panel that draws streamed interfaces as **native SwiftUI**. No
browser, no WebView, no bundle. It never takes focus, follows you across spaces,
and survives a full-screen app.

```
any agent ──Bob Lines──▶ ~/.bob/hud.sock ──▶ BobHUD.app
```

```bash
swift build
./.build/arm64-apple-macosx/debug/BobHUD &

# from anywhere, including a shell
cat demo.bl > /dev/tcp/... # or:
bob hud "how many people am I waiting on"
```

## Why the wire format is already right for this

Bob Lines is line-oriented, so a line is either complete or invisible. Over a
socket that means there is no partial-value state to get wrong: a half-arrived
instruction sits in the buffer until its newline lands. A JSON stream would need
a repairing parser and could still paint a number that is about to change.

The parser and store here are ports of `src/core/lines.ts` and
`src/core/store.ts`, so the panel enforces the same three rules the web renderer
does: nothing paints before the root resolves, a child that has not arrived draws
a placeholder in place, and bound or computed props resolve at render time.

## The panel

`.nonactivatingPanel` with `canBecomeKey == false`, so showing it never steals
focus: ask for a dashboard mid-sentence in another app and your cursor stays put.
`.floating` level, `.canJoinAllSpaces`, `.fullScreenAuxiliary`. Real
`NSVisualEffectView` material rather than a translucent colour, so it reads as
part of the system.

## Prior art, honestly

thesysdev/appless does streaming-DSL-to-native-components on React Native, with
Cupertino and Material 3 targets. It is the closest thing to this and it works,
which is why the approach here is a safer bet than it looks.

Two differences: this is a floating desktop surface rather than a phone OS, and
Bob keeps the model out of the request path entirely, which appless does not.

## Compiling

`SurfaceView` is split into four small builders returning `AnyView` rather than
written as one `@ViewBuilder` switch. That is not style. Twelve branches in one
builder makes Swift unify twelve view types into nested `_ConditionalContent`
generics, and the cost grows exponentially: as one function this file took over
three and a half minutes of CPU. Split, the whole package builds in 2.3 seconds.

If you add a component, put it in an existing family rather than growing a switch.
