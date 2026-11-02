# Release Candidate Report

Branch `stabilize/audit-and-modernize`, after the release validation phase.

## Verdict
**NOT YET a release candidate.** The code, tests and documents are in good shape, but three gates that only you can open are still closed. Nothing has been deployed and nothing has been tested on a physical device.

| Gate | Status | Who |
|---|---|---|
| G1 Production rules compared with the repository | **DONE: production rules are fully open (P0). Phase-1 stopgap and phase-2 candidate prepared and tested; NOT deployed** | you decide (PRODUCTION_SECURITY_MIGRATION.md) |
| G2 Five indexes deployed and READY | **OPEN: not deployed** | you (after confirmation) |
| G3 Cashier device test (nine screens + the added checks) | **OPEN: not performed** | you / a tester with a phone |
| G4 Code, tests, emulator evidence | **CLOSED: green** | done |

A release should not go out until G1-G3 are closed, because G1 decides how serious bug B-32 is in production and G2 is a hard prerequisite for the cashier screens.

## What this phase added
| Area | Outcome |
|---|---|
| Business decision 1 (no offline billing) | Behaviour confirmed and tested: with the connection cut, a bill or repayment fails, nothing is saved and nothing is queued; the same request id then saves exactly once. |
| Decision 2 (fund is organisation-wide) | Cashier screens now say so (title, labels, shared-fund note, dashboard alert wording). Numbers unchanged. Admin screens unchanged. |
| Decision 3 (menu delete admin-only) | App: delete button hidden for cashiers. Rules: **proposal only**, one line, tested (10 + the whole suite of 68 against it). |
| Decision 4 (backfill needs an audit first) | Read-only audit tool built and validated on synthetic legacy data. **No production audit run, no migration.** |
| Index release | Verified: exactly 5 indexes, 19 registered queries, correct project, no deletion possible. |
| Financial integration testing | 26 emulator tests with fault injection; duplicate prevention made structural. |
| **New finding (B-32)** | Cashiers cannot read documents that do not exist under the repository rules; several released flows do. Code now works either way. |

## Evidence
`flutter analyze` clean; 236 Dart tests; 68 emulator tests (also 68 against the proposed rules); 7 rules-diff tests; index checker OK; 56 workbook checks. Details and what each does *not* prove: TEST_RESULTS.md, TRANSACTION_INTEGRATION_REPORT.md.

## Risks that remain
1. **B-32 in production is unknown.** If production rules equal the repository, then before this build a cashier could not save the first credit bill to a new customer, nor submit the day's first cash closing. If production rules differ, those flows worked. The rules comparison answers this in minutes.
2. **The Dart code has never run against Firestore in a test** (only unit tests and a faithful Node port). The Android SDK behaviour (transaction timeout, retry) is unobserved.
3. **Indexes not built.** Until READY, the nine cashier screens fail with `failed-precondition` (the three existing-query screens may already be failing).
4. **Cashier behaviour changes** to announce: no delete button in Add Item; fund wording; sync strip; login without the 3 s wait; credit repayments accept the exact balance.
5. Legacy records without `canteenId`/`date` are still invisible to branch-scoped queries; production extent unknown.
6. The request id for an in-progress bill lives in memory; killing the app mid-save loses the link, so check Today's Sales before re-entering.

## Decisions still needed from you
- Supply `deployed.rules` (G1).
- Confirm and run the index deployment (G2).
- Treatment of unrecoverable legacy records (assign to `main`?) and whether medium/low-confidence records need manual confirmation.
- When to deploy the menu-delete rule (after G1, applied to the verified deployed rules).

## Files changed in this phase
**App code (9):** `lib/print_bill_page.dart` (document id = request id, no read of a missing customer, customer-exists query), `lib/credit_detail_page.dart` (document id = request id), `lib/cash_reconciliation_page.dart` (query-based today streams, query-then-create-only closing), `lib/billing_dashboard_page.dart` (own-branch query for the card, fund alert wording), `lib/funds_received_page.dart` (cashier fund wording + note), `lib/add_item_page.dart` (delete admin-only), `lib/money.dart` (`kSharedFundNote`), plus imports.
**Tests (7):** `security-tests/transactions.test.mjs` (26), `legacy-audit.test.mjs` (5), `menu-delete-proposal.test.mjs` (10); `test/shared_fund_wording_test.dart` (4); `RULES_FILE` support in `firestore.rules.test.mjs`, `export-paging.test.mjs`, `analytics-queries.test.mjs`.
**Tools / proposals (3):** `security-tests/legacy-audit.mjs`, `proposals/firestore.rules.menu-admin-delete`, `tool/check_indexes.mjs` (19-query registry).
**Documents:** new `TRANSACTION_INTEGRATION_REPORT.md`, `LEGACY_DATA_AUDIT.md`, `MENU_SECURITY_CHANGE_PROPOSAL.md`, `RELEASE_CANDIDATE_REPORT.md`; updated `BUG_REGISTER.md`, `TEST_RESULTS.md`, `FIRESTORE_RELEASE_CHECKLIST.md`, `CASHIER_DEVICE_TEST_PLAN.md`.
**Unchanged:** `firestore.rules`, `firestore.indexes.json`, `firebase.json`, all production Firebase state.

## Go / no-go checklist
- [ ] G1 rules comparison reviewed (no unexplained difference)
- [ ] G2 five indexes READY
- [ ] G3 device test sheet all PASS on a small and a large phone, including A1-A12
- [x] G4 analyze, unit, emulator and tool suites green
- [ ] Owner sign-off on the cashier-visible changes listed under Risks
- [ ] Play Store release of the app build (not started, not requested)
- [ ] Menu-delete rule deployment (separate, later)
- [ ] Legacy backfill (separate project)

UI redesign has not been started.

---

## Update after the production rules comparison
- **G1 is closed in the sense that the answer is known, and it is a P0 finding:** production Firestore rules allow any signed-in account to read and write everything. Do not wait for G2/G3 to address this: the phase-1 stopgap rules change nothing for real staff and close the exposure.
- B-32 is confirmed relevant: the candidate rules deny cashier reads of missing documents, which today's open rules allow. The app no longer depends on such reads (guarded by a test).
- The repository rules were found to be unsafe as written (main-branch leak, cash-closing mismatch); both are fixed in the candidate.
- Remaining gates unchanged: indexes (G2) and device testing (G3). Rules phase 2 must wait for adoption of the new app build.
