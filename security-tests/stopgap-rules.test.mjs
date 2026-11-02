// Phase-1 STOPGAP rules: strangers are shut out, real staff see no difference.
// Compares the stopgap with the DEPLOYED rules on the same operations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, serverTimestamp, setDoc, updateDoc, where } from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (p) => fs.readFileSync(path.join(here, '..', p), 'utf8');
const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const mk = (projectId, rules) => initializeTestEnvironment({ projectId, firestore: { host: hp[0], port: Number(hp[1]), rules } });
let stop; let open;
before(async () => { stop = await mk('demo-stopgap', read('proposals/firestore.rules.stopgap')); open = await mk('demo-stopgap-open', read('deployed.rules')); });
after(async () => { await stop.cleanup(); await open.cleanup(); });

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'canteenStaff/admin-1'), { role: 'admin', canteenId: 'main' });
    await setDoc(doc(db, 'canteenStaff/cashier-north'), { role: 'cashier', canteenId: 'north' });
    await setDoc(doc(db, 'canteenStaff/cashier-main'), { role: 'cashier' });            // no canteenId, no active flag
    await setDoc(doc(db, 'canteenStaff/cashier-off'), { role: 'cashier', canteenId: 'north', active: false });
    await setDoc(doc(db, 'bills/b1'), { canteenId: 'north', totalAmount: 10 });
    await setDoc(doc(db, 'bills/b2'), { canteenId: 'south', totalAmount: 20 });
    await setDoc(doc(db, 'monthlyFunds/2026-11'), { fundAmount: 5 });
  });
}
beforeEach(async () => { await seed(stop); await seed(open); });
const as = (env, uid) => env.authenticatedContext(uid, { email: `${uid}@x.com` }).firestore();

// the operations an OLD app build performs as staff (queries unscoped, missing-doc reads, deletes...)
const staffOps = [
  ['unscoped bill list (old dashboard)', (db) => getDocs(query(collection(db, 'bills'), orderBy('totalAmount')))],
  ['read a document that does not exist (old first-credit-customer / first-closing flows)', (db) => getDoc(doc(db, 'creditCustomers/north_new'))],
  ['create a bill with the old payload', (db) => setDoc(doc(db, 'bills/new'), { canteenId: 'north', createdBy: 'x', items: [], totalAmount: 5, timestamp: serverTimestamp() })],
  ['read another branch', (db) => getDoc(doc(db, 'bills/b2'))],
  ['delete a menu item', (db) => deleteDoc(doc(db, 'menuItems/anything'))],
  ['set the monthly fund', (db) => setDoc(doc(db, 'monthlyFunds/2026-12'), { fundAmount: 9 })],
  ['read own staff record', (db, uid) => getDoc(doc(db, `canteenStaff/${uid}`))],
  ['update a bill', (db) => updateDoc(doc(db, 'bills/b1'), { totalAmount: 11 })],
  ['query with the scoped filter', (db) => getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'north')))],
];

for (const uid of ['cashier-north', 'cashier-main', 'admin-1']) {
  test(`NO CHANGE for active staff (${uid}): every operation behaves exactly as under the deployed rules`, async () => {
    for (const [name, op] of staffOps) {
      const under = async (env) => op(as(env, uid), uid).then(() => 'allowed', () => 'denied');
      const a = await under(open); const b = await under(stop);
      assert.equal(b, a, `${name}: deployed=${a} stopgap=${b}`);
      assert.equal(b, 'allowed', name);
    }
  });
}

test('strangers (signed in, no staff record) are shut out of everything', async () => {
  const s = as(stop, 'stranger');
  for (const c of ['bills', 'expenses', 'canteenStaff', 'creditCustomers', 'repayments', 'cashReconciliations', 'dailyStats', 'notifications', 'menuItems', 'monthlyFunds', 'canteens', 'counters']) {
    await assertFails(getDocs(collection(s, c)));
    await assertFails(getDoc(doc(s, `${c}/x`)));
    await assertFails(setDoc(doc(s, `${c}/x`), { a: 1 }));
  }
  // and the same stranger is fully powerful today
  await assertSucceeds(getDocs(collection(as(open, 'stranger'), 'bills')));
  await assertSucceeds(setDoc(doc(as(open, 'stranger'), 'canteenStaff/stranger'), { role: 'admin' }));
});

test('a stranger cannot register themselves as staff', async () => {
  const s = as(stop, 'stranger');
  await assertFails(setDoc(doc(s, 'canteenStaff/stranger'), { role: 'admin', canteenId: 'main' }));
  await assertFails(getDocs(collection(s, 'bills')));
});

test('a stranger can only read their own (missing) staff record, which is what the app needs to say "role not found"', async () => {
  const snap = await assertSucceeds(getDoc(doc(as(stop, 'stranger'), 'canteenStaff/stranger')));
  assert.equal(snap.exists(), false);
  await assertFails(getDoc(doc(as(stop, 'stranger'), 'canteenStaff/cashier-north')));
});

test('a deactivated user keeps only the right to read their own record (so the app can explain)', async () => {
  const off = as(stop, 'cashier-off');
  await assertSucceeds(getDoc(doc(off, 'canteenStaff/cashier-off')));
  await assertFails(getDocs(collection(off, 'bills')));
  await assertFails(setDoc(doc(off, 'expenses/x'), { amount: 1 }));
  await assertSucceeds(getDocs(collection(as(open, 'cashier-off'), 'bills'))); // today they still work
});

