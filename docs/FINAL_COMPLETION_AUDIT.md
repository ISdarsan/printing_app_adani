# Final Completion Audit

Date: 2026-11-02 · Branch: `stabilize/audit-and-modernize` · Project: `canteen-app-adani`
Nothing in this document was deployed, published or uploaded. No production data was read or changed.

## 1. Where the code stands

| Item | State |
|---|---|
| Latest commits | `918220f` security hardening + verifier, `ee466e0` audit tool, `0b3b559`, `b7eaffd` rules migration, `a06d10b` financial/ids, `2de270d` login/sync/paise |
| Uncommitted files | none after `918220f` (docs commit follows) |
| Secrets in git | none found (scan of every staged diff). `key.properties`, `*.jks`, audit JSON are git-ignored. `google-services.json` / `firebase_options.dart` are public client config. |

## 2. Completed

- Login without fixed delay; deactivated/removed staff are signed out (auth lifecycle).
- Create-once bills and repayments (`clientRequestId` = document id, server refuses a second create).
- Whole-paise money logic, IST half-open business days, dailyStats semantics (see FINANCIAL_LOGIC_REFERENCE.md).
- Sync status strip (pending / offline / failed). Offline billing is **unsupported by decision**; the app says so instead of pretending.
- Branch isolation in the app (scoped queries) and in the candidate rules (proved on the emulator).
- 5 composite indexes cover all 19 registered queries (`tool/check_indexes.mjs`).
- Excel export validated by a real parser (`tool/validate_workbook.py`, 56 checks).
- Phase 1 stopgap rules and Phase 2 candidate rules written and tested; separate deploy configs with an offline verifier.
- Legacy audit tool (read-only) with identifiable / uncertain / unknown classes.

## 3. Incomplete / needs a person

| Item | Why it is open |
|---|---|
| Deploy of stopgap rules | Approved in principle, **not executed**. Needs your go-ahead after the pre-flight checklist. |
| Phase 2 (candidate) | Waits 14 days after the app rollout **and** every active cashier device on the new build. |
| Authentication user list check | You said you will verify it personally. |
| Real-device checks (printer, Bluetooth reconnect, airplane mode, low-end phone) | **Not performed.** Only code inspection and unit/emulator tests. |
| Legacy backfill | Needs a read-only audit against production first, then your approval of each class. |
| R8/minify | Not enabled. Deliberately left off; turning it on needs a device pass (custom MethodChannel, Firebase). |
| Release build default target | `flutter build appbundle --release` fails here with `/main.dart` not found; `-t lib/main.dart` works. See KNOWN_LIMITATIONS.md. |
| Kotlin 2.1.0 warning | Flutter will drop support soon; plugin `share_plus` applies KGP. Upgrade planned, not done (would change the build toolchain). |

## 4. Risks

Security
- **Production is still on `allow read, write: if request.auth != null;`.** Until the stopgap is deployed anyone with any Firebase Auth account can read and write everything. This is the largest open risk.
- Candidate rules need staff records with `role` and `canteenId`. A cashier whose record has no `canteenId` is denied everything by design (no implicit `main`).
- Old app builds that do not send `submittedByUid` on day closings are refused by the candidate (no e-mail fallback). Retire them before Phase 2.

Financial
- Global monthly funds are organisation-wide; every screen labels them so. Branch staff can read them.
- Legacy records without `canteenId` stay admin-only under the candidate until classified.
- Offline billing unsupported: a cashier who bills with no connection gets a clear failure, not a queued bill.

## 5. Firebase and Android readiness

Firebase: rules and index files verified offline by `node tool/verify_deploy_files.mjs <phase>` (all four phases pass). Hash manifest: `proposals/RULES_MANIFEST.json`.

Android: application id `com.adani.canteen_adani`; version from `pubspec.yaml` (1.0.5+6); release signing from `android/key.properties`, build **throws** if the keystore is missing (never falls back to debug); permissions are minimal for Bluetooth printing and camera; a signed release bundle built successfully (58.8 MB, SHA-256 `4267675B…1623C`). Not uploaded.

## 6. Decisions that need your approval

1. Deploy the stopgap rules now? (recommended, after the checklist)
2. Date to start the 14-day Phase 2 clock (the day all cashier devices run the new app).
3. Classes of legacy records to backfill after the read-only audit.
4. Enable R8/minify after a device test? (optional)
5. Upgrade Kotlin / plugins in a separate, tested change.
