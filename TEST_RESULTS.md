# Test Results

Branch `stabilize/audit-and-modernize`, after the Q1-Q4 / B-17 / B-18 phase.

| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | No issues found |
| Dart tests | `flutter test` | 63 passed, 0 failed |
| Firestore rules + query shapes (emulator) | `firebase emulators:exec --only firestore ... "cd security-tests && node --test"` | 10 passed, 0 failed |

## Dart tests by file
| File | Tests | Covers |
|---|---|---|
| `test/widget_test.dart` | 9 | original suite (id helpers, bill items, receipt text, routing). One test made timezone-independent |
| `test/canteen_provider_staff_test.dart` | 3 | branch/role assignment (B-01) |
| `test/financial_metrics_test.dart` | 30 | cash/UPI/credit sales; cash/UPI repayments; combined collections; repayments never revenue; writer deltas vs source records; no double counting; drift detection; reconciliation shortage/surplus; monthly and branch aggregation; **Q2** expected cash ignores expenses, expenses reduce both positions; **Q3** accrual = sales - expenses, cash basis = received - expenses, credit raises accrual only until repaid, difference = outstanding credit, legacy formula double count demonstrated; **Q4** new/removed labels, sales vs repayment separation, Total Cash/UPI Received equal `dailyStats`, no "profit" wording, formula text on every row, other-mode repayments shown |
| `test/business_time_test.dart` | 15 | `[start, nextStart)` boundaries, 23:59:59.5 no longer lost, midnight in IST vs UTC, month ends (Oct/Nov, Dec/Jan, leap February), months tile with no gap, lookback across year end |
| `test/business_day_ids_test.dart` | 5 | dailyStats / reconciliation id at 23:59:59.999 vs 00:00 IST, month-end and year-end ids, bill/day-range/id agreement, branch scope helper |

## Emulator tests (`security-tests/firestore.rules.test.mjs`)
10 tests: the 7 original, plus
- cashier date-range queries on `bills` and `expenses` are **denied without `canteenId`** and **allowed with it** (B-14);
- exact query shape of the six screens (`canteenId ==` + `>= start` + `< nextStart` + optional `orderBy`): 2 Nov includes 23:59:59.500 and 23:59:59.999, excludes 3 Nov 00:00 and 1 Nov; 3 Nov starts exactly at midnight; the month range loses nothing and counts nothing twice; a cashier cannot scope to another branch; admin's unscoped query sees all branches;
- cashier reads only their own `dailyStats` document by id.

## Tested vs NOT tested
Tested: pure financial arithmetic and report rows; IST boundaries and ids; Firestore rules and query shapes against the emulator.

Not tested (be aware before release):
- **Composite indexes**: the emulator does not enforce them. Whether the six screens work in production depends on deploying `firestore.indexes.json` first.
- **Deployed rules** versus repository rules: not compared (no way to read them from here; commands in FIRESTORE_INDEX_AUDIT.md).
- **Excel workbook generation and sharing**: cell writing, layout and the share sheet were never executed; only the numbers and labels (pure functions) were tested. Please export one file and open it.
- The screens themselves (widgets) with a Firestore backend: no Flutter-to-emulator integration test exists; the screen code was compile-checked and its query shapes tested separately.
- Bill and repayment transactions end to end, offline/reconnect behavior, printing, anything on a physical device or against production data.
- Non-IST phones (the logic is timezone-independent by construction and unit-tested with UTC instants, but no device in another timezone was used).

## Environment notes
- A Firestore emulator from an earlier interrupted run (PID 13656, port 8080) and another from a later run were left running; a request to stop one was blocked. Tests ran on other ports (8091/8092). The suite reads `FIRESTORE_EMULATOR_HOST` if set.
