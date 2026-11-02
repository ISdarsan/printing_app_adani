"""Independent validation of the generated Excel report.

Reads build/validation/synthetic_report.xlsx with openpyxl (a different XLSX
reader from the Dart `excel` package) and recomputes every figure from the raw
synthetic records in synthetic_source.json using its own arithmetic.

Run:  flutter test test/excel_report_builder_test.dart
      python tool/validate_workbook.py
Exit code 0 = all checks passed.
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent / "build" / "validation"
IST = timezone(timedelta(hours=5, minutes=30))
failures = []
passed = 0


def check(name, cond, detail=""):
    global passed
    if cond:
        passed += 1
        print(f"PASS  {name}")
    else:
        failures.append(name)
        print(f"FAIL  {name} {detail}")


def close(a, b, tol=0.005):
    return abs(a - b) <= tol


src = json.loads((ROOT / "synthetic_source.json").read_text(encoding="utf-8"))
wb = openpyxl.load_workbook(ROOT / "synthetic_report.xlsx")  # formulas not evaluated
wbv = openpyxl.load_workbook(ROOT / "synthetic_report.xlsx", data_only=True)
names = wb.sheetnames
print("Sheets:", names)

bid = lambda r: (r.get("canteenId") or "main")

# ---------- independent recomputation ----------
bills, exps, reps = src["bills"], src["expenses"], src["repayments"]
rev = sum(b["totalAmount"] for b in bills)
by = lambda mode: sum(b["totalAmount"] for b in bills if b["paymentMode"] == mode)
cash_s, upi_s, credit_s = by("Cash"), by("UPI"), by("Credit")
rep_by = lambda m: sum(r["amount"] for r in reps if r["paymentMode"] == m)
cash_r, upi_r = rep_by("Cash"), rep_by("UPI")
rep_all = sum(r["amount"] for r in reps)
expense_total = sum(e["amount"] for e in exps)
due = sum(c["totalPending"] for c in src["credits"])
disc = sum(r["discrepancy"] for r in src["recons"])
expected = {
    "Overall Revenue (All Branches)": rev,
    "Cash Sales": cash_s,
    "UPI Sales": upi_s,
    "Credit Issued": credit_s,
    "Cash Repayments": cash_r,
    "UPI Repayments": upi_r,
    "Total Credit Repayments Received": rep_all,
    "Total Cash Received": cash_s + cash_r,
    "Total UPI Received": upi_s + upi_r,
    "Total Credits Still Due": due,
    "Overall Expenses": expense_total,
    "Cumulative Cash Discrepancy": disc,
    "Accrual Operating Position (Sales - Expenses)": rev - expense_total,
    "Cash-Basis Movement (Received - Expenses)": cash_s + upi_s + cash_r + upi_r - expense_total,
    "Credit Check (Issued - Repaid - Still Due)": credit_s - rep_all - due,
}

# ---------- worksheets ----------
for required in ["Dashboard Summary", "All Bills", "All Expenses", "Credit Accounts",
                 "Repayment Logs", "Cash Reconciliations", "Top Selling Items"]:
    check(f"sheet exists: {required}", required in names)
check("per-branch Bills sheets (2)", len([n for n in names if n.endswith(" Bills") and n != "All Bills"]) == 2)
check("per-branch Expenses sheets (2)", len([n for n in names if n.endswith(" Expenses") and n != "All Expenses"]) == 2)
check("sheet names valid (<=31, no illegal chars, unique)",
      all(len(n) <= 31 and not re.search(r"[:\\/?*\[\]]", n) for n in names) and len(set(names)) == len(names))

# ---------- dashboard values ----------
ds = wbv["Dashboard Summary"]
rows = {}
for r in range(5, 40):
    label = ds.cell(r, 1).value
    if not label:
        break
    rows[label] = (ds.cell(r, 2).value, ds.cell(r, 3).value)
for label, exp in expected.items():
    got = rows.get(label, (None, None))[0]
    check(f"summary '{label}' = {exp:.2f}", got is not None and close(got, exp), f"got {got}")
check("no row labelled 'Cash Collected' / 'UPI Collected'", "Cash Collected" not in rows and "UPI Collected" not in rows)
check("the word 'profit' is not used as a metric name", not any("profit" in k.lower() for k in rows))
check("all rows have a formula explanation", all(v[1] for v in rows.values()))
check("position rows state 'Not a profit figure'",
      all("Not a profit figure" in rows[k][1] for k in rows if "Position" in k or "Movement" in k))
check("Credit Check equals zero", close(rows["Credit Check (Issued - Repaid - Still Due)"][0], 0))
check("accrual - cash-basis == credit still outstanding (issued - repaid)",
      close(rows["Accrual Operating Position (Sales - Expenses)"][0] - rows["Cash-Basis Movement (Received - Expenses)"][0],
            credit_s - rep_all))

# ---------- branch breakdown ----------
brow = next(r for r in range(1, 80) if ds.cell(r, 1).value == "BRANCH-WISE BREAKDOWN")
hdr = [ds.cell(brow + 1, c).value for c in range(1, 12)]
check("branch header has original 4 + new columns", hdr[:4] == ["Branch", "Sales (INR)", "Bills Count", "Expenses (INR)"] and len(hdr) == 11, str(hdr))
branches = {}
r = brow + 2
while ds.cell(r, 1).value:
    branches[ds.cell(r, 1).value] = [ds.cell(r, c).value for c in range(2, 12)]
    r += 1
check("two branches listed", len(branches) == 2, str(list(branches)))
for bidv, nm in [("main", "Main Canteen"), ("north", src["canteenNames"]["north"])]:
    sb = [b for b in bills if bid(b) == bidv]
    sr = [x for x in reps if bid(x) == bidv]
    se = [e for e in exps if bid(e) == bidv]
    exp_row = [
        sum(b["totalAmount"] for b in sb), len(sb), sum(e["amount"] for e in se),
        sum(b["totalAmount"] for b in sb if b["paymentMode"] == "Cash"),
        sum(b["totalAmount"] for b in sb if b["paymentMode"] == "UPI"),
        sum(b["totalAmount"] for b in sb if b["paymentMode"] == "Credit"),
        sum(x["amount"] for x in sr if x["paymentMode"] == "Cash"),
        sum(x["amount"] for x in sr if x["paymentMode"] == "UPI"),
    ]
    exp_row += [exp_row[0] - exp_row[2], exp_row[3] + exp_row[4] + exp_row[6] + exp_row[7] - exp_row[2]]
    got = branches.get(nm)
    check(f"branch row '{nm[:20]}' matches recomputation",
          got is not None and all(close(g, e) for g, e in zip(got, exp_row)), f"got {got} exp {exp_row}")
check("branch sales sum to overall revenue", close(sum(v[0] for v in branches.values()), rev))

# ---------- data sheets: counts, IST, amounts ----------
def sheet_rows(name):
    ws = wbv[name]
    return [[c.value for c in row] for row in ws.iter_rows(min_row=2) if any(c.value is not None for c in row)]

ab = sheet_rows("All Bills")
check("All Bills row count", len(ab) == len(bills))
check("All Bills amounts sum", close(sum(r[6] for r in ab), rev))
src_ist = sorted(datetime.fromisoformat(b["timestamp"].replace("Z", "+00:00")).astimezone(IST).strftime("%Y-%m-%d %H:%M") for b in bills)
check("All Bills timestamps equal source instants converted to IST", sorted(r[0] for r in ab) == src_ist, str(sorted(r[0] for r in ab)))
check("Midnight edge: 23:59 on 31 Oct and 00:00 on 1 Nov present",
      "2026-10-31 23:59" in [r[0] for r in ab] and "2026-11-01 00:00" in [r[0] for r in ab])
check("legacy bill without canteenId shown under Main Canteen",
      any(r[1] == 3 and r[2] == "Main Canteen" for r in ab))
bb = sum(len(sheet_rows(n)) for n in names if n.endswith(" Bills") and n != "All Bills")
check("branch Bills sheets together hold every bill exactly once", bb == len(bills))
be = sum(len(sheet_rows(n)) for n in names if n.endswith(" Expenses") and n != "All Expenses")
check("branch Expenses sheets together hold every expense once", be == len(exps))
check("All Expenses total", close(sum(r[3] for r in sheet_rows("All Expenses")), expense_total))
rl = sheet_rows("Repayment Logs")
check("Repayment Logs count and total", len(rl) == len(reps) and close(sum(r[4] for r in rl), rep_all))
check("Repayment Logs has appended branch column", wbv["Repayment Logs"].cell(1, 7).value == "Canteen Branch")
check("Credit Accounts total due", close(sum(r[2] for r in sheet_rows("Credit Accounts")), due))
check("Cash Reconciliations discrepancy total", close(sum(r[3] for r in sheet_rows("Cash Reconciliations")), disc))
top = {r[0]: r[1] for r in sheet_rows("Top Selling Items")}
exp_top = {}
for b in bills:
    for it in b["items"]:
        exp_top[it["name"]] = exp_top.get(it["name"], 0) + int(it["quantity"])
check("Top Selling Items equals independent tally", top == exp_top, f"{top} vs {exp_top}")

# ---------- no formulas, no gaps, formatting ----------
n_formula = sum(1 for ws in wb.worksheets for row in ws.iter_rows() for c in row if c.data_type == "f")
check("workbook contains no formulas (values only, safe in previewers)", n_formula == 0)
check("no error values (#REF!, #VALUE!, ...)",
      not any(isinstance(c.value, str) and c.value.startswith("#") for ws in wbv.worksheets for row in ws.iter_rows() for c in row))
hdr_ok = all(ws.cell(1, 1).font.bold for ws in wb.worksheets if ws.title != "Dashboard Summary")
check("header rows are bold on every data sheet", hdr_ok)
check("header has filled background", wb["All Bills"].cell(1, 1).fill.fgColor.rgb not in (None, "00000000"), str(wb["All Bills"].cell(1, 1).fill.fgColor.rgb))
check("money cells use a 2-decimal number format", wb["All Bills"].cell(2, 7).number_format in ("0.00", "#,##0.00"), wb["All Bills"].cell(2, 7).number_format)
check("column widths set (not default 8.43)", (wb["All Bills"].column_dimensions["A"].width or 0) > 10)
check("summary label column is wide enough", (wb["Dashboard Summary"].column_dimensions["A"].width or 0) >= 40)

print(f"\n{passed} passed, {len(failures)} failed")
if failures:
    print("FAILED:", *failures, sep="\n  - ")
sys.exit(1 if failures else 0)
