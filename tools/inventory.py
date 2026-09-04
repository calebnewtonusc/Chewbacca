#!/usr/bin/env python3
"""Regenerate the Chewbacca inventory from what is installed on this machine.

Run it from anywhere:  python3 tools/inventory.py
It rewrites the generated regions of README.md, setup.sh, and
settings/toolkit.json to match the skills, plugins, MCP servers and CLI
tools actually present, so adding a skill updates the repo without anyone
remembering to.

The kit's README table and setup.sh install list used to be hand-maintained, so
every skill or plugin added to the local machine silently made the public repo
wrong. This reads what is actually installed and rewrites the generated regions
of README.md, setup.sh, and settings/toolkit.json to match.

What it will publish:
  - skills carrying a .source file (an upstream public repo)
  - skills vendored in the repo's own skills/ directory
  - skills symlinked out of a skill pack in PACKS, grouped into one row
  - plugins from enabledPlugins, with the marketplace they came from
  - the MCP servers in KIT_MCP, which is repo-owned data
  - CLI tools and macOS apps in CLI_TOOLS whose probe finds them installed

What it will never publish:
  - a skill with no .source that is not in the repo (assumed personal)
  - anything at all out of ~/.claude.json. It holds client hostnames and API
    keys, and nothing in this generator reads it.

Exit codes: 0 wrote changes, 1 nothing to do, 2 error.
"""

import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
# The repo this file lives in, not a path on one machine. The hardcoded
# absolute path meant a fork got generated files and no way to regenerate
# them, with a comment pointing at a script that was never shipped.
REPO = Path(__file__).resolve().parent.parent
SKILLS = HOME / ".claude/skills"
SETTINGS = HOME / ".claude/settings.json"

# The MCP servers the installer sets up, sourced from mcpmarket.com. This is
# repo-owned data, not a read of ~/.claude.json: that file holds client
# hostnames and API keys, and the old design published a server only if it was
# also installed on the maintainer's laptop, which made the kit's catalog a
# function of one machine. Nothing here is read from local config, so there is
# nothing to leak.
#
#   cmd/args  what `claude mcp add <name> --scope user --` runs
#   env       environment variables the server needs to do anything. A server
#             with an empty list works the moment it is installed; one with a
#             non-empty list is installed only when those variables are already
#             set, because a server that 500s on every call is worse than a
#             server that is absent.
KIT_MCP = {
    # Works with no account. This tier is why the feature is worth shipping:
    # someone who signs up for nothing still gets five new capabilities.
    "fetch": {
        "url": "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch",
        "description": "Pulls a URL down as markdown the agent can read, no key",
        "cmd": "uvx",
        "args": ["mcp-server-fetch"],
        "env": [],
    },
    "time": {
        "url": "https://github.com/modelcontextprotocol/servers/tree/main/src/time",
        "description": "Real current time and timezone conversion, no key",
        "cmd": "uvx",
        "args": ["mcp-server-time"],
        "env": [],
    },
    "git": {
        "url": "https://github.com/modelcontextprotocol/servers/tree/main/src/git",
        "description": "Reads, searches, and edits a git repo as structured calls, no key",
        "cmd": "uvx",
        "args": ["mcp-server-git"],
        "env": [],
    },
    "sequential-thinking": {
        "url": "https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking",
        "description": "Externalizes a long chain of reasoning into revisable steps, no key",
        "cmd": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
        "env": [],
    },
    "chart": {
        "url": "https://github.com/antvis/mcp-server-chart",
        "description": "Renders 25 chart types from data, so an answer can be a picture, no key",
        "cmd": "npx",
        "args": ["-y", "@antv/mcp-server-chart"],
        "env": [],
    },
    # mcpmarket.com's own Official row. Every one of these needs an account,
    # which is the whole reason they are gated on the key being present.
    "exa": {
        "url": "https://github.com/exa-labs/exa-mcp-server",
        "description": "Web search built for agents rather than for people, from Exa",
        "cmd": "npx",
        "args": ["-y", "exa-mcp-server"],
        "env": ["EXA_API_KEY"],
    },
    "tavily": {
        "url": "https://github.com/tavily-ai/tavily-mcp",
        "description": "Search plus extraction in one call, tuned for grounding answers",
        "cmd": "npx",
        "args": ["-y", "tavily-mcp"],
        "env": ["TAVILY_API_KEY"],
    },
    "firecrawl": {
        "url": "https://github.com/firecrawl/firecrawl-mcp-server",
        "description": "Crawls a whole site and returns clean markdown, not raw HTML",
        "cmd": "npx",
        "args": ["-y", "firecrawl-mcp"],
        "env": ["FIRECRAWL_API_KEY"],
    },
    "elevenlabs": {
        "url": "https://github.com/elevenlabs/elevenlabs-mcp",
        "description": "Text to speech and voice cloning as tools the agent can call",
        "cmd": "uvx",
        "args": ["elevenlabs-mcp"],
        "env": ["ELEVENLABS_API_KEY"],
    },
    "browserbase": {
        "url": "https://github.com/browserbase/mcp-server-browserbase",
        "description": "Drives a cloud browser, for sites that block a local one",
        "cmd": "npx",
        "args": ["-y", "@browserbasehq/mcp"],
        "env": ["BROWSERBASE_API_KEY", "BROWSERBASE_PROJECT_ID"],
    },
    "magic": {
        "url": "https://github.com/21st-dev/magic-mcp",
        "description": "Generates a real UI component from a description, from 21st.dev",
        "cmd": "npx",
        "args": ["-y", "@21st-dev/magic"],
        "env": ["TWENTY_FIRST_API_KEY"],
    },
}

