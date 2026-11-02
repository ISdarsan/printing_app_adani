# Firestore Index Audit

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
