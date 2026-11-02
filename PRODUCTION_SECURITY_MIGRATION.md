# Production Security Migration

**Status: PREPARED AND TESTED. NOT DEPLOYED. Nothing in Firebase was changed, no rules were published, no production data was read or written.** The original deployed rules are preserved untouched (section 2).

## 1. The issue
The deployed Firestore rules are exactly:
```
match /{document=**} { allow read, write: if request.auth != null; }
```
**Anyone who is signed in to the Firebase project can read, change and delete every record: all branches' bills, credit customers, repayments, expenses, cash closings, funds, and the `canteenStaff` collection that decides who is an admin.** A cashier can make themselves an admin, delete a bill, or erase a customer's debt.

### How exposed is it? (reasoned, not verified)
The admin dashboard creates staff logins from the app with `createUserWithEmailAndPassword` on a second `FirebaseApp` (`lib/admin_dashboard_page.dart`, around line 2230). For that to work, e-mail/password **sign-up must be enabled** in the project, and the Firebase API key is public (it ships inside the app). So very likely **anyone on the internet can create an account and then read and write the whole database**. I could not see the Firebase Authentication settings, so this is an inference. Please check the Authentication > Users list for accounts you do not recognise.

Because the rules have always been open, the app has **never been exercised against restrictive rules in production**. That is why this migration needed a systematic review of every Firestore operation of the app (section 6) and not just a rules file.

## 2. Evidence and backup
| Item | Value |
|---|---|
| Saved deployed rules | `deployed.rules` (11 lines) |
| **Preserved original (read-only copy)** | `backups/deployed.rules.2026-11-02.ORIGINAL` |
| SHA-256 of the original | `ae2ee8da028777e9c26193163c1b318d7a4d4d54c5de38916a3a714ded6a819a` (also in `backups/…ORIGINAL.sha256`; the copy is byte-identical to `deployed.rules`) |
| Comparison | `node tool/compare_rules.mjs --deployed-file backups/deployed.rules.2026-11-02.ORIGINAL --repo-file proposals/firestore.rules.candidate`: 23 rule elements (10 helper functions, 12 collections, the catch-all) all differ; the catch-all goes from `if request.auth != null` to `if false` |
| Candidate rules | `proposals/firestore.rules.candidate`, SHA-256 `6bc1d1ae3bd289924dbef6915d27d60fce94e967b5c141324796a17b36882a10` (verify this before deploying; any edit changes it) |
| Phase-1 stopgap rules | `proposals/firestore.rules.stopgap`, SHA-256 `d8ef0f4b1e13e44683e695aa3f4902b97a18ded11d8dafad83f1372113a7c728` |
| Deploy / rollback configs | `firebase.candidate.json`, `firebase.stopgap.json`, `firebase.rollback.json` (each points to one rules file; the emulator loads all three without error; their use on production is untested) |

**Checksum note:** the hashes above were taken on the files with LF line endings. Git on Windows may check them out with CRLF, which changes the SHA-256 of identical rules. If a hash differs, do not assume tampering: run `node tool/compare_rules.mjs --deployed-file <copy of the file> --repo-file proposals/firestore.rules.candidate`, which ignores line endings and comments, and expect exit 0.

## 3. The recommended path: two phases
| Phase | Rules | Effect for real staff | Closes |
|---|---|---|---|
| **1 Stopgap** (can go now, after the staff check in 8.1) | `firestore.rules.stopgap` | **None.** For every operation an old or new app build performs, an active staff member gets identical results to today (tested: 3 identities x 9 operations compared against the deployed rules) | strangers, self-registered accounts, deactivated staff, signed-out clients |
| **2 Candidate** (after the new app build is in use) | `firestore.rules.candidate` | Cashiers lose cross-branch access, edits to financial records, deletes; **old app builds partly break** (section 7) | roles, branches, record integrity, admin-only deletes |

Why two: the full candidate cannot be deployed safely while app builds that predate this branch are still in use, but waiting for adoption leaves the database open to the internet. The stopgap removes the largest exposure first at zero workflow risk.

## 4. What the candidate enforces
Notation: R read, C create, U update, D delete. "Own" = the caller's own canteen (`canteenId == their branch`). A list query must itself carry the branch filter.

Always required: signed in, a `canteenStaff/{uid}` record exists, `active` is not `false`, and `role` is exactly `admin` or `cashier`.

