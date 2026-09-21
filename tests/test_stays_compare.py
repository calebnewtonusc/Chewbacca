"""procedures/stays-compare, on the cards the sites gave on 2026-09-20.

No network: the fixtures are the raw cards run.py saved, so a parser that
drifts from what the sites say fails here before it fails at midnight.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures" / "stays"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    # dataclasses resolves a module's annotations through sys.modules, so an
    # unregistered module fails with "'NoneType' object has no attribute '__dict__'".
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


run = load("stays_run", ROOT / "procedures" / "stays-compare" / "run.py")
verify = load("stays_verify", ROOT / "procedures" / "stays-compare" / "verify.py")
airbnb = json.loads((FIXTURES / "raw-airbnb.json").read_text())["cards"]
booking = json.loads((FIXTURES / "raw-booking.json").read_text())["cards"]
NIGHTS = 30


def test_airbnb_cards() -> None:
    stays = [run.airbnb_card(c, NIGHTS) for c in airbnb]
    stays = [s for s in stays if s]
    assert len(stays) == len(airbnb), "every card with a link is a row"
    for s in stays:
        assert s.url.startswith("https://www.airbnb.com/rooms/") and "source_impression_id" not in s.url
        assert s.total and 1000 < s.total < 20000, (s.title, s.total)
        assert s.per_night and 30 < s.per_night < 700
        assert s.area != "Valencia", "the city is not a neighborhood"
        assert s.rating is None or 0 < s.rating <= 5
    discounted = next(s for s in stays if "monthly, originally" in json.dumps(airbnb))
    assert discounted.total, "the discounted monthly total is the one kept"


def test_booking_cards() -> None:
    stays = [run.booking_card(c, NIGHTS) for c in booking]
    stays = [s for s in stays if s]
    assert len(stays) == len(booking)
    for s in stays:
        assert s.url.startswith("https://www.booking.com/hotel/") and "srpvid" not in s.url
        assert s.total and s.per_night, (s.title, s.total, s.per_night)
        # The card's price field is per night; the total is the stay's.
        assert s.total > s.per_night * 10, (s.title, s.total, s.per_night)
        assert abs(s.total - s.per_night * NIGHTS) / s.total < 0.08, (s.title, s.total, s.per_night)
        assert s.rating is None or 0 < s.rating <= 5, "Booking's score out of 10 is halved"
    assert any(s.area == "Ciutat Vella" for s in stays)


def test_assemble_and_verify() -> None:
    stays = run.assemble({"airbnb": airbnb, "booking": booking}, NIGHTS, 3500.0)
    assert len(stays) == len(airbnb) + len(booking)
    assert stays == sorted(stays, key=lambda s: -s.score), "best first"
    assert all(s.score <= t.score for s, t in zip(stays[1:], stays)), "score is what orders the sheet"
    over = [s for s in stays if s.total and s.total > 3500]
    under = [s for s in stays if s.total and s.total <= 3500]
    assert over and under and max(o.score for o in over) < max(u.score for u in under), "over budget costs"
    args = argparse.Namespace(city="Valencia, Spain", from_="2026-11-01", to="2026-12-01", guests=3,
                              budget=3500.0, currency="USD", currency_sign="$")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        for name, cards in (("airbnb", airbnb), ("booking", booking)):
            (out / f"raw-{name}.json").write_text(json.dumps({"cards": cards}))
        run.write_outputs(stays, args, out, NIGHTS, ["vrbo: Bot or Not? human check"])
        assert verify.verify(out) == []
        text = (out / "RECOMMENDATION.md").read_text()
        assert "## Shortlist" in text and "Not read: vrbo" in text and "fit the budget" in text
        rows = (out / "stays.csv").read_text().splitlines()
        assert len(rows) == 1 + len(stays) and rows[0].startswith("Site,Listing,Area")
        (out / "stays.csv").write_text(rows[0] + "\n" + rows[1].rsplit(",", 1)[0] + ",\n")
        assert any("no link" in p for p in verify.verify(out)), "a row without a link fails"


if __name__ == "__main__":
    failed = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  ok   {name}")
            except AssertionError as err:
                failed += 1
                print(f"  FAIL {name}: {err}")
    print("all passed" if not failed else f"{failed} failed")
    sys.exit(1 if failed else 0)
