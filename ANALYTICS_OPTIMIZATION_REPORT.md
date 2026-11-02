# Analytics Optimization Report (B-08)

Files: `lib/admin_analytics_page.dart` (1,134 -> 922 lines), new `lib/analytics_calc.dart`, `lib/analytics_loader.dart`.

## Audit of the original implementation
Four nested `StreamBuilder`s held live listeners on **entire** collections:

| Stream | What it fed | Cost problem |
|---|---|---|
| `bills` (all) | item profit, staff ranking, time-slot mix, 30-day forecast | every bill ever created, each with its `items` array; every new bill by any branch re-triggers the whole page |
| `dailyStats` (all) | weekly chart, monthly chart, anomalies | small, but unbounded |
| `expenses` (all) | **only which month keys exist** for the Monthly tab (`monthlyExpensesMap` was computed but never displayed) | every expense including its base64 proof photo |
| (branch filter) | applied on the device after downloading all branches | other branches' data downloaded then discarded |

What each tab shows: Weekly = last 7 days from `dailyStats`; Monthly = last 6 months with sales or expenses; Payments = hour-of-day mix from bills; Profit = per-item revenue/cost/profit from bills; Ops = staff ranking (bills), anomalies (`dailyStats`, 7-day rolling), 30-day stock forecast (bills).

## What changed
- **Bounded, paged reads** with a visible period selector: 30 days, 90 days, **6 months (default)**, 12 months, All time. Windows are IST business calendar ranges (`AnalyticsRange`).
- **Bills are aggregated as pages arrive** (`BillAggregates`) and never retained: memory is the aggregates plus a set of ids (for duplicate protection).
- **`dailyStats` stays the source for daily/weekly/monthly figures and anomalies** (not re-derived from bills). Windowed by its `date` field (`date >= start`, ordered by `date`): single-field index, no composite needed.
- **Expenses** are read only for the window and reduced to month keys; the photo is dropped immediately. Months that have expenses but no sales still appear (unchanged behaviour).
- **Branch isolation unchanged**: every document still passes `CanteenProvider.matchesSelectedCanteen`; for a concrete (non-main) branch the bills/expenses queries are additionally scoped by `canteenId` on the server. Branch `main` is read unscoped because it also owns legacy documents without a `canteenId` (a query cannot match a missing field). Admin permission is unchanged: the page is admin-only, and the emulator confirms a cashier cannot run these queries.
- **Chart/maths unchanged**: the former `_build*` methods moved into `analytics_calc.dart` with identical logic. The IST hour bucketing from the earlier phase is kept.
- Page keeps its tabs and charts; added a period chip row, a refresh button and a one-line status ("N bills - M daily records - updated hh:mm", "INCOMPLETE" if a safety row limit was hit).

## Behaviour changes you should know about
1. **Default period is 6 months**, not all time. The Weekly, Monthly and Ops-anomaly figures are unaffected for normal data; the Payments, Profit and staff-ranking tabs now cover 6 months until "All time" is chosen (which reproduces the old numbers).
2. **Not live any more.** The old page updated in real time; the new one loads once and on Refresh. For an analytics view this trades freshness for far fewer reads.
3. Reads use `Source.server`: offline shows an error with Retry instead of silently showing cached numbers.
4. Windowed `dailyStats` reads need the `date` field. Documents created before that field existed would be excluded from windows (they are included by "All time", which pages by document id). If such documents exist they are old, and the emulator test `dailyStats all-time ... includes dateless legacy docs` demonstrates both behaviours.
5. Edge case: if one of the last six calendar months has **no sales and no expenses at all**, the old all-time view reached back to an older month to show six; the 6-month window shows only the months that exist inside it (test `KNOWN LIMIT`). "12 months" or "All time" shows the older month.

## Cross-check of optimized vs original results
`test/support/legacy_analytics.dart` is a **verbatim extraction** of the original code (generated from the pre-change file, not retyped). `test/analytics_equivalence_test.dart` feeds both the same seeded synthetic dataset (2,500 bills over 14 months, 3 branches plus untagged legacy bills, string and numeric quantities, with/without cost price, 4 staff, 7 items; 2 branches x 420 days of daily stats, a dateless legacy doc and an invalid-date doc):

| Comparison | Result |
|---|---|
| Item performance, staff, time slots, forecast: all-time | identical (to 1e-6) |
| Same four, for each of the 5 windows (original fed the same windowed documents) | identical |
| Forecast across all windows >= 30 days | identical (it is a rolling 30-day figure) |
| Page-by-page feeding vs one-shot | identical |
| Branch main / north / south (client filter + server rule) | identical to original on the filtered set; legacy untagged bills count for `main` only; no cross-branch leakage; branch sums add up to the total |
| dailyStats per-date totals, weekly list, monthly sales, anomalies | identical to original |
| Monthly-tab months and sales: 6-month window vs all time (continuous data) | identical |
| Window boundaries (30/90 days, 6/12 months, January roll-over) | exact IST midnights, inclusive start |

Emulator (`security-tests/analytics-queries.test.mjs`, 7 tests): the exact query shapes return the right documents; 1 Jun 00:00 IST is inside the window and 31 May 23:59:59.999 outside; scoped `canteenId` queries return only that branch; main unscoped returns untagged legacy bills; a cashier is denied.

## Performance
**Modelled, not measured.** On the synthetic 2,500-bill / 14-month set, documents read per visit:

| Period | Bills read | vs all time |
|---|---|---|
| All time | 2,500 | 100% (old behaviour) |
| 12 months | 1,979 | 79% |
| **6 months (default)** | 883 | **35%** |
| 90 days | 517 | 21% |
| 30 days | 166 | 7% |

Further reductions that are certain by construction: the expenses stream no longer downloads photos for the whole history (only the window, and discarded per page); one live listener on every collection (re-reading deltas on every sale by any branch) is gone; `dailyStats` is bounded. Real production savings depend on your data volume and were not measured. Bill documents still carry their `items` arrays because this SDK has no field projection.

## Remaining limitations
- Not run in the app (no device, no Flutter-to-emulator test): the loader and the page UI are compile-checked and their query shapes proven in Node, not executed.
- `main` is still read unscoped (other branches' bills are downloaded and discarded for that view). Fixing it needs either a one-off backfill that adds `canteenId: 'main'` to legacy documents (a data migration, needs approval) or accepting loss of untagged legacy bills.
- A true server-side sum is not available in `cloud_firestore` 4.17.5 (only `count()`), so aggregation stays client-side.
- Safety row limit 200,000 per collection (flagged on screen if hit).
