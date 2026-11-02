# Excel Workbook Validation

Status: **a real .xlsx was generated from synthetic data and inspected with two independent readers.** LibreOffice recalculation was **not** possible (not installed). Nothing here uses production data.

## What was generated
`flutter test test/excel_report_builder_test.dart` runs `ExcelReportBuilder.build(...)` (the same function the app's export now calls) on a hand-made dataset and writes:

- `build/validation/synthetic_report.xlsx` (14.5 KB, valid zip/OOXML)
- `build/validation/synthetic_source.json` (the raw records, for the independent check)

The dataset: 2 branches (`main`, and `north` with a deliberately awkward name `North: Block/A [Annex] Campus Canteen Long Name`), 8 bills (Cash/UPI/Credit, one untagged legacy bill, bills at 23:59:59 IST on 31 Oct and 00:00:00 IST on 1 Nov), 3 expenses (one untagged, one with a proof image field), 3 repayments (Cash, UPI, Cash), 2 credit customers, 2 cash closings, quantities given both as numbers and as strings.

## How it was inspected
| Reader | What it checked | Result |
|---|---|---|
| Dart `excel` package (decode the produced bytes, test file) | 14 tests: sheets, column headers, row counts, IST text, all summary numbers, branch rows, top items | 14 passed |
| Python `openpyxl` 3.1.5 (`tool/validate_workbook.py`), a different XLSX implementation | 56 checks. Every number is **recomputed from the raw records with separate arithmetic** and compared with the cell in the file | **56 passed, 0 failed** |
| LibreOffice headless recalculation | would verify formula results | **NOT RUN: LibreOffice is not installed here.** See "Formulas" below |
| Microsoft Excel / Google Sheets / a phone previewer | visual check | **NOT RUN (pending, needs a human)** |

Re-run: `flutter test test/excel_report_builder_test.dart && python tool/validate_workbook.py`.

## Findings against your checklist
| Requirement | Result | Evidence |
|---|---|---|
| All expected worksheets exist | PASS | Dashboard Summary, All Bills, one Bills sheet per branch, All Expenses, one Expenses sheet per branch, Credit Accounts, Repayment Logs, Cash Reconciliations, Top Selling Items (11 sheets for 2 branches) |
| Existing columns preserved | PASS | Original column titles are at their original positions on every data sheet. New columns are appended only (Canteen Branch on Credit Accounts, Repayment Logs, Cash Reconciliations; extra branch columns on the summary) |
| Cash Sales / UPI Sales separate | PASS | 950.50 / 650.25 |
| Cash Repayments / UPI Repayments separate | PASS | 290.00 / 100.00 |
| Total Cash Received | PASS | 1240.50 = 950.50 + 290.00 |
| Total UPI Received | PASS | 750.25 = 650.25 + 100.00 |
| Accrual Operating Position | PASS | 1950.00 = 2200.75 revenue - 250.75 expenses |
| Cash-Basis Movement | PASS | 1740.00 = 950.50 + 650.25 + 290.00 + 100.00 - 250.75 |
| Credit Check equals zero | PASS | 600.00 issued - 390.00 repaid - 210.00 due = 0.00 |
| Branch breakdowns consistent | PASS | Main 1700.00 / North 500.75 sum to 2200.75; per-branch positions recomputed; branch Bills/Expenses sheets together hold every record exactly once |
| IST dates and times | PASS | UTC instants rendered as IST; the 23:59 / 00:00 boundary bills land on 2026-10-31 23:59 and 2026-11-01 00:00; the "Report Generated" line is IST |
| Nothing missing | PASS | Row counts equal source counts on every sheet; no error values (`#REF!` etc.); every summary row has a non-empty explanation |
| No "profit" wording | PASS | The two positions say "Not a profit figure" |
| Old labels removed | PASS | No "Cash Collected" / "UPI Collected" |
| Professional, readable formatting | PASS (structure) | Bold white-on-navy header rows with a taller height, explicit column widths (not the 8.43 default), 2-decimal number format on all money cells, wrapped explanation column, bold key rows. **Not visually confirmed in a spreadsheet application** |

## Formulas
The workbook deliberately contains **no formulas** (verified: 0 formula cells). Values are written directly and the "Basis / Formula" column explains each row in words. Reason: the `excel` package cannot store cached results for formulas, and phone previewers and some share targets show blank/0 for formula cells that have never been calculated. Consequently LibreOffice recalculation has nothing to recalculate; the equivalent check was done by recomputing every figure from source records in Python.

If you would like live formulas (so a reader can audit the sheet in Excel), that is possible but would need a decision about the previewer risk above.

## Defects found and fixed during validation
- Per-branch sheet names: an illegal character (`: / [ ]`) or more than 31 characters would have produced a corrupt sheet, and two branches whose names share a prefix would have been merged into one sheet. Names are now sanitised, whitespace-collapsed, truncated to 31 characters and made unique.
- Money cells were stored as raw doubles (e.g. 1699.9999999). They are rounded to 2 decimals.

## Not validated
- Opening the file in real Excel / Google Sheets / a phone viewer (visual layout, column wrapping on a small screen).
- Generating the file **inside the running app** (Firestore loader, progress dialog, share sheet). Those parts compile and are covered by separate paging tests, but were never executed on a device.
- A realistically large workbook (50k+ rows): see EXPORT_OPTIMIZATION_REPORT.md for what was and was not measured.
