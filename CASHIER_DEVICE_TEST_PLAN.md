# Cashier Device Test Plan

## Status: NOT EXECUTED. No physical cashier device was available.
Everything below is a plan to run by hand. **Nothing in this file has been tested on a device and no result is recorded.** What has been checked without a device: Firestore rules and query shapes on the emulator, widget behaviour in `flutter test`, and the arithmetic. None of that proves layout, real network behaviour, printing, or index availability.

## 0. Preconditions
1. The 5 indexes are `READY` (FIRESTORE_RELEASE_CHECKLIST.md section 4) and the rules comparison is done.
2. Install the build from branch `stabilize/audit-and-modernize` (release or profile mode, not debug).
3. Accounts (create in a TEST project or use clearly marked test staff; do not delete real data):
   - `cashier-A` on branch **A** (not `main`), `cashier-B` on branch **B**, `cashier-main` on `main`, one **deactivated** cashier, one admin.
4. Seed data (use the app itself, on the test branch):
   | Branch A | Contents |
   |---|---|
   | Bills today | Cash 100, Cash 50.50, UPI 200, Credit 300 (customer 9000000001) = 4 bills, revenue **650.50** |
   | Bills yesterday | 2 bills, 120 total |
   | Bills last month (admin can back-date via console on the TEST project) | 3 bills |
   | Bill at **23:55 IST** one day and **00:05 IST** the next | to check the day boundary |
   | Expense today | Gas 80, with proof photo |
   | Repayment | Cash 100 from customer 9000000001 |
   | Notice | one from admin to branch A, one to branch B |
   | Menu | 5 items for A, different items for B |
   | Cash closing | one submitted for yesterday |
   Branch B gets different numbers (for example one bill of 999) so leaks are obvious.
5. Phone settings to vary: smallest and largest available screen, system font size 100% and 150%, timezone **IST** and, once, a different timezone to confirm dates stay IST.

## 1. Screen-by-screen checks
Mark each: PASS / FAIL / NOT RUN, with device model, OS, build, tester, date.

### 1. Cashier dashboard (`/billing_dashboard`)
| Check | Expected |
|---|---|
| Open as cashier-A | "Today's Revenue" **₹651** (650.50 shown in whole rupees), "Bills Issued" **4**; only a dash while loading, never a made-up 0 |
| Make a new Cash bill of 40 | within a few seconds revenue **₹691**, bills **5** (the card is live) |
| Credit bill | counts in revenue and bills (sales), as before |
| Repayment of 100 | revenue and bills **do not change** (repayments are not sales) |
| cashier-B on another device | sees only branch B figures |
| Midnight | after IST midnight the card shows ₹0 / 0 for the new day (leave the app open across midnight once) |
| Budget banner | appears only if a monthly fund is set; "spent" equals the sum on Funds Received for the same month |
| Notice alert | a new notice for branch A pops once; one for branch B never does |
| Offline (airplane mode) | orange strip "Offline. Showing saved data..." ; figures are labelled by that strip as saved data |

### 2. Today's Sales
| Check | Expected |
|---|---|
| List | exactly branch A's 4/5 bills of today, newest first; totals pills Cash / UPI / Credit / Bills equal the list |
| Bill at 23:59 yesterday | not listed; bill at 00:00-00:05 today is listed |
| Tap a bill | detail opens with the right items |
| Empty branch / day | "No bills today yet." (not an error) |
| Error state | if you see red error text containing `failed-precondition`, the index is missing |

### 3. Daily Sales Report
Pick today, yesterday, a date with no bills, and the 23:55/00:05 pair: each date shows only its own bills; totals match Today's Sales for today. Date picker cannot pick the future.

### 4. Bills History (monthly)
Current month lists branch A bills; previous month shows its 3 bills; next month button disabled for the current month; header month label correct near month end (check on the 1st/last day if possible).

### 5. Monthly Breakdown
Per-day totals sum to the month's revenue; each day's total equals that day's Daily Report; days appear in ascending date order.

### 6. Funds Received
Month expenses list contains branch A expenses only, oldest first (unchanged); "spent" = sum of that list; previous months selectable; cashier cannot edit the fund (admin can). Note B-17: the fund itself is global.

