"""Tests for tools/inventory.py frontmatter parsing and house-style normalising.

Both cases here are bugs that shipped into docs/REFERENCE.md, which is a public
file, on 2026-09-16 when Cap's two skills were installed.

    python3 tests/test_inventory.py
"""

import importlib.util
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("inventory", ROOT / "tools" / "inventory.py")
inv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inv)

PASSED = FAILED = 0


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def frontmatter(text):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(text)
    return inv.read_frontmatter(pathlib.Path(fh.name))


# ── YAML block scalars ───────────────────────────────────────────────────────
#
# The parser handled a bare "|" and ">" and nothing else. Cap writes
# `description: >-`, so the marker became the value and the folded lines were
# appended behind it. docs/REFERENCE.md published ">- Always use Cap's CLI...".

for marker in ("|", ">", "|-", ">-", "|+", ">+", "|2", ">2"):
    fm = frontmatter(f"---\nname: x\ndescription: {marker}\n  the real text here\n---\n\nbody\n")
    check(
        f"block scalar '{marker}' does not leak into the value",
        fm.get("description") == "the real text here",
        repr(fm.get("description")),
    )

fm = frontmatter("---\nname: x\ndescription: a plain one-line value\n---\n")
check(
    "a plain scalar is untouched",
    fm.get("description") == "a plain one-line value",
    repr(fm.get("description")),
)

# A value that merely starts with > is not a block scalar.
fm = frontmatter("---\nname: x\ndescription: '>= 3 files'\n---\n")
check(
    "a value that only looks like a marker survives",
    ">= 3 files" in (fm.get("description") or ""),
    repr(fm.get("description")),
)


# ── house style on vendored text ─────────────────────────────────────────────
#
# Vendored descriptions ship verbatim into README.md and docs/REFERENCE.md,
# where this repo's writing rules ban em dashes outright. Cap's cap-demo
# description put one straight into the generated table.

check(
    "a spaced em dash becomes a colon",
    inv.house_style("Generate a demo — scouts the page") == "Generate a demo: scouts the page",
    inv.house_style("Generate a demo — scouts the page"),
)
check(
    "an unspaced em dash becomes a comma",
    inv.house_style("zoom—on click") == "zoom, on click",
    inv.house_style("zoom—on click"),
)
check("text without an em dash is unchanged", inv.house_style("plain text") == "plain text")
check("a non-string passes through", inv.house_style(None) is None)

fm = frontmatter("---\nname: x\ndescription: >-\n  a demo — with a dash\n---\n")
check(
    "frontmatter is normalised on the way out",
    "—" not in (fm.get("description") or ""),
    repr(fm.get("description")),
)


# ── skill packs whose skills are not under skills/ ───────────────────────────

# gtm-engineer-skills (2026-09-23) keeps its skills at the repo root. The
# generated loop hardcoded "$PACK_DIR"/skills/*/, which would have linked
# nothing and logged "0 skills linked" as if that were success.
root_pack = {"name": "p", "url": "https://x/p", "skip": [], "subdir": ".", "note": []}
nested_pack = {"name": "q", "url": "https://x/q", "skip": [], "subdir": "skills", "note": ["hello"]}
block = inv.cli_block({}, [root_pack, nested_pack])
check("a root-level pack loops over the clone root", '"$PACK_DIR"/./*/' in block, block)
check("a nested pack still loops over skills/", '"$PACK_DIR"/skills/*/' in block, block)
check("a pack's note becomes a comment", "# hello" in block, block)


# ── the generated files themselves ───────────────────────────────────────────

for rel in ("docs/REFERENCE.md", "README.md", "settings/toolkit.json"):
    p = ROOT / rel
    if not p.is_file():
        continue
    body = p.read_text(encoding="utf-8")
    check(f"{rel} carries no em dash", "—" not in body)
    check(f"{rel} carries no leaked scalar marker", ">- " not in body and "| >-" not in body)

# Guarded because the filename matches pytest's discovery pattern. Without
# this, importing the module to collect it runs sys.exit and pytest aborts the
# whole session with INTERNALERROR, taking every other test file down with it.
if __name__ == "__main__":
    print(f"\n{PASSED} passed, {FAILED} failed.")
    sys.exit(1 if FAILED else 0)
