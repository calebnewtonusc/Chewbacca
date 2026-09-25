"""Answers that never wake the model: math, time, date, unit conversion, weather.

THE MEASUREMENT. 123 voice turns in ~/.bob/listen.log to 2026-09-25: first
words 1.2 s at the median for a turn with no tool call, 5.6 s with one, and
a whole turn 19 s. "What time is it" and "what's 17 times 23" paid that, plus
the thinking a model does before a one-word answer (854 thinking tokens for
"Morning." on 2026-09-21, see `pleasantry` in hud-listen). Here the answer is
computed, so it is ready as fast as the speaker can start.

Code answers; it never guesses. Jev only decides whether a sentence that
looks like a weather question is one ("remind me to check the weather" is
not), because Jev picks and scores and never writes text. Anything this
cannot answer exactly returns None and goes to the model as before.
"""
from __future__ import annotations

import ast
import datetime
import json
import math
import operator
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

BOB = Path(os.environ.get("BOB_DIR", str(Path.home() / ".bob")))
HOME = BOB / "home.json"          # {"name": ..., "lat": ..., "lon": ..., "timezone": ...}
GEO_CACHE = BOB / "geo.json"
# Open-Meteo answered in 0.63 s from this Mac on 2026-09-25, and a forecast
# does not move in ten minutes, so home is refetched in the background and
# a question about it is answered from memory.
WEATHER_TTL_S = 600
NET_TIMEOUT_S = 2.0
# guessed, never measured: Jev's answer has to arrive well inside the time
# the model would take to say its first word (1.2 s at the median).
JEV_TIMEOUT_S = 0.8
JEV_FLOOR = 0.7

# A sentence carrying one of these is a task that mentions a topic ("remind
# me to check the weather", "text Sam the time"), never a question about it.
TASK_WORDS = re.compile(
    r"\b(add|remind|reminder|text|send|email|mail|tell|put|schedule|write|note|save|"
    r"calendar|message|call|open|search|google|look up|play|draft|set)\b")
WEATHER_WORDS = re.compile(
    r"\b(weather|temperature|temp|degrees|rain|raining|rainy|snow|snowing|forecast|hot|cold|"
    r"warm|chilly|jacket|coat|umbrella|sunny|humid|humidity|windy|wind|storm|storms|outside|"
    r"sweater|hoodie|shorts)\b")
QUESTION_START = re.compile(
    r"^(what|whats|what's|how|is|are|will|do|does|should|can|could|gonna|going|hows|how's|any)\b")


def _norm(said: str) -> str:
    s = said.lower().strip()
    s = s.replace("’", "'").replace("×", " times ").replace("÷", " divided by ")
    s = re.sub(r"(?<=\d),(?=\d{3})", "", s)  # "1,200" is a number, not a pause
    s = re.sub(r"[?!,]", " ", s)
    s = re.sub(r"\.(?!\d)", " ", s)
    s = re.sub(r"^(hey |yo |ok |okay |so |um |uh )+", "", s)
    s = re.sub(r"\b(please|real quick|quickly|for me|right now)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


# ---------- math

_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
        ast.Div: operator.truediv, ast.Pow: operator.pow, ast.USub: operator.neg,
        ast.UAdd: operator.pos, ast.Mod: operator.mod}
MATH_PREFIX = re.compile(r"^(what's|whats|what is|how much is|calculate|compute|what does|solve|work out)\s+")
MATH_WORDS = [
    (r"\bsquare root of\s+", " sqrt "), (r"\bto the power of\b", "**"), (r"\bsquared\b", "**2"),
    (r"\bcubed\b", "**3"), (r"\bmultiplied by\b", "*"), (r"\btimes\b", "*"), (r"(?<=\d)\s*x\s*(?=\d)", "*"),
    (r"\bdivided by\b", "/"), (r"\bover\b", "/"), (r"\bplus\b", "+"), (r"\bminus\b", "-"),
    (r"\bpercent of\b", "/100*"), (r"%\s*of\b", "/100*"), (r"\bpercent\b", "/100"), (r"%", "/100"),
    (r"\bmod(ulo)?\b", "%"), (r"\bequals?\b", ""), (r"\bequal\b", ""), (r"\bis\b$", ""),
]


