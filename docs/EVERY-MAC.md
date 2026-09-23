# Every Mac but this one

Caleb merged the presence field and could not see it. Nothing on his Mac could
have told him why, and four different causes would have looked identical:
no app built, an app built before the feature existed, a Metal shader that
would not compile on his GPU, or a second monitor.

That is not a HUD bug. It is the shape of every bug this project has left for
somebody else to find, and it has one property in common: **it is silent on a
machine that is not this one.**

This is the plan for fixing that class, not that instance.

## What tonight actually turned up

Five things, all real, all found in one pass, none of which would ever have
announced itself:

1. **The app on this Mac was 71 commits behind its own repo.** Build 590
   against a repo at 661. The presence field, the terminal loop and the voice
   router were all merged and none of them were running. `hud status` said
   "running". It was, just not the code anyone thought.
2. **`bundle.sh` could only build on Apple Silicon.** It copied from
   `.build/arm64-apple-macosx/`, a path SwiftPM writes as
   `x86_64-apple-macosx` on an Intel Mac. The compile would succeed and the
   copy would fail, which reads as a broken repo rather than a wrong path.
3. **`setup.sh` never built the app.** It linked the `hud` commands, printed
   two warning lines about the thing that draws, in the middle of a setup that
   prints hundreds, and moved on. An install that ends in an instruction has
   not installed anything.
4. **`doctor.sh` had twenty sections and none of them knew the display
   existed.** The most visible thing the kit does was the one thing its health
   check could not see.
5. **The first version of the shader check reported a broken GPU on a working
   one.** `log show` writes its own argv into the log, predicate text
   included, so an unscoped query matched itself from its first run onwards.

Four are fixed, with a test each. The fifth is in this document because a check
that lies is worse than no check, and it took thirty seconds to write and five
minutes to catch.

## The rule

> A feature is not shipped until the system can tell a stranger, on their own
> machine, that it is broken and what to do about it.

Not "until it works here". Not "until the tests pass". Until the machine you do
not own can explain itself to the person sitting at it.

Everything below is that rule applied.

## 1. The machine matrix

"Every Mac" is not one axis. It is seven, and most of them have never had a
single run against them.

| Axis | What breaks | Caught by | Status |
| --- | --- | --- | --- |
| Intel vs Apple Silicon | Hardcoded build triples, Homebrew prefix, no universal binary | Static check, plus a cross-compile in CI | bundle.sh fixed; CI job still to add |
| macOS 14 vs 15 vs 26 | `LSMinimumSystemVersion` refuses to launch; API availability | `hud doctor` names the floor; CI runs only `macos-latest` | doctor done; second CI job to add |
| Xcode vs Command Line Tools only | Anything needing `xcrun metal` or `xcbuild` | Nothing today | The shader already compiles from source at launch for this reason. Universal builds now use two passes and `lipo` instead of `--arch a --arch b`, which needs Xcode |
| One display vs several | The glass is locked to the menu bar display, so the border draws on a screen you are not looking at | `hud doctor` says so in words after lighting the field | Named, not solved. `hud/docs/1000-WAYS-IT-FALLS-SHORT.md` items 566 to 605 already catalogue it |
| Retina scale, notch, resolution | Surfaces sized in points look different at 4K; marks land off target | `hud screen` prints points | Partial |
| Permissions granted vs not | Microphone, Speech, Accessibility, Screen Recording, Full Disk Access | doctor covers Full Disk Access and peekaboo, not the HUD's own microphone grant | Gap |
| A fresh Mac with nothing on it | No brew, no node, no Swift, no git | `tests/bare_machine.sh` simulates exactly this for `bootstrap.sh` | Good pattern, does not cover the HUD yet |

The Intel row is the cheapest of these and was the most broken. Cross-compiling
the whole HUD for x86_64 on this machine takes 48 seconds, which is a CI job,
not a project.

## 2. Reporting from a machine you do not own

Three of tonight's five failures were invisible because nothing on the far
machine could speak. What is missing is a channel back.

### Shipped today

- `hud doctor` walks the chain in the order it breaks: macOS floor, app
  present, build current, process running, socket open, shader compiled. It
  names the first broken link and prints the exact command that repairs it.
  Then it lights the field for six seconds, because the only honest test of
  something visual is looking at it.
- `doctor.sh` grew a display section that calls `hud doctor --no-lights` and
  files its answers under the same severities as everything else. One
  implementation, not two: two copies of a check are one check and one lie.
- CI now parses and shellchecks `bin/hud` and `hud/scripts/*.sh`, which it
  never did, because the glob only matched `bin/*.sh`.

### Still to build

In the order of what each one unblocks.

