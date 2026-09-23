#!/bin/bash
# Chewbacca: the one line you paste.
#
#   curl -fsSL https://chewbacca.sh | bash
#   curl -fsSL https://chewbacca.sh | bash -s -- --full-send
#
# Written for someone who just put Claude on a laptop, has no GitHub account,
# has never opened Terminal before today, and should not have to care about any
# of that. Three things it deliberately does differently from `git clone`:
#
#   1. Downloads a tarball, not a repo. codeload.github.com serves those to
#      anyone, so no account, no git, no `gh auth login`.
#   2. Installs to ~/.chewbacca, not to a Chewbacca folder in whatever
#      directory they happened to be standing in. They will never trip over it.
#   3. Waits for the Command Line Tools dialog instead of telling them to come
#      back and run something again. Nobody comes back.
#
# It asks nothing. Every answer it needs it either detects or defaults, and
# anything it cannot decide is left for Claude to ask in conversation, which is
# the whole design of the kit.
set -uo pipefail

REPO="calebnewtonusc/Chewbacca"
BRANCH="main"
REF=""
HOME_DIR="$HOME/.chewbacca"
BIN_DIR="$HOME/.local/bin"

FULL_SEND=0
PROFILE="personal"
DRY_RUN=0
FAST=0
PERSON_NAME=""

# Normalize harmless convenience flags. Permission changes require the exact
# documented flag; a typo must not change the scope of an installation.
normalize() {
  local a="$1"
  case "$a" in --full-send|--bypass-permissions) echo --full-send; return ;; esac
  a="${a#-}"; a="${a#-}"          # strip any number of leading dashes
  a="$(printf '%s' "$a" | tr 'A-Z_' 'a-z-')"
  case "$a" in
    fast|minimal|quick|demo)                echo "--fast" ;;
    dryrun|dry-run)                         echo "--dry-run" ;;
    ref|pin|pin-to)                         echo "--pin" ;;
    version|v)                              echo "--version" ;;
    profile)                                echo "--profile" ;;
    name)                                   echo "--name" ;;
    h|help)                                 echo "--help" ;;
    *)                                      echo "$1" ;;
  esac
}

require_value() {
  if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
    echo "Missing value for $1" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$(normalize "$1")" in
    --full-send) FULL_SEND=1; shift ;;
    --fast) FAST=1; TOTAL=5; shift ;;
    # Pin the install. Without this, everyone gets whatever landed on main an
    # hour ago, and "which version am I running" has no answer.
    --pin) require_value "$@"; REF="$2"; shift 2 ;;
    # --version used to silently mean "pin to this tag", so `--version` alone
    # ate the next argument and `--version 1.1.0` looked like it was reporting a
    # version while actually pinning one. It now does what every other command
    # line tool does, and still pins when handed a tag, because that spelling is
    # in the wild and in the README.
    --version)
      if [ -n "${2:-}" ] && [ "${2#-}" = "$2" ]; then
        REF="$2"; shift 2
      else
        echo "chewbacca start.sh, repo version $(curl -fsSL --max-time 10 \
          "https://raw.githubusercontent.com/$REPO/$BRANCH/VERSION" 2>/dev/null || echo unknown)"
        exit 0
      fi ;;
    --profile)   require_value "$@"; PROFILE="$2"; shift 2 ;;
    --name)      require_value "$@"; PERSON_NAME="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --help)
      cat <<'HELP'
Chewbacca full macOS installer
  --profile personal|student|developer|portable
  --name NAME       Optional for personal/student; never inferred from an account
  --fast            Install the smaller configuration set
  --dry-run         Preview before installing
  --pin REF         Install a specific version
  --full-send       Explicitly disable the supported agent permission prompts
  --help            Show this help

For an existing local agent, use the smaller runtime setup from a checkout:
  bash setup.sh --runtime codex
  bash setup.sh --runtime claude-code
HELP
      exit 0 ;;
    *) echo "Unknown option: $1. Use --help to review supported options." >&2; exit 2 ;;
  esac
done

case "$PROFILE" in
  personal|student|developer|portable) ;;
  *) echo "Unknown profile: $PROFILE. Choose personal, student, developer or portable." >&2; exit 2 ;;
