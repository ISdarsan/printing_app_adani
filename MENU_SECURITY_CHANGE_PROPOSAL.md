# Menu Security Change Proposal: admin-only deletion

Status: **PROPOSAL. Not deployed. `firestore.rules` is unchanged.** The proposed rules live in `proposals/firestore.rules.menu-admin-delete`.

## Decision being implemented
Business decision 3: menu item deletion should be admin-only. Today the repository lets any staff member of a branch delete that branch's menu items, while every other collection restricts delete to admins (bug B-20).

## The change (one rule line)
```diff
   match /menuItems/{itemId} {
     allow read: if canReadBranch(resource.data);
     allow create: if canWriteBranch(request.resource.data) && ...;
     allow update: if canWriteBranch(resource.data) && ...;
-    allow delete: if canReadBranch(resource.data);
+    allow delete: if isAdmin();
   }
```
Verified mechanically: `compareRules(current, proposed)` reports exactly one differing rule element, `/menuItems/{itemId}`, with exactly those two lines.

## Evidence (emulator, real rules)
`security-tests/menu-delete-proposal.test.mjs` runs the **current** and the **proposed** rules side by side (10 tests, all pass):
| Requirement | Result |
|---|---|
| Baseline: a cashier can delete their branch item under the current rules | confirmed (this is the behaviour being removed) |
| **Admin can delete** menu items of any branch | pass |
| **Cashier cannot delete** (own branch or another branch); item still exists afterwards | pass |
| Inactive cashier and unauthenticated client cannot delete | pass |
| **Cashier can still read and use the menu**: the exact Add Item list query (`canteenId ==` + `orderBy name`) works | pass |
| Cashier can still **add and edit** items of their own branch | pass |
| **Branch isolation intact**: other-branch read, unscoped list, create, edit, and moving an item to another branch are all still denied | pass |
| Admin keeps full read / create / update | pass |
| Deleting a missing document is admin-only (no side effects) | pass |

Regression proof: the **entire** emulator suite (68 tests: rules, query shapes, paging, analytics, all 26 financial-transaction tests, legacy audit) was also run with `RULES_FILE=proposals/firestore.rules.menu-admin-delete` and passes 68/68, so no other behaviour depends on the old rule.

## App companion change (already in the code, safe to ship before the rule)
`lib/add_item_page.dart`: the delete button is shown only when `CanteenProvider.isAdmin`, and `_deleteItem` returns immediately for non-admins. Without this, after the rule is deployed a cashier would still see a delete button that fails with a permission error. Cashiers keep Add and Edit. This changes cashier behaviour today (they lose the delete button), which is the approved intent. Guarded by a source-level test in `test/shared_fund_wording_test.dart`.

## Impact
- Cashiers can no longer remove menu items; they must ask an admin. Items they created by mistake can still be edited (renamed, priced) but not removed.
- Old app versions in the field (which still show the button) will get a permission-denied error on delete after the rule is deployed; nothing is lost or corrupted.
- Admin flows are unchanged.

## Deployment (when you decide; not now)
1. **First** complete the production rules comparison (PRODUCTION_RULES_COMPARISON.md). 
2. **Do not deploy the proposal file as it is**: it is a copy of the *repository* rules. If production differs from the repository, deploying it would silently overwrite those differences. Instead apply the single `allow delete` change to the **verified deployed** rules (or reconcile the differences first), save that as the rules file, and compare it with `node tool/compare_rules.mjs --deployed-file <deployed> --repo-file <candidate>` to confirm that only `/menuItems/{itemId}` changes.
3. Ship the app build with the gated delete button.
4. Deploy: `firebase deploy --only firestore:rules --project canteen-app-adani` (needs your explicit approval at that moment).
5. Verify: as a cashier, Add Item shows no delete button; as admin, deleting an item works (use a test item).
6. Rollback: redeploy the previous rules file (keep a copy of the deployed rules before step 4).

## Open question
Do you also want cashiers to lose *editing* of prices (more sensitive than deleting)? That is a separate decision; this proposal does not change it.

---

## Update: superseded by the production security migration
The deployed rules turned out to be fully open (no rule exists to patch), so the menu change is delivered as part of `proposals/firestore.rules.candidate` (phase 2), which already contains `allow delete: if isAdmin();`. Deployment follows PRODUCTION_SECURITY_MIGRATION.md; the "apply to the verified deployed rules" step is moot because there is nothing to preserve in the deployed file. The separate one-line proposal file remains for reference.