| Collection | Deployed (any signed-in user) | Candidate: cashier | Candidate: admin |
|---|---|---|---|
| `canteenStaff` | R C U D all | R own record only (also when deactivated, so the app can say so). No list, no create/update/delete: **no self-promotion** | R C U D all |
| `canteens` | R C U D all | nothing | R C U D |
| `menuItems` | all | R own; C own; U own (cannot move to another branch); **D denied** | R C U D all |
| `bills` | all | R own; C own with checks (below); U only the pending amount/status of own CREDIT bills, **downward only**; D denied | R C U D all |
| `dailyStats` | all | R own; C own (fixed key set); U own, totals **can only grow**; D denied | all |
| `expenses` | all | R own; C own, signed with own uid, amount > 0; U D denied | all |
| `creditCustomers` | all | R own; C own; U own (name, balance, last update only, phone/branch fixed); D denied | all |
| `repayments` | all | R own; C own, amount > 0, server time; U D denied | all |
| `cashReconciliations` | all | R own; C own, signed by the caller, server time; U D denied (create-only, one per day by id) | all |
| `notifications` | all | R own; U only to add own uid to `readBy`; C D denied | all |
| `monthlyFunds` | all | R (organisation-wide fund, by decision); C U D denied | R C U D |
| `counters` | all | get own branch counter (and the legacy `billCounter`); create/update only to +1; list denied; D denied | all |
| anything else | all | denied | denied |

Bill create checks: created by the caller; payment mode is Cash, UPI or Credit; **time equals the server time (no back-dating)**; a new credit bill starts `Pending` with pending = total; total >= 0.

## 5. Every permission change, and why
### 5.1 Compared with the deployed rules (what each kind of user gains or loses)
| Who | Loses | Keeps |
|---|---|---|
| Signed-in stranger or self-registered account | **everything** (read and write) except reading their own missing staff record | nothing |
| Deactivated staff (`active: false`) | everything but their own staff record | that read |
| Staff record with missing/unknown role (for example `"Admin"`) | everything but their own staff record | that read |
| Cashier | other branches' data (reads and writes); writing `canteenStaff`, `canteens`, `monthlyFunds`, notices; deleting anything; editing bills, repayments, expenses, closings after creation; lowering `dailyStats`; resetting counters; listing without a branch filter | everything the app's cashier screens do (section 6) |
| Admin | writing unknown collections | all admin screens and operations |

### 5.2 Compared with the repository `firestore.rules` (the five collections where the candidate differs)
| Change | Reason | Impact on the app |
|---|---|---|
| **Branch check no longer uses `get('canteenId','main')`** (`canReadBranch`/`canWriteBranch`) | **Security fix found in this review.** With that default, an *unfiltered* list query was allowed for staff of branch `main` and returned every branch's records (proved in the emulator for both a staff record without `canteenId` and one with `canteenId: 'main'`). The repository rules have this flaw too, and my earlier isolation tests only used the `north` and `south` branches, so they missed it | None for the app (it always filters by `canteenId`). Records without a `canteenId` become admin-only until the legacy backfill |
| `role` must be `admin` or `cashier` | A staff record with an unknown role still got branch access | None: the app already refuses such users at login |
| `bills` create: payment mode, server time, credit starts pending | stop back-dating and forged credit state | none (the app sends exactly this) |
| `bills` update: credit bills only, pending can only decrease, `Paid` means 0 pending | a cashier could set any pending amount or status | none: repayments only decrease |
| `repayments`, `cashReconciliations` create: server time | stop back-dating | none |
| `cashReconciliations` create: signed by uid **or** by the caller's own token e-mail | the repository rule required `submittedByUid`, which no released build sends; every cashier closing would have been refused. The e-mail alternative keeps old builds working and still cannot be forged | New builds send the uid (changed in `cash_reconciliation_page.dart`). The e-mail clause is transitional |
| `menuItems`: delete admin-only; admin may also update (re-tag) | business decision; backfill support | Add Item hides the delete button for cashiers (already in the app) |
| `creditCustomers` update: null-safe phone check | legacy customers without a phone field would be unupdatable | none |

## 6. The application under the candidate rules (B-32 and every operation)
### 6.1 B-32: cashiers cannot read a document that does not exist
Proved on the emulator for `bills`, `creditCustomers`, `dailyStats`, `cashReconciliations`, `expenses`, `repayments`, `menuItems`, `notifications`: the rules cannot judge the branch of a missing document, so a cashier's `get` is denied. Allowed exceptions: the organisation fund, the user's own staff record, counters. **I did not loosen the rules** to change this. The app was changed instead:

