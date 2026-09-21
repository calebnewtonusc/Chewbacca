# When the data is not in the table yet

Caleb's case: "let's say someone has a niche app that they want the data on.
This should be an MD that says, all right, figure out all the apps on this
person's setup and we'll design the way that we can super quickly scrape the
data and store it."

This is that file. It runs once per person, not once per request, and what it
learns is appended to `data-loaders.md` so the next session inherits it.

## Step 1: inventory what is actually installed

```sh
ls /Applications /Applications/Utilities ~/Applications 2>/dev/null
ls ~/Library/Application\ Support | head -60      # apps that keep local state
ls ~/Library/Containers | head -60                # sandboxed apps
ls ~/Library/Group\ Containers 2>/dev/null
brew list --formula 2>/dev/null; brew list --cask 2>/dev/null
```

An app with a directory under `Application Support` or `Containers` is keeping
state locally, which means there is something to read without a network call.

## Step 2: find its store, in this order

The order is by cost to read and by how stable the result is.

1. **A CLI.** `<app> --help`, then `man <app>`. A vendor CLI with `--json` is
   the whole answer and takes a minute to find.
2. **An export.** Most apps have one. A one-time export beats a fragile
   scraper for anything that does not need to be live.
3. **A SQLite file.** `find ~/Library -name '*.sqlite*' -o -name '*.db'` under
   the app's own directory. Open read-only and `.schema` it.
4. **JSON or plist on disk.** `plutil -convert json -o - <file>` reads a
   binary plist.
5. **A documented API.** Needs a key, so it needs the user. Cheapest to
   maintain of anything that must be live.
6. **AppleScript or JXA.** `sdef /Applications/<App>.app` prints the
   dictionary. This is what `mac` and `macos-automator-mcp` already use.
7. **The accessibility tree.** `chewie see --app <App>`. Structured, fast, and
   correct where the app exposes labels.
8. **Pixels**, via `peekaboo image` plus vision. Last in every case, because
   it is the slowest and the only one that can be confidently wrong.

**Stop at the first one that works.** The instinct to jump to step 8 is the
cross-platform habit `docs/mac/LANDSCAPE.md` names: vision is the only
universal option, so it becomes the default even on a Mac that is handing you
a free structured API.

## Step 3: confirm before building on it

Read ten real records and check them against what the app's own UI shows. A
schema guessed from column names is how a dashboard ends up confidently
reporting the wrong number, and the wrongness survives because nobody
re-checks a chart that renders.

Note the record count and the date range. "Nobody is overdue" off a 90-day
window looked like a clean bill of health and was a bug.

## Step 4: write it down, or it did not happen

Append a row to `data-loaders.md` with the app, the exact command or path, the
shape, and anything surprising. The next session gets it for free, which is the
entire point of preloading.

## The line this does not cross

Read-only, local, and only what the person asked for. Discovering that an app
holds someone's data is not permission to read it, and a niche app is often
the most personal one on the machine. If a source needs a credential, print
what is needed and let them provide it. Never read a keychain, a token file or
a password store to make a dashboard prettier.
