# Test Results

Branch `stabilize/audit-and-modernize`, after the Excel validation / B-08 / B-09 / index review phase. All data in every test is synthetic.

| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | No issues found |
| Dart tests | `flutter test` | **145 passed, 0 failed** |
| Firestore emulator (rules, query shapes, paging, analytics queries) | `firebase emulators:exec --config <test config> --only firestore --project demo-test "cd security-tests && node --test"` | **25 passed, 0 failed** |
| Independent workbook check (openpyxl) | `flutter test test/excel_report_builder_test.dart && python tool/validate_workbook.py` | **56 passed, 0 failed** |

## Dart tests by file
| File | Tests | Covers |
|---|---|---|
| `test/widget_test.dart` | 9 | original suite (id helpers, bill items, receipt text, routing); one test made timezone-independent |
| `test/canteen_provider_staff_test.dart` | 3 | branch/role assignment (B-01) |
| `test/financial_metrics_test.dart` | 30 | sales/repayment arithmetic, dailyStats deltas, reconciliation, Q2 expense treatment, Q3 accrual vs cash basis, Q4 Excel summary rows, branch split |
| `test/business_time_test.dart` | 16 | IST day/month ranges, midnight and month-end boundaries, leap year, lookbacks |
| `test/business_day_ids_test.dart` | 5 | dailyStats/closing ids at midnight and month/year end, branch scope helper |
| `test/excel_report_builder_test.dart` | 14 | **generates a real .xlsx**, decodes it again, worksheets, columns, row counts, IST text, every summary figure, branch rows, top items |
| `test/paged_fetch_test.dart` | 44 | paging: 28 size/ties combinations with no skip/duplicate, order, negative control (timestamp-only cursor loses rows), duplicate drop, amounts reconcile after paging, 50,000-record run, row cap, transient/permanent failure, cancel, no infinite loop, export periods in IST (month/quarter/year ends, January) |
| `test/analytics_equivalence_test.dart` | 24 | new analytics vs the verbatim original on 2,500 synthetic bills: all-time and 5 windows, forecast, page-by-page feeding, branch isolation (main/north/south/legacy untagged), dailyStats totals/weekly/monthly/anomalies, 6-month window vs all time, IST period starts, modelled read volume |

## Emulator tests (`security-tests/*.test.mjs`, 25)
- `firestore.rules.test.mjs` (11): original rules coverage; B-14 date-range queries need `canteenId`; exact scoped half-open day/month query shapes with boundary bills; **B-19 query shapes** for cash-closing history, notices (with `limit(1)`) and menu list; own-branch dailyStats read.
- `export-paging.test.mjs` (7): 1,203 bills with 7 per timestamp paged with a document cursor in pages of 7/250/500 (every id exactly once), order, negative control, period range paged vs one-shot, admin-only.
- `analytics-queries.test.mjs` (7): window start inclusive/exclusive at the millisecond, concrete-branch server scope, main unscoped with untagged legacy bills, dailyStats windowed vs all-time (dateless legacy doc), expenses scoped ascending, cashier denied.
(11 + 7 + 7 = 25.)

## Workbook validation
Details in EXCEL_WORKBOOK_VALIDATION.md. Real file generated from synthetic data and read back by two independent XLSX readers.

## Tested vs NOT tested
Tested:
- All financial arithmetic and the Excel summary rows; the generated workbook's contents.
- Paging strategy on the real Firestore emulator and on a fake source; retries, cancel, row cap.
- Analytics maths equal to the original; period boundaries; branch isolation; query shapes and rules.

**Not tested (pending):**
- LibreOffice headless recalculation: **not installed here**. The workbook has no formulas, so the equivalent check was an independent Python recomputation.
- The file opened in real Excel / Google Sheets / a phone viewer (visual check).
- The Flutter UI of the export dialog, progress, retry, and of the Analytics page (period chips, refresh): compile-checked only.
- `ReportDataLoader`, `AnalyticsLoader` and `firestorePageFetcher` executed against Firestore from Dart: no Flutter-to-emulator integration test exists. Their query shapes are proven in Node; the Dart code is a thin wrapper.
- **Composite indexes**: the emulator neither builds nor enforces them.
- Deployed rules versus repository rules (tool written and tested on local files; live fetch not run).
- **B-19 on a real cashier device**: no device available. Rule outcomes are verified in the emulator only.
- Memory use and timing of a very large real export on a phone; Firestore billing figures (read counts are modelled on synthetic data).
- Bill/repayment transactions end to end, offline/reconnect behaviour, printing, anything against production.

## Environment notes
- A few Firestore emulator processes from earlier interrupted runs are still alive (ports 8080 and others); stopping them was blocked, so each run used a fresh port via a temporary `firebase.test.json` (deleted after each run). Tests read `FIRESTORE_EMULATOR_HOST`.
- `build/validation/` holds the generated workbook; it is git-ignored.