esac
if [ "$PROFILE" = developer ] && [ -z "$PERSON_NAME" ]; then
  echo "The developer profile needs --name for its repositories. Personal setup can leave your name unset." >&2
  exit 2
fi

# Colors, but only into a real terminal that says it can do them. Piping this
# into a file or a terminal without color support used to print escape codes.
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  B=$(tput bold); G=$(tput setaf 2); Y=$(tput setaf 3); R=$(tput setaf 1); N=$(tput sgr0)
else
  B=""; G=""; Y=""; R=""; N=""
fi
say()  { echo "${B}$*${N}"; }
ok()   { echo "  ${G}done${N}  $*"; }
work() { echo "  ${Y}....${N}  $*"; }
bad()  { echo "  ${R}stop${N}  $*"; }

STEP=0
TOTAL=5
step() { STEP=$((STEP + 1)); echo; say "[$STEP/$TOTAL] $1"; }

# ── Introduce yourself before doing anything ─────────────────────────────────
cat <<INTRO

  ${B}Chewbacca${N}
  Makes the Claude you already pay for a lot better at your actual life.

  This will:
    1. Check what your Mac already has
    2. Install what is missing (Apple's developer tools, Homebrew, Node)
    3. Download Chewbacca to ~/.chewbacca
    4. Set up Claude to read your calendar, send texts, and see your screen
    5. Open Claude and introduce you

  Before any of it runs, here is exactly what it touches:

    Chewbacca configuration goes in your account:
      ~/.chewbacca        the kit itself
      ~/.claude           what your agent reads every session
      ~/.local/bin        the commands it installs

    It will ask for your Mac password ONCE, and only for Homebrew, which
    installs shared developer tools outside your account. Nothing else here
    needs it.

    Setup downloads software. Agent conversations and connected services can
    send data to their providers. Personal data imports are separate choices.

    To remove kit configuration later: chewbacca uninstall
    Personal stores and separately installed software may remain.

  About 10 minutes, most of it downloads. Add --fast to install only the part
  that makes the agent know you, which takes seconds instead.

INTRO

if [ "$DRY_RUN" -eq 1 ]; then
  # A dry run that only says "nothing was changed" answers the wrong
  # question. The question a careful person has is what WOULD change, and
  # this script is 440 lines in front of another 2,404 arriving from a URL.
  # Sam called this installer malware and quit after two hours, which is a
  # reasonable response to being asked to trust that much unseen shell.
  #
  # So: fetch only the two files needed to describe the install, into a temp
  # directory, print the manifest, and delete them. Nothing is installed and
  # nothing outside the temp directory is touched.
  _dry="$(mktemp -d)"
  trap 'rm -rf "$_dry"' EXIT
  mkdir -p "$_dry/bin"
  _base="https://raw.githubusercontent.com/$REPO/${REF:-$BRANCH}"
  # A local checkout is authoritative when there is one: it is the code
  # about to run, and it works with no network at all.
  # BASH_SOURCE is UNSET when this script arrives through a pipe, which is
  # the documented way to run it, and `set -u` turns that into a hard exit
  # before the fallback is ever reached. The whole point of this branch is
  # the person who has not cloned anything. Default it.
  _self="${BASH_SOURCE[0]:-}"
  _here=""
  [ -n "$_self" ] && _here="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
  if [ -n "$_here" ] && [ -x "$_here/bin/preflight" ] && [ -f "$_here/setup.sh" ]; then
    python3 "$_here/bin/preflight" || true
  elif curl -fsSL --max-time 30 "$_base/setup.sh" -o "$_dry/setup.sh" \
     && curl -fsSL --max-time 30 "$_base/bin/preflight" -o "$_dry/bin/preflight"; then
    chmod +x "$_dry/bin/preflight"
    python3 "$_dry/bin/preflight" || true
  else
    echo "  --dry-run: could not reach GitHub, so nothing can be described."
    echo "  Nothing was changed."
  fi
  exit 0
fi

# ── 1. Is this machine even a candidate ──────────────────────────────────────
step "Checking this Mac"

if [ "$(uname -s)" != "Darwin" ]; then
  bad "The full install is macOS only. You are on $(uname -s)."
  echo
  echo "  Half of this kit is macOS automation and none of that will work here."
  echo "  The other half is platform-neutral: the standards, the skills, the"
  echo "  slash commands and the subagents are plain text a Claude Code session"
  echo "  reads on any OS. To install only that part:"
  echo
  echo "    git clone https://github.com/calebnewtonusc/Chewbacca"
  echo "    cd Chewbacca && ./setup.sh --profile portable"
  echo
  echo "  That writes ~/.claude and nothing else. No Homebrew, no Mac tools, no"
  echo "  permissions. Tracked as items 671-675 in docs/1000.md."
  exit 1
fi
ok "macOS $(sw_vers -productVersion)"

MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then
  bad "macOS 13 or newer is needed. This is $(sw_vers -productVersion)."
  exit 1
fi

# Homebrew plus Apple's tools plus Node is a few gigabytes. Finding that out
# halfway through, on a full laptop, is a bad ending to an install.
FREE_GB=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [ "${FREE_GB:-99}" -lt 8 ]; then
  bad "Only ${FREE_GB}GB free. This needs about 8GB. Free some space and re-run."
  exit 1
fi
ok "${FREE_GB}GB free"

if ! curl -fsS --max-time 10 -o /dev/null https://github.com 2>/dev/null; then
  bad "Cannot reach github.com. Check your wifi and re-run."
  exit 1
fi
ok "online"

# ── 2. Apple's developer tools ───────────────────────────────────────────────
step "Apple's developer tools"

if xcode-select -p &>/dev/null; then
  ok "already installed"
else
  work "opening Apple's installer. Click Install in the window that appears."
  xcode-select --install &>/dev/null || true
  echo
  echo "      Waiting for it to finish. This is the slow part: it is a large"
  echo "      download from Apple and can take several minutes."
  echo
  # The old advice was "re-run this script when the dialog finishes", and
  # nobody re-runs a script. Wait instead. 30 minutes is generous enough for a
  # slow connection and short enough that a cancelled dialog does not hang here
  # forever.
  WAITED=0
  until xcode-select -p &>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$((WAITED % 60))" -eq 0 ]; then
      echo "      still waiting... ${B}$((WAITED / 60))m${N}"
    fi
    if [ "$WAITED" -ge 1800 ]; then
      bad "Gave up after 30 minutes. If you closed the window, paste this line again."
      exit 1
    fi
  done
  ok "installed"
fi

# ── 3. Download ──────────────────────────────────────────────────────────────
step "Downloading Chewbacca"

if [ -d "$HOME_DIR" ]; then
  work "found an existing install, updating it in place"
  rm -rf "$HOME_DIR.previous"
  mv "$HOME_DIR" "$HOME_DIR.previous"
fi

mkdir -p "$HOME_DIR"
# A tag if one was asked for, main otherwise. A tag is the reproducible
# install: two people running the same --version get the same tree.
if [ -n "$REF" ]; then
  TARBALL="https://codeload.github.com/$REPO/tar.gz/refs/tags/$REF"
  work "pinned to $REF"
else
  TARBALL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
fi
if ! curl -fsSL --max-time 120 "$TARBALL" | tar -xz -C "$HOME_DIR" --strip-components=1; then
  bad "Download failed.${REF:+ Is $REF a real tag?}"
  if [ -d "$HOME_DIR.previous" ]; then
    rm -rf "$HOME_DIR"
    mv "$HOME_DIR.previous" "$HOME_DIR"
    echo "      Your previous install was put back."
  fi
  exit 1
fi
rm -rf "$HOME_DIR.previous"
chmod +x "$HOME_DIR"/*.sh "$HOME_DIR"/bin/* 2>/dev/null || true

# Verify what was just downloaded against the checksums committed in the repo.
# It does not defend against a compromised repo, and it is not pretending to:
# it catches a truncated download, a proxy that rewrote something, and a
# mirror that is not what it claims. What it actually buys is written down in
# docs/THREAT-MODEL.md.
if [ -f "$HOME_DIR/SHA256SUMS.txt" ] && command -v shasum >/dev/null 2>&1; then
  MISMATCH=0
  VERIFIED=0
  while IFS= read -r line; do
    want="${line%% *}"
    file="${line##* }"
    # A manifest entry with no file on disk is a truncated download, or a
    # release that shipped the manifest without the file. Skipping it quietly
    # is how an absent file walks through the gate that exists to catch it.
    if [ ! -f "$HOME_DIR/$file" ]; then
      MISMATCH=$((MISMATCH+1)); echo "      missing: $file"; continue
    fi
    got="$(shasum -a 256 "$HOME_DIR/$file" | cut -d" " -f1)"
    if [ "$want" = "$got" ]; then
      VERIFIED=$((VERIFIED+1))
    else
      MISMATCH=$((MISMATCH+1)); echo "      changed: $file"
    fi
  done < "$HOME_DIR/SHA256SUMS.txt"
  if [ "$MISMATCH" -eq 0 ]; then
    # Count what was actually hashed, not the manifest's line count: those
    # differ precisely when something is missing, which is when it matters.
    ok "$VERIFIED files match their checksums"
  else
    bad "$MISMATCH file(s) do not match the committed checksums."
    echo "      Stopping. Report this: https://github.com/$REPO/issues"
    exit 1
  fi
fi
ok "$HOME_DIR"

# `chewbacca` on PATH, so update, doctor, and uninstall are one word each and
# nobody has to remember a path or the word "repo".
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/chewbacca" <<'LAUNCHER'
#!/bin/bash
# Chewbacca control. Installed by start.sh.
CB="$HOME/.chewbacca"
case "${1:-help}" in
  update)    exec bash "$CB/start.sh" "${@:2}" ;;
  doctor)    exec bash "$CB/doctor.sh" "${@:2}" ;;
  uninstall) exec bash "$CB/uninstall.sh" "${@:2}" ;;
  setup)     exec bash "$CB/setup.sh" "${@:2}" ;;
  where)     echo "$CB" ;;
  version)   cat "$CB/.version" 2>/dev/null || echo "unknown" ;;
  *)
    echo "chewbacca update      get the latest version"
    echo "chewbacca doctor      check that everything still works"
    echo "chewbacca setup       re-run part of the install"
    echo "chewbacca uninstall   remove all of it"
    echo "chewbacca where       print the install directory"
    echo ""
    echo "To control your Mac, the command is: chewie" ;;
esac
LAUNCHER
chmod +x "$BIN_DIR/chewbacca"
date -u +"%Y-%m-%d" > "$HOME_DIR/.version"

# A fresh Mac does not have ~/.local/bin on PATH, so the command we just
# installed would not exist for them. Add it to whichever shell they use.
for RC in "$HOME/.zshrc" "$HOME/.bash_profile"; do
  [ -f "$RC" ] || continue
  grep -q '.local/bin' "$RC" 2>/dev/null && continue
  printf '\n# Added by Chewbacca\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
done
export PATH="$BIN_DIR:$PATH"
ok "chewbacca command installed"

# ── 4. Everything else ───────────────────────────────────────────────────────
step "Installing the tools Claude will use"

if [ -x "$HOME_DIR/bin/bootstrap.sh" ]; then
  # The profile decides whether GitHub is part of this install at all. Without
  # it, bootstrap demanded a GitHub account and a git identity from someone
  # installing the personal profile, which creates no repos and needs neither.
  bash "$HOME_DIR/bin/bootstrap.sh" --profile "$PROFILE" ||
    work "some tools were skipped, continuing"
fi

SETUP_ARGS=(--profile "$PROFILE")
[ -n "$PERSON_NAME" ] && SETUP_ARGS+=(--name "$PERSON_NAME")
[ "$FULL_SEND" -eq 1 ] && SETUP_ARGS+=(--full-send)
[ "$FAST" -eq 1 ] && SETUP_ARGS+=(--fast)

step "Setting up Claude"
echo "      Name: ${PERSON_NAME:-not provided; your agent can ask later}."
echo
bash "$HOME_DIR/setup.sh" "${SETUP_ARGS[@]}" || {
  bad "Setup stopped after a failure. Some changes may already be installed; chewbacca doctor can inspect them."
  exit 1
}

# ── 5. Hand them to Claude, with something to do ─────────────────────────────
# A fast install deliberately left things out. Say which, and say the one
# command that gets them, rather than letting someone discover months later
# that their dictation and their MCP servers were never installed.
if [ "$FAST" -eq 1 ]; then
  FAST_TAIL="
  This was the fast install: it knows you, but it has no Homebrew packages,
  no plugins, no MCP servers and no dictation yet. To add all of that:
    ${B}chewbacca setup${N}
"
else
  FAST_TAIL=""
fi

# WHICH AGENT THIS PERSON ACTUALLY HAS.
#
# This screen used to say "Claude" three times and then exec claude, on a
# machine that might not have it. Sam hit exactly that on 2026-09-19: the
# install finished, told him to type `claude`, and Claude Code asked him to buy
# credits. His reply was "how is this model agnostic? i don't want to add
# claude credits", and he stopped there. A second tester said the same. That is the whole
# product claim failing on the last screen of the install.
#
# The kit already runs on Codex: tools/codex_context.py and tools/codex_hooks.py
# install its context and native lifecycle hooks, and the suite covers both. The
# installer simply never asked what was on the machine.
#
# Order is by how much of this kit each one can actually drive, and the first
# one present wins. Nothing here installs an agent or asks anyone to pay.
AGENT_CMD=""
AGENT_NAME=""
for candidate in "claude:Claude Code" "codex:Codex" "gemini:Gemini CLI"; do
  cmd="${candidate%%:*}"
  if command -v "$cmd" >/dev/null 2>&1; then
    AGENT_CMD="$cmd"
    AGENT_NAME="${candidate#*:}"
    break
  fi
done

if [ -n "$AGENT_CMD" ]; then
  START_LINE="  To start it any time: open Terminal and type ${B}${AGENT_CMD}${N}"
  SUBJECT="$AGENT_NAME"
else
  # No agent on the machine. Saying "type claude" here is how someone ends up
  # at a paywall they never asked for, so say what is true instead: the kit is
  # installed and works with whichever one they already use.
  START_LINE="  No coding agent found on this Mac yet. Chewbacca works with
  Claude Code, Codex or Gemini CLI: install whichever you already pay for and
  it will pick it up. Nothing here needs a second subscription."
  SUBJECT="Your agent"
fi

cat <<DONE

  ${G}${B}Done.${N}

  ${SUBJECT} can now read your calendar and contacts, send texts, see your
  screen, summarize any video or article, and remember what matters to you.

  Try asking it:
    "what's on my calendar tomorrow"
    "text <someone> that I'm running late"
    "what did this video actually say" and paste a link

${START_LINE}
  If something looks wrong:  ${B}chewbacca doctor${N}
  To remove everything:      ${B}chewbacca uninstall${N}
${FAST_TAIL}
DONE

# Opening Claude for them matters more than it sounds. The install otherwise
# ends at a shell prompt, which is the single highest-abandonment moment in the
# whole flow: ten minutes of work and then a blinking cursor. Needs a real
# terminal, so this is skipped when the output is piped somewhere.
if [ -n "$AGENT_CMD" ] && [ -t 0 ] && [ -t 1 ]; then
  say "Starting $AGENT_NAME..."
  sleep 1
  exec "$AGENT_CMD" "Introduce yourself in three sentences. The person supplied this name: ${PERSON_NAME:-no name provided; do not infer it from the computer account}. You were just
installed on their Mac. Say what you can now do that you could not before,
Ask what they want help with today. Do not read their calendar, contacts or
other private sources until they authorize the relevant access. Record only
what they choose to share. Do not list your features."
else
  # No TTY means this is running inside an agent's shell, which is the common
  # case: someone pasted the repo link at Claude and Claude ran this. Claude is
  # already here, so telling them to go open Claude is nonsense. Tell the agent
  # what to do next instead.
  echo "  Setup is done. Ask what the person wants help with today."
  echo "  Read personal sources only within the access they authorize."
  echo "  Then load the life-context skill and follow it. Do not ask them to"
  echo "  describe themselves."
fi