1. **`chewbacca report`.** One paste-able block: `doctor --json`, `hud doctor`,
   macOS version, architecture, display count, installed build against repo
   head. No file contents, no message text, no tokens, no paths under
   `$HOME` that are not the kit's own. Caleb runs one word and pastes the
   answer into an issue. This is the single highest-value thing left.
2. **Setup ends in a verdict.** `setup.sh` currently ends in a wall of output
   where a warning and a success line look the same. It should end by running
   the doctor and printing one line: what works, what does not, what to run.
3. **The Intel and floor CI jobs.** `swift build --arch x86_64` on the existing
   runner, plus a `macos-14` job so the declared floor is a tested floor rather
   than a number in a plist.
4. **Extend `tests/bare_machine.sh` to the HUD.** It already proves
   `bootstrap.sh` offers no dead ends to a machine with nothing on it. The HUD
   install path has never been run that way.
5. **A permissions check for the HUD's own grants.** The microphone and speech
   grants are keyed to the bundle identifier, which is why `bundle.sh` pins the
   designated requirement. Nothing verifies they survived a rebuild.

## 3. The part where grandma is real

She is not a figure of speech and she is not going to open a terminal. Two
things have to be true, and only one of them is achievable, so say which.

The app can be hers. Kyber is one bundle, so it can be signed with a
Developer ID, notarized, stapled, and taught to update itself. She downloads it
once and never thinks about it again, and every change made here reaches her
the same week.

The kit cannot, and should stop pretending. Skills, rules, hooks, `.claude`
configuration and eleven CLIs are a developer tool for people who already run
Claude Code, and making that grandma-ready would be a different product.
Naming the split is what lets the app half ship.

### What the app half takes

The craft here is well travelled and the checklist is not ours to invent. A
release is done when the appcast entry has a URL, a length and a Sparkle
signature; the downloaded enclosure verifies against the public key in the
app; and the extracted app passes `codesign`, `spctl` and `stapler validate`.
Anything short of that is a download that Gatekeeper will refuse on a machine
that is not this one, which is the whole failure mode again.

1. **Apple Developer Program**, 99 dollars a year, for a Developer ID
   Application certificate. Ad-hoc signing is what we have now: it runs here
   and nowhere else.
2. **Universal binary.** Done tonight: `./scripts/bundle.sh release
   --universal` fuses arm64 and x86_64 with `lipo` into a 6.2 MB bundle. Two
   passes rather than `--arch arm64 --arch x86_64`, because the multi-arch flag
   routes SwiftPM through `xcbuild`, which ships with Xcode and not with the
   Command Line Tools. Keeping a full Xcode off the build requirements is the
   same call the presence field already makes by compiling its shader from
   source at launch.
3. **Notarize and staple.** `notarytool submit --wait`, then `stapler staple`,
   so the app opens on a Mac with no network and no prompt.
4. **Sparkle 2, with EdDSA.** `SUFeedURL` and `SUPublicEDKey` in the plist, an
   appcast on GitHub Releases, the private key in 1Password and never on disk.
   The version already carries the commit count, so an update is traceable back
   to the code it came from.
5. **A release manifest in the repo**, so the pipeline is data rather than a
   script somebody remembers how to run.
6. **A first-run pass** that asks for the microphone once, explains the border
   in one sentence, and shows it. Not a manual.

### What she never sees

No terminal. No Xcode. No git. No `setup.sh`. No permission dialog she has to
guess at. If any of those appear, that step is not finished.

## 4. The hard line

Three things this must refuse to do, because they are the versions of "works
everywhere" that turn into harm.

It never updates itself silently into something that can act on her Mac. An
assistant that can click, type and send is not a thing to push changes into
behind someone's back. Updates say what changed, in her words, and a change to
what it is allowed to do asks again rather than inheriting the old answer.

It never phones home with content. `chewbacca report` carries versions,
architecture, counts and check results, never message text, file contents,
transcripts, tokens or her paths. It is paste-able, so she sees exactly what
she is sending, which is the only consent worth having.

It never reports a check it did not run. Tonight's shader check called a
working GPU broken because it matched its own command line. A confidently wrong
answer is worse than no answer, because the person stops looking.

## 5. The order

1. `chewbacca report`, and setup ending in a verdict. Both are days, and both
   pay off on the next machine that goes quiet.
2. The Intel and macOS 14 CI jobs. Hours.
3. `bare_machine.sh` extended to the HUD install. Days.
4. Developer ID, notarization, Sparkle. Weeks, and blocked on the developer
   account, which is the one thing here nobody but Gavin can do.
5. The first-run pass, once there is something signed for it to run inside.

The first three make the current install honest. The last two make it somebody
else's.
