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
