# Chewbacca, where things stand

Written 2026-09-21, about 1am, after a day that put 96 commits from Gavin and
71 from Caleb onto main. This is the context to read before you open a tab, so
nobody re-derives it at 2am.

---

## 1. Read this first if the globe key does nothing for you

It cost hours tonight and the cause was not what anyone guessed.

Holding the globe key opens push to talk. If it does nothing, the reflex is to
blame the Accessibility permission. That was wrong on this machine. Accessibility
was granted and working the whole time, and every press was landing in the log:

```
voice.key down=true mode=off
```

The key arrives. `mode=off` is what drops it. The listening mode lives in a
UserDefaults key, `hud.listening`, and `restoreListening()` reads it at launch.
Nobody had ever picked "Hold the globe key to talk" from the menu bar, so the
key was never written, the mode came up `off` on every launch, and the guard in
`globe(down:)` returned before anything happened.

Two ways to fix it. Pick it from the BobHUD menu bar item, or:

```
defaults write dev.bobthebuilder.hud hud.listening -string "pushToTalk"
killall BobHUD; open -a BobHUD
```

Then confirm it actually works rather than trusting it:

```
log show --predicate 'subsystem == "bob.hud"' --last 5m --style compact
```

You want `mode=pushToTalk` and a `voice.start` line. `voice.warm done code=1110`
is healthy, not an error: 1110 is "no speech detected" and the warm-up
deliberately feeds the recognizer silence.

**The general lesson, which is the part worth keeping:** the HUD logs to
`subsystem == "bob.hud"` on purpose, after a night in September when two presses
produced no trace at all and there was no way to tell a key that stopped working
from a key that stopped arriving. Read the log before forming a theory. It would
have answered this in thirty seconds.

## 2. hud doctor was crying wolf, and the false alarm was expensive

`hud doctor` compared the installed `CFBundleVersion` against the repo's total
commit count. `CFBundleVersion` is the commit count for the whole repo, so any
commit anywhere made the display look stale. Tonight a spec document under
`docs/` moved it 675 to 676 and doctor demanded a rebuild of Swift that had not
changed.

That is not a wasted minute. `bundle.sh` writes a new bundle, the signature
changes, and macOS drops the Accessibility grant that push to talk needs. So
obeying the false alarm costs you the globe key, which is the exact thing most
people would be running doctor to fix.

Fixed in `be0e8a3`: counted at the newest commit under `hud/` instead. The mtime
check beside it is untouched and still catches an uncommitted Sources edit. The
two are complementary, mtimes survive an uncommitted edit and lie after a fresh
clone.

**If you rebuild the HUD, expect to re-grant Accessibility.** That is macOS, not
our bug, and it is worth knowing before you wonder why voice died after a pull.

## 3. Two sessions in one checkout keeps eating work

This has now happened four times and it is the most expensive recurring problem
we have. `git commit` commits the whole index, not the files you just added, so
staging by filename is careful and irrelevant if another session already staged
its work hours ago.

Tonight's near miss: a stale staged `setup.sh` sitting in the index would have
silently reverted Gavin's Intel Mac fix, putting back a hardcoded
`/opt/homebrew/bin/peekaboo` over his `command -v peekaboo`. It was caught by
reading the diff, not by any tool.

What exists now: `.githooks/pre-commit` prints the staged list on every commit
and refuses when the index holds files written by more than one session, using
the session ids in `~/.chewbacca/write-log.tsv`. Enable it:

```
git config core.hooksPath .githooks
```

And the habit that actually works, because the hook is a backstop and not a fix:

```
git commit -m "message" -- path/one path/two
```

Note the order. The message goes before the `--`. Anything after `--` is a
pathspec, so `git commit -- paths -m "msg"` quietly treats your commit message as
a filename and fails.

**Known rough edge, not yet fixed.** When two sessions are live the hook refuses
and tells you to name your paths, but naming your paths does not clear that
particular gate: it inspects the index, and `git commit -- paths` does not change
the index. Only `CHEWBACCA_PATHSPEC_COMMIT=1` gets past it. The advice it prints
is wrong and should say so.

## 4. Gavin's check-in idea, which is the right problem

From tonight's call: "we need to add some check-in thing if people are working on
the same stuff. Like for code."

Everything we have solves this **inside one machine**. `write-log.tsv` records a
session id beside every path a tool writes, and the pre-commit hook reads it. None
of that crosses between people, so Gavin and Caleb editing the same file in
different checkouts is still invisible until the merge.

Shapes worth arguing about, pick one rather than building all three:

- **Cheapest.** A `WORKING-ON.md` at the repo root, one line per person, committed
  and pushed when you start. Zero infrastructure, fails the moment someone forgets.
- **Middle.** A pre-push hook that reads which files the remote's recent commits
  touched and warns when your branch overlaps with someone else's last hour. No
  new service, uses git as the shared state.
- **Most.** Something live over the group chat or a small server. Real coverage,
  real thing to maintain.

The middle one is probably right, since git is already the shared state and
nobody has to remember anything. Not built. Needs a decision before it is.

## 5. What shipped today

Gavin: hud-voice on the Neural Engine, the router, chewie terminal, hud-music,
hud-guide, the procedures and maps layer that lets the kit learn a task by doing
it once, the Intel Mac fixes, the Terminal guard so an agent-opened window no
longer inherits a Claude session, and the dictation bubble spec.

Caleb: the fitness function and evolve loop with worktree isolation, consolidate,
maintain, method, scars, doctor's hook wiring check, write-log attribution in
pre-commit, the submit guard on coursework, and the toolkit/REFERENCE cleanup.

Main is green as of the last five CI runs.

## 6. Open, in rough priority

1. `hud-voice` does not build. It fails fetching FluidAudio with "unable to read
   tree". Nobody has bisected it.
2. `hud doctor` does not check Accessibility at all, which is the permission the
   whole voice path depends on. Given section 1, it should, and it should say what
   to click.
3. The pre-commit advice message in section 3 sends you to a command that cannot
   work.
4. The dictation bubble (`docs/superpowers/specs/2026-09-21-dictation-bubble-design.md`)
   is specced and unbuilt. The spec says spike the accessibility insertion against
   Messages, Terminal, Mail and Chrome first, before any code, to find out whether
   the clipboard fallback is rare or normal. Do not skip the spike.
5. The behavioural fitness run scored 84.8 with 139 of 164 passing, but which 25
   failed was never written down, so the number is not actionable yet.

## 7. Questions for the team

Answer in the chat, these are real forks and not rhetorical.

1. **Who owns the dictation bubble, and does the AX spike happen first?** The
   spec says it is mutually exclusive with push to talk by construction, one
   AVAudioEngine and one mode enum. That is a real constraint on whoever builds
   it.
2. **Which check-in shape from section 4?** Cheapest, middle, or most.
3. **What does "expert at go to market engineering" mean concretely, and how do we
   know when it is true?** Caleb's focus this week is making Chewbacca good at GTM
   engineering and, in his words, giving it "grounds to be creative and not just
   regurgitate creative people's stuff." That second half is the hard half and it
   needs an eval, not a vibe. What is the test that fails today and passes when it
   works?
4. **Should `hud doctor` check Accessibility?** It is the permission everything
   voice depends on and doctor is currently blind to it.
5. **Is anyone besides Gavin and Caleb committing this week?** There is a third
   author in today's log. Worth knowing before the check-in thing gets designed
   for two people.

---

Built with Chewbacca
