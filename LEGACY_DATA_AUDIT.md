# Legacy Data Audit (Task 6)

## Status
**The tool is built and validated on synthetic legacy data. No production audit was run** (no production access in this session). Therefore this document contains **no production numbers**. Nothing was migrated and nothing will be until the production audit has been reviewed and approved.

## Why it matters
- Documents without a `canteenId` are treated by the app as branch `main` (client-side), but no server query can match a missing field. That is why branch `main` analytics read other branches' data and discard it (B-21), and why cashiers' branch-scoped queries cannot see untagged legacy records.
- `dailyStats` and `cashReconciliations` documents without a `date` field are skipped by windowed analytics and by the "today" queries (B-22).

## The tool: `security-tests/legacy-audit.mjs`
- **Read-only.** It imports no write function (a test asserts the source contains none) and performs only paged `getDocs` reads. Reads run under the normal security rules as an admin, so no rule is bypassed.
- **No service account.** It signs in with your own admin e-mail and password, passed through environment variables, nothing stored:
  ```
  $env:FIREBASE_API_KEY="<web API key, public client config>"
  $env:FIREBASE_AUDIT_EMAIL="<your admin email>"; $env:FIREBASE_AUDIT_PASSWORD="<password>"
  node security-tests/legacy-audit.mjs --project canteen-app-adani --out legacy-audit.json
  ```
  (`--emulator host:port` is how it is tested.) Output contains counts and **document ids only**; no names, phone numbers or amounts.
- Covers: bills, expenses, repayments, cashReconciliations, creditCustomers, dailyStats, notifications, menuItems, canteenStaff (canteens are the lookup table).

## Classification
"Missing" means the field is absent, empty, whitespace or not a string.

### `canteenId`: recoverable or not
| Evidence | Applies to | Confidence |
|---|---|---|
| id prefix `<canteenId>_...` where the prefix is a known canteen | dailyStats, cashReconciliations, creditCustomers | **high** |
| `canteenName` equals exactly one known canteen name | any | **high** (ambiguous names are not trusted) |
| creator is a non-admin staff member with a branch (uid or e-mail) | bills, expenses, repayments, cashReconciliations | **medium** (a cashier may have been moved) |
| customer phone belongs to exactly one branch | bills, repayments | **medium** (a phone in two branches is ambiguous and not trusted) |
| creator is an admin | bills, expenses, notifications | **low** (an admin's own branch says little about the record) |
| none of the above | | **unrecoverable**: no evidence, keeps today's meaning (branch `main`) |

### `date`: recoverable or not
| Evidence | Confidence |
|---|---|
| id suffix `..._yyyy-MM-dd`, or a legacy id that is itself a date | **high** |
| `lastUpdated` / `timestamp` converted to the **IST** day | medium |
| nothing | unrecoverable |

## Validation on a synthetic legacy dataset (emulator, real rules)
The dataset has 7 bills, 3 customers, 3 repayments, 4 dailyStats, plus closings, an expense, a notice, a menu item and 3 staff, built to hit every branch of the rules above. `legacy-audit.test.mjs`: 5 tests pass.

| Collection | Docs | Missing canteenId | Recoverable (high/med/low) | Unrecoverable | Missing date | Date recoverable | Date unrecoverable |
|---|---|---|---|---|---|---|---|
| bills | 7 | 6 | 1 / 2 / 1 | 2 | n/a | n/a | n/a |
| creditCustomers | 3 | 2 | 1 / 0 / 0 | 1 | n/a | n/a | n/a |
| repayments | 3 | 2 | 0 / 2 / 0 | 0 | n/a | n/a | n/a |
| dailyStats | 4 | 1 | 0 / 0 / 0 | 1 | 3 | 2 (id) | 1 |
| cashReconciliations | 1 | 1 | 1 / 0 / 0 | 0 | 0 | 0 | 0 |
| expenses / notifications / menuItems / canteenStaff | 1 / 1 / 1 / 3 | 1 / 1 / 1 / 1 | 0/1/0, 0/0/1, 0/0/0, 0/0/0 | 0 / 0 / 1 / 1 | | | |
| **Totals** | | **16** | | | **3** | **2** | **1** |

Also tested: an unknown id prefix is not trusted, an ambiguous canteen name is not trusted, a phone in two branches is not trusted, IST day boundaries (18:30 UTC rolls to the next IST day), a cashier cannot run the audit (rules deny listing), and the audit leaves the data unchanged.

## Proposed backfill strategy (NOT executed, needs your approval after the production audit)
1. **Run the audit on production** and send me `legacy-audit.json`. Decide per collection from real numbers.
2. **Dry run on a copy**: restore a Firestore export into the emulator (or a separate test project) and rehearse every step there first.
3. **Backup**: a managed Firestore export, plus the script saves every document's *before* values to a file so each change can be reversed.
4. **Script (separate, reviewed, idempotent)**: writes only `canteenId` (or `date`) on documents where it is missing, using admin rights (the rules allow admin updates on every collection). It never touches amounts, balances, ids or timestamps, skips documents that already have the field (safe to re-run), works in small batches, logs every id changed.
5. **Order and policy**
   - First the **high-confidence** records (id prefix, unique name, id-suffix dates).
   - **Medium/low** records: list them for a human to confirm; do not auto-assign.
   - **Unrecoverable** records: assign `main` only if you confirm the convention (it is what the app already assumes); otherwise leave untouched.
   - Missing `date` on `dailyStats` / `cashReconciliations`: set from the id suffix; for timestamp-derived dates, review the list.
6. **Verify**: re-run the audit (expect zero high-confidence gaps), compare per-branch totals before and after (bills, `dailyStats`, credit balances must be identical), spot-check screens for the main and one other branch.
7. **Then, and only then**, consider code simplifications that the backfill would allow (server-side scoping for branch `main` analytics, removing the client-side `main` special case). Those are separate changes.

Risks to review before step 4: bills/customers whose true branch differs from the creator's branch; customers sharing a phone across branches; any process that reads the old (missing) field expecting `main`.

## Decision needed from you
Whether unrecoverable legacy records may be assigned to `main`, and whether medium/low-confidence records require manual confirmation (recommended).
