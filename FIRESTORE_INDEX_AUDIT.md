# Firestore Index Audit

> **Update (phase 4): the required set is 5 composite indexes, not 6.** Sections 3 and 7 below describe the earlier 6-entry file; "Phase 4: index count resolved" at the end is authoritative and is checked by `node tool/check_indexes.mjs`.

Project `canteen-app-adani`, database `(default)`. Nothing in this document was deployed.

## 1. Deployed state (read-only check)
`firebase firestore:indexes --project canteen-app-adani` returned `{"indexes": [], "fieldOverrides": []}`: **no composite indexes exist in production.**

## 2. Every query that needs a composite index

A query needs one when it combines an equality filter on one field with a range filter or `orderBy` on another field.

| Collection | Query shape | Screens | Needed index | Status in production |
|---|---|---|---|---|
| bills | `canteenId ==`, `timestamp >= / <`, optional `orderBy timestamp desc` or asc | Cashier dashboard, Today's Sales, Daily Sales Report, Bills History, Monthly Breakdown (new in this phase) | `canteenId ASC, timestamp ASC` and `canteenId ASC, timestamp DESC` | missing (new) |
| expenses | `canteenId ==`, `timestamp >= / <` | Cashier budget banner, Funds Received (new in this phase) | `canteenId ASC, timestamp ASC` | missing (new) |
| cashReconciliations | `canteenId ==`, `orderBy timestamp desc`, `limit 30` | Cashier "Daily Cash Closing" history (existing code) | `canteenId ASC, timestamp DESC` | **missing: existing query** |
| notifications | `canteenId ==`, `orderBy timestamp desc` (2 places) | Notice list, cashier dashboard alert (existing code) | `canteenId ASC, timestamp DESC` | **missing: existing query** |
| menuItems | `canteenId ==`, `orderBy name` | Add Item / menu list (existing code) | `canteenId ASC, name ASC` | **missing: existing query** |

Three existing queries need indexes that production does not have. Either those queries currently fail with `FAILED_PRECONDITION` (the app prints a console link to create the index), or the indexes were created some other way and the listing is incomplete. I could not tell which from here. Please check those three screens on a cashier device. The file below includes them so the state becomes explicit.

Queries that do not need composite indexes (equality-only filters use merged single-field indexes): `credit_detail_page` bills (`customerPhone`, `canteenId`, `creditStatus`) and repayments (`customerPhone`, `canteenId`); `credit_customers_page`, `menu_view_page` (`canteenId ==` only); `dailyStats` and `cashReconciliations` document gets by id; admin screens (single-field `orderBy`/range, unscoped).

## 3. `firestore.indexes.json` (new, 6 indexes)
bills x2, expenses x1, cashReconciliations x1, notifications x1, menuItems x1, all `queryScope: COLLECTION`. `firebase.json` now points `firestore.indexes` at it.

Validation performed:
- JSON parses and has the Firebase CLI structure.
- The Firestore emulator starts with this file configured, with no errors.
- **Not validated:** the emulator does not enforce or build composite indexes, so the real build happens only on deploy. `bills` has both ASC and DESC because Monthly Breakdown orders ascending and the other screens descending; this is the conservative choice (two small indexes).

## 4. Rules comparison (deployed vs repository): NOT performed
The Firebase CLI cannot print deployed rules, and I did not extract stored credentials to call the REST API. To compare, run (needs `gcloud` or a bearer token, read-only):

```
# list releases, then fetch the ruleset named in the response
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://firebaserules.googleapis.com/v1/projects/canteen-app-adani/releases/cloud.firestore"
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://firebaserules.googleapis.com/v1/<rulesetName from above>" \
  | python -c "import json,sys;print(json.load(sys.stdin)['source']['files'][0]['content'])" > deployed.rules
diff deployed.rules firestore.rules
```
(Or copy the rules from Firebase Console > Firestore > Rules.) Send me any differences; this phase does not change `firestore.rules`.