def _eval(node):
    if isinstance(node, ast.Expression):
        return _eval(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
        left, right = _eval(node.left), _eval(node.right)
        if isinstance(node.op, ast.Pow) and abs(right) > 100:
            raise ValueError("exponent too large")
        return _OPS[type(node.op)](left, right)
    if isinstance(node, ast.UnaryOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_eval(node.operand))
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "sqrt" and len(node.args) == 1:
        return math.sqrt(_eval(node.args[0]))
    raise ValueError("not arithmetic")


def spoken_number(x: float) -> str:
    if isinstance(x, float) and x.is_integer() and abs(x) < 1e15:
        x = int(x)
    if isinstance(x, int):
        return f"{x:,}"
    return f"{x:,.4f}".rstrip("0").rstrip(".")


def math_answer(words: str) -> str | None:
    s = MATH_PREFIX.sub("", words)
    for pattern, repl in MATH_WORDS:
        s = re.sub(pattern, repl, s)
    s = re.sub(r"(?<=\d),(?=\d{3})", "", s)
    s = re.sub(r"\bsqrt\s+([\d.]+)", r"sqrt(\1)", s).strip()
    if not re.fullmatch(r"[\d.\s+\-*/%()sqrt]+", s) or not re.search(r"\d", s):
        return None
    if not re.search(r"[+\-*/%]|sqrt", s):
        return None  # a bare number is not a sum
    try:
        value = _eval(ast.parse(s, mode="eval"))
    except ZeroDivisionError:
        return "That's undefined, it divides by zero."
    except (ValueError, SyntaxError, TypeError, OverflowError):
        return None
    return spoken_number(value) + "."


# ---------- unit conversion

UNITS = {  # name: (dimension, factor to the base unit)
    "mile": ("len", 1609.344), "kilometer": ("len", 1000), "meter": ("len", 1), "centimeter": ("len", 0.01),
    "millimeter": ("len", 0.001), "foot": ("len", 0.3048), "inch": ("len", 0.0254), "yard": ("len", 0.9144),
    "pound": ("mass", 0.45359237), "kilogram": ("mass", 1), "gram": ("mass", 0.001), "ounce": ("mass", 0.028349523125),
    "stone": ("mass", 6.35029318),
    "liter": ("vol", 1), "milliliter": ("vol", 0.001), "gallon": ("vol", 3.785411784), "quart": ("vol", 0.946352946),
    "pint": ("vol", 0.473176473), "cup": ("vol", 0.2365882365), "tablespoon": ("vol", 0.01478676478125),
    "teaspoon": ("vol", 0.00492892159375), "fluid ounce": ("vol", 0.0295735295625),
    "mph": ("speed", 0.44704), "kph": ("speed", 0.2777777778),
    "fahrenheit": ("temp", None), "celsius": ("temp", None), "kelvin": ("temp", None),
}
ALIASES = {
    "miles": "mile", "mi": "mile", "kilometers": "kilometer", "kilometres": "kilometer", "kilometre": "kilometer",
    "km": "kilometer", "kms": "kilometer", "meters": "meter", "metres": "meter", "metre": "meter", "m": "meter",
    "centimeters": "centimeter", "cm": "centimeter", "millimeters": "millimeter", "mm": "millimeter",
    "feet": "foot", "ft": "foot", "inches": "inch", "in": "inch", "yards": "yard", "yd": "yard",
    "pounds": "pound", "lbs": "pound", "lb": "pound", "kilograms": "kilogram", "kilos": "kilogram", "kilo": "kilogram",
    "kg": "kilogram", "grams": "gram", "g": "gram", "ounces": "ounce", "oz": "ounce",
    "liters": "liter", "litres": "liter", "litre": "liter", "l": "liter", "milliliters": "milliliter", "ml": "milliliter",
    "gallons": "gallon", "quarts": "quart", "pints": "pint", "cups": "cup", "tablespoons": "tablespoon",
    "tbsp": "tablespoon", "teaspoons": "teaspoon", "tsp": "teaspoon", "fluid ounces": "fluid ounce",
    "fl oz": "fluid ounce", "miles per hour": "mph", "kilometers per hour": "kph", "km/h": "kph", "kmh": "kph",
    "degrees fahrenheit": "fahrenheit", "f": "fahrenheit", "degrees celsius": "celsius", "c": "celsius",
    "centigrade": "celsius", "k": "kelvin", "degrees": None,
}
_UNIT_NAMES = sorted(set(UNITS) | {a for a, v in ALIASES.items() if v}, key=len, reverse=True)
_UNIT_RE = "|".join(re.escape(u) for u in _UNIT_NAMES)


def _unit(word: str) -> str | None:
    word = word.strip()
    return word if word in UNITS else ALIASES.get(word)


def _to_kelvin(v, unit):
    return {"kelvin": v, "celsius": v + 273.15, "fahrenheit": (v - 32) * 5 / 9 + 273.15}[unit]


def _from_kelvin(k, unit):
    return {"kelvin": k, "celsius": k - 273.15, "fahrenheit": (k - 273.15) * 9 / 5 + 32}[unit]


def plural(unit: str, value: float) -> str:
    if value == 1 or unit in ("mph", "kph", "fahrenheit", "celsius", "kelvin"):
        return {"fahrenheit": "degrees Fahrenheit", "celsius": "degrees Celsius"}.get(unit, unit)
    return {"foot": "feet", "inch": "inches"}.get(unit, unit + "s")


def convert_answer(words: str) -> str | None:
    m = (re.fullmatch(rf"(?:how many|how much)\s+({_UNIT_RE})\s+(?:is|are|in|make)\s+(?:a|an|one|([\d.,]+))\s+({_UNIT_RE})(?:\s+in\s+({_UNIT_RE}))?", words)
         or None)
    if m:
        target, amount, source = m.group(1), m.group(2) or "1", m.group(3)
        if m.group(4):  # "how many X is 5 Y in Z" is not a shape anyone says; refuse it
            return None
    else:
        m = re.fullmatch(rf"(?:convert |what's |whats |what is )?([\d.,]+)\s*({_UNIT_RE})\s+(?:in|to|into|in to)\s+({_UNIT_RE})", words)
        if not m:
            return None
        amount, source, target = m.group(1), m.group(2), m.group(3)
    src, dst = _unit(source), _unit(target)
    if not src or not dst or src == dst:
        return None
    try:
        value = float(amount.replace(",", ""))
    except ValueError:
        return None
    (dim_a, fa), (dim_b, fb) = UNITS[src], UNITS[dst]
    if dim_a != dim_b:
        return None
    out = _from_kelvin(_to_kelvin(value, src), dst) if dim_a == "temp" else value * fa / fb
    shown = round(out, 2) if abs(out) >= 1 else round(out, 4)
    return f"{spoken_number(value)} {plural(src, value)} is {spoken_number(shown)} {plural(dst, shown)}."


# ---------- time and date

TIME_Q = re.compile(r"(what time is it|what's the time|whats the time|what is the time|time is it|got the time|"
                    r"do you know what time it is|what time do you have|current time)")
DATE_Q = re.compile(r"^(what's|whats|what is) (the date|today's date|todays date|the date today|today)$|"
                    r"^what day is (it|today)( today)?$|^what's the day$|^what date is it( today)?$")
TIME_IN = re.compile(r"(?:what time is it|what's the time|whats the time|what is the time|time is it) in ([a-z][a-z .'-]+)$")


def clock(now: datetime.datetime) -> str:
    return now.strftime("%-I:%M %p").replace("AM", "AM").replace("PM", "PM")


def time_answer(words: str, now: datetime.datetime | None = None) -> str | None:
    m = TIME_IN.search(words)
    if m:
        place = geocode(m.group(1))
        if not place or not place.get("timezone"):
            return None
        there = datetime.datetime.now(ZoneInfo(place["timezone"]))
        day = ""
        here = (now or datetime.datetime.now()).astimezone()
        if there.date() != here.date():
            day = " tomorrow" if there.date() > here.date() else " yesterday"
        return f"It's {clock(there)}{day} in {place['name']}."
    if TIME_Q.search(words) and len(words.split()) <= 8:
        return f"{clock(now or datetime.datetime.now())}."
    if DATE_Q.search(words):
        return (now or datetime.datetime.now()).strftime("%A, %B %-d.")
    return None


# ---------- places and weather

def _http_json(url: str) -> dict | None:
    try:
        with urllib.request.urlopen(url, timeout=NET_TIMEOUT_S) as resp:
            return json.loads(resp.read())
    except (OSError, ValueError):
        return None


def _load(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def home() -> dict | None:
    h = _load(HOME)
    return h if {"lat", "lon"} <= set(h) else None


US_STATES = {"texas": "Texas", "tx": "Texas", "california": "California", "ca": "California", "new york": "New York",
             "ny": "New York", "florida": "Florida", "fl": "Florida", "illinois": "Illinois"}


def geocode(name: str) -> dict | None:
    """The best match for a place name, cached forever on disk."""
    name = re.sub(r"\s+", " ", name.strip(" .'-"))
    if not name or name in {"the morning", "the afternoon", "the evening", "a bit", "an hour"}:
        return None
    cache = _load(GEO_CACHE)
    if name in cache:
        return cache[name] or None
    query, state = name, None
    parts = name.rsplit(" ", 1)
    if len(parts) == 2 and parts[1] in US_STATES:
        query, state = parts[0], US_STATES[parts[1]]
    data = _http_json("https://geocoding-api.open-meteo.com/v1/search?count=10&name=" + urllib.parse.quote(query))
    if data is None:
        return None
    results = data.get("results") or []
    if state:
        results = [r for r in results if r.get("admin1") == state] or results
    place = None
    if results:
        r = max(results[:10], key=lambda r: r.get("population") or 0) if not state else results[0]
        place = {"name": r["name"], "lat": r["latitude"], "lon": r["longitude"], "timezone": r.get("timezone")}
    cache[name] = place
    try:
        BOB.mkdir(parents=True, exist_ok=True)
        GEO_CACHE.write_text(json.dumps(cache))
    except OSError:
        pass
    return place


_weather: dict[tuple, tuple[float, dict]] = {}
_weather_lock = threading.Lock()


def forecast(lat: float, lon: float, fresh: bool = False) -> dict | None:
    key = (round(lat, 2), round(lon, 2))
    with _weather_lock:
        hit = _weather.get(key)
    if hit and not fresh and time.time() - hit[0] < WEATHER_TTL_S:
        return hit[1]
    data = _http_json(
        "https://api.open-meteo.com/v1/forecast?"
        f"latitude={lat}&longitude={lon}&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"
        "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"
        "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=2")
    if data and "current" in data:
        with _weather_lock:
            _weather[key] = (time.time(), data)
        return data
    return hit[1] if hit else None


def warm() -> None:
    """Refetch home's forecast in the background when it has gone stale."""
    h = home()
    if not h:
        return
    key = (round(h["lat"], 2), round(h["lon"], 2))
    with _weather_lock:
        hit = _weather.get(key)
    if hit and time.time() - hit[0] < WEATHER_TTL_S * 0.8:
        return
    threading.Thread(target=forecast, args=(h["lat"], h["lon"], True), daemon=True).start()


def sky(code: int, day: bool = True) -> str:
    if code == 0:
        return "sunny" if day else "clear"
    if code == 1:
        return "mostly sunny" if day else "mostly clear"
    if code == 2:
        return "partly cloudy"
    if code == 3:
        return "cloudy"
    if code in (45, 48):
        return "foggy"
    if 51 <= code <= 57:
        return "drizzly"
    if 61 <= code <= 67 or 80 <= code <= 82:
        return "rainy"
    if 71 <= code <= 77 or code in (85, 86):
        return "snowy"
    if code >= 95:
        return "stormy"
    return "mixed"


CITY_IN = re.compile(r"\bin ([a-z][a-z .'-]+?)(?:\s+(?:today|tomorrow|tonight|now|this (?:morning|afternoon|evening)))?$")


def weather_answer(words: str, when: str) -> str | None:
    place, where = home(), ""
    m = CITY_IN.search(words)
    if m and not re.match(r"(the |a |an )", m.group(1)):
        place = geocode(m.group(1))
        if not place:
            return None
        where = f" in {place['name']}"
    if not place:
        return None
    data = forecast(place["lat"], place["lon"])
    if not data:
        return None
    cur, daily = data["current"], data["daily"]
    i = 1 if when == "tomorrow" else 0
    high, low = round(daily["temperature_2m_max"][i]), round(daily["temperature_2m_min"][i])
    rain = daily["precipitation_probability_max"][i] or 0
    day_sky = sky(daily["weather_code"][i])
    rain_part = f", {rain}% chance of rain" if rain >= 20 else ""
    if re.search(r"\b(jacket|coat|sweater|hoodie)\b", words):
        feels = round(cur["apparent_temperature"]) if i == 0 else low
        return (f"Yes, it feels like {feels}{where}." if feels < 58
                else f"No, it's {round(cur['temperature_2m']) if i == 0 else high}{where}.")
    if re.search(r"\b(umbrella|rain|raining|rainy)\b", words):
        verdict = "Yes" if rain >= 40 else ("Maybe" if rain >= 20 else "No")
        return f"{verdict}, {rain}% chance of rain {'tomorrow' if i else 'today'}{where}."
    if when == "tomorrow":
        return f"Tomorrow{where}: {day_sky}, high of {high}, low of {low}{rain_part}."
    now_sky = sky(cur["weather_code"], bool(cur.get("is_day", 1)))
    return f"It's {round(cur['temperature_2m'])} and {now_sky}{where}. High of {high}{rain_part}."


def _prefetch(words: str) -> None:
    m = CITY_IN.search(words)
    place = geocode(m.group(1)) if m and not re.match(r"(the |a |an )", m.group(1)) else home()
    if place:
        forecast(place["lat"], place["lon"])


JEV_QUESTIONS = {
    "kind": {"type": "choice", "instructions": {
        "question": "The person said `said` out loud to their assistant. What do they want?",
        "note": "Only a question asking for the weather counts as weather. A task that mentions the weather "
                "(remind me, text someone, add to the calendar) is other."},
        "criteria": {
            "weather": "a question about the weather, temperature, rain, or what to wear outside",
            "other": "anything else, including a task or a message that only mentions the weather"}},
    "when": {"type": "choice", "instructions": "Which time does the weather question in `said` ask about?",
             "criteria": {"now": "right now or today", "tomorrow": "tomorrow",
                          "later": "a day after tomorrow, a weekend, or a week"}},
}


def weather_intent(said: str, words: str, ask=None) -> str | None:
    """"now", "tomorrow" or None. Jev decides; without it, only a sentence
    that is plainly a question with no task word is taken."""
    ask = ask or (lambda s, q: jev.ask(s, q, timeout=JEV_TIMEOUT_S, decision="quick"))
    answers = ask({"said": said}, JEV_QUESTIONS)
    if answers:
        kind, when = answers.get("kind") or {}, answers.get("when") or {}
        p = (kind.get("probabilities") or {}).get("weather", 0.0)
        if kind.get("choice") != "weather" or p < JEV_FLOOR:
            return None
        return when.get("choice") if when.get("choice") in ("now", "tomorrow") else None
    if not QUESTION_START.search(words):
        return None
    if re.search(r"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekend|week)\b", words):
        return None
    return "tomorrow" if "tomorrow" in words else "now"


def answer(said: str, ask=None, now: datetime.datetime | None = None) -> dict | None:
    """{"kind", "text"} when the answer is exact and ready, else None."""
    words = _norm(said)
    if not words or len(words) > 120 or TASK_WORDS.search(words):
        return None
    for kind, fn in (("math", math_answer), ("convert", convert_answer)):
        text = fn(words)
        if text:
            return {"kind": kind, "text": text}
    text = time_answer(words, now)
    if text:
        return {"kind": "time", "text": text}
    if WEATHER_WORDS.search(words):
        # The place lookup and the forecast run while Jev decides, so the
        # answer costs the slower of the two, not their sum (1.4 s measured
        # 2026-09-25 for "the weather in Chicago" done one after the other).
        threading.Thread(target=_prefetch, args=(words,), daemon=True).start()
        when = weather_intent(said, words, ask)
        if when:
            text = weather_answer(words, when)
            if text:
                return {"kind": "weather", "text": text}
    return None
