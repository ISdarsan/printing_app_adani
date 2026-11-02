# Final Release Readiness

Date: 2026-11-02 · Branch: **`release/production-candidate`** · Firebase project: `canteen-app-adani`

**Nothing has been deployed by this integration.** No rules were deployed, no indexes were deployed by this integration (see section 6 for the one earlier index deploy, which you authorised), no production data was changed, nothing was published to Google Play, no force-push, `master` untouched, no branch deleted.

## 1. Integration

| Item | Value |
|---|---|
| Base | `stabilize/audit-and-modernize` at `22db499` |
| Merged in | `feature/ui-modernization-performance` at `d5e5301` (12 commits) |
| Merge base | `22db499` = the stabilization tip |
| Result | merge commit `f011b08` (two parents: `22db499`, `d5e5301`), plus the follow-up commits on this branch (see `git log`) |
| Conflicts | **None.** The UI branch had been created from the stabilization tip, so the branches were not independent: stabilization contained nothing the UI branch lacked, and the UI branch was strictly 12 commits ahead. No cherry-picks were needed. |
| Tree check | The merged tree hash equals the UI branch tip's tree hash (`9be2db6b…`), so the integrated code is exactly the code that was already tested. |
| Not touched | `master`, `stabilize/audit-and-modernize`, `feature/ui-modernization-performance` (all still exist, unchanged) |

### Commits that came in with the merge (oldest first)

| Commit | What |
|---|---|
| `4f57693` | perf: cache Firestore listeners (stop re-opening on rebuild); shared loading / empty / error views |
| `9021049` | tests for the cache, state views and regression guards; friendly errors instead of raw exceptions |
| `88982f8` | billing controls: tap targets, screen-reader labels, long names no longer overflow; text contrast |
| `4c9b071` | login keyboard flow, autofill, empty-field message |
| `27d3f20` | UI/UX audit, modernization report, performance audit |
| `1d620b7` | real-device QA build record, install / rollback, checklist |
| `7640f1d` | loading/error sweep: missing-index message, no made-up zeros, no raw errors |
| `2125385` | slow-connection hint on every loading state; one loading view; recheck of queries and flags |
| `71d11c9` | record of the production index deploy |
| `e984532` | fund-card overflow fixed (found on the phone); billing total row at large text; honest layout tests (real width, real font) |
| `229cc31` | fund-card layout test includes the page padding |
| `d5e5301` | monthly budgets are per canteen (owner decision) |

Earlier stabilization commits already in the base: `2de270d`, `a06d10b`, `b7eaffd`, `0b3b559`, `ee466e0`, `918220f`, `22db499`.

## 2. Manual-testing fixes

**Evidence supplied by you** was a set of phone screenshots (failing screens, the Firebase Console Indexes page, the fund-card overflow) and your statements. **No pass/fail checklist from the device run was supplied or recorded**, so this document does **not** claim that any manual test passed. After the fixes below, the only supplied confirmation is that the budget screen then loaded (your later screenshot showed it loading, with the overflow); you later said the overflow was still there, and a later fix was made without a supplied confirmation.

| # | Reported (your evidence) | Root cause | Fix | Regression test | Commit | Business doc |
|---|---|---|---|---|---|---|
| 1 | "Could not load" on Bills History, Daily Sales, Monthly Budget, Manage Menu (screenshots) | Firestore composite indexes were never deployed to production, so the branch-scoped queries failed with `failed-precondition` | Deployed the 5 indexes with your permission (Console later showed all 5 **Enabled**); app now explains the cause in plain language | message mapping tests; index registry vs code vs file check | `7640f1d`, `71d11c9` | `REAL_DEVICE_QA.md` |
| 2 | Raw technical error text on screens | builders printed the exception object | friendly message + Retry on every load/save path; sync strip too | source guards (fail on old code) | `9021049`, `7640f1d` | `UI_UX_AUDIT.md` |
| 3 | Endless spinners / blank or ₹0 on failure | no error branch, bare spinners, made-up zero | error views, dashes instead of ₹0, "Still loading, check your internet" after 8 s | widget + guard tests | `7640f1d`, `2125385` | `PERFORMANCE_AUDIT.md` |
| 4 | Monthly Budget fund card: "RIGHT OVERFLOWED BY 68 PIXELS" | three columns with long labels in a plain Row | columns share width, labels wrap, amounts scale down; card extracted and tested at 320/360/800 px and 150–200% text | `fund_card_layout_test.dart` (mutation-checked) | `e984532`, `229cc31` | – |
| 5 | (found by corrected tests) billing total row overflow at large text | fixed-size amount in a Row | amount scales down | `billing_widgets_test.dart` | `e984532` | – |
| 6 | "Monthly budget is assigned to each canteen, not one amount for all" | earlier decision (organisation-wide fund) was wrong for the business | per-canteen budgets: new data layout, screens, alerts, candidate rule | 14 maths tests, 9 source guards (fail on old code), 2 emulator tests | `d5e5301` | **Yes**: `FINANCIAL_LOGIC_REFERENCE.md`, `KNOWN_LIMITATIONS.md`, `FIRESTORE_RULES_ROLLOUT.md` |
| 7 | red build warnings (Kotlin 2.1.0, `share_plus`) | toolchain deprecation notices, not errors | not changed (decision: hide with a flag, upgrade later as its own change) | – | – | `KNOWN_LIMITATIONS.md` #10 |