# Skills that ship inside the repo. Their descriptions are the repo's to write,
# not the local copy's, so the generator only confirms they still exist.
VENDORED = {
    "second-brain": "Reading, writing, and auditing your personal context repo",
    "stack-rules": "The 12 stack-specific standards, loaded only when the work needs them",
    "graph-engineering": "Knowledge graphs and agent task graphs, with teaching mode",
    "agent-setup": "Finishing the install steps that need a browser or a permission dialog",
    "setup": "Installing the kit by conversation instead of a terminal questionnaire",
    "coursework": "Your syllabi as a ledger: deadlines, attendance math, per-course AI policy",
    "study-system": "Retrieval practice over rereading, exam run-ups, and the four-cause postmortem",
    "life-ops": "The weekly review, life admin with real deadlines, and what to cut",
}

# A skill pack is one upstream repo holding many skills, symlinked in per skill
# rather than copied. Listing 54 rows for one clone would bury everything else,
# so a pack collapses to a single row carrying its live count.
PACKS = {
    "agent-scripts": {
        "root": HOME / "Projects/agent-scripts",
        "url": "https://github.com/steipete/agent-scripts",
        "description": "Peter Steinberger's shared agent skills: macOS, Swift, GitHub, release ops",
        # sync-skills, the pack's own installer, points ~/.claude/CLAUDE.md at the
        # pack's AGENTS.MD. That silently replaces your global instructions, so the
        # generated install below links skills itself and never calls it.
        # frontend-design collides by name with the Anthropic plugin of the
        # same name, which has far more behind it. Two skills answering to one
        # name makes routing a coin flip.
        "skip": ["codex-first", "frontend-design"],
    },
}

