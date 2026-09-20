#!/usr/bin/env python3
"""hud-speak, the parts that need no model: how a reply is split into the
sentences that are made one at a time, and where a short line's sound is
kept between runs.

The script is a uv script whose dependencies (mlx-audio, spacy) are not on
the test machine and are only imported inside the functions that need
them, so the module loads with the standard library alone.
"""
from __future__ import annotations

import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "bin" / "hud-speak"
failures: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def load():
    spec = importlib.util.spec_from_file_location(
        "hud_speak", BIN, loader=SourceFileLoader("hud_speak", str(BIN))
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["hud_speak"] = module
    spec.loader.exec_module(module)
    return module


def test_sentences(m) -> None:
    parts = m.sentences("Checking your calendar. You have three things tomorrow! Two are all day. Ok.")
    check("split at sentence ends",
          parts == ["Checking your calendar.", "You have three things tomorrow!", "Two are all day. Ok."],
          f"got {parts}")
    check("a two-word tail joins the sentence before it", parts[-1].endswith("Ok."))
    check("blank in, nothing out", m.sentences("   ") == [])
    check("a short opening joins the sentence after it",
          m.sentences("Dr. Who is here. Yes.") == ["Dr. Who is here. Yes."]
          and m.sentences("Yes. That is the one you booked yesterday.") == ["Yes. That is the one you booked yesterday."],
          f"got {m.sentences('Dr. Who is here. Yes.')}")
    check("one short line stays", m.sentences("Yes.") == ["Yes."])


def test_cache_path(m) -> None:
    short = m.cache_path("af_heart", 1.0, "Done.")
    check("a short line has a home", short is not None and short.parent == m.CACHE and short.suffix == ".wav")
    check("the same words, voice and speed land in the same file",
          short == m.cache_path("af_heart", 1.0, "Done."))
    check("another voice is another file", short != m.cache_path("am_michael", 1.0, "Done."))
    check("another speed is another file", short != m.cache_path("af_heart", 1.2, "Done."))
    check("the words are not in the name", "Done" not in short.name)
    long = m.cache_path("af_heart", 1.0, " ".join(["word"] * (m.CACHE_WORDS + 1)))
    check("a long line is never kept", long is None)
    edge = m.cache_path("af_heart", 1.0, " ".join(["word"] * m.CACHE_WORDS))
    check("a line of exactly the limit is kept", edge is not None)


def test_trim_cache(m, tmp: Path) -> None:
    m.CACHE = tmp
    for i in range(6):
        f = tmp / f"{i}.wav"
        f.write_bytes(b"x")
        import os
        os.utime(f, (1_000_000 + i, 1_000_000 + i))
    m.trim_cache(limit=4)
    left = sorted(p.name for p in tmp.glob("*.wav"))
    check("the oldest go first", left == ["2.wav", "3.wav", "4.wav", "5.wav"], f"got {left}")
    m.trim_cache(limit=4)
    check("under the limit nothing goes", len(list(tmp.glob("*.wav"))) == 4)


def main() -> int:
    import tempfile

    module = load()
    print("sentences")
    test_sentences(module)
    print("the cache")
    test_cache_path(module)
    test_trim_cache(module, Path(tempfile.mkdtemp()))
    print()
    if failures:
        print(f"{len(failures)} failed: {', '.join(failures)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
