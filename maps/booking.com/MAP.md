# booking.com

Read on 2026-09-20 with a headless Chromium saying it is Mac Chrome 128. No sign-in needed.

- Search: `/searchresults.html?ss=<city>&checkin=&checkout=&group_adults=&no_rooms=1&group_children=0&selected_currency=USD&nflt=privacy_type%3D3` (entire homes and apartments). 20 to 25 cards a page; `offset=25` for the next.
- A card is `[data-testid="property-card"]`: `[data-testid="title"]`, `a[data-testid="title-link"]`, `[data-testid="review-score"]` ("Scored 9.1 ... 17 reviews", out of 10).
- `[data-testid="price-and-discounted-price"]` is the PER-NIGHT figure ("Per night$100"). The stay total is elsewhere in the card text: "Price $3,246" or "Original price $3,281. Current price $2,986." Taxes are a separate line, "+$293 taxes and fees".
- The neighborhood is the text before "Show on map": "Ciutat Vella, ValenciaShow on map".
- The link is long with `aid`, `label`, `srpvid`; keep `checkin`, `checkout`, `group_adults`, `no_rooms`, `group_children`.
