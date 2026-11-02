# Production Deployment Checklist (12 steps)

**Nothing here has been run.** Every command that changes Firebase is marked ⚠ and needs your explicit go-ahead. Run PowerShell from `D:\app\printing_app_adani-master`.

## Before touching Firebase

**1. Be on the right code.**
```powershell
git status --short        # expect: nothing listed
git log --oneline -1
```

**2. Run every local test.** Expected: analyzer "No issues found"; Flutter 240 passed; tool tests 20 passed.
```powershell
flutter analyze
flutter test
node --test tool/rules_diff.test.mjs tool/verify_deploy_files.test.mjs
node tool/check_indexes.mjs
```

**3. Run the emulator suites** (safe: fake `demo-` project, no internet data). See TEST_RESULTS.md for the exact command and expected counts (203 / 53).

**4. Verify the deployment files** (read-only). Each ends with `ALL n CHECKS PASSED`.
```powershell
node tool/verify_deploy_files.mjs stopgap
node tool/verify_deploy_files.mjs indexes
node tool/verify_deploy_files.mjs rollback
```

**5. Check staff before any rules change** (you do this in the Firebase Console): Authentication → Users, and Firestore → `canteenStaff`. Every person who must keep working has an **active** staff record. Admin has `role: admin`.

**6. Confirm the rollback file is ready.** `firebase.rollback.json` + `backups/deployed.rules.2026-11-02.ORIGINAL` (hash is checked by step 4).

**7. Log in and confirm the project.**
```powershell
firebase login
firebase projects:list     # expect canteen-app-adani
```
Do not run `firebase ext:list` or anything touching extensions (it tries to enable an API; see BUG_REGISTER B-43).

## Deploy (⚠ each needs approval)

**8. Indexes: ALREADY DEPLOYED on 2026-11-02 (all 5 showed Enabled in the Console). Do not redeploy; just confirm in Firebase Console -> Firestore -> Indexes that all 5 are Enabled.** The command below is kept only for a fresh project or if an index is ever lost.

(Original wording: Indexes first, additive, cannot lock anyone out.)
```powershell
firebase deploy --only firestore:indexes --project canteen-app-adani
```
Wait until the Console shows all 5 indexes "Enabled". (This uses `firebase.json`, whose indexes file is `firestore.indexes.json`. The stricter alternative is adding `--config firebase.indexes.json`.)

**9. ⚠ Phase 1 stopgap rules.**
```powershell
firebase deploy --only firestore:rules --config firebase.stopgap.json --project canteen-app-adani
```
The stopgap config names only the `(default)` database and the stopgap file – no indexes, no candidate.

## After deploying

**10. Smoke test immediately** with the real admin and a real cashier on the current app: log in, open a bill screen, make one small test bill (cancel/mark per your process), open the dashboard. Also try the app with a signed-in account that has **no** staff record: it must be refused.

**11. If anything legitimate is blocked → rollback** (⚠):
```powershell
firebase deploy --only firestore:rules --config firebase.rollback.json --project canteen-app-adani
```
Then report what failed; do not retry blindly.

**12. Record it.** Note date/time and the file hash (`proposals/RULES_MANIFEST.json`), start the 14-day Phase 2 clock only when every cashier device runs the new app, and keep this checklist with the notes.

Phase 2 (candidate) uses a separate procedure: FIRESTORE_RULES_ROLLOUT.md.
