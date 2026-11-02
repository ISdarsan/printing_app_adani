# Security Migration Plan

## Why

The deployed rules (preserved in `backups/deployed.rules.2026-11-02.ORIGINAL`, SHA-256 `ae2ee8da028777e9c26193163c1b318d7a4d4d54c5de38916a3a714ded6a819a`) are `allow read, write: if request.auth != null;`. Any signed-in account can read or change any branch's data.

## Three rule sets

| Set | File | Who gets in | Status |
|---|---|---|---|
| Deployed (open) | `backups/…ORIGINAL` | any signed-in user | live today, insecure |
| Phase 1 stopgap | `proposals/firestore.rules.stopgap` | users with an **active** staff record | tested (23 tests), approved in principle, not deployed |
| Phase 2 candidate | `proposals/firestore.rules.candidate` | roles + branches + deny-by-default | tested (108 tests), not deployed |

### Phase 1 – stopgap
No change for real staff. Blocks random accounts and deactivated staff. Does **not** isolate branches. Safe to deploy first because the app already reads the staff record at login.

### Phase 2 – candidate
- Staff management admin-only; nobody can promote themselves or change their own role/branch.
- Every collection tied to the caller's `canteenId`; list queries must filter by it (rules are not filters).
- Staff record with no `canteenId` = no branch = denied (no implicit `main`).
- Day closings must carry `submittedByUid == request.auth.uid`. **No e-mail fallback.**
- Bill/repayment ids are request ids; a duplicate create is an update that the rules refuse.
- Menu delete admin-only; cashiers cannot read documents that do not exist (except funds, own staff doc, counters).
- Final `match /{document=**}` denies everything else.

## Gating for Phase 2

1. Phase 1 live and stable.
2. Updated app released; **≥ 14 days** passed.
3. Every active cashier device is on the new build (no old builds send closings without `submittedByUid`).
4. Staff list reviewed: every active staff has `role` and `canteenId` (`node security-tests/legacy-audit.mjs --staff-only`; last result: 2 staff, 1 admin, 1 cashier, 0 issues, known branches `main`).
5. Read-only legacy audit run; you have decided on each class.

## Legacy records

Classified, never auto-assigned:
- **identifiable** – strong evidence (id prefix, unique branch name).
- **uncertain** – indirect evidence (creator, customer phone). Needs a human decision.
- **unknown** – no evidence. Stays untouched; admin-only under the candidate.
No migration without your approval.

## Rollback

`firebase.rollback.json` redeploys the preserved open rules (documented as insecure). Use only if the stopgap or candidate blocks legitimate staff and cannot be fixed quickly.

## Verification before any deploy

```powershell
node tool/verify_deploy_files.mjs stopgap
node tool/verify_deploy_files.mjs candidate
node tool/verify_deploy_files.mjs rollback
node tool/verify_deploy_files.mjs indexes
```
Each must end with `ALL n CHECKS PASSED`. They only read local files.
