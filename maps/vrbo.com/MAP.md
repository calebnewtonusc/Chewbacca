# vrbo.com

- Search: `/search?destination=<city>&startDate=&endDate=&adults=`. Cards would be `[data-stid="lodging-card-responsive"]`.
- 2026-09-20: a headless Chromium (Playwright's, and the real Chrome binary in headless mode) gets a "Bot or Not? Show us your human side" page and no cards, however long it waits. That is a human check, and the kit does not work around one.
- The route that is allowed: the person's own Chrome, read with `chrome-js --match vrbo.com --text` once "Allow JavaScript from Apple Events" is on (View, Developer, in Chrome). Not yet done.
