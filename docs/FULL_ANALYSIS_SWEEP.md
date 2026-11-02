# Full Analysis Sweep

Branch `fix/full-analysis-sweep` (from `release/production-candidate`, which is left exactly as verified). 2026-11-02.

## How it was done

Static analysis with a stricter rule set (not committed), pattern scans for crash classes across all of `lib/`, a route-table cross-check, a security-hygiene scan, a dependency review, and a manual read of the bill-saving transaction. **No screen was run on a device and no production data was read in this sweep.**

## Bugs found and fixed

| # | Problem | Why it matters | Fix | Regression test |
|---|---|---|---|---|
| 1 | **Wrong phone date files money under the wrong day.** Bills carry server time, but the day's totals (`dailyStats`), repayment stats and the cash-closing record use the phone's date. A phone with a reset or manual clock would make the dashboard, reports and cash closing disagree. | Financial integrity | `lib/clock_guard.dart`: compares the phone's clock with a server-supplied time (HTTP `Date` header of the Firebase endpoint, cached 10 min, checked in the background so billing is not slowed). Blocks a bill, repayment or closing **only** when it would land on the wrong IST business day (and the difference is more than 2 minutes); explains in plain words and says nothing was saved. Unknown (offline) never blocks. | `clock_guard_test.dart` (16) |
| 2 | **Back button / back swipe discards a bill in progress** without asking; also allowed leaving mid-save. | Lost sales entries on an accidental tap | `PopScope` on the billing screen + `confirmDiscardBill` dialog ("3 items, ₹125.50 will be discarded"); leaving is blocked while a save runs. | `crash_hardening_test.dart` |
| 3 | **An expense with a missing amount crashes the admin expense list and the expense detail page** (`amount as num`). | A single odd record takes down a screen | safe reads (`?? 0`) in the list, the detail page and the (unlinked) cashflow page | source guard |
| 4 | **An expense with no server timestamp yet crashes its detail page** (`timestamp as Timestamp`); a just-created expense briefly has none. | Crash right after logging an expense | shows "Time not available yet" | source guard |
| 5 | **A malformed `date` on a `dailyStats` document crashes the dashboard weekly chart / analytics chart** (`DateTime.parse`). | One bad document blanks the admin chart | `tryParse`, bad entries skipped | source guard |
| 6 | **Bill counter read as a hard `as int`.** If a counter were ever stored as a decimal, billing in that canteen would stop. | Billing outage | read as a number and converted | source guard |

All source guards were confirmed to **fail on the pre-sweep code** and pass on the fixed code.

## UI enhancement

- **Budget usage bar** on the monthly budget card: "62% of the budget used"; orange below 15% left; red with "Over budget by ₹…" when exceeded; screen-reader label; hidden when no budget is set. Same exact-paise maths as the alerts. 5 tests, and every card layout test (320/360/800 px, 150–200% text) now includes it.

## Checked and found fine

- **Unsafe `BuildContext` use after `await`:** none. **Leaked subscriptions:** none.
- **Not-awaited futures (12):** all benign (dialogs, navigation, deliberate background waits).
- **Named routes:** every route used by a screen is registered (now a permanent guard test).
- **Secrets:** none in tracked source; no keystore or `key.properties` tracked; nothing sensitive in debug logs.
- **Queries vs indexes:** unchanged; registry agrees.
- **Rules, indexes, configs, `pubspec.yaml`, Android config:** byte-identical to the release branch.

## Observations that were NOT changed (need your decision)

| Observation | Note |
|---|---|
| **Firebase packages are several major versions behind** (`cloud_firestore` 4.17.5 vs 7.1.0, `firebase_auth` 4.20 vs 7.0.1, `firebase_core` 2.32 vs 5.1, `share_plus` 10 vs 13) | Upgrading changes the production database client. Do it as its own change with a full device pass, not in this sweep. |
| Credit limit of **₹2,000 per customer is hard-coded** in the billing screen | A business rule; confirm it is intended, or make it a setting. |
| About 50 `discarded_futures` hints | Style-level (button handlers); no defect found. |
| Repo `firestore.rules` is an old, never-deployed design | Never run a bare `firebase deploy`; always pass `--config`. |
| Kotlin 2.1.0 / `share_plus` build warnings | Unchanged (see `KNOWN_LIMITATIONS.md`). |

