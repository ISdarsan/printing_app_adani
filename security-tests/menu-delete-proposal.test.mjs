// Proves the PROPOSED rule (proposals/firestore.rules.menu-admin-delete) against
// the CURRENT rules (firestore.rules), side by side, on the emulator.
// Nothing here deploys anything.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { compareRules } from '../tool/rules_diff.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const CURRENT = fs.readFileSync(path.join(here, '..', 'firestore.rules'), 'utf8');
const PROPOSED = fs.readFileSync(path.join(here, '..', 'proposals', 'firestore.rules.menu-admin-delete'), 'utf8');
let cur; let prop;

const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const mk = (projectId, rules) => initializeTestEnvironment({ projectId, firestore: { host: hp[0], port: Number(hp[1]), rules } });

before(async () => { cur = await mk('demo-menu-current', CURRENT); prop = await mk('demo-menu-proposed', PROPOSED); });
after(async () => { await cur.cleanup(); await prop.cleanup(); });

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'canteenStaff/cashier-north'), { role: 'cashier', canteenId: 'north' });
    await setDoc(doc(db, 'canteenStaff/cashier-south'), { role: 'cashier', canteenId: 'south' });
    await setDoc(doc(db, 'canteenStaff/admin-1'), { role: 'admin', canteenId: 'main' });
    await setDoc(doc(db, 'canteenStaff/cashier-off'), { role: 'cashier', canteenId: 'north', active: false });
    await setDoc(doc(db, 'menuItems/tea-n'), { canteenId: 'north', name: 'Tea', fullPrice: 10 });
    await setDoc(doc(db, 'menuItems/vada-n'), { canteenId: 'north', name: 'Vada', fullPrice: 12 });
    await setDoc(doc(db, 'menuItems/tea-s'), { canteenId: 'south', name: 'Tea', fullPrice: 11 });
  });
}
beforeEach(async () => { await seed(cur); await seed(prop); });
const as = (env, uid) => env.authenticatedContext(uid).firestore();

test('the proposal differs from the current rules in exactly one place: menuItems delete', () => {
  const res = compareRules(CURRENT, PROPOSED);
  const changed = res.rows.filter((r) => r.status !== 'IDENTICAL');
  assert.equal(changed.length, 1);
  assert.equal(changed[0].name, '/menuItems/{itemId}');
  assert.deepEqual(changed[0].details, [
    '- allow delete: if canReadBranch(resource.data)',
    '+ allow delete: if isAdmin()',
  ]);
});

test('BASELINE (current rules): a cashier CAN delete their branch menu item', async () => {
  await assertSucceeds(deleteDoc(doc(as(cur, 'cashier-north'), 'menuItems/tea-n')));
});

test('PROPOSAL: admin can delete menu items of any branch', async () => {
  const admin = as(prop, 'admin-1');
  await assertSucceeds(deleteDoc(doc(admin, 'menuItems/tea-n')));
  await assertSucceeds(deleteDoc(doc(admin, 'menuItems/tea-s')));
  assert.equal((await getDoc(doc(admin, 'menuItems/tea-n'))).exists(), false);
});

test('PROPOSAL: a cashier cannot delete menu items (own branch or another)', async () => {
  const north = as(prop, 'cashier-north');
  await assertFails(deleteDoc(doc(north, 'menuItems/tea-n')));
  await assertFails(deleteDoc(doc(north, 'menuItems/tea-s')));
  assert.equal((await getDoc(doc(north, 'menuItems/tea-n'))).exists(), true, 'the item is still there');
});

test('PROPOSAL: an inactive cashier and an unauthenticated client cannot delete either', async () => {
  await assertFails(deleteDoc(doc(as(prop, 'cashier-off'), 'menuItems/tea-n')));
  await assertFails(deleteDoc(doc(prop.unauthenticatedContext().firestore(), 'menuItems/tea-n')));
});

test('PROPOSAL: cashiers can still READ and USE their branch menu (the Add Item list query)', async () => {
  const north = as(prop, 'cashier-north');
  const list = await assertSucceeds(getDocs(query(collection(north, 'menuItems'), where('canteenId', '==', 'north'), orderBy('name'))));
  assert.deepEqual(list.docs.map((d) => d.id), ['tea-n', 'vada-n']);
  await assertSucceeds(getDoc(doc(north, 'menuItems/tea-n')));
});

test('PROPOSAL: cashiers can still ADD and EDIT items of their own branch', async () => {
  const north = as(prop, 'cashier-north');
  await assertSucceeds(setDoc(doc(north, 'menuItems/idli-n'), { canteenId: 'north', name: 'Idli', fullPrice: 8 }));
  await assertSucceeds(updateDoc(doc(north, 'menuItems/tea-n'), { fullPrice: 15 }));
  assert.equal((await getDoc(doc(north, 'menuItems/tea-n'))).data().fullPrice, 15);
});

test('PROPOSAL: branch isolation is intact (reads, creates and edits across branches are still denied)', async () => {
  const north = as(prop, 'cashier-north');
  await assertFails(getDoc(doc(north, 'menuItems/tea-s')));
  await assertFails(getDocs(query(collection(north, 'menuItems'), where('canteenId', '==', 'south'))));
  await assertFails(getDocs(collection(north, 'menuItems')));
  await assertFails(setDoc(doc(north, 'menuItems/x-s'), { canteenId: 'south', name: 'X', fullPrice: 1 }));
  await assertFails(updateDoc(doc(north, 'menuItems/tea-s'), { fullPrice: 1 }));
  await assertFails(updateDoc(doc(north, 'menuItems/tea-n'), { canteenId: 'south' }), 'cannot move an item to another branch');
});

test('PROPOSAL: admin keeps full read/create/update access', async () => {
  const admin = as(prop, 'admin-1');
  await assertSucceeds(getDocs(collection(admin, 'menuItems')));
  await assertSucceeds(setDoc(doc(admin, 'menuItems/new-s'), { canteenId: 'south', name: 'New', fullPrice: 5 }));
  await assertSucceeds(updateDoc(doc(admin, 'menuItems/tea-s'), { fullPrice: 13 }));
});

test('PROPOSAL: deleting a missing document is also admin-only (no information leak, no side effects)', async () => {
  await assertFails(deleteDoc(doc(as(prop, 'cashier-north'), 'menuItems/does-not-exist')));
});
