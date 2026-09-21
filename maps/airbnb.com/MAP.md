# airbnb.com

Read on 2026-09-20 with a headless Chromium saying it is Mac Chrome 128. No sign-in needed for search.

- Search: `/s/<City>--<Country>/homes?checkin=&checkout=&adults=&currency=USD&room_types[]=Entire home/apt`. Renders about 24 cards a page.
- A card is `[data-testid="card-container"]`. Inside: `[data-testid="listing-card-title"]` ("Rental unit in Extramurs": the part after "in" is the neighborhood, or the city when there is none), `[data-testid="listing-card-subtitle"]` (the listing's own name), a link `a[href*="/rooms/"]`.
- Prices in the card text: a strike-through original, then the discounted figure, then "$3,565 monthly, originally $4,909" for a month-long stay ("for N nights" for shorter). Keep the figure with "monthly" or "for N nights"; failing that, the last one.
- Rating in the text: "4.84 out of 5 average rating, 418 reviews". Badges: "Guest favorite", "Superhost", "Free cancellation".
- The link carries tracking (`source_impression_id`, `federated_search_id`); keep `adults`, `check_in`, `check_out` only.
- Logged out looks the same as logged in for search. A listing page has the real total with fees.