Test-method correction found along the way (recorded in `TEST_RESULTS.md`): earlier small-screen tests did not constrain the real layout width and used a placeholder font; both fixed. One integration-time fix: the verifier mutation test was sensitive to Windows line endings; test normalised, code unchanged.

## 3. Test results on this branch

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **359 passed**, 0 failed |
| Emulator, whole `security-tests` folder (repository rules) | **205 / 205** |
| Candidate rules suite | **110 / 110** |
| Stopgap rules suite | **23 / 23** |
| Older suites run against the candidate rules | **63 / 63** |
| Legacy audit tool | 9 / 9 |
| Tool tests (rules diff, deploy verifier) | **20 / 20** |
| Index registry (`check_indexes`) | OK: every query covered by the 5 composite indexes or automatic single-field indexes |
| Deploy-file verifier | stopgap 16, candidate 18, rollback 14, indexes 11 checks: all pass |
| Excel workbook (generated by test, parsed by `validate_workbook.py`) | 14 generation tests; **56 / 56** parser checks |
| Android release build (`-t lib/main.dart`) | APK and AAB both built, exit 0 |

All emulator runs used a fake `demo-` project. Not covered by any automated test: real devices, real printer/Bluetooth, real Auth timing.

## 4. Security status

| Item | Status |
|---|---|
| Deployed rules backup preserved | `backups/deployed.rules.2026-11-02.ORIGINAL`, raw SHA-256 `ae2ee8da…a819a` equals its recorded checksum; `deployed.rules` is byte-identical |
| **What is live in production now** | **still the original open rules** (`allow read, write: if request.auth != null;`). No rules have been deployed. |
| Stopgap rules | **unchanged** since `22db499`; manifest SHA-256 `d8ef0f4b…7c728` (LF-normalised); 23 tests pass |
| Candidate rules | one approved change in this integration: per-canteen `monthlyFunds`. Manifest SHA-256 `1df30bf9…290c5`; 110 tests pass |
| Branch isolation | candidate suite group D plus the regression that stopped a `main` cashier listing other branches |
| Cashiers cannot promote themselves | tested: a cashier cannot set `role: admin`, change `canteenId`, reactivate themselves, create/delete/list staff |
| Admin staff management | tested with the exact payloads the admin dashboard sends |
| Unknown collections denied | tested for every non-admin identity, including sub-collections and root documents; final catch-all is deny |
| No e-mail fallback, no implicit `main` | enforced by the verifier and tests |
| Budgets (new) | cashier reads only `<ownCanteenId>_<yyyy-MM>`; other canteens and the old month-only documents denied; admin write requires id = `<canteenId>_<monthYear>` |
| Indexes | `firestore.indexes.json` unchanged since the stabilization line; exactly 5: bills (canteenId, timestamp desc), expenses (canteenId, timestamp), cashReconciliations (canteenId, timestamp desc), notifications (canteenId, timestamp desc), menuItems (canteenId, name). Deployed 2026-11-02 and shown **Enabled** in the Console (your screenshot). |
| Original open rules hash note | the manifest hashes the LF-normalised text (`1561f5d0…`), the backup checksum is of the raw bytes (`ae2ee8da…`): same file, two methods |

## 5. Financial correctness

- All money is whole paise; IST half-open day ranges; create-once bills and repayments; `dailyStats` semantics (sales vs. cash movement vs. repayments); cash closing blocked until the expected cash is known; see `FINANCIAL_LOGIC_REFERENCE.md`.
- **Changed in this integration (business rule):** monthly budgets are per canteen. A canteen's budget is compared only with that canteen's expenses; alert below 15% left or when exceeded; no budget (or 0) = no alert. The previous shared fund documents are left untouched and **ignored**: each canteen shows "No budget set" until the admin sets it.
- No calculation of sales, credit, repayments, cash or expenses was changed by the UI work.
- Verified by unit tests, source guards and emulator transaction tests (26, a JavaScript port of the Dart logic: a stated limit).

## 6. Production changes made during development (disclosed)

1. 2026-11-02: the five composite indexes were deployed to `canteen-app-adani` with your permission (`firebase deploy --only firestore:indexes --config firebase.indexes.json`). Additive; rules and data untouched.
2. Earlier incident (BUG_REGISTER B-43): a `firebase ext:list` attempt tried to enable the Extensions API.