### 7. Daily Cash Closing
| Check | Expected |
|---|---|
| Expected cash | equals Cash sales today + cash repayments today (not minus expenses; that is the approved rule) |
| Enter exactly the expected amount | status **Balanced** (this used to fail on some amounts because of rounding) |
| Enter 1 less / 1 more | Shortage / Surplus of 1.00 |
| Submit twice quickly | exactly one record; second tap ignored |
| Airplane mode, submit | clear failure, banner "1 change not saved"; reconnect, submit again: no "already submitted" confusion and one record |
| History list | shows branch A closings only (needs the cashReconciliations index) |
| Reopen after submit | "Reconciled for Today" view with the submitted values |

### 8. Notices
List shows only branch A notices, newest first, unread count on the bell matches; opening a notice marks it read (check with a second account that read state is per user); notice for branch B never appears.

### 9. Menu list / Add Item
Only branch A items, alphabetical; search works; add / edit price; delete asks confirmation (see B-20: whether a cashier may delete is a decision pending).

## 2. Cross-cutting checks
### Branch data and isolation
Compare cashier-A and cashier-B side by side on screens 1-9: no figure, bill, expense, notice or menu item from the other branch anywhere. The admin sees all branches.

### Historical bills and date filtering
Old bills (last month, last year if seeded) appear only under their own date/month; none missing or duplicated in the monthly list vs the daily lists.

### Expense visibility
An expense logged by cashier-A is visible to cashier-A (Funds Received, banner) and to the admin; not to cashier-B.

### Loading, empty and error states
For each screen: spinner or dash while loading; a friendly empty message with no data; with the network off the strip appears and no screen shows a fake zero. Take a screenshot of any red error text.

### Sync and duplicate protection (new in this phase)
| Scenario | Expected |
|---|---|
| Log an expense in airplane mode | after about 8 s: orange message "Saved on this device, not confirmed yet"; strip shows 1 change waiting; reconnect: strip disappears, expense appears once (check admin) |
| Log an expense, double tap Save | one expense |
| Save a bill with airplane mode on | red message "Bill not confirmed..."; cart kept; no bill exists. Reconnect, tap Save: exactly one bill |
| Save a bill, turn airplane mode on at the instant of tapping, then off, tap Save again | exactly one bill (the app checks the server for its own request id first) |
| Credit repayment, same two scenarios | exactly one repayment, customer balance reduced once |
| Strip tap | details sheet lists waiting/failed items; Retry only on expenses/notices, never on bills or repayments |
| Force-close the app with an expense queued offline, reopen online | expense is delivered once; strip shows briefly if it takes more than 1.5 s |

### Login speed (B-10)
Sign in as cashier, admin, deactivated cashier, wrong password, no network:
- cashier/admin reach their dashboard right after authorisation (previously +3 s). Time it: target well under 1.5 s on a good connection.
- deactivated: "This account has been deactivated." for about 2.5 s, then back to the login screen, signed out.
- wrong password: message under the button; button works again.
- no network: "Connection Error" then login screen.
- Tap Sign In several times quickly: one sign-in only.

### Printing (not changed in this phase, regression only)
Save a bill and print to the thermal printer; receipt total equals the bill total including paise (for example 150.50).

## 3. Results sheet
| # | Screen / scenario | Device | OS | Build | Result | Notes / screenshot |
|---|---|---|---|---|---|---|
| 1 | Dashboard | | | | NOT RUN | |
| 2 | Today's Sales | | | | NOT RUN | |
| 3 | Daily Report | | | | NOT RUN | |
| 4 | Bills History | | | | NOT RUN | |
| 5 | Monthly Breakdown | | | | NOT RUN | |
| 6 | Funds Received | | | | NOT RUN | |
| 7 | Cash Closing | | | | NOT RUN | |
| 8 | Notices | | | | NOT RUN | |
| 9 | Menu list | | | | NOT RUN | |
| X | Sync / duplicate scenarios | | | | NOT RUN | |
| X | Login | | | | NOT RUN | |

Sign-off requires every row PASS on at least one small and one large phone. Any `failed-precondition` text means a missing index; any `permission-denied` means a rules difference: stop and report it.