# Command-line tools and macOS apps. Homebrew where a formula or cask exists, a
# clone plus a wrapper where none does. Only entries whose probe finds them on
# this machine are published, on the same rule the skills follow: the table
# describes what is actually installed, not what was once intended.
#   probe ("bin", x)  -> x is on PATH
#   probe ("app", x)  -> /Applications/x exists
#   probe ("path", x) -> path exists (~ expanded)
CLI_TOOLS = {
    "peekaboo": {
        "display": "peekaboo",
        "url": "https://github.com/openclaw/Peekaboo",
        "install": "brew install steipete/tap/peekaboo",
        "probe": ("bin", "peekaboo"),
        "description": "Screenshots, UI inspection, and click/type automation for any macOS app",
        # Also an MCP server. Registering it gives Claude the tools directly
        # instead of only through shell calls.
        "mcp_serve": "peekaboo mcp serve",
    },
    "summarize": {
        "display": "summarize",
        "url": "https://github.com/steipete/summarize",
        "install": "brew install steipete/tap/summarize",
        "probe": ("bin", "summarize"),
        "description": "Gist of any URL, YouTube video, podcast, or local file",
    },
    "macos-use": {
        "display": "mac-use",
        "url": "https://github.com/browser-use/macOS-use",
        "install": "see docs/MACOS-TOOLS.md (clone plus a uv venv, no formula)",
        "probe": ("bin", "mac-use"),
        "description": "Natural-language agent that drives any Mac app through Accessibility",
        # No formula and no console script upstream, so the kit ships the CLI
        # (bin/mac-use, bin/mac_use_cli.py) and installs the venv behind it.
        "shell": [
            'if command -v mac-use &>/dev/null; then',
            '  log "mac-use already installed"',
            'elif ! command -v uv &>/dev/null; then',
            '  warn "uv not found, skipping macOS-use. Install uv, then re-run:"',
            '  warn "  ./setup.sh --only tools"',
            'else',
            '  MU_DIR="$HOME/Projects/macOS-use"',
            '  [ -d "$MU_DIR/.git" ] || git clone -q --depth 1 \\',
            '    https://github.com/browser-use/macOS-use.git "$MU_DIR" 2>/dev/null || true',
            '  if [ -d "$MU_DIR" ]; then',
            '    cp "$SCRIPT_DIR/bin/mac_use_cli.py" "$MU_DIR/mac_use_cli.py"',
            '    cp "$SCRIPT_DIR/bin/mac_use_claude.py" "$MU_DIR/mac_use_claude.py"',
            '    mkdir -p "$HOME/.local/bin"',
            '    cp "$SCRIPT_DIR/bin/mac-use" "$HOME/.local/bin/mac-use"',
            '    chmod +x "$HOME/.local/bin/mac-use"',
            '    if (cd "$MU_DIR" && uv venv --python 3.11 &>/dev/null \\',
            '        && uv pip install --python .venv/bin/python --editable . &>/dev/null); then',
            '      log "mac-use installed"',
            '    else',
            '      warn "macOS-use deps failed. Retry: cd $MU_DIR && uv pip install -e ."',
            '    fi',
            '  else',
            '    warn "could not clone macOS-use"',
            '  fi',
            'fi',
        ],
    },
    "mac-cli": {
        "display": "mac",
        "url": "https://github.com/31Carlton7/mac-cli",
        "install": "see docs/MACOS-APP-CONTROL.md (clone plus swift build, no formula yet)",
        "probe": ("bin", "mac"),
        "description": "Calendar, Reminders, Contacts, Mail, Messages, Notes, and Finder as JSON",
        # No Homebrew tap yet (it is on the upstream roadmap), and `make install`
        # targets /usr/local/bin, which needs sudo. Build it and install to
        # ~/.local/bin alongside the kit's other user tools instead.
        "shell": [
            'if [ "$(uname -s)" != "Darwin" ]; then',
            '  :',
            'elif command -v mac &>/dev/null; then',
            '  log "mac-cli already installed"',
            'elif ! command -v swift &>/dev/null; then',
            '  warn "swift not found, skipping mac-cli. Run: xcode-select --install"',
            'else',
            '  MC_DIR="$HOME/Projects/mac-cli"',
            '  [ -d "$MC_DIR/.git" ] || git clone -q --depth 1 \\',
            '    https://github.com/31Carlton7/mac-cli.git "$MC_DIR" 2>/dev/null || true',
            '  if [ -d "$MC_DIR" ]; then',
            '    # SwiftPM caches dependencies as bare repos, which a global',
            '    # safe.bareRepository=explicit forbids it from reading. Override the',
            '    # setting for this one build rather than changing it machine-wide.',
            '    if (cd "$MC_DIR" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository \\',
            '        GIT_CONFIG_VALUE_0=all swift build -c release &>/dev/null); then',
            '      mkdir -p "$HOME/.local/bin"',
            '      install "$MC_DIR/.build/release/mac" "$HOME/.local/bin/mac"',
            '      log "mac-cli installed. Run: mac doctor  (grants are per-terminal)"',
            '    else',
            '      warn "mac-cli build failed. Retry: cd $MC_DIR && swift build -c release"',
            '    fi',
            '  else',
            '    warn "could not clone mac-cli"',
            '  fi',
            'fi',
        ],
    },
    "youtube-transcripts": {
        "display": "yt-transcript",
        "url": "https://github.com/calebnewtonusc/claude-youtube-transcripts",
        "install": "see docs/MACOS-TOOLS.md (its own installer, no formula)",
        "probe": ("bin", "yt-transcript"),
        "description": "Transcript of any YouTube video, channel, or playlist, read without asking",
        # Cloning the skill alone shipped a skill that told Claude to run a
        # command that was never installed. The upstream installer does the
        # whole job: yt-dlp, ffmpeg, two venvs, both CLIs, the skill, and a
        # UserPromptSubmit hook that notices a YouTube link on its own.
        "shell": [
            "if command -v yt-transcript &>/dev/null; then",
            '  log "yt-transcript already installed"',
            "else",
            '  YT_DIR="$(mktemp -d)"',
            '  if git clone -q --depth 1 https://github.com/calebnewtonusc/claude-youtube-transcripts \\',
            '      "$YT_DIR" 2>/dev/null && [ -x "$YT_DIR/install.sh" ]; then',
            '    if (cd "$YT_DIR" && ./install.sh &>/dev/null); then',
            '      log "yt-transcript installed"',
            "    else",
            '      warn "youtube-transcripts installer failed. Run it by hand: $YT_DIR/install.sh"',
            "    fi",
            "  else",
            '    warn "could not clone claude-youtube-transcripts"',
            "  fi",
            '  rm -rf "$YT_DIR"',
            "fi",
        ],
    },
    "beads": {
        "display": "bd",
        "url": "https://github.com/gastownhall/beads",
        "install": "brew install beads",
        "probe": ("bin", "bd"),
        "description": "Issue tracker your agent reads and writes, so work survives a context reset",
    },
    "anki": {
        "display": "Anki",
        "url": "https://github.com/ankitects/anki",
        "install": "brew install --cask anki",
        "probe": ("app", "Anki.app"),
        "description": "Spaced repetition, where the flashcards the study skills write actually live",
    },
    "maccy": {
        "display": "Maccy",
        "url": "https://github.com/p0deje/Maccy",
        "install": "brew install --cask maccy",
        "probe": ("app", "Maccy.app"),
        "description": "Clipboard history, so a value scrolled past is still recoverable",
    },
}


