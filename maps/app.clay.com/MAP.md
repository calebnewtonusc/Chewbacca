# app.clay.com

Read on 2026-09-23 in a signed-in Chrome through `chrome-js`, on a workspace
with a small paid plan. The first sections come from Clay's own Claude plugin
(clay 2.25.0), which documents the CLI and API. The last section is what the
web app actually showed.

## What Clay is made of

- **Audiences**: the workspace's own people, companies and deals. Reading them is
  free. Look here before searching or enriching, or you pay to rediscover data
  the workspace already has.
- **Searches**: net-new people and companies from Clay's database. People and
  companies only, not job posts. Result counts are capped per period.
- **Routines**: run a Clay-managed function (work email, phone, title, domain,
  tech stack, funding), a custom function, or a saved workflow over a batch.
  Custom functions can only be built in the app.
- **Workflows**: multi-node automations on a trigger or schedule, with run
  history. No row cap. Cannot take a search as a source yet: send the search to
  Audiences first.
- **Tables**: the spreadsheet view. About 50k rows before bulk enrich starts
  archiving rows. Only creatable in the app.
- **Campaigns**: outbound email sequences, variants and reply analytics.

Order the plugin tells agents to try: Audiences, Search, Routines, Workflows,
Tables.

## Money

- Two separate balances: data credits (`balance`) and, on newer plans, action
  executions (`actionExecutionBalance`). Having plenty of one doesn't cover the
  other.
- Data credits can be topped up. Action executions only come back by changing
  plan.
- Enabling auto top-up while already under the threshold buys credits right away.
- Anything that spends credits, buys credits or sends email is outbound. Confirm
  every time.

## URLs known from the plugin

- Table: `/workspaces/<workspaceId>/tables/<tableId>`
- Workflow: `/workspaces/<workspaceId>/terracotta/tc-workflows/<workflowId>`
- Home with the add-credits dialog: `/workspaces/<workspaceId>/home?addCredits=true`
- Plan selector: `/workspaces/<workspaceId>/billing/plan-selector`

## Observed in the UI

Read only: every page reached by URL, nothing clicked that saves, runs or spends.

### Getting around

- Every page is under `/workspaces/<workspaceId>/`. Going by URL beats clicking,
  since the sidebar's link targets are stable:
  `home`, `signals`, `claygents`, `terracotta` (Workflows), `api-and-cli`,
  `exports`, `trash`, `settings`.
- "Find leads", "Ads" and "Sequencer" in the sidebar are buttons, not links.
- Sidebar order: "Home", "Find leads", then an "Orchestration" group ("Signals",
  "Ads", "Sequencer", "Claygents", "Workflows" badged "Beta", "API and CLI").
  Pinned to the bottom: "Exports", "Trash", "Settings".
- An "Upgrade" pill beside a sidebar item means the page is a paywall. On a
  lower plan, "Signals" shows no pill but opens to "Upgrade to Launch to unlock
  this feature!", so the pill alone can't be trusted.

### Pages

- **Home**: four starter cards ("Find leads", "Import data", "Build a segment",
  "Start from template"), then "All Files": tabs "All files", "Recents",
  "Favorites", an "Owner" filter, "Filters", a "New" button. Folders open at
  `home/<folderId>` (ids start `f_`). Every row has "Edit" and a "..." menu.
  Those change other people's files: don't touch them.
- **Claygents**: "Build agent", a model picker ("Automatically assign model"),
  "Upload files", and templates: Prospecting, Account Scoring, Contact Scoring,
  Copywriting.
- **Workflows** (`terracotta`): "Published" and "All" tabs, a "New" button, an
  Owner filter.
- **API and CLI**: the prompt for setting up the agent plugin (the same one that
  points at github.com/clay-run/agent-plugins), a search-usage meter ("0 of 100
  results", rolling 30 days), a routine-runs log with batch downloads, and an
  "API keys" tab. Nothing that creates a key should be clicked without asking.
- **Settings**: workspace name at the top. Workspace side: "Team", "Connections"
  (`settings/accounts`), "Web intent" (`settings/website-tracking`), "Usage"
  (`settings/credit-usage`), "Referrals", "External webhooks"
  (`settings/webhooks`). Account side: "Account", "Appearance".
- **Usage** is where the plan's limits live: data-credit balance and monthly
  allowance, rollover, and a separate monthly "actions" allowance. Read it
  before promising any enrichment run. It has a "Manage plan" link: don't
  click it.
- **Connections** lists about 150 providers. Most say "Clay-managed" (Clay's own
  keys). Keys users added themselves show the provider, a masked key and who
  added it. Never open, copy or verify a key there.

### What costs what

- On a small plan, the numbers that run out first are search results (100 a
  period), data credits (about 100 a month) and actions (500 a month). One
  table enrichment over a few hundred rows can use up the month.
- Signals is gated behind the Launch plan. Ads and Sequencer are behind
  upgrades.

### Inside a table (from Clay's docs, not yet seen live)

- Shortcuts: `Cmd+K` or `Cmd+P` jump to a table by name, `Cmd+E` opens the
  enrichment panel, `Cmd+F` searches the table, `Cmd+G` goes to a row number,
  `Space` previews a row, `Esc` closes it, `Cmd+Z` undoes. They survived the
  June 2026 navigation redesign, so prefer them to clicks.
- New columns: "Add column" at the right edge, or a column's dropdown >
  "Insert right" / "Insert left". Double-clicking an enrichment or formula
  header opens its settings. The column dropdown also shows what depends on it
  downstream.
- Table-level auto-run is **on by default**. Every row added or edited then
  runs every enrichment that has column auto-run on. Turn it off before
  building anything.
- "Only run if" takes a formula. "Keep existing results" is checked by
  default and prevents paying twice for the same cell. Leave it checked.
- Sculptor ("Chat with Sculptor") builds AI columns and formulas itself, only
  recommends enrichments and waterfalls, and edits in Sandbox mode.

## Never, without a person saying yes that time

Anything that spends credits or actions (running a column, "Run all", turning
auto-run on, a search that brings results into a table), "Manage plan", buying
credits, sending email, creating or showing an API key, the "Verify" button on
a connection, and "Edit", "..." or delete on anything someone else owns.

## Mistakes already paid for

Each of these cost a turn once. Each is a check now.

- 2026-09-23: the account was called unlimited, and the Usage page showed 100
  data credits and 500 actions a month. **Check:** read Usage before trusting
  any statement about the plan.
- 2026-09-23: `chrome-js --check` still said DISABLED after the Apple Events
  setting was turned on, and reading the page worked anyway. **Check:** try
  one read before believing `--check`.
- 2026-09-23: Signals had no "Upgrade" pill and still opened to a paywall.
  **Check:** read the page, not the sidebar badge.
- 2026-09-23: reading Chrome's cookie store to find the signed-in profile was
  blocked by the permission layer, and should never have been tried.
  **Check:** find the profile from `Local State` names, or ask.
- 2026-09-23: a direct read of Clay's `api.clay.com/v3` from the page was
  blocked by the permission layer. It needs a person's decision, not a
  workaround.
