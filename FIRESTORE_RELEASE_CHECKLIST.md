# Firestore Release Checklist

Nothing has been deployed. Order matters. Steps marked (YOU) need your credentials or a decision; I have not requested or used any private key or token.

## 0. State of the repository
- Branch `stabilize/audit-and-modernize`.
- `firestore.rules`: **unchanged in every phase.** The new features need no rules change (verified in the emulator, see section 5).
- `firestore.indexes.json`: **5** composite indexes (was 6; see FIRESTORE_INDEX_AUDIT.md, "Phase 4"). `firebase.json` references it.

## 1. Compare deployed rules with the repository (YOU, read-only) - STILL PENDING
Not performed: no token or pasted rules were available (PRODUCTION_RULES_COMPARISON.md).
```
# A) Console > Firestore > Rules > copy all into deployed.rules, then:
node tool/compare_rules.mjs --deployed-file deployed.rules

# B) your own short-lived token, never stored by the tool:
gcloud auth print-access-token                       # in your shell
$env:FIREBASE_ACCESS_TOKEN = "<token>"               # PowerShell
node tool/compare_rules.mjs --project canteen-app-adani
```
Exit 0 identical / 1 differences (rule by rule) / 2 input problem. **Send me the output before step 4.** Do not deploy rules from this repository without that comparison and your approval.

## 2. Confirm the index state and the index definitions
```
node tool/check_indexes.mjs                          # registry, source code and firestore.indexes.json agree (expects: OK)
firebase firestore:indexes --project canteen-app-adani   # read-only; on 2 Nov 2026 this returned an empty list
```

## 3. The five required composite indexes
| # | Collection | Fields | Serves |
|---|---|---|---|
| 1 | bills | canteenId ASC, timestamp DESC | Today's Sales, Daily Sales Report, Bills History, Monthly Breakdown (cashier); analytics for a concrete branch (admin) |
| 2 | expenses | canteenId ASC, timestamp ASC | Dashboard budget banner, Funds Received (cashier); analytics for a concrete branch (admin) |
| 3 | cashReconciliations | canteenId ASC, timestamp DESC | Daily Cash Closing history (cashier) **existing query** |
| 4 | notifications | canteenId ASC, timestamp DESC | Notices list, dashboard new-notice alert **existing query** |
| 5 | menuItems | canteenId ASC, name ASC | Add Item / menu list **existing query** |

No index is needed for: the cashier "today" card (a document read), export reads, analytics `dailyStats` windows, the create-once checks (`canteenId ==` plus `clientRequestId ==`, equality only), credit detail queries, admin unscoped streams.

## 4. Deploy the indexes (YOU, after final confirmation)
```
firebase deploy --only firestore:indexes --project canteen-app-adani
```
Expected effect: creates the 5 indexes; reads or changes no data; does not touch rules; the currently released app keeps working. If the CLI offers to delete indexes that are not in the file, answer **No** (production has none, so it should not ask). Wait until every index is `READY` (Console > Firestore > Indexes, or re-run `firebase firestore:indexes`).

## 5. What the new app build does that touches Firestore (all verified against the real rules in the emulator)
| Behaviour | Needs rules change? | Evidence |
|---|---|---|
| Bills and repayments carry an extra field `clientRequestId` | No (create rules do not restrict extra fields on these collections) | emulator test `clientRequestId: cashiers can store it...` |
| "Did this bill/repayment already get saved?" check: `canteenId == own` and `clientRequestId == id`, server read | No (branch-scoped equality query is allowed; unscoped or other-branch is denied) | same test |
| Expenses and notices written with `set` on a pre-chosen id | No (a repeat is denied as an update for cashiers; the app then confirms by reading the document) | emulator test `idempotent expense write...` |
| Cashier dashboard reads `dailyStats/<branch>_<IST date>` | No (own-branch document read is allowed) | emulator test (earlier phase) |
| Staff lookup at sign-in uses `Source.server` | No | n/a |
| Analytics and export queries | No | emulator tests (earlier phase) |

## 6. Ship the app build only after step 4 shows READY
Releasing earlier makes the cashier screens (and scoped analytics) fail with `FAILED_PRECONDITION` until the indexes finish. Rollback of indexes: delete them in the Console; older app versions are unaffected either way.

## 7. Post-deploy verification on real devices (PENDING: nothing below has been tested on a device)
The full per-screen checklist is CASHIER_DEVICE_TEST_PLAN.md. Minimum smoke test:
- [ ] Cashier (non-main branch): dashboard card, Today's Sales, Daily Report, Bills History, Monthly Breakdown, Funds Received, Daily Cash Closing history, Notices, Menu list all load with that branch's data and no error text.
- [ ] Admin: Analytics (each period), Export (This month, 12 months), then open the workbook.
- [ ] Airplane mode: banner shows "Offline"; saving a bill fails with a clear message; an expense shows "Saved on this device, not confirmed yet"; reconnecting clears the banner.
- [ ] Console log search for `failed-precondition` (missing index) and `permission-denied` (rules).

## 8. Things I cannot confirm from here
- Production rules versus repository (step 1).
- Whether the three existing-query screens currently fail for cashiers without the indexes.
- Anything about real devices, real data volumes, or billing.


---

# Release validation addendum (final order of operations)

## Task 1 verification (done, read-only)
| Check | Result |
|---|---|
| Exactly five required composite indexes | `node tool/check_indexes.mjs`: **19 registered queries -> 5 required indexes; file declares 5; OK**. The registry grew from 15 to 19 with four new equality-only queries (customer-exists check, request-id checks, closing/dashboard "today" queries); none needs a composite index |
| The 15 original mappings | unchanged; each re-checked against its source file by the tool |
| No accidental deletions | `firebase firestore:indexes --project canteen-app-adani` returned `{"indexes": [], "fieldOverrides": []}`: production has **no** indexes, so a deploy can only add. The file has `"fieldOverrides": []`. Never use `--force`; if the CLI offers to delete anything, answer No |
| Correct project | `canteen-app-adani` in `firebase.json` and `lib/firebase_options.dart`. **There is no `.firebaserc`**, so a command without `--project` would use whatever the CLI default is. Always pass `--project canteen-app-adani` |

## Final order (nothing below has been run)
1. (YOU) Provide `deployed.rules`; run the comparison; send me the output. **Blocking for step 5.**
2. (YOU) `node tool/check_indexes.mjs` -> expect OK.
3. (YOU, after final confirmation) `firebase deploy --only firestore:indexes --project canteen-app-adani`; wait until every index is READY.
4. (YOU) Run CASHIER_DEVICE_TEST_PLAN.md on a real phone **with a build from this branch**. No result is recorded yet.
5. Only after 1-4: decide on deploying the app build. **Rules are not part of this release.** The menu-delete rule is a separate, later change (MENU_SECURITY_CHANGE_PROPOSAL.md) and must be applied to the *verified deployed* rules, not the repository copy.
6. Legacy backfill is a separate project after the production audit (LEGACY_DATA_AUDIT.md).

## What changed in the app since the last checklist (all rule-agnostic; no rules change needed)
| Change | Why |
|---|---|
| Bill and repayment document id == request id | duplicate create is rejected by the rules atomically |
| No reads of possibly-missing documents (customer, closing, dashboard card, closing screen) | cashiers cannot read missing documents under the repository rules (B-32) |
| Fund wording on cashier screens; menu delete hidden for non-admins | business decisions 2 and 3 |

## Rollback
App: previous Play Store release. Indexes: delete in the Console (additive, harmless). Nothing else was changed in Firebase.
