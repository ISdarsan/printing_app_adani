# Test Results

Branch `stabilize/audit-and-modernize`, release validation phase. All data synthetic. Nothing deployed, no production access, **no physical device used**.

| Suite | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **236 passed, 0 failed** |
| Firestore emulator suite (`security-tests/*.test.mjs`) against the repository rules | **68 passed, 0 failed** |
| The same 68 against the PROPOSED rules (`RULES_FILE=proposals/firestore.rules.menu-admin-delete`) | **68 passed, 0 failed** |
| `node --test tool/rules_diff.test.mjs` | 7 passed |
| `node tool/check_indexes.mjs` | OK: 19 registered queries -> 5 composite indexes, file declares 5 |
| `python tool/validate_workbook.py` (after `flutter test test/excel_report_builder_test.dart`) | 56 passed |

## Dart tests (236)
`widget_test` 9, `canteen_provider_staff` 3, `financial_metrics` 30, `business_time` 16, `business_day_ids` 5, `excel_report_builder` 14, `paged_fetch` 44, `analytics_equivalence` 24, `auth_flow` 18, `sync_status` 40, `today_summary` 12, `money_precision` 17, **`shared_fund_wording` 4 (new)**: shared-fund note text; cashier labels explicit and admin labels unchanged; the dashboard alert no longer calls the fund "this canteen's budget"; Add Item delete is admin-only in the app.

## Emulator tests (68)
| File | Tests | Covers |
|---|---|---|
| `firestore.rules.test.mjs` | 13 | rules, scoped query shapes, B-19 shapes, create-once field and checks, idempotent expense |
| `export-paging.test.mjs` | 7 | document-cursor paging with ties, negative control, period range |
| `analytics-queries.test.mjs` | 7 | analytics query shapes and branch isolation |
| **`transactions.test.mjs`** (new) | **26** | **Tasks 4 and 5**: bill and repayment workflows, double tap, concurrency, lost acknowledgement, retry with the same request id, real network cut, balances, closings, offline expenses (details in TRANSACTION_INTEGRATION_REPORT.md) |
| **`legacy-audit.test.mjs`** (new) | **5** | **Task 6**: audit classification and counts on a synthetic legacy dataset; read-only |
| **`menu-delete-proposal.test.mjs`** (new) | **10** | **Task 7**: current vs proposed rules side by side |

## Task-by-task status
| Task | Status | Evidence |
|---|---|---|
| 1 Index release | **Verified, ready; NOT deployed** | `check_indexes.mjs` OK (19 queries, 5 indexes); file has exactly 5 entries and no `fieldOverrides`; project `canteen-app-adani` in `firebase.json` and `firebase_options.dart`; no `.firebaserc` so every command must pass `--project`; production has 0 indexes (read-only listing) so no index can be deleted |
| 2 Rules comparison | **NOT PERFORMED: `deployed.rules` was not supplied** | tool ready (7 tests); PRODUCTION_RULES_COMPARISON.md |
| 3 Cashier device testing | **NOT PERFORMED: no device, and indexes are not deployed** | CASHIER_DEVICE_TEST_PLAN.md (updated); every row NOT RUN |
| 4 Financial transaction integration | **Done on the emulator (port of the Dart logic)** | 26/26; limits stated in the report |
| 5 Offline reliability | **Done at protocol/SDK level on the emulator; NOT on a device** | offline-write, outage and reconnect tests; sync banner logic by 40 unit tests; no real airplane-mode run |
| 6 Legacy data audit | **Tool built and validated; production audit NOT run** | 5 tests; LEGACY_DATA_AUDIT.md |
| 7 Menu security | **Proposal + tests done; NOT deployed** | 10 tests + full suite against the proposal |

## NOT tested
- Anything on a physical device (login speed, layout, printing, real airplane mode, banner timing, Add Item delete gating on screen, the new fund wording on screen).
- The Dart code against the emulator (only a port plus unit tests), and the Android Firestore SDK behaviour.
- Production rules versus the repository; composite index build/READY state; legacy data in production.
- A network-level loss of only the commit acknowledgement (simulated at protocol level instead).
- Excel workbook opened in Excel/Sheets; LibreOffice recalculation.

## Environment notes
- Several emulator processes from earlier interrupted runs are still alive; every run used a fresh port through a temporary `firebase.test.json` (deleted afterwards). Suites read `FIRESTORE_EMULATOR_HOST` and `RULES_FILE`.
- The transaction suite takes about 65 s (two real connection cuts wait for the SDK to give up, about 12-14 s each).
