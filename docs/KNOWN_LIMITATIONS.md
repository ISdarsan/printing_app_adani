# Known Limitations

1. **Production rules are still open** until the stopgap is deployed (needs your approval).
2. **Stopgap does not isolate branches.** Only the candidate does.
3. **Offline billing is unsupported** (decision). Failed writes show a clear state; nothing is silently queued.
4. **Monthly budgets are per canteen** (decision of 2026-11-02, replacing the earlier shared fund). Existing shared fund documents are ignored, so each canteen shows "No budget set" until the admin sets its budget. The production rules are still the open ones, so the new per-canteen access rule only takes effect when the candidate rules are deployed; until then any signed-in user can read budgets.
5. **Legacy records without `canteenId`** are admin-only under the candidate until classified; nothing is migrated automatically.
6. **Old app builds** that omit `submittedByUid` on day closings are refused by the candidate. Remove them from devices first.
7. **Staff record without `canteenId`** gets no access under the candidate (no implicit `main`). Current staff audit: no such records.
8. **No real-device testing was done** for printing, Bluetooth reconnect or airplane mode.
9. **Release build needs `-t lib/main.dart`** in this environment; plain `flutter build appbundle --release` fails with "Error when reading '/main.dart'". Root cause not identified (not caused by the project files, the shell or env vars); workaround documented.
10. **R8/minify off**, Kotlin 2.1.0 and `share_plus`/KGP warnings pending an upgrade.
11. **Transaction tests use a JS port** of the Dart money logic, not the Dart code itself.
12. **Firebase Authentication "one account per email"** setting and user list are for you to verify in the Console.
13. `node --test tool/` (directory form) reports a spurious failure; run the test files explicitly.
14. An earlier `firebase ext:list` attempted to enable the Extensions API on the production project (BUG_REGISTER B-43). Avoid extension commands.

## UI / performance branch additions

15. **No visual QA or screenshots.** The UI work was verified by analyzer, 77 new tests and source inspection only; no screen was run on a device or emulator.
16. **Dashboards, customer search, repayment dialog and cash-closing page have no widget tests** because they create Firestore streams directly. Their key behaviours are covered by source guards and the emulator suites.
17. **About a quarter of text is 11 px or smaller** and was not enlarged without a device pass.
18. **Admin monthly sales still reads every bill of the month** and pending credit reads all credit customers. Cheaper alternatives change where financial figures come from and need a decision.
19. **Portrait-only, phone-first layout.** No tablet layout.
20. Real read-count and frame-time improvements are **not measured**; the only measured figure is the listener count in a test model.

## Added by the full analysis sweep

21. **Phone-date guard needs the server's time.** It reads the HTTP `Date` header of the Firebase endpoint; offline or blocked networks mean "cannot tell" and the save is allowed. It blocks only when the phone's IST day differs from the server's by more than 2 minutes.
22. **Firebase client packages are several major versions behind** (see `FULL_ANALYSIS_SWEEP.md`); a major upgrade is a separate, fully tested change.
23. **Credit limit of ₹2,000 per customer is hard-coded** in the billing screen.

## Added by round 2

24. **SMS Broadcast is not implemented**: both menus show "Coming soon"; the old SMS code remains in the project but is unreachable.
25. **Analytics for a single canteen** reads that canteen's bills on the server (needs the existing indexes); for "All canteens" and for "Main Canteen" it reads all bills of the period and filters on the device (Main also owns older records with no canteen id). Large histories take longer; the page shows progress and a row limit.
26. **One malformed bill** (for example an item price stored as text) makes the whole Analytics load fail with "Could not load analytics" instead of skipping that bill. No such record is known.

## Added by round 3

27. **Deleting Main (or any canteen) keeps its records.** Bills, expenses, closings, customers and menu items tagged to a deleted canteen, and older records with no canteen id, stay in the database. They still count under "All canteens" but cannot be picked as a single canteen, and creating a new canteen with the same name gives a different id (for example `main_canteen`), so they are not re-attached automatically.
28. **A canteen with cashiers cannot be deleted** unless Main exists and is a different canteen: move the cashiers first. Admins never block a delete.
29. **The app assumes the Main record exists in the database today** (the Branches screen lists it). If it did not, Main would no longer appear in the pickers.
