# Pre-Deployment Security Audit (phase 1 stopgap)

Date: 2 Nov 2026. Branch `stabilize/audit-and-modernize`. Scope: read-only checks before deploying `proposals/firestore.rules.stopgap`.

## Verdict
**NOT READY TO DEPLOY YET.** Items 9, 10 and 11 are answered below with evidence. **Items 1 to 8 (the production staff audit) could not be run from this session** because they need your admin login, which was not available here and which I will not ask you to paste into a chat. The tool is ready and takes one command in your own terminal (section 2). Deployment stays blocked until those numbers are reviewed.

## Constraints respected
- No Firebase CLI credential files were read. No credentials, tokens or passwords were requested, seen or printed.
- No production data was read or written. No rules, indexes or app were published or deployed.
- **One unintended side effect, disclosed:** I ran `firebase ext:list` as a read-only listing. The CLI printed *"missing required API firebaseextensions.googleapis.com. Enabling now…"*, i.e. **it attempted to enable the Firebase Extensions API on your production project.** I do not know whether the enabling completed (it printed "no extensions installed" afterwards). This enables no feature, creates no data and has no cost by itself, but it is a change to the project that I did not intend and should have avoided. To check or undo it: Google Cloud Console > APIs & Services > Enabled APIs > "Firebase Extensions API" > Disable. I will not use any CLI command again without first checking that it cannot change the project.

## Summary of the 11 items
| # | Item | Status | Result |
|---|---|---|---|
| 1 | Run the read-only staff audit | **NOT RUN** | needs your admin login (section 2) |
| 2 | Total staff accounts | **NOT RUN** | output field `totalStaffAccounts` |
| 3 | Active admins | **NOT RUN** | `activeAdmins` |
| 4 | Active cashiers | **NOT RUN** | `activeCashiers` |
| 5 | Inactive staff | **NOT RUN** | `inactiveStaff` + ids |
| 6 | Invalid or unexpected roles | **NOT RUN** | `invalidOrUnexpectedRoles` + ids |
| 7 | Missing `canteenId` | **NOT RUN** | `missingCanteenId` + ids (admins and cashiers separately) |
| 8 | At least one active admin | **NOT RUN** | `atLeastOneActiveAdmin` (the command exits with code 3 if false) |
| 9 | Stopgap supports every legitimate staff identity | **DONE (tested), one class to check** | section 3 |
| 10 | Admin can still create staff under the stopgap | **DONE (code + tests): yes** | section 4 |
| 11 | No other client depends on unrestricted access | **PARTLY: repository and project listings clean; the rest needs your confirmation** | section 5 |

