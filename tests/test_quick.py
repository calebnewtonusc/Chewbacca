"""quick: exact answers for math, time, date and conversions with no model and
no Jev; weather only when Jev says it is a weather question; a task that
mentions the weather or the time is never answered. Network is stubbed: a
fixed forecast and a fixed place."""
import datetime
import json
import os
import sys
import tempfile
from pathlib import Path

os.environ["BOB_DIR"] = tempfile.mkdtemp()
os.environ["BOB_DECISIONS"] = os.path.join(os.environ["BOB_DIR"], "d.jsonl")
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bin" / "lib"))
import quick  # noqa: E402

failed = 0


def check(name, ok, got=None):
    global failed
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"  got {got!r}"))
    failed += not ok


FORECAST = {"current": {"temperature_2m": 71.6, "apparent_temperature": 50.2, "weather_code": 0, "is_day": 1},
            "daily": {"temperature_2m_max": [80.4, 66], "temperature_2m_min": [60, 55],
                      "precipitation_probability_max": [10, 70], "weather_code": [0, 61]}}


def fake_http(url):
    if "geocoding" in url:
        return {"results": [{"name": "Tokyo", "latitude": 35.7, "longitude": 139.7, "timezone": "Asia/Tokyo",
                             "population": 9000000}]}
    return FORECAST


def jev_says(kind, when="now", p=0.95):
    calls = []

    def ask(state, questions):
        calls.append(state)
        return {"kind": {"choice": kind, "probabilities": {kind: p}}, "when": {"choice": when}}
    ask.calls = calls
    return ask


def main() -> int:
    quick._http_json = fake_http
    Path(os.environ["BOB_DIR"], "home.json").write_text(json.dumps({"name": "Home", "lat": 1, "lon": 2}))
    now = datetime.datetime(2026, 9, 25, 16, 6)
    never = jev_says("weather")

    cases = [
        ("what's 17 times 23", "391."), ("What is 15% of 80?", "12."), ("square root of 144", "12."),
        ("what's 2 to the power of 10", "1,024."), ("1,200 plus 34", "1,234."),
        ("100 divided by 0", "That's undefined, it divides by zero."),
        ("convert 5 miles to km", "5 miles is 8.05 kilometers."),
        ("how many ounces in a pound", "1 pound is 16 ounces."),
        ("how many cups in a gallon", "1 gallon is 16 cups."),
        ("what time is it", "4:06 PM."), ("what's the date", "Friday, September 25."),
    ]
    for said, want in cases:
        got = (quick.answer(said, ask=never, now=now) or {}).get("text")
        check(f"{said!r} is computed", got == want, got)
    check("none of those asked Jev", not never.calls)

    for said in ["remind me to check the weather", "text Sam what time it is", "add 5 plus 5 to my notes",
                 "what's 5", "how are you", "who won the game", "what's up"]:
        got = quick.answer(said, ask=jev_says("weather"), now=now)
        check(f"{said!r} goes to the model", got is None, got)

    got = quick.answer("what's the weather", ask=jev_says("weather"))
    check("weather now, from the forecast", got and got["text"] == "It's 72 and sunny. High of 80.", got)
    got = quick.answer("is it gonna rain tomorrow", ask=jev_says("weather", "tomorrow"))
    check("rain tomorrow is a yes with the chance", got and got["text"] == "Yes, 70% chance of rain tomorrow.", got)
    got = quick.answer("do I need a jacket", ask=jev_says("weather"))
    check("a jacket question answers by how it feels", got and got["text"] == "Yes, it feels like 50.", got)
    got = quick.answer("what's the weather in Tokyo", ask=jev_says("weather"))
    check("another city is named", got and "in Tokyo" in got["text"], got)
    check("Jev saying other means the model", quick.answer("is the weather app broken", ask=jev_says("other")) is None)
    check("a weak Jev answer means the model",
          quick.answer("what's the weather", ask=jev_says("weather", p=0.5)) is None)
    check("a week ahead goes to the model", quick.answer("weather this weekend", ask=jev_says("weather", "later")) is None)
    check("Jev down: a plain weather question is still answered",
          (quick.answer("what's the weather", ask=lambda s, q: None) or {}).get("kind") == "weather")
    check("Jev down: a statement is not",
          quick.answer("the weather was nice", ask=lambda s, q: None) is None)

    listen = (Path(__file__).resolve().parent.parent / "bin" / "hud-listen").read_text()
    check("the voice takes the fast path only with nothing running",
          "def quick_answer" in listen and "if self.in_flight():\n            return False" in listen)
    print("all passed" if not failed else f"{failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
