# Optimization Plan

Priority order follows the master brief: data correctness, then crash/bug, then performance.

## Done
- B-05: dashboard recent-bills stream limited (was whole collection).
- B-06: weekly stats query filters on `date` (was a doc-id range matching all history).
- B-14: six cashier screens now scoped by `canteenId` (needs index deploy).
- B-18: half-open day/month ranges and IST day keys everywhere.

## Next (recommended order)
1. **B-08 Analytics**: replace three whole-collection streams (`bills`, `dailyStats`, `expenses`) with a bounded window (for example last 90 days, "load more" for older), and use `dailyStats` for daily totals instead of recomputing from bills. Requires no new index for the admin (unscoped) case.
2. **Master credit ledger**: stream only bills with `creditStatus == 'Pending'` (or use `creditCustomers.totalPending`) instead of every Credit bill ever created.
3. **B-09 Excel export**: add a date-range picker (default current financial year or last 12 months) and page the reads; keep "all time" as an explicit choice. Sheets and columns unchanged.
4. **Cashier today cards**: read `dailyStats/{branch}_{today}` by id for totals (one document, no index) and keep the bills query only for the list.
5. **Startup**: remove the fixed 3 s role-splash delay (B-10) and wait only for the role fetch plus the animation minimum.
6. **Offline/sync state (B-12)**: a small banner driven by `snapshotsInSync` / pending-writes metadata and friendly error text for failed transactions.
7. Money type: consider integer paise for new writes (B-11) once a migration plan is approved. Not before.

## Principles
- No change that alters stored financial semantics without a decision.
- Every query change ships with an emulator test of its exact shape and, if needed, an entry in `firestore.indexes.json`.
