# Performance Audit

Branch `feature/ui-modernization-performance`. **No production data, Firestore project, rules or indexes were touched.** No device or profiler (DevTools) run was done in this session, so frame times, startup time and real read counts were **not measured**. Where a number is given below it says exactly what produced it.

## Problems found, root causes, changes

| # | Problem | Root cause | Change | Evidence |
|---|---|---|---|---|
| P1 | Firestore listeners re-opened on every rebuild on 8 screens (admin dashboard 6 cards, cashier bell and banner, today / daily / monthly sales, cashflow, funds, expense report) | `StreamBuilder(stream: _makeStream())` inside `build` creates a new stream each time. Flutter cancels the old listener and opens a new one, re-reading the data. | `lib/stream_cache.dart`: one stream per call site, kept while its inputs (branch, day, month) are unchanged; `reset()` for Retry. | **Measured in a widget test**: over 1 build + 10 rebuilds, 11 listeners opened without the cache and 1 with it (`test/stream_cache_test.dart`). This uses a broadcast-stream model shaped like Firestore's, not a live Firestore. |
| P2 | Listener leak risk in my own first version | `asBroadcastStream()` without `onCancel` never closes the source. Found by a test, fixed before commit. Firestore `snapshots()` is already a broadcast stream (verified in the plugin source), so it is used as is; only single-subscription sources are wrapped, with a cancel. | – | `stream_cache_test.dart` |
| P3 | Unreleased text controllers on 4 pages | missing `dispose()` | added | source |
| P4 | Failed loads indistinguishable from empty or zero | builders ignored `hasError` | error view + Retry on all affected screens | source guards |

## Firestore reads

- **No query, collection, filter, `limit`, index or rule was changed.** All branch-scoped requirements (`canteenId ==` filters, half-open IST ranges) are exactly as before. `tool/check_indexes.mjs` still reports 19 queries ↔ 5 indexes.
- Expected effect of P1: fewer duplicate reads when a screen redraws (for example the admin dashboard's whole-month bills listener no longer restarts when the branch filter or a parent rebuilds without the filter changing). **The real reduction in reads was not measured**; it depends on how often those rebuilds happened in production.
- Already efficient before this work (not mine): cashier dashboard reads one `dailyStats` document for today; recent-bills query is limited; analytics and export use paged fetch.

## Rendering

- POS screen is already split into small stateless widgets, which keeps rebuilds cheap. Hit areas were enlarged without changing layout height, and cart names now wrap, so there is no extra animation or work on the billing path.
- `const` constructors: not audited exhaustively; the analyzer reports no issues under the project's lint set.
- Not measured: frame build times, jank, memory.

## Remaining limitations (honest list)

1. Admin "monthly sales" still listens to every bill of the month. With growth this becomes the largest cost. Using `dailyStats` would be cheaper but changes where a financial figure comes from, which needs your decision and a reconciliation of historic data.
2. Admin pending-credit card listens to all `creditCustomers`.
3. Branch filtering on the admin dashboard is client-side by design (avoids new indexes).
4. The billing page rebuilds on each search keystroke (`_searchController` listener). Not measured; not changed.
5. State management is plain `setState` plus streams. There was no measurable reason to replace it, so it was not.
6. Real-device profiling (DevTools timeline, memory, cold start) is outstanding.
