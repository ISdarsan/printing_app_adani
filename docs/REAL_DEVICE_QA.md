# Real-Device QA Build

Built 2026-11-02 from branch `feature/ui-modernization-performance` (rebuilt after the loading/error fixes below; commit hash is in `git log`), clean working tree. Nothing was uploaded, no Firebase rules or indexes were deployed, no signing credential was changed or printed.

## The build

| Item | Value |
|---|---|
| APK path | `D:\app\printing_app_adani-master\build\app\outputs\flutter-apk\app-release.apk` |
| APK size | 62,384,344 bytes (59.5 MB) |
| APK SHA-256 | `2AF8893549F3B33D392752FB1766BF0E56D7694EB7E0313FF0538B5AE2F4FF5E` |
| AAB path (not for phones) | `D:\app\printing_app_adani-master\build\app\outputs\bundle\release\app-release.aab` |
| AAB size / SHA-256 | 61,739,343 bytes · `C7F633910D9AA76345CEA62BC539A63A7B2D1BEAE1379680BAA28B38B0AD2B9A` |
| Commands | `flutter build apk --release -t lib/main.dart` and `flutter build appbundle --release -t lib/main.dart`, both exit 0 |
| Application id | `com.adani.canteen_adani` |
| Version | 1.0.5, versionCode 6 |
| minSdk / targetSdk | 24 / 36 |
| Signature | Verified by `apksigner` (scheme v2). Signer `CN=Adani Canteen, OU=CSR, O=Adani, L=Ahmedabad, ST=Gujarat, C=IN`, RSA 2048, certificate SHA-256 `30fbaf8d9006ecb658b6ce2caa069ef7277762af3b5b6b2e27289084a5acb879`. This is the production signing certificate, **not** the debug key. |
| Firebase project | `canteen-app-adani`. `google-services.json` and `firebase_options.dart` both name it; Android package name in the config matches the application id. Android app id `1:1081372073317:android:a9de02d9171aa3c7ea158c`. |

The build output folder is git-ignored, so the APK is not in the repository. Copy it somewhere safe if you want to keep it.

## DONE 2026-11-02: Firestore indexes deployed

The 5 indexes below were deployed to `canteen-app-adani` with `firebase deploy --only firestore:indexes --config firebase.indexes.json --project canteen-app-adani` (you granted permission; exit 0, rules and data untouched). A read-only listing confirms all 5 exist. They may take a few minutes to finish building: check Firebase Console -> Firestore -> Indexes for **Enabled**, then tap *Try again* on any screen that still shows the setup message. The original explanation is kept below for the record.

## Why the indexes were needed (found during first QA run)

This build reads data with branch-filtered, date-ordered queries. Firestore needs **composite indexes** for them, and the production project does **not have them yet** because indexes have never been deployed. Without them these screens fail with `failed-precondition: The query requires an index` (the app now says "needs a one-time database setup, please tell the admin"): Daily Sales Report, Today's Sales, All Bills, Monthly breakdown, Expenses, Notices, Cash closing history, and the menu list with sorting.

The indexes are in `firestore.indexes.json` (5 of them, additive, they cannot lock anyone out and do not change any data or rules). Deploy them with:

```powershell
cd D:\app\printing_app_adani-master
node tool/verify_deploy_files.mjs indexes          # must end: ALL 11 CHECKS PASSED
firebase deploy --only firestore:indexes --project canteen-app-adani
```

Then wait in Firebase Console -> Firestore -> Indexes until all 5 show **Enabled** (usually a few minutes). Only then start QA. **This is a production change and was not run by me; it needs your decision.**

## READ BEFORE INSTALLING

1. **This build talks to the live production database.** Every bill, expense or repayment made during QA is real data in `canteen-app-adani`. Use clearly named test items and a test customer, keep amounts small, and agree how test records will be handled afterwards (do not delete production financial records casually).
2. **Production Firestore rules are still the open ones** until the stopgap is deployed. That is unchanged by this build.
3. The signing certificate is the production one, so this APK installs **over** the existing production app and keeps its data and login, if that app has the same certificate.

## Install (one phone at a time)

