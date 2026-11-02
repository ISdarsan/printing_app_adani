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
