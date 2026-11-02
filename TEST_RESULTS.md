# Test Results

Branch `stabilize/audit-and-modernize`, after phase 4 (release preparation, cashier reliability, sync, login, precision). All data is synthetic.

| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | No issues found |
| Dart tests | `flutter test` | **232 passed, 0 failed** |
| Firestore emulator (rules, query shapes, paging, analytics, create-once) | `firebase emulators:exec --config <temp config> --only firestore --project demo-test "cd security-tests && node --test"` | **27 passed, 0 failed** |
| Rules diff engine | `node --test tool/rules_diff.test.mjs` | **7 passed** |
| Index registry vs source vs `firestore.indexes.json` | `node tool/check_indexes.mjs` | OK: 15 queries -> 5 indexes, file declares 5 |
| Independent workbook check | `flutter test test/excel_report_builder_test.dart && python tool/validate_workbook.py` | 56 passed, 0 failed |

## Dart tests by file (232)
| File | Tests | Covers |
|---|---|---|
| `widget_test.dart` | 9 | original suite |
| `canteen_provider_staff_test.dart` | 3 | branch/role assignment |
| `financial_metrics_test.dart` | 30 | sales/repayment arithmetic, Q2-Q4 rules, Excel summary rows |
| `business_time_test.dart` / `business_day_ids_test.dart` | 16 / 5 | IST boundaries, ids at midnight and month end |
| `excel_report_builder_test.dart` | 14 | real .xlsx generated and inspected |
| `paged_fetch_test.dart` | 44 | paging with ties, retry, cancel, cap, 50,000 records, export periods |
| `analytics_equivalence_test.dart` | 24 | new analytics equals the original on 2,500 synthetic bills |
| **`auth_flow_test.dart`** (new) | 18 | **authentication routing**: admin/cashier/deactivated/missing/unknown role/read error decisions; role splash goes to the dashboard right after the lookup (no 3 s wait), denials never reach a dashboard and sign out; **login loading behaviour**: spinner, repeated taps start one sign-in, wrong password, unexpected error, sign-in alone never opens a dashboard |
| **`sync_status_test.dart`** (new) | 40 | **sync status, failed writes, reconnection, duplicate prevention**: every state; success only after acknowledgement; offline -> reconnect -> acknowledged; failure recording and retry (safe vs financial); duplicate keys; create-once (lost acknowledgement creates nothing); idempotent set; tracked writes; banner UI |
| **`today_summary_test.dart`** (new) | 12 | **daily stats consistency**: `dailyStats` card equals the bills query for sales / count / credit; repayments never change sales; collections = sales + repayments; equals the reconciliation figure; missing doc; deleted-bill drift detected; noise not reported; per-branch ids; midnight rollover |
| **`money_precision_test.dart`** (new) | 17 | **financial precision**: old vs new logic on 24,000 / 151,360 / 2,000 / 15,920 / 2,518,464 cases; `planRepayment` semantics and conservation; rounding; `BillItem`; `dailyStats` deltas; price display |

## Emulator tests (27)
`firestore.rules.test.mjs` (13): original coverage, B-14 scoped queries, half-open boundaries, B-19 shapes, **`clientRequestId` store + branch-scoped verification query (allowed) and unscoped/other-branch (denied)**, **idempotent expense: repeat of a committed create is denied for a cashier and a server read confirms it**, own-branch `dailyStats` read. `export-paging.test.mjs` (7) and `analytics-queries.test.mjs` (7) unchanged from phase 3.

## What each requested test area maps to
| Requested | Where |
|---|---|
| Sync status | `sync_status_test.dart` (states, message text, banner) |
| Failed writes | `sync_status_test.dart` (failure recording, retry rules, tracked-write failures) |
| Reconnection | `sync_status_test.dart` (offline/reconnect/flapping, restored writes) |
| Duplicate submission prevention | `sync_status_test.dart` (same key refused, create-once), `auth_flow_test.dart` (repeated sign-in taps), emulator (idempotent expense) |
| Daily stats consistency | `today_summary_test.dart`, `financial_metrics_test.dart` |
| Authentication routing | `auth_flow_test.dart` |
| Login loading behaviour | `auth_flow_test.dart` |
| Financial precision | `money_precision_test.dart` |

## Tested vs NOT tested
Tested: all pure logic above; widget behaviour against fakes; rules and query shapes on the emulator.

**Not tested (pending):**
- **Anything on a physical device**, including login speed, banner behaviour in real airplane mode, printing, layout (CASHIER_DEVICE_TEST_PLAN.md is not executed).
- **Production rules vs repository**: not compared (no token or pasted rules).
- **Composite indexes**: the emulator neither builds nor enforces them; deployed state unknown (production list was empty on 2 Nov 2026).
- The Firestore-bound code executed from Dart: `ConnectionProbe` (listener + `waitForPendingWrites`), `ReportDataLoader`, `AnalyticsLoader`, the bill and repayment create-once wiring inside the real transactions, `Source.server` staff lookup. Their decision logic is unit-tested and their query shapes proven in Node, but no Flutter-to-emulator integration test exists.
- Live fetch path of `tool/compare_rules.mjs --project` (only the file mode ran).
- LibreOffice recalculation of the workbook (not installed), opening the workbook in Excel/Sheets.
- Real menu-price exposure to the precision problems (menu data not visible here).

## Environment notes
- Emulator processes from earlier interrupted runs remain; each run used a fresh port through a temporary `firebase.test.json` (deleted afterwards). Tests read `FIRESTORE_EMULATOR_HOST`.
- `build/validation/` holds the generated workbook (git-ignored).