| Flow | Before | Now |
|---|---|---|
| First credit bill for a new customer | read the missing customer inside the transaction (would be denied) | scoped "does it exist?" query, then update, or create with merge + increment |
| First cash closing of a day | read the missing closing inside the transaction (would be denied) | scoped query for today's closing, then a create-only transaction |
| Closing screen streams | document streams on missing documents (error, and a failed stream never recovers) | own-branch queries that return empty, then the record |
| Dashboard "today" card | document stream (would show a dash all morning) | own-branch query |
| Duplicate-bill protection | check-then-create | document id = request id, so a duplicate create is an update, which the rules refuse atomically |

`test/missing_document_reads_test.dart` scans the source for every single-document or in-transaction read and requires each to be on a reviewed allowlist. I mutation-checked it: adding a forbidden read makes the test fail.

### 6.2 Every operation, verified
The operation matrix in `security-tests/candidate-rules.test.mjs` replays each cashier and admin operation with the payload copied from the Dart source: sign-in lookup and connection probe, dashboard card/notices/budget banner, the five bill list screens and bill detail, menu list/add/edit/delete, notices and mark-as-read, expense create, credit customer screens, repayment, cash closing, funds, plus the full billing and repayment transactions, and the same workflows for **branch `main`** (both staff-record variants). Admin: dashboard streams, analytics, export, expense report, master credit ledger, staff and canteen management, funds, notices, deletes.

**One mismatch was found by this process and fixed:** the app never sent `submittedByUid` on cash closings (the repository rule required it). My earlier transaction port had added the field itself, which hid the problem. The Dart code now sends it, and the candidate also accepts the older payload (section 5.2).

## 7. Workflows that may break (read this before deploying phase 2)
### 7.1 Accounts that get locked out
| Case | Result |
|---|---|
| A person with a Firebase login but **no `canteenStaff` record** | no access (the app already says "role not found") |
| `active: false` | no access (intended) |
| `role` other than exactly `admin` / `cashier` (case-sensitive) | no access |
| **No active admin at all** | nobody can administer; **check this first** |
Run the read-only staff check (8.1) before deploying. A deactivated or mis-typed admin is the main lock-out risk.

### 7.2 App builds that predate this branch (phase 2 only; phase 1 does not affect them)
These builds' behaviour is tested as denied under the candidate:
- Cashier dashboard figures, Today's Sales, Daily Report, Bills History, Monthly Breakdown, Funds Received and the budget banner: they query by date **without a branch filter** and would show errors.
- Saving the **first credit bill for a new customer** and the **first cash closing of a day**: they read a missing document.
- Closing screen live updates.
- Cash closing payload from old builds is accepted (compatibility clause), billing, repayments, expenses, notices, menu add/edit work.
- Admin builds keep working.
There is no mechanism to force an update, so cashiers on old builds will see broken screens until they update.

