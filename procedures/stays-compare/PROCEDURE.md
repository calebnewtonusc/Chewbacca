# stays-compare

Places to stay in a city for given dates and guests, read from the booking sites and written as one table with a link per listing and a short recommendation.

Run it:

```
stays "Valencia, Spain" --from 2026-11-01 --to 2026-12-01 --guests 3 --budget 3500 --out ~/Desktop/valencia-stays
```

It writes `stays.csv` (one row per listing: site, name, area, type, bedrooms, rating out of 5, reviews, total for the stay, per night, notes, score, link), `RECOMMENDATION.md` (the shortlist and the areas, in words), `stays.json`, and `raw-<site>.json` (what each site's cards said, for the tests). The recommendation is read aloud or put in the hyper bar as is; the CSV is what goes into a sheet.

## Sites

| Site        | How it is read                                  | State on 2026-09-20                                          |
| ----------- | ----------------------------------------------- | ------------------------------------------------------------ |
| Airbnb      | headless Chromium, the public search page       | 24 cards, monthly totals with the discount, ratings, reviews |
| Booking.com | headless Chromium, the public search page       | 20 to 25 cards, per-night and stay totals, scores out of 10  |
| Vrbo        | not here: its search page answers a headless browser with a "Bot or Not?" human check | read it in the person's own Chrome (`chrome-js`, once "Allow JavaScript from Apple Events" is on), or by hand |

The kit does not work around a human check. That is a hard line, in docs/LEARNING-TO-ACT.md.

## What the numbers are

Prices are what the search page shows for the whole stay in the currency asked for. Airbnb's is the discounted monthly total; Booking's is the stay total before the taxes and fees it lists on the card (kept in Notes). The link is the truth; open it before deciding. Ratings are on one scale: Booking's score out of 10 is halved.

The score is rating times ten, plus reviews up to 200 counted a tenth each, plus a little for being under budget and a lot against for being over it. It orders the sheet; it is not a verdict.

## Origin

Distilled from the first run on 2026-09-20 for Gavin: Valencia, three people, about $3,500, a month from November 1. The city, dates, guests and budget were literals then; they became parameters here because the doc's rule (parameters only from evidence) was met by the request itself naming all four as the things that vary. See origin.jsonl.

## Not yet

- The Google Sheet. This session made it through the Google Drive connector, which the voice does not have. The keyless route is a `sheets.new` tab in the person's own Chrome filled through `chrome-js`; it needs "Allow JavaScript from Apple Events" on in Chrome, which was off on every profile on 2026-09-20.
- Vrbo, for the reason above.
- Distance to the beach or the center, per listing: a second run asking for it is what earns the column.
