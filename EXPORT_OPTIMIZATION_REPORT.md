# Export Optimization Report (B-09)

## Problem
`_exportExcelReport` read five whole collections with one `get()` each (bills, expenses, repayments, cash closings, credit customers) and kept every `DocumentSnapshot` in memory. Expense documents carry a base64 proof photo, so the expenses read alone could be tens of megabytes. No progress, no cancel, no error recovery, and a failure left a stuck spinner or a generic message.

## What changed
| Area | Before | After |
|---|---|---|
| Scope | Everything, always | Admin picks a period: This month / Last 3 months / Last 12 months / All time (IST business months, `[start, end)`); All time is labelled "large, can be slow" |
| Reading | 5 unbounded `get()` | Cursor-paged reads (`lib/paged_fetch.dart` + `lib/report_data_loader.dart`): bills/repayments/closings/customers 500 per page, expenses 40 per page (photos) |
| Memory | Full snapshots retained | Each document is mapped immediately to a small record (`lib/report_records.dart`); photos and item arrays are dropped; top-selling items are tallied while paging |
| Pagination key | none | `orderBy timestamp desc` + `startAfter(lastDocument)`; Firestore's implicit document-id tiebreak keeps pages contiguous |
| Duplicates | n/a | Detected by document id and dropped (counted); expected 0 |
| Failures | one exception | Each page retried twice with backoff; then a clear error with a **Retry** button. **No partial file is ever shared** |
| Interruption | none | **Cancel** button; checked before every page |
| Offline | Could silently use cached data | Reads use `Source.server`: offline fails loudly instead of exporting a stale partial cache |
| Row guard | none | 200,000 rows per collection; if hit, the sheet period reads "(INCOMPLETE: row limit reached ...)" |
| Workbook | built inline in the widget | Pure `ExcelReportBuilder` (testable, validated, see EXCEL_WORKBOOK_VALIDATION.md) |
| Date formatting | device timezone | IST |

Preserved: every worksheet and column, the financial calculations (Q3/Q4 summary), branch breakdowns, share sheet behaviour, file naming (`Canteen_Report_<yyyyMMdd>_<period>.xlsx`).

## Verification
| Claim | How verified | Result |
|---|---|---|
| No record skipped or repeated | Fake Firestore-like source with 7 documents per timestamp, n in {0,1,7,499,500,501,1203}, page sizes {1,7,250,500} | 28 combinations pass |
| Same on real Firestore semantics | Emulator: 1,203 bills with tied timestamps, admin under real rules, pages of 7/250/500 | every id exactly once |
| Why the cursor must be a document | Negative control: a timestamp-only cursor | **loses rows** in both the fake and the emulator (test asserts the loss) |
| Period filter | Emulator: `timestamp >= start`, `< end`, `orderBy timestamp desc`, paged vs one-shot | identical sets; boundaries exact |
| Totals reconcile | 1,203 bills summed directly vs through pages; 8-bill workbook vs independent Python recomputation | equal within 1e-6 / 0.005 |
| Large dataset | 50,000 records, pages of 500 | 101 pages, 0 duplicates, completes in well under the 60 s limit (pure CPU, no network) |
| Retry / permanent failure / cancel / cap | unit tests | transient failure retried and result complete; permanent failure throws with the count reached; cancel stops before the next page; cap sets `truncated` |
| Admin only | Emulator | a cashier's unscoped export query is denied |

## Not verified / limitations
- The Firestore loader and the dialogs have **never run**: no device, no Flutter-to-emulator test. The query shapes and paging strategy are proven in Node against the emulator; the Dart adapter is a thin wrapper (`firestorePageFetcher`) that is compile-checked only.
- **Memory is bounded per page, not overall.** The `excel` package builds the whole workbook in memory and has no streaming writer. A 200,000-bill "All time" export may exhaust memory on a low-end phone. The period picker is the real control; 12 months is the sensible maximum for large branches. No memory profile was taken.
- Network time is not modelled: pages are sequential (about one round trip per 500 documents; expenses 40). Read *cost* (document reads) is unchanged for the same period; it drops only because the default periods are shorter than "all time".
- Firestore offers no field projection in this SDK version, so expense photos are downloaded and then discarded.
- Credit customers are "as of now" and ignore the period; cash closings and repayments follow it.
- A document written during the export (after its page was read) is not included; the export is a consistent-enough snapshot, not a transaction.
- Index needs: none new. Range plus `orderBy` on `timestamp` uses single-field indexes, and `creditCustomers.orderBy(totalPending)` is single-field.
