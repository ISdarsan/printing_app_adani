# Optimization Plan

Priority order follows the master brief: data correctness, then crash/bug, then performance.

## Done
| Item | Where |
|---|---|
| B-05 dashboard recent-bills stream limited | pass 1 |
| B-06 weekly stats filtered on `date` | pass 1 |
| B-14 six cashier screens branch-scoped | pass 2 (needs index deploy) |
| B-18 half-open IST day/month ranges | pass 2 |
| **B-08 Analytics**: bounded paged reads, period selector (default 6 months), single-pass aggregation, equivalent to the original on synthetic data | this pass, ANALYTICS_OPTIMIZATION_REPORT.md |
| **B-09 Excel export**: period picker, cursor paging, retry/cancel, no partial file, pure workbook builder with professional formatting, validated on a real generated file | this pass, EXPORT_OPTIMIZATION_REPORT.md, EXCEL_WORKBOOK_VALIDATION.md |
| Index review incl. the three B-19 queries; rules-compare tool; release checklist | this pass |

## Done in phase 4
| Item | Where |
|---|---|
| Cashier dashboard card reads one `dailyStats` document instead of every bill of the day | `today_summary.dart`, `billing_dashboard_page.dart` |
| Index set reduced to the proven minimum (5) by making every bills query descending | `tool/check_indexes.mjs`, FIRESTORE_INDEX_AUDIT.md |
| B-10 login without the fixed 3 s wait | `role_routing.dart`, `role_splash_page.dart` |
| B-11 paise-based money logic, no migration | `money.dart`, FINANCIAL_PRECISION_AUDIT.md |
| B-12 sync strip, create-once financial writes, idempotent expenses/notices | `sync_status.dart`, `sync_banner.dart`, SYNC_RELIABILITY_REPORT.md |
| Rule-by-rule production comparison tool | `tool/rules_diff.mjs`, `tool/compare_rules.mjs` |

## Next (recommended order)
1. **You**: supply the deployed rules (PRODUCTION_RULES_COMPARISON.md), deploy the 5 indexes, run CASHIER_DEVICE_TEST_PLAN.md on a real phone. Until then B-14, B-19, B-12 and B-10 are verified only in emulator/unit tests.
2. **Decide**: whether to allow offline billing (needs an offline-safe bill numbering scheme), B-17 (global funds), B-20 (cashier menu delete), Q2 follow-ups.
3. **Flutter-to-emulator integration test** that runs `ReportDataLoader`, `AnalyticsLoader`, the bill create-once and the sync probe against the emulator (needs the Firebase test harness).
4. **Extend the sync tracker** to the remaining admin-only writes (menu, funds, staff, canteens) and to read receipts.
5. **Legacy backfill** (B-21/B-22), reviewed and backed up, so branch `main` can be scoped server-side.
6. **Admin dashboard today figures** from `dailyStats` for sales / credit / count. Not done now: its Cash/UPI cards are defined as sales-only while `dailyStats` cash/UPI include repayments, and `dailyStats` has no cash-repayment field to subtract.
7. UI redesign stage (not started).

## Principles
- No change that alters stored financial semantics without a decision.
- Every query change ships with an emulator test of its exact shape and an entry in the index registry.
- Every report change is compared with the previous implementation or independent arithmetic.
- Financial writes are never retried blindly; they are verified against the server first.
