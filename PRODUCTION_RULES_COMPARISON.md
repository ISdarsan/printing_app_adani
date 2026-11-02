# Production Rules Comparison

## Status: NOT PERFORMED (blocked on input)

The deployed Firestore rules could not be fetched in this session. The approved method needs one of two inputs and neither was available:

| Input | Available? |
|---|---|
| `FIREBASE_ACCESS_TOKEN` environment variable (short-lived token of your own account) | **No**, not set |
| A rules file copied from Firebase Console > Firestore > Rules | **No**, none provided |
| `gcloud` on this machine (to mint such a token) | **No**, not installed |

The Firebase CLI is signed in, but it has no command that prints deployed rules, and the only other route would be to extract its stored refresh token from disk. I did not do that: the approved method forbids reading credential files, and a stored refresh token is more powerful than the read-only access this task needs. **No comparison result exists, and none is claimed.** The repository rules are NOT known to match production.

## What is ready (so this takes about a minute for you)
`tool/compare_rules.mjs` now performs a true rule-by-rule comparison (functions, each collection, each `allow` statement; insensitive to comments, whitespace and line endings). It is read-only, never prints a token, has no deploy path.

Option A, no token needed:
1. Firebase Console > Firestore Database > Rules > select all > copy into a file `deployed.rules`.
2. `node tool/compare_rules.mjs --deployed-file deployed.rules`

Option B, token from your own shell (never written to disk by the tool):
```
gcloud auth print-access-token                      # run in your shell
$env:FIREBASE_ACCESS_TOKEN = "<token>"              # PowerShell
node tool/compare_rules.mjs --project canteen-app-adani
```
Exit code 0 = identical, 1 = differences (listed per element, `-` deployed / `+` repository), 2 = input or network problem.

Verified (offline): `node --test tool/rules_diff.test.mjs` passes 7/7: parses the real `firestore.rules` into 10 functions and 13 match blocks; reports CRLF/comment/whitespace-only changes as identical; reports a loosened `delete` on `bills` on exactly that collection and operation; reports collections present on only one side; reports a changed helper function; catches a flipped catch-all deny rule. **Not verified:** the live fetch path of option B (no token was available).

## Rule inventory of the repository (what the comparison will check)
23 elements: 10 helper functions, 12 collection matches, 1 catch-all.

| Element | Intent in the repository | Security meaning if production differed |
|---|---|---|
| `signedIn`, `staffPath`, `staffExists`, `staffData` | Identify the caller through `canteenStaff/{uid}` | A change here changes every rule that uses them |
| `activeStaff` | Staff document exists and `active` is not false | Weaker: deactivated staff keep access |
| `isAdmin` | active and `role == 'admin'` | Weaker: privilege escalation |
| `staffCanteenId` | Branch of the caller (default `main`) | Different default would move users between branches |
| `canReadBranch` / `canWriteBranch` | Admin, or same `canteenId` | **Branch isolation**; the core multi-canteen guarantee |
| `nonDecreasing` | Non-admins may only increase `dailyStats` counters | Weaker: cashiers could lower sales totals |
| `canteenStaff` | self-read; admin list/write | Looser: staff enumeration or self-promotion |
| `canteens` | admin only | |
| `menuItems` | branch read; create/update own branch (cannot change `canteenId`); **delete: any branch member (repository)** | Repository already lets a cashier delete menu items; production may be stricter (see B-20) |
| `bills` | branch read; create own branch with `createdBy == uid`; update only pending fields (non-admin); delete admin | Looser update/delete = tampering with sales |
| `dailyStats` | create with fixed key set; non-decreasing updates for non-admins; delete admin | Looser = a cashier could rewrite daily totals |
| `expenses` | branch read; create own; update/delete admin | |
| `creditCustomers` | branch read/create; non-admin update limited to `name`, `totalPending`, `lastUpdated` | Looser = phone/branch rewrite |
| `repayments` | branch read/create (`amount > 0`); update/delete admin | |
| `cashReconciliations` | branch read; create own (`submittedByUid == uid`); update/delete admin | Looser = closings editable after submission |
| `notifications` | branch read; admin create; `readBy` append-only update | |
| `monthlyFunds` | any active staff read; admin write | |
| `counters` | per-branch `billCounter_<branch>`; increment by exactly 1; no list | Looser = bill-number manipulation |
| `/{document=**}` | deny everything else | **If production allowed this, the whole database would be open** |

## How I will interpret a difference (decision guide)
- Production **stricter** than the repository: usually safe for security but may break app features (for example reads rejected for a screen the repository allows). I will map it to the screen and tell you.
- Production **looser**: a security finding; I will state the exact exposure and recommend deploying the repository version, but I will not deploy it. Deployment of rules always needs your explicit approval.
- Only in production: a collection the app does not know. I will list who can read it.
- Only in the repository: an unreleased rule. Check whether the app version in the Play Store depends on it.

## One known candidate difference
`menuItems` `delete` is `canReadBranch(...)` in the repository (any member of the branch can delete a menu item). Every other collection restricts delete to admins. If production says `isAdmin()` there, the Add Item screen's delete button would currently fail for cashiers. This is bug B-20 (needs your decision); it is listed here because it is the first thing I would expect the comparison to show.
