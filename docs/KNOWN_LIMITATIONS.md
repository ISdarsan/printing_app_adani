# Known Limitations

1. **Production rules are still open** until the stopgap is deployed (needs your approval).
2. **Stopgap does not isolate branches.** Only the candidate does.
3. **Offline billing is unsupported** (decision). Failed writes show a clear state; nothing is silently queued.
4. **Monthly funds are global** across branches (decision). Labelled as organisation-wide.
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
