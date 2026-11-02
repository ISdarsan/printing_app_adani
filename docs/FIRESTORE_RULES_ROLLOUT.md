# Firestore Rules Rollout

Order: **indexes → stopgap → (wait) → candidate**. Never deploy `firebase.json` blindly; use the dedicated config for each step.

| Step | Config | Command | Reversible by |
|---|---|---|---|
| Indexes | `firebase.indexes.json` (or `firebase.json`) | `firebase deploy --only firestore:indexes --project canteen-app-adani` | indexes are additive; leaving them is harmless |
| Phase 1 | `firebase.stopgap.json` | `firebase deploy --only firestore:rules --config firebase.stopgap.json --project canteen-app-adani` | rollback config |
| Phase 2 | `firebase.candidate.json` | `firebase deploy --only firestore:rules --config firebase.candidate.json --project canteen-app-adani` | stopgap config (preferred) or rollback config |
| Rollback | `firebase.rollback.json` | `firebase deploy --only firestore:rules --config firebase.rollback.json --project canteen-app-adani` | – (restores the insecure open rules) |

All four configs contain only a `firestore` section with `"database": "(default)"`. `.firebaserc` pins `canteen-app-adani`. `tool/verify_deploy_files.mjs` fails if any config gains an extra key, points at the wrong file, or if a rules file differs from `proposals/RULES_MANIFEST.json`.

## Phase 1 acceptance (live)
- Real admin and cashier work as before.
- A signed-in account without an active staff record is refused.
- A deactivated staff member is refused on the next request.

## Phase 2 preconditions
See SECURITY_MIGRATION_PLAN.md ("Gating for Phase 2"). In short: ≥ 14 days after the app rollout, all active cashier devices migrated, every active staff has `role` and `canteenId`, legacy audit reviewed.

## Phase 2 acceptance
- Cashier of branch A: sees only A's bills, expenses, repayments, customers, closings; cannot see or write B.
- Cashier cannot change staff, menu deletes, or their own role/branch.
- Admin can do everything and sees all branches.
- Day closing succeeds from the current app (sends `submittedByUid`).
- Monthly funds still readable by all active staff (global, labelled as organisation-wide).

## When rules change after testing
Edit → re-run the emulator suites → `node tool/verify_deploy_files.mjs --update-manifest` → commit. The manifest update is deliberate; any unexplained rules edit makes the verifier fail.

## Not covered by emulator tests
Real device behaviour, real Firebase Auth token timing, Console index build time. Verify these in the smoke test.
