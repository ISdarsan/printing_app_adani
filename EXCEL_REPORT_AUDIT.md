# Excel Report Audit (admin "Export Excel")

Code: `_exportExcelReport` in `lib/admin_dashboard_page.dart`; figures come from `lib/financial_metrics.dart` (`FinancialSummary`, `buildExecutiveSummaryRows`).

## Worksheets (all preserved)
Dashboard Summary, All Bills, one "<Branch> Bills" per branch, All Expenses, one "<Branch> Expenses" per branch, Credit Accounts, Repayment Logs, Cash Reconciliations, Top Selling Items. Column layouts of every sheet other than Dashboard Summary are unchanged.

## Dashboard Summary: before and after

| Before | After | Change |
|---|---|---|
| Overall Revenue (All Branches) | same | unchanged (sales only) |
| Cash Collected | **Cash Sales** | renamed; same value (cash bills only) |
| UPI Collected | **UPI Sales** | renamed; same value |
| Credit Issued | same | |
| - | **Cash Repayments**, **UPI Repayments** | new |
| Total Credit Repayments Received | same | now = cash + UPI + other-mode repayments |
| - | **Total Cash Received**, **Total UPI Received** | new = sales + repayments in that mode; equal to `dailyStats` totalCash/totalUpi |
| Total Credits Still Due | same | |
| Overall Expenses | same | |
| Cumulative Cash Discrepancy | same | |
| Net Position (Sales + Repayments - Expenses) | **removed** | double counted repaid credit |
| - | **Accrual Operating Position (Sales - Expenses)** | new |
| - | **Cash-Basis Movement (Received - Expenses)** | new |
| - | **Credit Check (Issued - Repaid - Still Due)** | new; should be 0 |
| - | optional row "Repayments (other / unrecorded mode)" | appears only if a repayment has a mode other than Cash/UPI |

New third column **Basis / Formula** explains every row in words. Neither position is called profit; both formulas end with "Not a profit figure".

Branch-wise breakdown keeps its four original columns (Branch, Sales, Bills Count, Expenses) and appends Cash Sales, UPI Sales, Credit Issued, Cash Repayments, UPI Repayments, Accrual Operating Position, Cash-Basis Movement, computed per branch from the same records.

Timestamps in every sheet and the "Report Generated" line are now IST (UTC+05:30), stated on the summary sheet; the file name date uses the business date.

## Formulas
- Accrual Operating Position = Sales Revenue (cash + UPI + credit) - Expenses. Repayments are not added.
- Cash-Basis Movement = Cash Sales + UPI Sales + Cash Repayments + UPI Repayments - Expenses. Unpaid credit excluded until repaid.
- Difference between the two = credit still outstanding (tested).
- Old formula overstated by exactly the total repayments (tested).

## Reconciliation with source data
Verified by unit tests on hypothetical data: Total Cash/UPI Received, Total Credit Repayments, Overall Revenue and Credit Issued each equal the value produced by applying the same `dailyStats` writers to the same records; branch rows sum to the combined row.
The export does not read `dailyStats` itself, so a live cross-check of stored documents against the sheet needs the read-only drift check described in FINANCIAL_DATA_AUDIT.md (not run).

## Tested vs untested
- Tested: every number on the summary sheet (pure functions), labels, absence of the old labels, no "profit" wording, formula text present.
- Untested: actual workbook generation and sharing (the `excel` package cell writing, sheet layout, file sharing on a device). The cell-writing code was only compile-checked by `flutter analyze`. Please export once and open the file.
- Unchanged and still heavy: the export downloads whole collections (B-09).
