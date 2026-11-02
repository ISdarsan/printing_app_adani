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