Nothing else was written to the production project by me.

## 7. Android build

| Item | Value |
|---|---|
| APK | `D:\app\printing_app_adani-master\build\app\outputs\flutter-apk\app-release.apk`, 62,384,344 bytes, SHA-256 `A177CA653C86D1236CE2E2C5555CF81435BA6B5B8D9382507E7C282160FD258C` |
| AAB | `…\build\app\outputs\bundle\release\app-release.aab`, 61,770,658 bytes, SHA-256 `1C1B3BE1DDCEDD560CB9679CBFD80D2B05A66CC90C85013B223170332857AF94` |
| Reproducible | identical hashes to the builds made from the UI branch before integration |
| Id / version | `com.adani.canteen_adani`, 1.0.5 (code 6), minSdk 24, targetSdk 36 |
| Signature | verified by `apksigner` (v2); signer `CN=Adani Canteen, OU=CSR, O=Adani`, certificate SHA-256 `30fbaf8d…acb879`; production certificate, not debug |
| Firebase binding | `canteen-app-adani` in `google-services.json` and `firebase_options.dart` |
| Before a Play upload | **bump the version code** (code 6 may already be in use), upload to an internal track first |
| Not done | upload / release |

## 8. Known limitations

See `KNOWN_LIMITATIONS.md`. The ones that matter for the deployment review:

- Production still on open rules until the stopgap is deployed.
- Offline billing unsupported by decision; a connection is required.
- Old shared budget documents are ignored; budgets must be entered per canteen.
- Old app builds that write a shared fund or omit `submittedByUid` on closings are refused by the candidate rules.
- Release build needs `-t lib/main.dart` in this environment; cause of the default failure unknown.
- Kotlin 2.1.0 / `share_plus` build warnings; R8/minify off.
- Admin monthly sales still reads every bill of the month.
- Small text (about a quarter of text is 11 px or less) not enlarged; portrait phone layout only.

## 9. Outstanding device tests

Not recorded as done: printing and Bluetooth reconnect (Android 12+ permission), airplane mode during billing and cash closing, double-tap save producing one bill, each role's budget screens after budgets are set, alert below 15%, Excel export/share on the phone, large-font and small-phone checks, TalkBack, 30-minute stability on the oldest phone, release APK (not debug) on at least two phones. Checklist: `REAL_DEVICE_QA.md`.

## 10. Deployment sequence (for the review; nothing here has been run)

1. Re-run the checks in section 3 on the commit you intend to ship; confirm `git status` is clean.
2. **Indexes: already deployed and Enabled.** Re-verify in the Console only.
3. Verify the Authentication users list and `canteenStaff` (every active person has a role and a `canteenId`; you said you would do this).
4. `node tool/verify_deploy_files.mjs stopgap` and `rollback` must pass.
5. **Approval gate:** deploy the **stopgap** rules (`firebase deploy --only firestore:rules --config firebase.stopgap.json --project canteen-app-adani`). Smoke test with the real admin and a cashier; try an account with no staff record (must be refused).
6. Admin sets each canteen's monthly budget (Expense Report -> pick a canteen).
7. Roll the new app to all cashier devices (upload the AAB to an internal track first, with a bumped version code).
8. Wait at least 14 days **and** until every active cashier device runs the new build; run the read-only legacy audit; decide each class.
9. **Approval gate:** deploy the **candidate** rules (`--config firebase.candidate.json`); smoke test both roles including the budget screens and a day closing.
10. After migration: remove any temporary compatibility, record the manifest hashes and the date.

## 11. Rollback

- **Rules:** `firebase deploy --only firestore:rules --config firebase.rollback.json --project canteen-app-adani` restores the preserved open rules (insecure; emergency only). If only the candidate misbehaves, redeploy the stopgap instead.
- **Indexes:** additive; leave them in place. They cannot lock anyone out.
- **App:** keep the previous APK/AAB. Android refuses to install a lower version code over a higher one: uninstall first (clears only on-phone login and printer pairing; Firestore data is unaffected), then install the previous build.
- **Budgets:** the new budget documents are additive; the old shared documents were never deleted.
- **Branch:** `stabilize/audit-and-modernize` and `feature/ui-modernization-performance` are untouched and can be returned to.

## 12. Remaining blockers and readiness

| Blocker | Owner |
|---|---|
| Production rules are still open (stopgap not deployed) | you (approval) |
| No recorded pass/fail result for the real-device checklist | you |
| Per-canteen budgets must be entered before the budget screens show figures | you |
| Authentication users / "one account per email" check | you |
| Phase 2 gating (14 days, all devices migrated, legacy audit) | you |
| Version code bump before any Play upload | release step |

**Ready for the production deployment review: yes.** The integrated code is tested and the builds are reproducible. It is **not** ready to be deployed without the approvals and device results above.