Enable *Developer options → USB debugging* on the phone and connect it. In PowerShell:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices                      # the phone must say "device", not "unauthorized"
Get-FileHash D:\app\printing_app_adani-master\build\app\outputs\flutter-apk\app-release.apk   # must equal the SHA-256 above
& $adb shell dumpsys package com.adani.canteen_adani | Select-String versionName,versionCode   # note what is installed NOW (write it down: this is your rollback target)
& $adb install -r D:\app\printing_app_adani-master\build\app\outputs\flutter-apk\app-release.apk
```

Without a cable: copy the APK to the phone and open it (allow "install unknown apps" for the file manager).

`install -r` replaces the app and keeps its data. Same version code (6) is allowed.

## Rollback

Android refuses to install a lower versionCode over a higher one, so rollback depends on what you saw in the "note what is installed NOW" step.

1. **Keep the previous APK before you start.** Pull it from the phone:
   ```powershell
   $p = (& $adb shell pm path com.adani.canteen_adani) -replace 'package:',''
   & $adb pull $p.Trim() D:\qa-backup\previous-base.apk
   ```
   (If the app was installed from a split bundle you will see several paths; pull them all and use `adb install-multiple`.)
2. **Same or higher versionCode previous build:** `& $adb install -r <previous.apk>`.
3. **Previous build had a lower versionCode (older app):** uninstall first, then install it:
   ```powershell
   & $adb uninstall com.adani.canteen_adani
   & $adb install D:\qa-backup\previous-base.apk
   ```
   Uninstalling removes only on-phone data (login, the remembered printer). Bills, customers and money live in Firestore and are unaffected. Staff must sign in again and re-pair the printer.
4. A bad data record created during QA is **not** rolled back by reinstalling; handle it in the Firebase Console with the admin.
5. Firestore rules rollback is separate and unchanged (`docs/FIRESTORE_RULES_ROLLOUT.md`).

## Real-device QA checklist

Mark each line Pass / Fail / Not tried and write what you saw. Test as the **cashier** account unless stated; also repeat the starred ones as **admin**.

### A. Install and start
- [ ] App installs, icon and name "FoodPrint" correct, opens without a crash.
- [ ] Cold start to login screen feels normal (note seconds on the oldest phone).
- [ ] Rotate the phone: app stays portrait.

### B. Login and accounts
- [ ] Wrong password shows a clear message. Empty fields show "Please enter your email and password."
- [ ] Keyboard "Next" moves to password; "Done" signs in.
- [ ] Cashier lands on the cashier dashboard, admin on the admin dashboard.
- [ ] A deactivated staff account is refused (use a test account, ask the admin to deactivate it).
- [ ] Sign out, sign in again, kill the app and reopen: still correct role.

### C. Billing (most important)
- [ ] Search an item, add it, change quantity with + / -, switch Full/Half, remove a line.
- [ ] A very long item name wraps and does not overflow the cart.
- [ ] Total shown equals the sum you expect, to the paisa (try 3 × 12.5 and a Half item).
- [ ] Cash, UPI and Credit each save. Credit asks for a customer and the pending balance rises by the right amount.
- [ ] Double-tap Save: only **one** bill is created.
- [ ] Bill number increases by one each time, no gaps or repeats.
- [ ] With the cart empty, Save does nothing.
- [ ] Turn on airplane mode and try to save: the app clearly says a connection is needed and does **not** show success. Turn it off: the next bill works.

### D. Printing and Bluetooth
- [ ] First use: Nearby-devices permission prompt appears (Android 12+), allow it.
- [ ] Pair and connect the real printer; receipt prints with correct items, total, date, bill number and alignment.
- [ ] Printer off during a print: app shows a clear failure, the bill is **not** duplicated on retry.
- [ ] Switch printer off/on, Bluetooth off/on, walk out of range and back: reconnects or tells you what to do.
- [ ] Kill the app and reopen: remembered printer reconnects.
- [ ] Deny the Bluetooth permission: message is understandable, app does not crash.

### E. Dashboards and reports
- [ ] Cashier dashboard: today's sales and bill count update after a bill and match Today's Sales page.
- [ ] Notice bell shows unread count and opens the notice.
- [ ] ★ Admin dashboard: today, month, pending credit and expenses cards load; switching the branch filter changes the numbers and does not freeze.
- [ ] Daily and monthly sales reports: change date/month, numbers match the bills.
- [ ] Turn on airplane mode while on a report: you see "Could not load" with **Try again**, not ₹0 or a blank. Turn it off, tap Try again: data returns.

### F. Money screens
- [ ] Credit customers: search, open a customer, see pending bills and repayment history.
- [ ] Take a small repayment (Cash and UPI): balance drops by exactly that amount; it appears in the repayment log; cash/UPI totals include it.
- [ ] Expenses: add one, it shows in Today and in the expense report.
- [ ] Funds: cashier sees "Organisation Fund" (shared by all canteens); admin sees the console. ★ Set a test fund only if agreed.
- [ ] **Cash closing:** the form shows "Loading…" until expected cash appears and the figure equals cash sales + cash repayments − nothing else you did not expect. Turn on airplane mode before opening it: it must show an error, **never** an expected cash of ₹0. Submit once; submitting again is blocked.

### G. Menu, notices, staff (admin)
- [ ] ★ Add and edit a menu item. Cashier cannot delete menu items; admin can.
- [ ] ★ Send a notice; cashier phone shows it.
- [ ] ★ Staff list loads; do not delete real staff during QA.

### H. Excel export
- [ ] ★ Export a short period. The share sheet opens, the file opens in a spreadsheet app, totals match the dashboard for the same days.

### I. Readability and comfort
- [ ] Set phone font size to Largest: screens stay usable, nothing is cut off on billing, login, closing.
- [ ] Smallest phone you have: billing screen usable one-handed. Note any text too small to read.
- [ ] Bright sunlight / low brightness: grey hint text still readable.
- [ ] TalkBack on: the +, −, Full/Half and remove buttons are announced with their names.

### J. Stability
- [ ] 30 minutes of normal use on the oldest phone: no slowdowns, no crashes.
- [ ] Switch to another app and back during billing: cart and screen intact.
- [ ] Low battery saver mode: still connects and prints.

### Report back
For each Fail: phone model and Android version, screen, exact steps, what you expected, what happened, and a screenshot. Do not paste passwords.