## 5. Deployment plan (run only after your final confirmation)
1. Confirm current state again: `firebase firestore:indexes --project canteen-app-adani`
2. Deploy indexes only: `firebase deploy --only firestore:indexes --project canteen-app-adani`
   - Effect: creates 6 composite indexes. No data is read, changed or deleted; rules are untouched; existing app versions keep working (adding an index is additive).
   - Because production has zero indexes, the CLI has nothing to offer to delete. If it ever prompts to delete indexes not in the file, answer **no**.
   - Build takes seconds to a few minutes at current data size.
3. Wait until all show `READY`: Firebase Console > Firestore > Indexes (or re-run step 1).
4. Only then release the app build containing the scoped queries. Releasing the app before step 3 completes would make those cashier screens fail with `FAILED_PRECONDITION` until the indexes finish building.
5. Rollback: delete the indexes in the console. Older app versions are unaffected either way.

## 6. Behavior notes for scoped queries
- A cashier's `canteenId ==` filter cannot match legacy documents that have **no** `canteenId` field. The rules treat a missing `canteenId` as `main`, but a query cannot. Cashiers of non-`main` branches never saw those documents; `main` cashiers will not see untagged legacy bills in the six screens (the previous unscoped queries were rejected for cashiers anyway). Admin screens are unchanged and still include untagged documents as `main`.
- `scopeQuery` leaves admin queries unscoped; admins' branch filtering is still done on the device as before.

---

# Phase 3 additions

## 7. B-19: the three existing cashier queries (shape, rule, index)

Verified against the **rules** in the emulator (test `B-19 query shapes`). Real-device behaviour is **PENDING: no cashier device was available and none of this was tested on one.**

| Screen / file | Exact query | Rule that applies | Rule outcome (emulator) | Index needed | Index in production |
|---|---|---|---|---|---|
| Daily Cash Closing history (`cash_reconciliation_page.dart`, cashier) | `cashReconciliations` where `canteenId == <own>` orderBy `timestamp` desc limit 30 | `read: canReadBranch(resource.data)` | own branch allowed; unscoped denied; other branch denied | `canteenId ASC, timestamp DESC` | **missing** |
| Same screen, admin | `cashReconciliations` orderBy `timestamp` desc limit 30 (no filter) | admin passes `canReadBranch` | allowed | single-field only | n/a |
| Notices (`notifications_page.dart`) | `notifications` where `canteenId == <selected>` orderBy `timestamp` desc | `read: canReadBranch(resource.data)` | own allowed; unscoped and other branch denied | `canteenId ASC, timestamp DESC` | **missing** |
| Dashboard notice alert (`billing_dashboard_page.dart`) | same + `limit(1)` | same | allowed | same index | **missing** |
| Menu list (`add_item_page.dart`) | `menuItems` where `canteenId == <selected>` orderBy `name` | `read: canReadBranch(resource.data)` | own allowed; unscoped and other branch denied | `canteenId ASC, name ASC` | **missing** |

Consequence: with no composite index, Firestore rejects each of these with `FAILED_PRECONDITION` ("The query requires an index"), so these three cashier screens would show an error or stay empty. Whether they do in production could not be checked from here. The `StreamBuilder`s on those screens will surface the error text, and the Flutter console prints a one-click link that creates the index. Verification steps are in FIRESTORE_RELEASE_CHECKLIST.md section 6.

Note on the notice query: it filters with `selectedCanteenId`, so a notice document with an empty/missing `canteenId` (legacy, which the app treats as `main`) is not returned by the server query even though `matchesNotificationCanteen` would accept it on the device.

## 8. Index review after B-08 / B-09
All queries were re-listed. The analytics loader and the paged export introduce **no new composite index**:

| New query | Shape | Index |
|---|---|---|
| Export: bills / expenses / repayments / cashReconciliations | `timestamp >= a`, `timestamp < b`, orderBy `timestamp desc` (admin, unscoped) | single-field (range and order on the same field) |
| Export: creditCustomers | orderBy `totalPending` desc | single-field |
| Analytics: bills, concrete branch | `canteenId ==`, `timestamp >= a`, orderBy `timestamp desc` | existing entry #2 |
| Analytics: bills, branch main | `timestamp >= a`, orderBy `timestamp desc` | single-field |
| Analytics: expenses, concrete branch | `canteenId ==`, `timestamp >= a`, orderBy `timestamp` asc | existing entry #3 (ASC is why expenses is ASC only) |
| Analytics: dailyStats window | `date >= a`, orderBy `date` | single-field |
| Analytics: dailyStats all-time | orderBy `__name__` | automatic |