### 7.3 Everything else
- **Other clients**: any script, web page, other app or console tool that uses this database relies on the open rules and will stop working unless it signs in as a valid admin. I could not see any.
- **Offline writes queued under the old rules** (an expense saved offline and not yet synced) are validated when they reach the server; ones that no longer comply would be rejected and show as failed in the sync strip.
- **Cashier delete of menu items** is gone (decision); old builds still show the button and will get a permission error.
- **Records without a `canteenId`** become invisible to non-admins until the backfill (the app's own queries already could not see them).

New build, new rules: no known workflow breaks. This is tested on the emulator, **not on a device**.

## 8. Deployment plan (NOT executed; every command is for you to run)
### 8.1 Pre-flight (read-only)
1. Firebase Console > Authentication > Users: look for accounts you do not recognise. Authentication > Settings: note whether sign-up is open.
2. Staff lock-out check: `node security-tests/legacy-audit.mjs --project canteen-app-adani --out audit.json` (needs `FIREBASE_API_KEY`, `FIREBASE_AUDIT_EMAIL`, `FIREBASE_AUDIT_PASSWORD` of an admin; read-only). In the `staff` section of the output you need `lockoutRisk: false`, `invalidRole: []`, and `inactive` / `unknownCanteen` / `cashierWithoutCanteen` that you recognise.
3. Optional but recommended: a managed Firestore export (Console > Firestore > Import/Export, or `gcloud firestore export`) before changing rules.
4. Confirm the files: `sha256sum proposals/firestore.rules.stopgap proposals/firestore.rules.candidate` equals section 2; `git status` clean.

### 8.2 Phase 1: stopgap (recommended as soon as 8.1 passes)
```
firebase deploy --only firestore:rules --config firebase.stopgap.json --project canteen-app-adani --dry-run   # optional compile check (if your CLI supports it)
firebase deploy --only firestore:rules --config firebase.stopgap.json --project canteen-app-adani
```
Verify immediately: sign in as an admin and as a cashier on the current app and use it (a bill, a report). Then confirm what is deployed: copy the Rules tab into `after.rules` and run `node tool/compare_rules.mjs --deployed-file after.rules --repo-file proposals/firestore.rules.stopgap` (exit 0). Rules propagate within about a minute.
**Rollback** (any time): `firebase deploy --only firestore:rules --config firebase.rollback.json --project canteen-app-adani`, or paste `backups/deployed.rules.2026-11-02.ORIGINAL` into the Console.

### 8.3 Index deployment and the new app build (existing plan)
Deploy the 5 indexes and wait for READY (FIRESTORE_RELEASE_CHECKLIST.md), then release the app build from this branch (it works with all three rule sets). Run the device test plan.

### 8.4 Phase 2: candidate (after most cashiers are on the new build)
1. Decide the grace period; you cannot measure adoption from here (Play Console may show it).
2. Re-run 8.1 steps 2 and 4.
3. `firebase deploy --only firestore:rules --config firebase.candidate.json --project canteen-app-adani`
4. Smoke test at once, with a **cashier of a non-main branch, a cashier of main, and an admin**: login; dashboard card; make a cash bill; make a credit bill for a brand-new customer; repay it; log an expense; submit the day's cash closing; open Today's Sales, Bills History, Funds, Notices, Add Item (no delete button); admin: dashboard, Analytics, export, staff list, send a notice. Check the app console for `permission-denied`.
5. Confirm deployed = candidate with `compare_rules.mjs` (exit 0).
**Rollback**: to the stopgap (`--config firebase.stopgap.json`) if only cashier screens break; to the original open rules (`--config firebase.rollback.json`) as a last resort. Rolling back to open rules re-opens the hole, so prefer the stopgap.

## 9. Test evidence
| Suite | Result |
|---|---|
| `flutter analyze` | no issues |
| `flutter test` | **240 passed** (includes the B-32 source guard) |
| Candidate permission suite `candidate-rules.test.mjs` | **97 passed**: deployed-vs-candidate attack matrix (19 scenarios, each open under the deployed rules and denied by the candidate), identity boundary (5 identities x all collections), privilege escalation, branch isolation for 8 collections, the main-branch leak regression (against candidate and, for contrast, the repository rules), the cashier and admin operation matrices, branch `main` end-to-end for 2 staff-record variants, financial protections, deny-by-default, B-32 behaviour, old-build compatibility and known breakage, documented residual risks |
| Older emulator suites (rules, paging, analytics, 26 financial-transaction tests, legacy audit) run with `RULES_FILE` against the candidate | **60 passed**, and the same 60 against the repository rules |
| Menu proposal suite | 10 passed |
| Stopgap suite | **9 passed**: staff unchanged, strangers shut out |
| Whole emulator suite, default rules | 176 passed |
| Rules diff tool | 9 passed (a parser bug that could return "no rules" for files with a long comment header was found and fixed, with regression tests) |
**Not tested:** any device; the production rules compiler (the emulator and production share the rules language, but `--dry-run` on production is the real check); the Android Firestore SDK; real latency; any other client of the database.

## 10. Residual risks the candidate cannot close alone
Rules cannot tell a real repayment from an arbitrary edit, so a cashier of a branch can still: set a customer balance of their own branch to any value >= 0; raise (never lower) their branch's daily totals; supply the closing's `systemCash`/`discrepancy`. Asserted as documented tests (group K). Mitigations today: every change leaves a bill/repayment trail; the admin master ledger reconciles. Phase-3 hardening ideas (need app changes): bind balance changes to a repayment/bill document with `getAfter()`, compute closing amounts server-side, create staff logins from a Cloud Function and then **disable open sign-up**, and enable App Check.

## 11. Decisions needed from you
1. Approve phase 1 (stopgap) and its timing. It is the smallest change that closes the internet exposure.
2. Grace period before phase 2, and whether stragglers on old builds are acceptable.
3. Who verifies the staff records (8.1) and Authentication > Users.
4. Whether to keep the transitional e-mail clause for closings after phase 2.
