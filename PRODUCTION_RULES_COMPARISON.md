# Production Rules Comparison

## Status: PERFORMED (2 Nov 2026) from the saved `deployed.rules`
Input: `deployed.rules` supplied by you (11 lines). Preserved untouched as `backups/deployed.rules.2026-11-02.ORIGINAL`, SHA-256 `ae2ee8da028777e9c26193163c1b318d7a4d4d54c5de38916a3a714ded6a819a`.
Tool: `node tool/compare_rules.mjs --deployed-file backups/deployed.rules.2026-11-02.ORIGINAL` (rule by rule; no token or credential was used or printed).

## Result: the deployed rules are completely open
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```
**Any signed-in account can read, create, change and delete every document in every collection**, including `canteenStaff` (so any user can make themselves an admin). No branch isolation, no roles, no `active` check, no field validation.

## Rule-by-rule comparison with the repository `firestore.rules` (23 elements)
| Kind | Element | Deployed | Repository |
|---|---|---|---|
| function | `signedIn`, `staffPath`, `staffExists`, `staffData`, `activeStaff`, `isAdmin`, `staffCanteenId`, `canReadBranch`, `canWriteBranch`, `nonDecreasing` (10) | absent | present |
| match | `/canteenStaff/{uid}` | absent (covered by the catch-all) | self-read, admin-only writes |
| match | `/canteens/{canteenId}` | absent | admin only |
| match | `/menuItems/{itemId}` | absent | branch scoped; delete allowed for branch staff |
| match | `/bills/{billId}` | absent | branch scoped create; limited update; admin delete |
| match | `/dailyStats/{statsId}` | absent | branch scoped; non-decreasing totals |
| match | `/expenses/{expenseId}` | absent | branch scoped create; admin edit/delete |
| match | `/creditCustomers/{customerId}` | absent | branch scoped; limited update |
| match | `/repayments/{repaymentId}` | absent | branch scoped create; admin edit/delete |
| match | `/cashReconciliations/{reconciliationId}` | absent | branch scoped create (needs `submittedByUid`); admin edit/delete |
| match | `/notifications/{noticeId}` | absent | branch read; admin create; `readBy` update |
| match | `/monthlyFunds/{monthId}` | absent | staff read; admin write |
| match | `/counters/{counterId}` | absent | per-branch, +1 only |
| match | `/{document=**}` | `allow read, write: if request.auth != null` | `allow read, write: if false` |

All 23 elements differ. None of the repository's protections is deployed.

## Security implications
| Collection | What is possible today (deployed) |
|---|---|
| `canteenStaff` | any user lists all staff, creates a staff record for themselves with `role: admin`, changes anyone's role or branch, deletes staff |
| `bills`, `repayments`, `creditCustomers`, `dailyStats` | any user, of any branch, reads, edits or deletes financial history; wipes a customer's debt; lowers sales |
| `cashReconciliations` | edit or delete submitted cash closings (hides shortages) |
| `expenses`, `monthlyFunds` | edit or delete expenses; change the monthly fund |
| `notifications`, `menuItems`, `counters`, `canteens` | send notices to any branch, delete menu items, reset bill numbers, create canteens |
| everything | readable by **any signed-in account**, which very likely includes anyone who registers one (staff logins are created from the app with `createUserWithEmailAndPassword`, so sign-up is presumably open; the Authentication settings were not visible to me) |

## Intentional or problematic?
**Problematic.** The comment in the deployed file ("allows ANY logged-in user to read and write to ALL collections") shows it is a development default that was never replaced. Do not treat it as deliberate. Production was not changed by this work.

## What was prepared
See PRODUCTION_SECURITY_MIGRATION.md: a tested two-phase plan (a stopgap that only requires an active staff record and changes nothing for real staff, then the full candidate rules), the preserved backup, and deploy and rollback configs. **Nothing was deployed.**

## Review finding that affects this comparison
The repository rules are not safe to deploy as they stand either: staff of branch `main` could list every branch's records by omitting the branch filter, and the cash-closing rule would refuse every closing from the released app. Both are fixed in the candidate (see the migration document, sections 5.2 and 6).