The 6 entries in `firestore.indexes.json` are the complete list. Validation performed: JSON parses; the Firestore emulator starts with the file configured and reports no error. **Not validated**: the emulator does not build or enforce composite indexes, so `READY` status can only be observed after a real deploy.

## 9. Comparing deployed rules with the repository
Added `tool/compare_rules.mjs` (read-only):
- `--deployed-file <path>`: compares a file you copy from the Console.
- `--project <id>`: fetches the ruleset through the Firebase Rules REST API using a **short-lived access token you place in the `FIREBASE_ACCESS_TOKEN` environment variable** (for example from `gcloud auth print-access-token` in your own shell). The tool never reads credential files, never prints the token, never writes to Firebase, and has no deploy code path.
- Ignores line-ending and trailing-space differences; prints a unified diff otherwise; exit codes 0 / 1 / 2.
Tested offline on local files only. The live fetch path has not been run (no token was available here).

## 10. Repository rule worth a look (not changed)
`firestore.rules` allows `delete` on `menuItems` for any staff member who can read that branch (`allow delete: if canReadBranch(resource.data)`), i.e. a cashier can delete a menu item of their own branch. Every other collection restricts delete to admins. This may be intentional (the Add Item screen has a delete button); flagged for your decision, not modified.

---

# Phase 4: index count resolved (6 became 5), with proof

## Why "six indexes vs nine screens" looked inconsistent
Nine cashier screens (six scoped in B-14 plus three from B-19) issue more than nine queries, but a composite index depends only on the query's **shape**: `collection + equality fields + the one ordered/ranged field with its direction`. Queries with the same shape share one index. I re-derived the requirement mechanically instead of by hand: `tool/check_indexes.mjs` holds a registry of every distinct query call site (file, collection, equality fields, range/order field and direction), derives the index each needs with the documented rule below, asserts that each query still exists in its source file (so the registry cannot go stale), and compares the derived set with `firestore.indexes.json`.

Rule used: equality filters on some fields plus a range or `orderBy` on one other field need a composite index on `[equality fields ASC..., that field in the query's direction]`. A range filter with no explicit `orderBy` orders by that field ascending. Equality-only queries (even on several fields) and single-field range/order queries need no composite index.

Result of `node tool/check_indexes.mjs`: **15 registered queries -> 5 required composite indexes; the file declares 5; OK.**

## Why 6 became 5 (a code change, not a guess)
The previous file contained `bills (canteenId ASC, timestamp ASC)` as well as `... DESC`. The ASC variant existed only because two bills queries ordered ascending:
- **Cashier dashboard "today" card**: no longer queries bills at all. It reads one `dailyStats` document by id (Part D).
- **Monthly Breakdown**: ordered ascending, but the page groups bills by day and sorts afterwards, so order is irrelevant. It now orders descending like every other bills query.

I deliberately did **not** rely on "a DESC index can be read backwards for an ASC query": the emulator cannot confirm index behaviour, so that claim cannot be proven here. Removing the only ascending bills query makes the question moot. `expenses` stays ascending because its consumers (Funds Received list, budget banner, analytics) rely on or tolerate ascending order, and changing the Funds list order would change what users see.