def read_frontmatter(path):
    """Pull name/description/license out of a SKILL.md without a YAML dep."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    out, key = {}, None
    for line in text[3:end].splitlines():
        if not line.strip():
            continue
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if m and not line.startswith(" "):
            key = m.group(1)
            val = m.group(2).strip()
            out[key] = "" if val in ("|", ">") else val
        elif key and line.startswith(" "):
            out[key] = (out[key] + " " + line.strip()).strip()
    return out


def first_sentence(text, limit=96):
    """One clause for a table cell. Long descriptions wreck the column."""
    text = re.sub(r"\s+", " ", text or "").strip()
    text = re.split(r"(?<=[.!?]) ", text)[0]
    text = re.sub(r"^Use (this skill )?when.*", "", text).strip()
    if len(text) > limit:
        text = text[: limit - 1].rsplit(" ", 1)[0] + "…"
    return text


def sniff_license(d):
    """Name the license from the LICENSE file when frontmatter omits it.

    add-skill.sh warns on AGPL and Proprietary because one AGPL skill can
    relicense an MIT project by contagion. A published table that shrugs and
    says "see LICENSE" throws away the warning, so read the file.
    """
    for name in ("LICENSE", "LICENSE.md", "LICENSE.txt"):
        f = d / name
        if not f.is_file():
            continue
        head = f.read_text(encoding="utf-8", errors="replace")[:400]
        for needle, label in (
            ("GNU AFFERO", "AGPL-3.0"),
            ("GNU GENERAL PUBLIC", "GPL"),
            ("Apache License", "Apache-2.0"),
            ("MIT License", "MIT"),
            ("BSD", "BSD"),
            ("Mozilla Public", "MPL-2.0"),
        ):
            if needle.lower() in head.lower():
                return label
        return "see LICENSE"
    return "see upstream"


def read_source(d):
    f = d / ".source"
    if not f.is_file():
        return None
    out = {}
    for line in f.read_text(encoding="utf-8").splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip()
    return out if out.get("source") else None


def pack_of(d):
    """Name the pack a skill directory was symlinked out of, if any.

    Pack skills carry no .source: they are links into one clone, so the source
    is the clone. Resolving the link is what tells them apart from a personal
    skill, which must never be published.
    """
    try:
        real = d.resolve()
    except OSError:
        return None
    for name, spec in PACKS.items():
        root = spec["root"].resolve() if spec["root"].exists() else spec["root"]
        try:
            real.relative_to(root)
        except ValueError:
            continue
        return name
    return None


def collect_skills():
    upstream, vendored = [], []
    packs = {}
    for d in sorted(p for p in SKILLS.glob("*") if p.is_dir()):
        name = d.name
        fm = read_frontmatter(d / "SKILL.md")
        desc = first_sentence(fm.get("description", ""))
        pack = pack_of(d)
        if pack:
            packs.setdefault(pack, []).append(name)
            continue
        src = read_source(d)
        if src:
            upstream.append(
                {
                    "name": name,
                    "url": src["source"],
                    "path": src.get("path", ""),
                    "license": fm.get("license") or sniff_license(d),
                    "author": (
                        fm.get("metadata_author")
                        or src["source"].rstrip("/").split("/")[-2]
                    ),
                    "description": desc,
                }
            )
        elif name in VENDORED:
            vendored.append({"name": name, "description": VENDORED[name]})
    for name, desc in VENDORED.items():
        if not any(v["name"] == name for v in vendored) and (REPO / "skills" / name).is_dir():
            vendored.append({"name": name, "description": desc})
    vendored.sort(key=lambda v: v["name"])
    packs = [
        {
            "name": n,
            "url": PACKS[n]["url"],
            "description": PACKS[n]["description"],
            "count": len(skills),
            "skills": sorted(skills),
            "skip": PACKS[n].get("skip", []),
        }
        for n, skills in sorted(packs.items())
    ]
    return upstream, vendored, packs


def collect_cli():
    """Publish only the tools this machine can actually prove it has."""
    found = []
    for key, spec in sorted(CLI_TOOLS.items()):
        kind, target = spec["probe"]
        if kind == "bin":
            ok = any(
                (Path(d) / target).is_file() and os.access(Path(d) / target, os.X_OK)
                for d in os.environ.get("PATH", "").split(":")
                if d
            )
        elif kind == "app":
            ok = Path("/Applications", target).exists()
        else:
            ok = Path(target).expanduser().exists()
        if ok:
            entry = {k: spec[k] for k in ("display", "url", "install", "description")}
            for extra in ("shell", "mcp_serve"):
                if extra in spec:
                    entry[extra] = spec[extra]
            found.append(entry)
    return found


def collect_plugins():
    try:
        s = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return [], []
    plugins = sorted(k for k, v in s.get("enabledPlugins", {}).items() if v)
    markets = {"anthropics/claude-plugins-official"}
    for spec in s.get("extraKnownMarketplaces", {}).values():
        repo = (spec.get("source") or {}).get("repo")
        if repo:
            markets.add(repo)
    return plugins, sorted(markets)


def collect_mcp():
    """The catalog, verbatim. Deliberately does not read ~/.claude.json."""
    return [dict(spec, name=name) for name, spec in KIT_MCP.items()]


def md_table(upstream, vendored, packs, plugins, mcp):
    rows = []
    for v in vendored:
        rows.append((f"[skills/{v['name']}](skills/{v['name']})", "Skill", v["description"]))
    for u in upstream:
        rows.append((f"[{u['name']}]({u['url']})", "Skill", u["description"]))
    for k in packs:
        rows.append(
            (
                f"[{k['name']}]({k['url']}) ({k['count']})",
                "Pack",
                k["description"],
            )
        )

    named = {
        "understand-anything", "context7", "humanizer",
        "security-guidance", "hookify", "claude-md-management",
        "feature-dev", "frontend-design", "session-report",
    }
    rest = []
    for p in plugins:
        short, _, market = p.partition("@")
        if short in named:
            repo = "https://github.com/anthropics/claude-plugins-official"
            if market == "understand-anything":
                repo = "https://github.com/Egonex-AI/Understand-Anything"
            elif market == "humanizer":
                repo = "https://github.com/blader/humanizer"
            desc = {
                "understand-anything": "Turns a codebase into an interactive knowledge graph you can query",
                "context7": "Real library docs on demand instead of the model's training recall",
                "humanizer": "Strips the Wikipedia-catalogued signs of AI writing out of a draft",
                "security-guidance": "Warns on the edit, not in review, when a change looks unsafe",
                "hookify": "Reads a session and writes the hook that stops the thing that annoyed you",
                "claude-md-management": "Audits the standards file this kit installs, so it does not rot",
                "feature-dev": "A seven-phase build: requirements, architecture, tests, review, docs",
                "frontend-design": "Design judgment, so a generated UI is not three cards on a gradient",
                "session-report": "An explorable report of what a session actually cost and did",
            }[short]
            rows.append((f"[{short}]({repo})", "Plugin", desc))
        else:
            rest.append(short)
    if rest:
        rows.append(
            (
                ", ".join(sorted(rest)),
                "Plugin",
                "Language servers, browser automation, deploys, and data tooling",
            )
        )
    for m in mcp:
        rows.append((f"[{m['name']}]({m['url']})", "MCP", m["description"]))

    w = [max(len(r[i]) for r in rows + [("Extension", "Layer", "What it does")]) for i in range(3)]
    out = [
        f"| {'Extension'.ljust(w[0])} | {'Layer'.ljust(w[1])} | {'What it does'.ljust(w[2])} |",
        f"| {'-' * w[0]} | {'-' * w[1]} | {'-' * w[2]} |",
    ]
    for r in rows:
        out.append(f"| {r[0].ljust(w[0])} | {r[1].ljust(w[1])} | {r[2].ljust(w[2])} |")
    return "\n".join(out)


def cli_table(cli):
    """Its own table: an install line matters more here than a layer label."""
    head = ("Tool", "Install", "What it does")
    # A pointer to the docs is prose, not a command. Code-formatting it invites
    # someone to paste "see docs/..." into a shell.
    rows = [
        (
            f"[{c['display']}]({c['url']})",
            c["install"] if c["install"].startswith("see ") else f"`{c['install']}`",
            c["description"],
        )
        for c in cli
    ]
    w = [max(len(r[i]) for r in rows + [head]) for i in range(3)]
    out = [
        "| " + " | ".join(head[i].ljust(w[i]) for i in range(3)) + " |",
        "| " + " | ".join("-" * w[i] for i in range(3)) + " |",
    ]
    for r in rows:
        out.append("| " + " | ".join(r[i].ljust(w[i]) for i in range(3)) + " |")
    return "\n".join(out)


def cli_block(cli, packs):
    """The setup.sh half: install the tools, then link the pack's skills.

    Every install is guarded on the probe already passing, so re-running setup
    on a machine that has them is a no-op rather than a pile of brew warnings.
    """
    lines = [
        "# Kit-owned helpers that sit in front of the installed tools.",
        "#   peekaboo: forces local execution, see docs/MACOS-TOOLS.md",
        "#   chrome-js: reads and clicks a Chrome tab through JavaScript",
        'mkdir -p "$HOME/.local/bin"',
        "for HELPER in peekaboo chrome-js slop-check; do",
        '  if [ -f "$SCRIPT_DIR/bin/$HELPER" ]; then',
        '    cp "$SCRIPT_DIR/bin/$HELPER" "$HOME/.local/bin/$HELPER"',
        '    chmod +x "$HOME/.local/bin/$HELPER"',
        '    log "$HELPER installed to ~/.local/bin/"',
        "  fi",
        "done",
        "",
        "# macOS command-line tools. Skipped without Homebrew, and skipped one by",
        "# one if already present, so this is safe to re-run.",
        "if command -v brew &>/dev/null; then",
    ]
    for c in cli:
        if not c["install"].startswith("brew ") or c.get("shell"):
            continue
        probe = c["display"]
        if probe == "Maccy":
            guard = '[ -d "/Applications/Maccy.app" ]'
        else:
            # The kit's own wrapper is on PATH ahead of brew, so `command -v`
            # would report peekaboo present before brew ever installed it.
            guard = (
                '[ -x /opt/homebrew/bin/peekaboo ]'
                if probe == "peekaboo"
                else f'command -v {probe} &>/dev/null'
            )
        lines += [
            f"  if {guard}; then",
            f'    log "{probe} already installed"',
            "  else",
            f"    {c['install']} &>/dev/null && log \"{probe} installed\" || warn \"could not install {probe}\"",
            "  fi",
        ]
    lines += [
        "else",
        '  warn "Homebrew not found. macOS tools skipped: see docs/MACOS-TOOLS.md"',
        "fi",
    ]

    for c in cli:
        if c.get("shell"):
            lines += ["", f"# {c['display']}: {c['description']}"] + c["shell"]

    for c in cli:
        if not c.get("mcp_serve"):
            continue
        name = c["display"]
        lines += [
            "",
            f"# {name} speaks MCP too. Registered at user scope so it is available in",
            "# every project, not just this one.",
            "if ! command -v claude &>/dev/null; then",
            '  warn "claude CLI missing, so the %s MCP server was not registered"' % name,
            "elif command -v %s &>/dev/null; then" % name,
            '  if claude mcp list 2>/dev/null | grep -q "^%s:"; then' % name,
            f'    log "{name} MCP already registered"',
            f'  elif claude mcp add {name} --scope user -- {c["mcp_serve"]} &>/dev/null; then',
            f'    log "{name} MCP registered"',
            "  else",
            f'    warn "could not register the {name} MCP server"',
            "  fi",
            "fi",
        ]

    for k in packs:
        skip = " ".join(k["skip"])
        lines += [
            "",
            f"# Skill pack: {k['name']}. Linked per skill, not copied, so `git pull` in",
            "# the clone updates every skill at once.",
            "#",
            "# Its own installer (scripts/sync-skills) repoints ~/.claude/CLAUDE.md at the",
            "# pack's AGENTS.MD, which would replace your global instructions. Do not run",
            "# it. The loop below does the linking and touches nothing else.",
            f'PACK_DIR="$HOME/Projects/{k["name"]}"',
            f'PACK_SKIP="{skip}"',
            'if [ -d "$PACK_DIR/.git" ]; then',
            f'  log "{k["name"]} already cloned, left alone"',
            'elif git clone -q --depth 1 "%s.git" "$PACK_DIR" 2>/dev/null; then' % k["url"],
            f'  log "{k["name"]} cloned"',
            "else",
            f'  warn "could not clone {k["name"]}"',
            "fi",
            'if [ -d "$PACK_DIR/skills" ]; then',
            '  PACK_N=0',
            '  for SK in "$PACK_DIR"/skills/*/; do',
            '    SK_NAME="$(basename "$SK")"',
            '    [ -f "$SK/SKILL.md" ] || continue',
            '    case " $PACK_SKIP " in *" $SK_NAME "*) continue;; esac',
            '    [ -e "$GLOBAL_CLAUDE/skills/$SK_NAME" ] && continue',
            '    ln -s "$SK" "$GLOBAL_CLAUDE/skills/$SK_NAME"',
            "    PACK_N=$((PACK_N+1))",
            "  done",
            f'  log "{k["name"]}: $PACK_N skills linked"',
            "fi",
        ]
    return "\n".join(lines)


def badge_block(plugins):
    """The three count badges. A stale number in a badge is a lie with a border."""
    cmds = len(list((REPO / ".claude/commands").glob("*.md")))
    rules = len(list((REPO / ".claude/rules").glob("*.md")))
    b = "https://img.shields.io/badge"
    return "\n".join(
        [
            f'  <a href=".claude/commands"><img src="{b}/slash_commands-{cmds}-indigo" alt="Commands"></a>',
            f'  <a href=".claude/rules"><img src="{b}/always_on_rules-{rules}-green" alt="Rules"></a>',
            f'  <a href="docs/EXTENSIONS.md"><img src="{b}/plugins-{len(plugins)}-orange" alt="Plugins"></a>',
        ]
    )


def summary_row(upstream, vendored, packs, plugins, markets):
    """Rewrite one cell of the what-you-get table. Markers would break the table."""
    packed = sum(k["count"] for k in packs)
    total = len(upstream) + len(vendored) + packed
    parts = [f"{len(vendored)} shipped here", f"{len(upstream)} cloned from upstream"]
    if packed:
        parts.append(f"{packed} from {len(packs)} skill pack{'s' if len(packs) > 1 else ''}")
    return (
        f"{total} skills ({', '.join(parts)}) "
        f"plus {len(plugins)} plugins across {len(markets)} marketplaces"
    )


def rewrite_row(path, label, cell):
    """Replace the last cell of the table row whose first cell is `label`."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        r"^(\|\s*\*\*" + re.escape(label) + r"\*\*\s*\|\s*).*?(\s*\|)\s*$",
        re.MULTILINE,
    )
    if not pattern.search(text):
        print(f"  row '{label}' not found in {path.name}, skipped", file=sys.stderr)
        return False
    new = pattern.sub(lambda m: m.group(1) + cell + m.group(2), text, count=1)
    if new == text:
        return False
    path.write_text(new, encoding="utf-8")
    return True