## Limits of this sweep

- The clock guard can only judge the phone's date when it can reach the server's time. With no connection it cannot tell and does **not** block (billing while offline is already unsupported by decision).
- Wrongly set time on a phone that stays on the same IST day is allowed (only the day matters for filing).
- Everything above is verified by tests and static analysis, not on a phone. See `REAL_DEVICE_QA.md` for the new device checks.

---

# Round 2: admin canteen choosers, cash reconciliation review, analytics check

Requested after device testing. Branch `fix/full-analysis-sweep`.

## What changed

| Area | Before | Now |
|---|---|---|
| **Manage Menu (admin)** | showed and edited the admin's own canteen's menu, with no way to choose | a canteen chooser; the menu list and the Add/Edit form follow the chosen canteen; **"All canteens" shows "Choose a canteen"** on both tabs and nothing can be edited; switching canteen clears a half-edited item. Cashiers unchanged (own canteen, no delete). |
| **Master Credit Ledger** | every canteen's credit bills mixed together, canteen not shown | chooser with **All canteens** (default) or one canteen (server-side filter, no new index); canteen name on each bill when All is selected; "N bills · ₹X still due" (exact paise) |
| **Analytics & Graphs** | **silently showed only the admin's own canteen (normally Main)**, no chooser | chooser with **All canteens** (default) or one canteen; the loader is told which canteen; a slow answer for an old choice never overwrites a newer one |
| **Monthly Budget (admin)** | had a selector, but no explanation when All was selected | explanatory note under the selector when All is selected |
| **SMS Broadcast** | opened the unfinished flow (admin) | "Coming soon" popup for **both** cashier and admin |

## Cash reconciliation review (cashier and admin)

Logic read line by line. Expected cash = `dailyStats.totalCash` for the canteen and day (cash sales + cash repayments, per the earlier decision); discrepancy = counted - expected in whole paise; a second closing for the same canteen and day is refused; the closing is signed with the caller's uid. Three defects found and fixed:

1. **Midnight rollover (cashier).** Expected cash was loaded for the day the page opened, but the save used the day at the moment of saving. A page left open past IST midnight could file today's closing against yesterday's cash. Now the screen reloads at the day change (30 s watcher) and refuses to save against stale figures, asking the cashier to check and submit again.
2. **Admin logs had no canteen.** Closings from all canteens were mixed with no canteen name. Now: canteen chooser with All, and the canteen name on every record.
3. **Admin log crash and rounding.** A record without a `date` field parsed its document id (`north_2026-11-02`) as a date and threw, blanking the whole list; amounts were rounded to whole rupees ("Shortage: ₹0" for 40 paise). Now a safe date parser (also rejects impossible dates like 2026-02-31) and exact amounts.

## Analytics and graphs: are they working?

Yes for the code paths now covered. The real page, all five tabs (Weekly, Monthly, Payments, Profit, Ops) and their charts, is rendered in tests with realistic data produced by the app's own calculation code: normal data, a canteen with no data, an item with unknown cost, a failed load with Retry, switching canteens, a late stale answer, small phone, and 160% text. That found **one real overflow** (Profit tab rows at large text and with long item names), now fixed. Not done: a run against live production data on a device.

## Tests

| Check | Result |
|---|---|
| `flutter analyze` | clean |
| `flutter test` | **434 passed** |
| Emulator, whole folder | **208 / 208** (candidate suite 113) |
| Index registry | 20 queries, still 5 composite indexes (the ledger's one-canteen query needs none) |
| Deploy verifiers / tool tests | all pass / 26 |
| Rules, indexes, configs, `pubspec.yaml`, Android config | identical to the release branch |
| New source guards (7) | confirmed to fail on the pre-change code |
