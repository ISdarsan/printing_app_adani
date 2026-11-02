# Test Results

Branch `stabilize/audit-and-modernize`, after the B-07 investigation pass.

| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | No issues found |
| Dart unit/widget tests | `flutter test` | 29 passed, 0 failed (9 original, 3 `canteen_provider_staff_test`, 17 `financial_metrics_test`) |
| Firestore rules (emulator) | `firebase emulators:exec --only firestore ... "cd security-tests && node --test"` | 9 passed, 0 failed (7 original, 2 new: cashier date-range queries need `canteenId`; own-branch `dailyStats` read by id) |

## What the new Dart tests cover (hypothetical data, no Firebase)
Cash/UPI/credit sales, cash/UPI repayments, combined collections, repayments not counted as sales, writer deltas vs source records, no double counting, drift detection, reconciliation shortage/surplus, monthly aggregation, cash-basis vs accrual vs legacy Excel net position.

## Not verified
- The Dart tests exercise the extracted pure functions and the shared delta helpers; the two Firestore transactions themselves were not run end to end (no Flutter-to-emulator integration test yet).
- Composite-index behavior is not enforced by the emulator, so the B-14 fix cannot be fully proven offline.
- Nothing was run on a device or against production.
- Emulator note: an earlier interrupted run left a Firestore emulator process (PID 13656) on port 8080; it was not stopped, and the rules suite was run on port 8085 instead. The suite now reads `FIRESTORE_EMULATOR_HOST`.