def setup_block(upstream, plugins, markets, mcp):
    lines = [
        "# Upstream skills are cloned rather than vendored, so each stays updatable and",
        "# keeps the LICENSE it shipped with. add-skill.sh does the same thing by hand.",
        "while IFS='|' read -r SK_NAME SK_URL SK_PATH SK_LICENSE SK_AUTHOR; do",
        '  [ -n "$SK_NAME" ] || continue',
        '  if [ -d "$GLOBAL_CLAUDE/skills/$SK_NAME" ]; then',
        '    log "$SK_NAME already present, left alone"',
        "    continue",
        "  fi",
        '  TMP_SK="$(mktemp -d)"',
        '  if git clone -q --depth 1 "$SK_URL" "$TMP_SK" 2>/dev/null; then',
        '    SK_SRC="$TMP_SK"',
        '    [ -n "$SK_PATH" ] && SK_SRC="$TMP_SK/$SK_PATH"',
        '    mkdir -p "$GLOBAL_CLAUDE/skills/$SK_NAME"',
        '    cp -R "$SK_SRC/." "$GLOBAL_CLAUDE/skills/$SK_NAME/" 2>/dev/null || true',
        '    rm -rf "$GLOBAL_CLAUDE/skills/$SK_NAME/.git"',
        '    [ -f "$TMP_SK/LICENSE" ] && cp "$TMP_SK/LICENSE" "$GLOBAL_CLAUDE/skills/$SK_NAME/LICENSE" 2>/dev/null',
        '    printf \'source: %s\\ninstalled: %s\\n\' "$SK_URL" "$(date -u +%Y-%m-%d)" \\',
        '      > "$GLOBAL_CLAUDE/skills/$SK_NAME/.source"',
        '    log "$SK_NAME installed ($SK_LICENSE, $SK_AUTHOR)"',
        "  else",
        '    warn "Could not reach GitHub for $SK_NAME. See docs/EXTENSIONS.md to add it later."',
        "  fi",
        '  rm -rf "$TMP_SK"',
        "done <<'UPSTREAM_SKILLS'",
    ]
    for u in upstream:
        lines.append(f"{u['name']}|{u['url']}|{u['path']}|{u['license']}|{u['author']}")
    lines += [
        "UPSTREAM_SKILLS",
        "",
        "# A missing claude CLI used to drop every plugin with one warning. The",
        "# installer already needs node, so install the CLI rather than skip the",
        "# largest single piece of what this kit is.",
        "if ! command -v claude &>/dev/null && command -v npm &>/dev/null; then",
        '  log "claude CLI not found, installing it"',
        "  npm install -g @anthropic-ai/claude-code &>/dev/null \\",
        '    && log "claude CLI installed" \\',
        '    || warn "could not install the claude CLI: npm install -g @anthropic-ai/claude-code"',
        "fi",
        "",
        "if command -v claude &>/dev/null; then",
        "  for m in \\",
    ]
    lines += [f"    {m} \\" for m in markets[:-1]] + [f"    {markets[-1]}; do"]
    lines += [
        '    claude plugin marketplace add "$m" </dev/null &>/dev/null || true',
        "  done",
        '  log "Marketplaces registered"',
        "",
        "  PLUGIN_FAILED=0",
        "  for p in \\",
    ]
    lines += [f"    {p} \\" for p in plugins[:-1]] + [f"    {plugins[-1]}; do"]
    lines += [
        '    if claude plugin install "$p" --scope user </dev/null &>/dev/null; then',
        '      log "installed ${p%%@*}"',
        "    else",
        '      warn "could not install ${p%%@*}"',
        "      PLUGIN_FAILED=1",
        "    fi",
        "  done",
        "",
        '  if [ "$PLUGIN_FAILED" -eq 1 ]; then',
        '    warn "Some plugins failed. Retry individually: claude plugin install <name>"',
        "  fi",
        '  warn "Plugins needing OAuth (Vercel, Railway) stay inert until you run /mcp and authorize."',
        "else",
        '  warn "claude CLI still missing. Plugins skipped: install node, then re-run"',
        '  warn "  ./setup.sh --only plugins"',
        "fi",
    ]
    if mcp:
        free = [m for m in mcp if not m["env"]]
        keyed = [m for m in mcp if m["env"]]
        lines += [
            "",
            "# MCP servers, curated from mcpmarket.com. See docs/EXTENSIONS.md.",
            "#",
            "# Two tiers on purpose. The keyless ones are installed outright. The ones",
            "# needing an account are installed only when their variables are already",
            "# exported, because `claude mcp add` will happily register a server that",
            "# fails on every call, and a broken tool in the list is worse than a",
            "# missing one: the agent keeps reaching for it.",
            "if command -v claude &>/dev/null; then",
            "  mcp_present() { claude mcp list 2>/dev/null | grep -q \"^$1:\"; }",
            "",
            "  while IFS='|' read -r M_NAME M_CMD M_ARGS; do",
            '    [ -n "$M_NAME" ] || continue',
            '    if mcp_present "$M_NAME"; then',
            '      log "$M_NAME already registered"',
            "      continue",
            "    fi",
            # The directive has to sit in front of a whole compound command.
            # In front of an elif branch shellcheck errors with SC1123.
            "    # shellcheck disable=SC2086  # M_ARGS is a deliberate argument list",
            '    if claude mcp add "$M_NAME" --scope user -- "$M_CMD" $M_ARGS &>/dev/null; then',
            '      log "$M_NAME registered"',
            "    else",
            '      warn "could not register $M_NAME"',
            "    fi",
            "  done <<'KEYLESS_MCP'",
        ]
        lines += [f"{m['name']}|{m['cmd']}|{' '.join(m['args'])}" for m in free]
        lines += [
            "KEYLESS_MCP",
            "",
            "  while IFS='|' read -r M_NAME M_CMD M_ARGS M_ENV; do",
            '    [ -n "$M_NAME" ] || continue',
            '    if mcp_present "$M_NAME"; then',
            '      log "$M_NAME already registered"',
            "      continue",
            "    fi",
            "    M_FLAGS=\"\"; M_MISSING=\"\"",
            "    for M_VAR in $M_ENV; do",
            '      M_VAL="$(eval "printf %s \\"\\${$M_VAR:-}\\"")"',
            '      if [ -n "$M_VAL" ]; then',
            '        M_FLAGS="$M_FLAGS --env $M_VAR=$M_VAL"',
            "      else",
            '        M_MISSING="$M_MISSING $M_VAR"',
            "      fi",
            "    done",
            '    if [ -n "$M_MISSING" ]; then',
            '      warn "$M_NAME skipped, needs:$M_MISSING"',
            "      continue",
            "    fi",
            "    # shellcheck disable=SC2086  # both are deliberate argument lists",
            '    if claude mcp add "$M_NAME" --scope user $M_FLAGS -- "$M_CMD" $M_ARGS &>/dev/null; then',
            '      log "$M_NAME registered"',
            "    else",
            '      warn "could not register $M_NAME"',
            "    fi",
            "  done <<'KEYED_MCP'",
        ]
        lines += [
            f"{m['name']}|{m['cmd']}|{' '.join(m['args'])}|{' '.join(m['env'])}" for m in keyed
        ]
        lines += [
            "KEYED_MCP",
            "",
            '  log "MCP servers done. Anything skipped: export its key and re-run"',
            '  log "  ./setup.sh --only plugins"',
            "fi",
        ]
    return "\n".join(lines)