## Query -> required index -> screen -> role
| # | Query / screen | Role | Required composite index |
|---|---|---|---|
| 1 | Cashier dashboard: budget banner (month expenses) (`lib/billing_dashboard_page.dart`) | cashier | expenses(canteenId ASC, timestamp ASC) |
| 2 | Today's Sales (`lib/today_sales_page.dart`) | cashier | bills(canteenId ASC, timestamp DESC) |
| 3 | Daily Sales Report (`lib/daily_sales_report_page.dart`) | cashier | bills(canteenId ASC, timestamp DESC) |
| 4 | Bills History (`lib/all_bills_page.dart`) | cashier | bills(canteenId ASC, timestamp DESC) |
| 5 | Monthly Breakdown (`lib/monthly_sales_breakdown_page.dart`) | cashier | bills(canteenId ASC, timestamp DESC) |
| 6 | Funds Received (month expenses) (`lib/funds_received_page.dart`) | cashier | expenses(canteenId ASC, timestamp ASC) |
| 7 | Daily Cash Closing history (`lib/cash_reconciliation_page.dart`) | cashier | cashReconciliations(canteenId ASC, timestamp DESC) |
| 8 | Notices list (`lib/notifications_page.dart`) | cashier + admin (selected branch) | notifications(canteenId ASC, timestamp DESC) |
| 9 | Cashier dashboard: new-notice alert (limit 1) (`lib/billing_dashboard_page.dart`) | cashier | notifications(canteenId ASC, timestamp DESC) |
| 10 | Menu list (Add Item) (`lib/add_item_page.dart`) | cashier + admin (selected branch) | menuItems(canteenId ASC, name ASC) |
| 11 | Analytics bills (concrete branch) (`lib/analytics_loader.dart`) | admin | bills(canteenId ASC, timestamp DESC) |
| 12 | Analytics expenses (concrete branch) (`lib/analytics_loader.dart`) | admin | expenses(canteenId ASC, timestamp ASC) |
| 13 | Cashier dashboard: today card (document get) (`lib/billing_dashboard_page.dart`) | cashier | none (single-field / document get) |
| 14 | Export: bills (unscoped, admin) (`lib/report_data_loader.dart`) | admin | none (single-field / document get) |
| 15 | Credit detail: pending bills (3 equality filters) (`lib/credit_detail_page.dart`) | cashier | none (single-field / document get) |

| Index | Serves |
|---|---|
| `expenses(canteenId ASC, timestamp ASC)` | 3 queries: Cashier dashboard: budget banner (month expenses); Funds Received (month expenses); Analytics expenses (concrete branch) |
| `bills(canteenId ASC, timestamp DESC)` | 5 queries: Today's Sales; Daily Sales Report; Bills History; Monthly Breakdown; Analytics bills (concrete branch) |
| `cashReconciliations(canteenId ASC, timestamp DESC)` | 1 queries: Daily Cash Closing history |
| `notifications(canteenId ASC, timestamp DESC)` | 2 queries: Notices list; Cashier dashboard: new-notice alert (limit 1) |
| `menuItems(canteenId ASC, name ASC)` | 1 queries: Menu list (Add Item) |

(`tool/check_indexes.mjs --markdown` regenerates this table; the three rows at the end of the first table need no composite index.)

## The nine screens
| # | Screen | Role | Query rows above | Index |
|---|---|---|---|---|
| 1 | Cashier dashboard (budget banner) | cashier | 1 | expenses ASC |
| 2 | Today's Sales | cashier | 2 | bills DESC |
| 3 | Daily Sales Report | cashier | 3 | bills DESC |
| 4 | Bills History | cashier | 4 | bills DESC |
| 5 | Monthly Breakdown | cashier | 5 | bills DESC |
| 6 | Funds Received | cashier | 6 | expenses ASC |
| 7 | Daily Cash Closing | cashier | 7 | cashReconciliations DESC |
| 8 | Notices (list + dashboard alert) | cashier | 8, 9 | notifications DESC |
| 9 | Menu list | cashier | 10 | menuItems ASC |

Admin analytics (rows 11, 12) reuse the bills DESC and expenses ASC indexes. Admin screens that read unscoped collections need none.

## What was not and cannot be proven offline
- That Firestore accepts these five definitions and builds them: only a deploy shows `READY`. JSON structure is valid and the emulator starts with the file configured.
- That production currently lacks the three B-19 indexes in some other form: the CLI listing is empty (checked 2 Nov 2026).
- The registry is a model of the code. The checker guards it with source substring checks, but a brand-new query added later must be added to the registry (the checker cannot discover it).
