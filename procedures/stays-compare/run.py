#!/usr/bin/env python3
"""stays-compare: places to stay in a city, from the booking sites, as one table.

    run.py "Valencia, Spain" --from 2026-11-01 --to 2026-12-01 --guests 3 \
        --budget 3500 --out ~/Desktop/stays-example

Reads the public search results of Airbnb and Booking.com in a headless
browser (Playwright), keeps entire places only, and writes:

    <out>/stays.csv             one row per listing, with the link
    <out>/RECOMMENDATION.md     the shortlist and where to stay, in words
    <out>/raw-<site>.json       what each site's cards said, for the tests

Vrbo is not read here. Its search page answers a headless browser with a
"Bot or Not?" human check (2026-09-20), and this kit does not work around
one. Vrbo is read in the person's own Chrome by sheet.py once "Allow
JavaScript from Apple Events" is on, or the person searches it by hand.

Prices are what the search page shows for the whole stay, in the currency
asked for; taxes and fees differ by site, so the link is the truth.
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from datetime import date
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit, parse_qsl, urlencode

# A browser that says it is a Mac Chrome. hud-music reads Spotify's search
# page with the same idea; Airbnb and Booking both answered on 2026-09-20.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
# Both sites paint their cards within 25 s on a home connection; the probe
# saw 24 and 25 cards inside 10 s. Past 45 s the page is not coming.
PAGE_TIMEOUT_MS = 45_000
CARDS_TIMEOUT_MS = 25_000


@dataclass
class Stay:
    site: str
    title: str
    area: str
    kind: str
    bedrooms: str
    rating: float | None
    reviews: int | None
    total: float | None
    per_night: float | None
    currency: str
    url: str
    notes: str = ""
    score: float = field(default=0.0)


# ---------------------------------------------------------------- parsing

MONEY = re.compile(r"([$€£])\s?([\d,]+(?:\.\d+)?)")


def money(text: str) -> tuple[str, float] | None:
    m = MONEY.search(text)
    if not m:
        return None
    return m.group(1), float(m.group(2).replace(",", ""))


def airbnb_card(card: dict, nights: int) -> Stay | None:
    """One Airbnb search card, from its text and link.

    The card text reads like: "Rental unit in Extramurs | Bright and
    spacious | 3 apartments available | $4,909 | $3,565 | $3,565 monthly,
    originally $4,909 | monthly | Monthly discount | Free cancellation |
    4.84 out of 5 average rating, 418 reviews | 4.84 (418)". The price to
    keep is the last one before "monthly" (or "for N nights"), which is the
    discounted total; the first is the strike-through original.
    """
    text = card.get("text", "")
    url = card.get("url", "")
    if not url:
        return None
    parts = [p.strip() for p in text.split("|") if p.strip()]
    title = card.get("title", "").strip()
    area = ""
    m = re.match(r"^(.*?) in (.+)$", title)
    kind = title
    if m:
        kind, area = m.group(1), m.group(2)
    if area.lower() == city_name(card).lower():
        area = ""  # "Rental unit in Valencia" names the city, not a neighborhood
    sub = card.get("sub", "").strip()
    m = re.search(r"\b(\d+) bedrooms?\b", text)
    bedrooms = f"{m.group(1)} bedroom{'s' if m.group(1) != '1' else ''}" if m else ""
    prices = [money(p) for p in parts]
    prices = [p for p in prices if p]
    total = None
    currency = "$"
    # "$3,565 monthly, originally $4,909": the total is the first number in
    # that phrase; with no discount phrase the last money seen is the total.
    for p in parts:
        if "monthly" in p and money(p):
            currency, total = money(p)  # type: ignore[misc]
            break
        if re.search(r"for \d+ nights?", p) and money(p):
            currency, total = money(p)  # type: ignore[misc]
            break
    if total is None and prices:
        currency, total = prices[-1]
    rating = reviews = None
    m = re.search(r"([\d.]+) out of 5 average rating, (\d+) review", text)
    if m:
        rating, reviews = float(m.group(1)), int(m.group(2))
    notes = ", ".join(p for p in ("Guest favorite", "Superhost", "Free cancellation") if p in text)
    offered = dict(parse_qsl(urlsplit(url).query))
    asked = (card.get("from", ""), card.get("to", ""))
    if asked[0] and (offered.get("check_in"), offered.get("check_out")) not in ((None, None), asked):
        notes = "; ".join(x for x in (notes, f"dates offered: {offered.get('check_in')} to {offered.get('check_out')}") if x)
    return Stay(
        site="Airbnb", title=sub or title, area=area, kind=kind, bedrooms=bedrooms,
        rating=rating, reviews=reviews, total=total,
        per_night=round(total / nights, 2) if total else None, currency=currency,
        url=clean_url(url, keep={"adults", "check_in", "check_out"}), notes=notes,
    )


def booking_card(card: dict, nights: int) -> Stay | None:
    """One Booking.com property card.

    Text reads like: "Trenor Apartments | Opens in new window | Ciutat
    Vella, ValenciaShow on map | 0.6 miles from downtown | Scored 9.1 | 9.1
    | Wonderful | 17 reviews | One-Bedroom Apartment with View | Entire
    apartment • 1 bedroom • 1 living room • 1 bathroom | 30 nights, 3 adults
    | $2,930 | +$293 taxes and fees". The price field the card exposes is
    the discounted total for the stay; taxes are a separate line.
    """
    url = card.get("url", "")
    if not url:
        return None
    text = card.get("text", "")
    parts = [p.strip() for p in text.split("|") if p.strip()]
    title = card.get("title", "").strip()
    area = ""
    m = re.search(r"\|\s*([^|]+?),\s*[^|,]+Show on map", text)
    if m:
        area = m.group(1).strip()
    kind = next((p.split("•")[0].strip() for p in parts if "•" in p), "")
    bedrooms = ""
    m = re.search(r"(\d+ bedrooms?)", text)
    if m:
        bedrooms = m.group(1)
    # The card's price field is the per-night figure ("Per night$100"); the
    # total for the stay is in "Price $3,246" or "Current price $2,986."
    # (2026-09-20, 30 nights: the first read took $100 as the total).
    nightly = money(card.get("price", "") or "")
    total_phrase = next((p for p in parts if re.search(r"(?:Current price|^Price) [$€£]", p)), "")
    priced = money(total_phrase.split("Current price")[-1]) if total_phrase else None
    if priced is None and nightly:
        priced = (nightly[0], round(nightly[1] * nights, 2))
    currency, total = priced if priced else ("$", None)
    per_night = nightly[1] if nightly else (round(total / nights, 2) if total else None)
    taxes = next((p for p in parts if "taxes" in p.lower() and money(p)), "")
    rating = reviews = None
    m = re.search(r"Scored ([\d.]+)", text)
    if m:
        rating = round(float(m.group(1)) / 2, 2)  # Booking scores out of 10
    m = re.search(r"([\d,]+) reviews?", text)
    if m:
        reviews = int(m.group(1).replace(",", ""))
    notes = "; ".join(x for x in (taxes, "Free cancellation" if "Free cancellation" in text else "") if x)
    return Stay(
        site="Booking.com", title=title, area=area, kind=kind, bedrooms=bedrooms,
        rating=rating, reviews=reviews, total=total, per_night=per_night, currency=currency,
        url=clean_url(url, keep={"checkin", "checkout", "group_adults", "no_rooms", "group_children"}),
        notes=notes,
    )


def city_name(card: dict) -> str:
    """The city the search was for, carried on each card by read_site."""
    return str(card.get("city", "")).split(",")[0].strip()


def clean_url(url: str, keep: set[str]) -> str:
    """The listing link without the tracking that the search page hangs on it."""
    parts = urlsplit(url)
    query = [(k, v) for k, v in parse_qsl(parts.query) if k in keep]
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))


# ---------------------------------------------------------------- reading

SITES = {
    "airbnb": {
        "url": lambda city, ci, co, guests, cur: (
            f"https://www.airbnb.com/s/{quote(city.replace(', ', '--').replace(' ', '-'))}/homes"
            f"?checkin={ci}&checkout={co}&adults={guests}&currency={cur}&room_types%5B%5D=Entire%20home%2Fapt"
        ),
        "cards": '[data-testid="card-container"]',
        "read": """els => els.map(e => ({
            title: (e.querySelector('[data-testid="listing-card-title"]')||{}).textContent||'',
            sub: (e.querySelector('[data-testid="listing-card-subtitle"]')||{}).textContent||'',
            url: (e.querySelector('a[href*="/rooms/"]')||{}).href||'',
            text: e.innerText.replace(/\\n/g,' | ')}))""",
        "parse": airbnb_card,
    },
    "booking": {
        "url": lambda city, ci, co, guests, cur: (
            f"https://www.booking.com/searchresults.html?ss={quote(city)}&checkin={ci}&checkout={co}"
            f"&group_adults={guests}&no_rooms=1&group_children=0&selected_currency={cur}&nflt=privacy_type%3D3"
        ),
        "cards": '[data-testid="property-card"]',
        "read": """els => els.map(e => ({
            title: (e.querySelector('[data-testid="title"]')||{}).textContent||'',
            price: (e.querySelector('[data-testid="price-and-discounted-price"]')||{}).textContent||'',
            url: (e.querySelector('a[data-testid="title-link"]')||{}).href||'',
            text: e.innerText.replace(/\\n/g,' | ')}))""",
        "parse": booking_card,
    },
}


async def read_site(name: str, city: str, ci: str, co: str, guests: int, currency: str, out: Path) -> tuple[list[dict], str]:
    from playwright.async_api import async_playwright

    site = SITES[name]
    url = site["url"](city, ci, co, guests, currency)
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(user_agent=USER_AGENT, viewport={"width": 1366, "height": 900}, locale="en-US")
        page = await context.new_page()
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=PAGE_TIMEOUT_MS)
            try:
                await page.wait_for_selector(site["cards"], timeout=CARDS_TIMEOUT_MS)
            except Exception:
                title = await page.title()
                return [], f"{name}: no listings appeared ({title!r} at {page.url})"
            await page.wait_for_timeout(2500)
            cards = await page.eval_on_selector_all(site["cards"], site["read"])
        finally:
            await browser.close()
    for card in cards:
        card.update(city=city, **{"from": ci, "to": co})
    (out / f"raw-{name}.json").write_text(json.dumps({"url": url, "cards": cards}, indent=1))
    return cards, ""


# ---------------------------------------------------------------- judging

def score(stay: Stay, budget: float | None) -> float:
    """Higher is better. Rating carries most of it, reviews make a rating
    believable, and price counts against once it is over the budget."""
    s = 0.0
    if stay.rating:
        s += stay.rating * 10
    if stay.reviews:
        s += min(stay.reviews, 200) / 20
    if stay.total and budget:
        if stay.total > budget:
            s -= 25 + (stay.total - budget) / budget * 50
        else:
            s += (budget - stay.total) / budget * 10
    return round(s, 1)


def recommendation(stays: list[Stay], city: str, ci: str, co: str, guests: int, budget: float | None, currency: str, skipped: list[str]) -> str:
    nights = (date.fromisoformat(co) - date.fromisoformat(ci)).days
    priced = [s for s in stays if s.total]
    within = [s for s in priced if not budget or s.total <= budget]
    top = sorted(within or priced, key=lambda s: -s.score)[:5]
    areas: dict[str, list[Stay]] = {}
    for s in priced:
        if s.area:
            areas.setdefault(s.area, []).append(s)
    lines = [
        f"# Where to stay in {city}",
        "",
        f"{guests} guests, {ci} to {co} ({nights} nights)"
        + (f", budget {currency}{budget:,.0f} for the stay" if budget else "")
        + f". {len(stays)} listings read: "
        + ", ".join(f"{n} on {site}" for site, n in sorted({s.site: sum(1 for t in stays if t.site == s.site) for s in stays}.items()))
        + ".",
    ]
    if skipped:
        lines += ["", *[f"Not read: {s}" for s in skipped]]
    if budget:
        lines += ["", f"{len(within)} of {len(priced)} priced listings fit the budget."]
    lines += ["", "## Shortlist", ""]
    for s in top:
        rating = f"{s.rating:.2f}/5 from {s.reviews} reviews" if s.rating and s.reviews else "no rating yet"
        lines.append(
            f"- {s.title} ({s.site}, {s.area or 'area not shown'}{', ' + s.bedrooms if s.bedrooms else ''}): "
            f"{s.currency}{s.total:,.0f} for the stay, {s.currency}{s.per_night:,.0f} a night, {rating}. {s.url}"
        )
    if areas:
        lines += ["", "## By neighborhood, from what the search returned", ""]
        for area, group in sorted(areas.items(), key=lambda kv: -len(kv[1])):
            totals = [s.total for s in group if s.total]
            lines.append(
                f"- {area}: {len(group)} listing{'s' if len(group) != 1 else ''}, "
                f"{group[0].currency}{min(totals):,.0f} to {group[0].currency}{max(totals):,.0f} for the stay."
            )
    lines += [
        "",
        "Prices are what each search page showed for the whole stay; Airbnb's is the discounted monthly total, "
        "Booking's is before the taxes and fees it lists separately. Open the link for the real total before deciding.",
    ]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- main

async def run(args: argparse.Namespace) -> int:
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    nights = (date.fromisoformat(args.to) - date.fromisoformat(args.from_)).days
    if nights <= 0:
        print("check-out must be after check-in", file=sys.stderr)
        return 2
    results = await asyncio.gather(*(read_site(n, args.city, args.from_, args.to, args.guests, args.currency, out) for n in args.sites))
    cards_by_site = {name: cards for name, (cards, _) in zip(args.sites, results)}
    skipped = [problem for _, problem in results if problem]
    stays = assemble(cards_by_site, nights, args.budget)
    write_outputs(stays, args, out, nights, skipped)
    return 0 if stays else 1


def assemble(cards_by_site: dict[str, list[dict]], nights: int, budget: float | None) -> list[Stay]:
    """Cards from each site to scored rows, best first."""
    stays: list[Stay] = []
    for name, cards in cards_by_site.items():
        for card in cards:
            stay = SITES[name]["parse"](card, nights)
            if stay:
                stay.score = score(stay, budget)
                stays.append(stay)
    stays.sort(key=lambda s: -s.score)
    return stays


def write_outputs(stays: list[Stay], args: argparse.Namespace, out: Path, nights: int, skipped: list[str]) -> None:
    with (out / "stays.csv").open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["Site", "Listing", "Area", "Type", "Bedrooms", "Rating (of 5)", "Reviews",
                         f"Total for {nights} nights", "Per night", "Currency", "Notes", "Score", "Link"])
        for s in stays:
            writer.writerow([s.site, s.title, s.area, s.kind, s.bedrooms,
                             s.rating if s.rating is not None else "", s.reviews if s.reviews is not None else "",
                             s.total if s.total is not None else "", s.per_night if s.per_night is not None else "",
                             s.currency, s.notes, s.score, s.url])
    text = recommendation(stays, args.city, args.from_, args.to, args.guests, args.budget, args.currency_sign, skipped)
    (out / "RECOMMENDATION.md").write_text(text)
    (out / "stays.json").write_text(json.dumps([asdict(s) for s in stays], indent=1))
    print(text)
    print(f"{len(stays)} rows in {out / 'stays.csv'}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("city", help='e.g. "Valencia, Spain"')
    ap.add_argument("--from", dest="from_", required=True, help="check-in, YYYY-MM-DD")
    ap.add_argument("--to", required=True, help="check-out, YYYY-MM-DD")
    ap.add_argument("--guests", type=int, default=2)
    ap.add_argument("--budget", type=float, default=None, help="for the whole stay")
    ap.add_argument("--currency", default="USD")
    ap.add_argument("--sites", nargs="+", default=list(SITES), choices=list(SITES))
    ap.add_argument("--out", default="~/Desktop/stays")
    args = ap.parse_args(argv)
    args.currency_sign = {"USD": "$", "EUR": "€", "GBP": "£"}.get(args.currency, args.currency + " ")
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