test('signed-out clients are denied', async () => {
  const anon = stop.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(anon, 'bills')));
  await assertFails(getDoc(doc(anon, 'canteenStaff/admin-1')));
});

test('the stopgap does not close the in-staff holes (documented): a cashier can still read other branches and change roles', async () => {
  await assertSucceeds(getDoc(doc(as(stop, 'cashier-north'), 'bills/b2')));
  await assertSucceeds(updateDoc(doc(as(stop, 'cashier-north'), 'canteenStaff/cashier-north'), { role: 'admin' }));
});

// ===========================================================================
// Pre-deployment audit, item 9: which existing staff identities keep working?
// Every shape a production staff record could plausibly have, tested under the
// DEPLOYED rules (works today) and the STOPGAP (must keep working).
const shapes = [
  ['admin with canteenId (as created by the admin dashboard, no `active` field)', { role: 'admin', canteenId: 'main', canteenName: 'Main', email: 'a@x.com' }, true],
  ['cashier with canteenId, no `active` field (as created by the admin dashboard)', { role: 'cashier', canteenId: 'north', canteenName: 'North', email: 'c@x.com' }, true],
  ['cashier without canteenId (acts as branch main)', { role: 'cashier', email: 'c@x.com' }, true],
  ['admin without canteenId', { role: 'admin', email: 'a@x.com' }, true],
  ['`active: true`', { role: 'cashier', canteenId: 'north', active: true }, true],
  ['unknown branch id', { role: 'cashier', canteenId: 'nowhere' }, true],
  ['role with the wrong case (the app itself refuses these at login)', { role: 'Admin', canteenId: 'north' }, true],
  ['role missing (the app refuses these at login)', { canteenId: 'north' }, true],
  ['`active: false` (deliberately deactivated)', { role: 'cashier', canteenId: 'north', active: false }, false],
  ['`active` stored as the TEXT "true" (the app lets this user in; the stopgap would not)', { role: 'cashier', canteenId: 'north', active: 'true' }, false],
  ['`active: null`', { role: 'cashier', canteenId: 'north', active: null }, false],
  ['`active: 1`', { role: 'cashier', canteenId: 'north', active: 1 }, false],
];
for (const [name, data, expectAccess] of shapes) {
  test(`staff identity coverage: ${name} -> stopgap ${expectAccess ? 'KEEPS' : 'removes'} access`, async () => {
    for (const env of [open, stop]) {
      await env.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'canteenStaff/shape-user'), data); });
    }
    const probe = (env) => getDocs(query(collection(as(env, 'shape-user'), 'bills'), where('canteenId', '==', 'north'))).then(() => true, () => false);
    assert.equal(await probe(open), true, 'works today under the deployed rules');
    assert.equal(await probe(stop), expectAccess);
    // the user can always read their own record to be told why
    await assertSucceeds(getDoc(doc(as(stop, 'shape-user'), 'canteenStaff/shape-user')));
  });
}

// ===========================================================================
// Pre-deployment audit, item 10: can the admin still create staff accounts?
// lib/admin_dashboard_page.dart (~2219): the login is created on a SECOND
// FirebaseApp's Auth (Firebase Authentication; Firestore rules do not apply),
// then the staff document is written with the default Firestore instance, i.e.
// signed in as the ADMIN. Replayed here step by step.
test('admin creates a staff member under the stopgap: exact sequence and payload', async () => {
  const admin = as(stop, 'admin-1');
  const newUid = 'new-staff-uid';

  // 1. the new login exists in Auth only: no staff record yet -> no access
  await assertFails(getDocs(collection(as(stop, newUid), 'bills')));
  const own = await assertSucceeds(getDoc(doc(as(stop, newUid), `canteenStaff/${newUid}`)));
  assert.equal(own.exists(), false);                       // the app would show "role not found"

  // 2. the admin (primary session) writes the staff record, payload as in the app
  await assertSucceeds(setDoc(doc(admin, `canteenStaff/${newUid}`), {
    email: 'new@x.com', role: 'cashier', canteenId: 'north', canteenName: 'North', createdAt: serverTimestamp(),
  }));

  // 3. the new staff member now has access, with no further step
  await assertSucceeds(getDocs(query(collection(as(stop, newUid), 'bills'), where('canteenId', '==', 'north'))));
  await assertSucceeds(getDoc(doc(as(stop, newUid), `canteenStaff/${newUid}`)));

  // 4. the other admin dashboard staff actions
  await assertSucceeds(getDocs(query(collection(admin, 'canteenStaff'), orderBy('email'))));
  await assertSucceeds(updateDoc(doc(admin, `canteenStaff/${newUid}`), { canteenId: 'south', canteenName: 'South' }));
  await assertSucceeds(deleteDoc(doc(admin, `canteenStaff/${newUid}`)));
  await assertFails(getDocs(collection(as(stop, newUid), 'bills')));   // removed staff lose access at once
});

test('a deactivated ADMIN cannot create staff under the stopgap (and a stranger cannot)', async () => {
  await stop.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'canteenStaff/admin-off'), { role: 'admin', active: false }); });
  await assertFails(setDoc(doc(as(stop, 'admin-off'), 'canteenStaff/x1'), { role: 'cashier', canteenId: 'north' }));
  await assertFails(setDoc(doc(as(stop, 'stranger'), 'canteenStaff/x2'), { role: 'admin', canteenId: 'main' }));
});
