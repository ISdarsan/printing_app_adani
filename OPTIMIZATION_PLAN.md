# Optimization Plan

Priority order follows the master brief: data correctness, then crash/bug, then performance.

## Done
| Item | Where |
|---|---|
| B-05 dashboard recent-bills stream limited | pass 1 |
| B-06 weekly stats filtered on `date` | pass 1 |
| B-14 six cashier screens branch-scoped | pass 2 (needs index deploy) |
| B-18 half-open IST day/month ranges | pass 2 |
| **B-08 Analytics**: bounded paged reads, period selector (default 6 months), single-pass aggregation, equivalent to the original on synthetic data | this pass, ANALYTICS_OPTIMIZATION_REPORT.md |
| **B-09 Excel export**: period picker, cursor paging, retry/cancel, no partial file, pure workbook builder with professional formatting, validated on a real generated file | this pass, EXPORT_OPTIMIZATION_REPORT.md, EXCEL_WORKBOOK_VALIDATION.md |
| Index review incl. the three B-19 queries; rules-compare tool; release checklist | this pass |

## Next (recommended order)
1. **You**: run the rules comparison and deploy the 6 indexes per FIRESTORE_RELEASE_CHECKLIST.md; verify on a cashier device (B-19 screens, B-14 screens). Until then the cashier fixes are unproven in production.
2. **Cashier "today" cards from `dailyStats`** (one document by id, no index): cuts the cashier dashboard's live bills listener to a single small document for totals while the bills list keeps its (now scoped) query.
3. **Offline/sync status (B-12)** and friendly error text: reuse the new `PagedFetchException` messages; add a pending-writes indicator.
4. **Startup (B-10)**: remove the fixed 3 s role-splash delay.
5. **Legacy backfill (B-21/B-22)**: a reviewed, backed-up script that tags untagged legacy documents with `canteenId: 'main'` and adds missing `dailyStats.date`. Requires approval; would let branch `main` use server-side scoping everywhere.
6. **Money type (B-11)**: consider integer paise for new writes only after a migration plan is approved.
7. **Integration test** that runs `ReportDataLoader` and `AnalyticsLoader` from Dart against the emulator (needs the Flutter Firebase test harness).
8. UI redesign stage (not started; waits for the data layer to be trusted in production).

## Principles
- No change that alters stored financial semantics without a decision.
- Every query change ships with an emulator test of its exact shape and, if needed, an entry in `firestore.indexes.json`.
- Every report change ships with a test that compares it against the previous implementation or independent arithmetic.
