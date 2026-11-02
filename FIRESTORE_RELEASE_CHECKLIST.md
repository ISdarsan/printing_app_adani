# Firestore Release Checklist

Nothing in this phase was deployed. This is the order to follow when you decide to release. Every step marked (YOU) needs your credentials or a decision; I have not requested or used any private key.

## 0. State of the repository
- Branch `stabilize/audit-and-modernize`.
- `firestore.rules`: **unchanged** in all phases.
- `firestore.indexes.json`: 6 composite indexes (below). `firebase.json` references it.

## 1. Compare deployed rules with the repository (YOU, read-only)
Pick one:
```
# A) Console: Firestore > Rules > copy everything into deployed.rules, then:
node tool/compare_rules.mjs --deployed-file deployed.rules

# B) Your own short-lived token (never stored, never printed by the tool):
gcloud auth print-access-token                          # in your shell
$env:FIREBASE_ACCESS_TOKEN = "<token>"                  # PowerShell
node tool/compare_rules.mjs --project canteen-app-adani
```
Exit 0 = identical. Exit 1 prints a unified diff (`-` deployed, `+` repository). **Send me any difference before continuing**: a deployed rule that is stricter or looser than the repository changes what the app can read. The tool was verified only on local files (identical, CRLF-only difference, changed rule, missing input); the live fetch path (B) has not been run.

## 2. Confirm the current index state (read-only, done once already)
```
firebase firestore:indexes --project canteen-app-adani
```
Result on 2 Nov 2026: `{"indexes": [], "fieldOverrides": []}` for database `(default)`.

## 3. Required composite indexes (`firestore.indexes.json`)
| # | Collection | Fields | Used by | New or existing query |
|---|---|---|---|---|
| 1 | bills | canteenId ASC, timestamp ASC | Monthly Breakdown (cashier); analytics scoped reads are DESC | new (B-14) |
| 2 | bills | canteenId ASC, timestamp DESC | Cashier dashboard, Today's Sales, Daily Report, Bills History; Analytics for a concrete branch | new (B-14, B-08) |
| 3 | expenses | canteenId ASC, timestamp ASC | Cashier budget banner, Funds Received; Analytics for a concrete branch | new (B-14, B-08) |
| 4 | cashReconciliations | canteenId ASC, timestamp DESC | Cashier "Daily Cash Closing" history | **existing query (B-19)** |
| 5 | notifications | canteenId ASC, timestamp DESC | Notices list and dashboard alert | **existing query (B-19)** |
| 6 | menuItems | canteenId ASC, name ASC | Add Item / menu list | **existing query (B-19)** |

No index is needed for: export reads (single-field range + `orderBy` on the same field), analytics `dailyStats` (`date` range), admin dashboard streams, `creditCustomers` ordering, credit detail queries (equality only), document gets. Re-checked after the B-08/B-09 changes: **no additional indexes** were introduced.

## 4. Deploy the indexes (YOU, after final confirmation)
```
firebase deploy --only firestore:indexes --project canteen-app-adani
```
Expected effect: creates the 6 indexes; reads/changes no data; leaves rules alone; the older app version keeps working. If the CLI asks to delete indexes absent from the file, answer **No** (production currently has none, so it should not ask).
Build time: seconds to a few minutes at current data sizes. Watch with:
```
firebase firestore:indexes --project canteen-app-adani        # state should be READY (or check Console > Indexes)
```

## 5. Only then ship the app build
Releasing the app before step 4 has finished makes the cashier screens and the scoped analytics return `FAILED_PRECONDITION`. Rollback: delete the indexes in the Console; app versions without the changes are unaffected either way.

## 6. Post-deploy verification on real devices (PENDING: nothing below was tested on a device)
Cashier account of a non-main branch:
- [ ] Dashboard "today" card, Today's Sales, Daily Report, Bills History, Monthly Breakdown load numbers (no error text).
- [ ] Funds Received page and the budget banner load.
- [ ] Daily Cash Closing shows the history list (B-19).
- [ ] Notices list opens; dashboard alert still appears for a new notice (B-19).
- [ ] Menu list opens in sorted order (B-19).
Admin account:
- [ ] Analytics loads for 6 months, then each period; Refresh works; status line shows counts.
- [ ] Export: This month, then 12 months; open the .xlsx and compare the Dashboard Summary with the app's totals.
- [ ] Export with airplane mode on: expect a clear error with Retry and no file.
Look in the app's console/Crashlytics for `failed-precondition` (missing index) and `permission-denied` (rules).

## 7. Things I cannot confirm from here
- Whether production rules equal the repository (step 1).
- Whether the three B-19 screens currently work for cashiers without the indexes (they cannot, by Firestore's rules, unless indexes were created some way the CLI listing does not show).
- Any device behaviour.