## 1. What the audit does and does not touch
`security-tests/legacy-audit.mjs --staff-only` reads **only** the `canteens` and `canteenStaff` collections, with the client SDK, signed in as **your own admin account**, under the normal security rules (today's open rules allow it; the stopgap and candidate also allow admins). It imports no write function (a test asserts this). Its output has counts and Firebase UIDs only: no e-mail addresses, names or amounts (a test asserts there is no `@` anywhere in the output). The Firebase web API key it needs is public client configuration that already ships inside the app (`lib/firebase_options.dart`).

## 2. How to run it (in your own terminal; nothing is stored)
PowerShell, from the repository folder:
```
$env:FIREBASE_API_KEY="<the web apiKey from lib/firebase_options.dart>"
$env:FIREBASE_AUDIT_EMAIL="<your admin e-mail>"
$env:FIREBASE_AUDIT_PASSWORD="<your admin password>"
node security-tests/legacy-audit.mjs --staff-only --project canteen-app-adani --out staff-audit.json
Remove-Item Env:FIREBASE_AUDIT_PASSWORD
```
It prints:
```
totalStaffAccounts, activeAdmins, activeCashiers, inactiveStaff,
invalidOrUnexpectedRoles, missingCanteenId, atLeastOneActiveAdmin,
staffThatWouldBeLockedOutByStopgap
```
and saves `staff-audit.json` with the lists of document ids (in the `staff` and `staffIdsByRole` sections). You can send me that file or just the numbers: it contains no secrets.

Fallback with no tooling: Firebase Console > Firestore Database > `canteenStaff`, and check each document for `role` (exactly `admin` or `cashier`), `active` (absent or `true`), `canteenId`.

### How to read the result (gates for deploying the stopgap)
| Field | Needed for GO | If not |
|---|---|---|
| `atLeastOneActiveAdmin` | `true` | **STOP.** Nobody could administer; fix the staff record first |
| `staffThatWouldBeLockedOutByStopgap` | empty, or each id is a person who should indeed be locked out | see section 3 (non-boolean `active`) |
| `invalidOrUnexpectedRoles` | 0 or recognised ids | these users cannot log in to the app today anyway; fix or confirm |
| `missingCanteenId` | acceptable: cashiers without it act as branch `main` | confirm they are meant to be `main` |
| UIDs in Authentication > Users that are **not** in `staffIdsByRole` | none you care about | those accounts will lose all access (the point of the stopgap, for strangers; a problem for real staff) |

Decision 3 (you verify the Authentication list) is the other half of this: compare the Authentication UIDs with `staffIdsByRole`.

## 3. Item 9: does the stopgap support every legitimate staff identity?
Tested on the emulator (`security-tests/stopgap-rules.test.mjs`, 23 tests). For each staff-record shape: does it work today under the deployed rules, and what does the stopgap do?

| Staff record shape | Works today | Under the stopgap |
|---|---|---|
| admin with `canteenId`, no `active` field (what the admin dashboard creates) | yes | **keeps access** |
| cashier with `canteenId`, no `active` field (what the admin dashboard creates) | yes | **keeps access** |
| cashier without `canteenId` (acts as branch `main`) | yes | keeps access |
| admin without `canteenId` | yes | keeps access |
| `active: true` | yes | keeps access |
| `canteenId` of a branch that does not exist | yes | keeps access |
| role with the wrong case (`Admin`), or role missing | yes (the app itself refuses these at login) | keeps access (stopgap does not check roles) |
| `active: false` | yes | **access removed (intended)** |
| `active` stored as the **text** `"true"`, or `null`, or `1` | yes, and the **app lets them in** | **access removed (unintended lock-out)** |
| no staff record at all | yes | **access removed (the intended target; the app already says "role not found")** |

Also tested: for 3 identities (cashier of a branch, cashier of `main`, admin) a set of 9 operations, including those an old app build performs (unfiltered lists, reading a missing document, deleting, editing), gives **identical results under the deployed rules and under the stopgap**.

**The one class to check:** a staff record where `active` exists but is not a real boolean. The app only denies an explicit `false`, the stopgap (like the candidate) requires `== true`. The app never writes `active` itself (only reads it), so such values could only come from manual edits in the Console. The audit lists them under `nonBooleanActive` and in `staffThatWouldBeLockedOutByStopgap`. If any appear, either correct the value to `true`/`false` in the Console, or I can change the rule to deny only an explicit `false`. I have **not** changed the approved stopgap file for this.

Every user, including a deactivated one or one with no record, can always read their **own** staff record, so the app can explain why.

## 4. Item 10: can the admin still create staff accounts under the stopgap?
**Yes.** Read from `lib/admin_dashboard_page.dart` (around lines 2219 to 2241):
1. A second Firebase app ("StaffCreator") creates the login with `createUserWithEmailAndPassword` on **Firebase Authentication**, then signs out. Firestore rules do not apply to this step.
2. The staff record is written with `FirebaseFirestore.instance`, the default app, which is still signed in as **the admin**. The stopgap authorises it because the admin is an active staff member.

Replayed on the emulator with the app's exact payload (`email, role, canteenId, canteenName, createdAt`): the new login has no access until the record exists; right after the admin writes it, the new staff member can work; the admin can list, change the branch of and delete staff (a removed staff member loses access immediately). A **deactivated admin** and a **stranger** cannot create staff.

Side observation: this flow means **e-mail/password sign-up is enabled in the project**, which is how strangers could register under today's rules. After the stopgap, a self-registered account gets nothing, but the sign-up itself remains possible until it is disabled (a later hardening step that needs staff creation moved off the client).

## 5. Item 11: does any other legitimate client depend on unrestricted authenticated access?
| Source checked | Finding |
|---|---|
| Repository code | Only the Flutter app uses Firestore. No Cloud Functions folder, no scripts, no server code. The `security-tests` and `tool` folders are test tooling run against the emulator |
| `firebase apps:list` (read-only) | 4 registered apps, all builds of this codebase: Android, iOS, and two Web registrations named "windows" and "web" |
| Firebase Hosting | default site `canteen-app-adani.web.app` returns **404 "Site Not Found"** and has no Flutter bundle: no hosted web client exists |
| Cloud Functions | `firebase functions:list` **failed** ("Failed to list functions"), so I could not confirm either way; the repository has none |
| Extensions | none installed (see the disclosed side effect above) |
| Service accounts / Admin SDK | not affected: they bypass rules entirely; a stopgap cannot break them |

**What I cannot verify and only you can confirm:**
- Is the **Windows or web build** of the app used by anyone? They use the same code and sign in as staff, so they keep working, but they must sign in with a staff account.
- Does anyone run **scripts, spreadsheets, dashboards or other apps** that read or write this database while signed in as a *non-staff* account? Anything that signs in as an account without a `canteenStaff` record (a shared "kiosk", test or reporting login) would stop working. The Authentication list comparison (decision 3) is how to find such accounts.
- **Anonymous sign-in**: if any client uses anonymous authentication, it has no staff record and would lose access. The repository has no such code.

## 6. Decision 4: the e-mail compatibility clause
The clause (cash closings only) reads: the closing is accepted if `submittedByUid == the caller's uid`, **or** the caller's token has an e-mail and `submittedBy == that e-mail`.
- **It is bound to the authenticated identity.** `request.auth.token.email` is set by Firebase from the signed-in account; a client cannot set it. The create is also only allowed for an *active staff member of that branch*.
- To forge a colleague's name a person would need an account whose e-mail equals the colleague's. Firebase Authentication refuses a second account with an existing e-mail **when "One account per email address" is selected** (Authentication > Settings > User account linking). **Please confirm that setting.** If instead "multiple accounts per e-mail" is enabled, the clause is weaker.
- It does not require a *verified* e-mail, because staff logins are created by the admin and are not verified; requiring verification would break the very builds the clause exists for.
- **Removal:** your gate for phase 2 (14 days and all cashier devices migrated) means no old build remains when the candidate goes out, so the clause is unnecessary at that point. My recommendation is to deploy the candidate **without** it, unless the audit or the device inventory finds a client that still sends the older payload. I have not changed the candidate file; I will prepare that variant (and re-run the suite) when you approve.

## 7. What happens next (waiting for your approval)
1. You run the staff audit (section 2) and send the numbers or the file.
2. You compare Authentication > Users with `staffIdsByRole` and confirm the points in section 5 and the "one account per email" setting.
3. If all gates pass, you confirm and I prepare the exact stopgap deploy steps (the commands are already in PRODUCTION_SECURITY_MIGRATION.md 8.2). **I will not deploy anything without your explicit go-ahead.**

## 8. Files changed in this task (no production effect)
- `security-tests/legacy-audit.mjs`: `--staff-only` mode, richer staff report (missing `canteenId` for admins and cashiers, non-boolean `active`, ids by role), exit code 3 when no active admin.
- `security-tests/legacy-audit.test.mjs` (9 tests) and `security-tests/stopgap-rules.test.mjs` (23 tests): identity coverage matrix, staff-creation sequence.
- This document.
Tests: whole emulator suite **192 passed**. `proposals/firestore.rules.stopgap` and `proposals/firestore.rules.candidate` are unchanged (checksums as recorded in PRODUCTION_SECURITY_MIGRATION.md).