def splice(path, begin, end, body, pad=False):
    """Replace the region between two markers. Returns True if the file changed.

    `pad` puts a blank line on each side of the body. Prettier adds those to
    markdown anyway, and a generator that keeps removing them turns every
    session into a no-op commit.
    """
    text = path.read_text(encoding="utf-8")
    # `.*?` rather than `\n.*?\n`: a freshly added marker pair has nothing
    # between its two lines yet, and the stricter pattern skipped those files
    # with "missing markers", which reads as a typo rather than an empty region.
    pattern = re.compile(re.escape(begin) + r"\n.*?" + re.escape(end), re.DOTALL)
    if not pattern.search(text):
        print(f"  missing markers in {path.name}, skipped", file=sys.stderr)
        return False
    gap = "\n" if pad else ""
    new = pattern.sub(lambda _: f"{begin}\n{gap}{body}\n{gap}{end}", text)
    if new == text:
        return False
    mode = path.stat().st_mode  # setup.sh is executable and must stay that way
    path.write_text(new, encoding="utf-8")
    os.chmod(path, mode)
    return True


def main():
    if not REPO.is_dir():
        print(f"repo not found: {REPO}", file=sys.stderr)
        return 2

    upstream, vendored, packs = collect_skills()
    plugins, markets = collect_plugins()
    mcp = collect_mcp()
    cli = collect_cli()
    if not plugins or not markets:
        print("no plugins resolved, refusing to write an empty install list", file=sys.stderr)
        return 2

    changed = []

    toolkit = REPO / "settings/toolkit.json"
    payload = {
        "_comment": "Generated by tools/inventory.py. Hand edits are overwritten.",
        "skills": {
            "vendored": [v["name"] for v in vendored],
            "upstream": [
                {k: u[k] for k in ("name", "url", "path", "license", "author")} for u in upstream
            ],
        },
        "packs": [
            {k: pk[k] for k in ("name", "url", "count", "skills")} for pk in packs
        ],
        "marketplaces": markets,
        "plugins": plugins,
        "mcp": mcp,
        "cli": [
            {k: v for k, v in c.items() if k not in ("shell", "mcp_serve")} for c in cli
        ],
    }
    rendered = json.dumps(payload, indent=2) + "\n"
    if not toolkit.is_file() or toolkit.read_text(encoding="utf-8") != rendered:
        toolkit.parent.mkdir(parents=True, exist_ok=True)
        toolkit.write_text(rendered, encoding="utf-8")
        changed.append("settings/toolkit.json")

    readme = REPO / "README.md"
    touched = splice(
        readme,
        "<!-- BEGIN GENERATED: extensions -->",
        "<!-- END GENERATED: extensions -->",
        md_table(upstream, vendored, packs, plugins, mcp),
        pad=True,
    )
    if cli:
        touched |= splice(
            readme,
            "<!-- BEGIN GENERATED: cli -->",
            "<!-- END GENERATED: cli -->",
            cli_table(cli),
            pad=True,
        )
    # No padding on the badges: a blank line inside the centered <p> block ends
    # the HTML block and dumps the raw tags into the rendered page.
    touched |= splice(
        readme,
        "<!-- BEGIN GENERATED: badges -->",
        "<!-- END GENERATED: badges -->",
        badge_block(plugins),
    )
    touched |= rewrite_row(
        readme, "Skills and plugins", summary_row(upstream, vendored, packs, plugins, markets)
    )
    if cli:
        # Hand-written, this row said "Google Workspace" for a tool that had
        # already been dropped. Generate it from the same list as the table.
        touched |= rewrite_row(
            readme,
            "macOS tools",
            f"{len(cli)} installed alongside the kit: "
            + ", ".join(c["display"] for c in cli),
        )
    if touched:
        changed.append("README.md")

    setup = REPO / "setup.sh"
    wrote = splice(
        setup,
        "# BEGIN GENERATED: extensions",
        "# END GENERATED: extensions",
        setup_block(upstream, plugins, markets, mcp),
    )
    if cli or packs:
        wrote |= splice(
            setup,
            "# BEGIN GENERATED: cli",
            "# END GENERATED: cli",
            cli_block(cli, packs),
        )
    if wrote:
        changed.append("setup.sh")

    if not changed:
        return 1
    print("\n".join(changed))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # a broken generator must never block a session
        print(f"inventory generator failed: {exc}", file=sys.stderr)
        sys.exit(2)
