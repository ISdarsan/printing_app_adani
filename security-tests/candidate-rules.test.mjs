// Permission-boundary suite for the CANDIDATE production rules
// (proposals/firestore.rules.candidate), run side by side with the DEPLOYED rules
// (deployed.rules: "any signed-in user may read and write everything").
// Payloads below are copied from the Dart sources (see comments); nothing here
// deploys or touches production.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  arrayUnion, collection, deleteDoc, doc, getDoc, getDocs, increment, limit, orderBy, query,
  runTransaction, serverTimestamp, setDoc, Timestamp, updateDoc, where, writeBatch,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (p) => fs.readFileSync(path.join(here, '..', p), 'utf8');
const CAND = read(process.env.CANDIDATE_RULES || 'proposals/firestore.rules.candidate');
const OPEN = read('deployed.rules');
const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const mk = (projectId, rules) => initializeTestEnvironment({ projectId, firestore: { host: hp[0], port: Number(hp[1]), rules } });
let cand; let open;
before(async () => { cand = await mk('demo-sec-cand', CAND); open = await mk('demo-sec-open', OPEN); });
after(async () => { await cand.cleanup(); await open.cleanup(); });

const DAY = '2026-11-02';
const ago = (d) => Timestamp.fromDate(new Date(Date.parse('2026-11-02T10:00:00Z') - d * 864e5));

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (p, d) => setDoc(doc(db, p), d);
    await Promise.all([
      put('canteenStaff/admin-1', { role: 'admin', canteenId: 'main', email: 'admin@x.com' }),
      put('canteenStaff/cashier-north', { role: 'cashier', canteenId: 'north', canteenName: 'North', email: 'n@x.com' }),
      put('canteenStaff/cashier-south', { role: 'cashier', canteenId: 'south', canteenName: 'South', email: 's@x.com' }),
      put('canteenStaff/cashier-main', { role: 'cashier', email: 'm@x.com' }),               // no canteenId => 'main'
      put('canteenStaff/cashier-main-explicit', { role: 'cashier', canteenId: 'main', email: 'cashier-main-explicit@x.com' }),
      put('bills/m1', { canteenId: 'main', createdBy: 'cashier-main', totalAmount: 7, paymentMode: 'Cash', items: [], timestamp: ago(0) }),
      put('canteenStaff/cashier-off', { role: 'cashier', canteenId: 'north', active: false, email: 'off@x.com' }),
      put('canteenStaff/user-badrole', { role: 'Admin', canteenId: 'north', email: 'bad@x.com' }), // wrong case
      put('canteenStaff/user-norole', { canteenId: 'north', email: 'nr@x.com' }),
      put('canteens/north', { name: 'North' }), put('canteens/south', { name: 'South' }),
      put('bills/n1', { canteenId: 'north', createdBy: 'cashier-north', totalAmount: 100, paymentMode: 'Cash', items: [], timestamp: ago(0) }),
      put('bills/n-credit', { canteenId: 'north', createdBy: 'cashier-north', totalAmount: 100, paymentMode: 'Credit', pendingAmount: 100, creditStatus: 'Pending', customerPhone: '900', items: [], timestamp: ago(1) }),
      put('bills/s1', { canteenId: 'south', createdBy: 'cashier-south', totalAmount: 50, paymentMode: 'Cash', items: [], timestamp: ago(0) }),
      put('bills/legacy1', { createdBy: 'cashier-main', totalAmount: 10, paymentMode: 'Cash', items: [], timestamp: ago(3) }),
      put('creditCustomers/north_900', { phone: '900', name: 'Ravi', canteenId: 'north', canteenName: 'North', totalPending: 100 }),
      put('creditCustomers/south_800', { phone: '800', name: 'S', canteenId: 'south', totalPending: 40 }),
      put('expenses/e-n', { canteenId: 'north', userId: 'cashier-north', amount: 80, description: 'Gas', timestamp: ago(0) }),
      put('expenses/e-s', { canteenId: 'south', userId: 'cashier-south', amount: 20, description: 'Tea', timestamp: ago(0) }),
      put('repayments/r-n', { canteenId: 'north', customerPhone: '900', amount: 10, paymentMode: 'Cash', timestamp: ago(0) }),
      put('repayments/r-s', { canteenId: 'south', customerPhone: '800', amount: 5, paymentMode: 'Cash', timestamp: ago(0) }),
      put(`cashReconciliations/north_${DAY}`, { canteenId: 'north', date: DAY, systemCash: 100, actualCash: 100, discrepancy: 0, submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: ago(0) }),
      put('cashReconciliations/south_2026-11-01', { canteenId: 'south', date: '2026-11-01', systemCash: 5, actualCash: 5, discrepancy: 0, submittedBy: 's@x.com', timestamp: ago(1) }),
      put(`dailyStats/north_${DAY}`, { canteenId: 'north', canteenName: 'North', date: DAY, totalSales: 200, totalBills: 2, totalCash: 100, totalUpi: 0, totalCredit: 100, creditReceived: 10 }),
      put(`dailyStats/south_${DAY}`, { canteenId: 'south', canteenName: 'South', date: DAY, totalSales: 50, totalBills: 1, totalCash: 50 }),
      put('notifications/nt-n', { canteenId: 'north', title: 'N', message: 'm', readBy: [], timestamp: ago(0) }),
      put('notifications/nt-s', { canteenId: 'south', title: 'S', message: 'm', readBy: [], timestamp: ago(0) }),
      put('menuItems/north_TEA', { code: 'TEA', name: 'Tea', canteenId: 'north', fullPrice: 10, costPrice: 4 }),
      put('menuItems/south_TEA', { code: 'TEA', name: 'Tea', canteenId: 'south', fullPrice: 11, costPrice: 4 }),
      put('monthlyFunds/2026-11', { fundAmount: 100000, monthYear: '2026-11' }),
      put('counters/billCounter_north', { canteenId: 'north', lastNumber: 5 }),
      put('counters/billCounter', { lastNumber: 40 }),
    ]);
  });
}
beforeEach(async () => { await seed(cand); await seed(open); });

const as = (env, uid, email) => env.authenticatedContext(uid, email ? { email } : {}).firestore();
const N = (env) => as(env, 'cashier-north', 'n@x.com');
const S = (env) => as(env, 'cashier-south', 's@x.com');
const A = (env) => as(env, 'admin-1', 'admin@x.com');
const STRANGER = (env) => as(env, 'stranger', 'x@x.com'); // signed in, NOT staff
const RANGE = [where('timestamp', '>=', ago(30)), where('timestamp', '<', Timestamp.fromDate(new Date('2026-12-01')))];
const ok = async (p) => { await assertSucceeds(p); };
const no = async (p) => { await assertFails(p); };

// ===========================================================================
describe('A. The deployed rules are wide open; the candidate closes each hole', () => {
  // [scenario name, action(env) -> promise]
  const attacks = [
    ['a signed-in stranger (no staff record) reads every bill', (e) => getDocs(collection(STRANGER(e), 'bills'))],
    ['a signed-in stranger reads the staff list', (e) => getDocs(collection(STRANGER(e), 'canteenStaff'))],
    ['a stranger creates a staff record for himself as admin', (e) => setDoc(doc(STRANGER(e), 'canteenStaff/stranger'), { role: 'admin', canteenId: 'main' })],
    ['a cashier promotes himself to admin', (e) => updateDoc(doc(N(e), 'canteenStaff/cashier-north'), { role: 'admin' })],
    ['a cashier moves himself to another branch', (e) => updateDoc(doc(N(e), 'canteenStaff/cashier-north'), { canteenId: 'south' })],
    ['a deactivated cashier keeps working', (e) => getDocs(query(collection(as(e, 'cashier-off'), 'bills'), where('canteenId', '==', 'north')))],
    ['a cashier reads another branch bill', (e) => getDoc(doc(N(e), 'bills/s1'))],
    ['a cashier lists all bills of all branches', (e) => getDocs(collection(N(e), 'bills'))],
    ['a cashier deletes a bill', (e) => deleteDoc(doc(N(e), 'bills/n1'))],
    ['a cashier rewrites a bill amount', (e) => updateDoc(doc(N(e), 'bills/n1'), { totalAmount: 1 })],
    ['a cashier deletes a repayment', (e) => deleteDoc(doc(N(e), 'repayments/r-n'))],
    ['a cashier edits a submitted cash closing', (e) => updateDoc(doc(N(e), `cashReconciliations/north_${DAY}`), { actualCash: 999 })],
    ['a cashier deletes an expense', (e) => deleteDoc(doc(N(e), 'expenses/e-n'))],
    ['a cashier lowers daily sales', (e) => updateDoc(doc(N(e), `dailyStats/north_${DAY}`), { totalSales: 1 })],
    ['a cashier sets the monthly fund', (e) => setDoc(doc(N(e), 'monthlyFunds/2026-11'), { fundAmount: 1 })],
    ['a cashier writes a notice to all branches', (e) => setDoc(doc(N(e), 'notifications/fake'), { canteenId: 'south', title: 'x', message: 'y' })],
    ['a cashier resets the bill counter', (e) => setDoc(doc(N(e), 'counters/billCounter_north'), { canteenId: 'north', lastNumber: 1 })],
    ['a cashier creates a canteen', (e) => setDoc(doc(N(e), 'canteens/evil'), { name: 'Evil' })],
    ['anyone writes to an unknown collection', (e) => setDoc(doc(N(e), 'secrets/x'), { a: 1 })],
  ];
  for (const [name, act] of attacks) {
    test(`${name}: DEPLOYED allows, CANDIDATE denies`, async () => {
      await ok(act(open));
      await no(act(cand));
    });
  }
});

// ===========================================================================
describe('B. Authentication and active-staff boundary (candidate)', () => {
  const identities = {
    unauthenticated: (e) => e.unauthenticatedContext().firestore(),
    'signed in, no staff record': STRANGER,
    'deactivated cashier (active:false)': (e) => as(e, 'cashier-off', 'off@x.com'),
    'role written as "Admin" (wrong case)': (e) => as(e, 'user-badrole', 'bad@x.com'),
    'staff record without role': (e) => as(e, 'user-norole', 'nr@x.com'),
    'cashier whose staff record has NO canteenId (no implicit main)': (e) => as(e, 'cashier-main', 'cashier-main@x.com'),
  };
  const reads = ['bills', 'expenses', 'creditCustomers', 'repayments', 'cashReconciliations', 'dailyStats', 'notifications', 'menuItems'];
  for (const [who, db] of Object.entries(identities)) {
    test(`${who}: cannot read any business data, scoped or not`, async () => {
      for (const c of reads) {
        await no(getDocs(query(collection(db(cand), c), where('canteenId', '==', 'north'))));
        await no(getDocs(collection(db(cand), c)));
      }
      // The organisation-wide fund is readable by ANY active staff member (by decision),
      // so a branch-less cashier may read it; everyone else listed here may not.
      const fund = getDoc(doc(db(cand), 'monthlyFunds/2026-11'));
      if (who.startsWith('cashier whose staff record has NO canteenId')) await ok(fund); else await no(fund);
      await no(getDoc(doc(db(cand), 'counters/billCounter_north')));
    });
    test(`${who}: cannot write business data`, async () => {
      await no(setDoc(doc(db(cand), 'expenses/x1'), { canteenId: 'north', userId: 'whoever', amount: 5 }));
      await no(setDoc(doc(db(cand), 'bills/x2'), { canteenId: 'north', createdBy: 'whoever', items: [], totalAmount: 1, paymentMode: 'Cash', timestamp: serverTimestamp() }));
      await no(setDoc(doc(db(cand), 'menuItems/x3'), { canteenId: 'north', name: 'x' }));
    });
  }
  test('staff members (not admins) can only read their OWN staff record; inactive ones too, so the app can explain', async () => {
    await ok(getDoc(doc(N(cand), 'canteenStaff/cashier-north')));
    await no(getDoc(doc(N(cand), 'canteenStaff/cashier-south')));
    await ok(getDoc(doc(as(cand, 'cashier-off'), 'canteenStaff/cashier-off')));
    await no(getDocs(collection(N(cand), 'canteenStaff')));
  });
  test('a user with no staff record can still ask for their own (missing) record, to be told "role not found"', async () => {
    const s = await assertSucceeds(getDoc(doc(STRANGER(cand), 'canteenStaff/stranger')));
    assert.equal(s.exists(), false);
  });
});

// ===========================================================================
describe('C. Privilege escalation is impossible for non-admins', () => {
  test('a cashier cannot create, change, delete or list staff records', async () => {
    await no(setDoc(doc(N(cand), 'canteenStaff/new'), { role: 'cashier', canteenId: 'north' }));
    await no(updateDoc(doc(N(cand), 'canteenStaff/cashier-north'), { role: 'admin' }));
    await no(updateDoc(doc(N(cand), 'canteenStaff/cashier-north'), { canteenId: 'south' }));
    await no(updateDoc(doc(N(cand), 'canteenStaff/cashier-north'), { active: true }));
    await no(deleteDoc(doc(N(cand), 'canteenStaff/cashier-north')));
    await no(updateDoc(doc(N(cand), 'canteenStaff/cashier-south'), { active: false }));
    await no(getDocs(collection(N(cand), 'canteenStaff')));
  });
  test('a cashier cannot touch canteens', async () => {
    await no(getDoc(doc(N(cand), 'canteens/north')));
    await no(getDocs(collection(N(cand), 'canteens')));
    await no(setDoc(doc(N(cand), 'canteens/evil'), { name: 'x' }));
  });
  test('an admin can manage staff and canteens (the admin dashboard operations, exact payloads)', async () => {
    const a = A(cand);
    // admin_dashboard_page.dart: add staff / change branch / remove staff
    await ok(setDoc(doc(a, 'canteenStaff/new-uid'), { email: 'n2@x.com', role: 'cashier', canteenId: 'north', canteenName: 'North', createdAt: serverTimestamp() }));
    await ok(updateDoc(doc(a, 'canteenStaff/new-uid'), { canteenId: 'south', canteenName: 'South' }));
    await ok(getDocs(query(collection(a, 'canteenStaff'), orderBy('email'))));
    await ok(getDocs(query(collection(a, 'canteenStaff'), where('canteenId', '==', 'south'))));
    await ok(deleteDoc(doc(a, 'canteenStaff/new-uid')));
    // canteens: create, rename (+ batch rename on staff), delete
    await ok(setDoc(doc(a, 'canteens/east'), { name: 'East', createdAt: serverTimestamp() }));
    await ok(updateDoc(doc(a, 'canteens/east'), { name: 'East Block' }));
    const b = writeBatch(a); b.update(doc(a, 'canteenStaff/cashier-south'), { canteenName: 'South Block' }); await ok(b.commit());
    await ok(deleteDoc(doc(a, 'canteens/east')));
  });
  test('an admin who is deactivated loses admin power immediately', async () => {
    await env_admin_deactivate();
    await no(getDocs(collection(A(cand), 'bills')));
    await no(setDoc(doc(A(cand), 'canteenStaff/x'), { role: 'admin' }));
  });
  async function env_admin_deactivate() {
    await cand.withSecurityRulesDisabled(async (ctx) => { await updateDoc(doc(ctx.firestore(), 'canteenStaff/admin-1'), { active: false }); });
  }
});

// ===========================================================================
describe('D. Canteen isolation, collection by collection (candidate)', () => {
  const docs = {
    bills: ['n1', 's1'], expenses: ['e-n', 'e-s'], creditCustomers: ['north_900', 'south_800'],
    repayments: ['r-n', 'r-s'], dailyStats: [`north_${DAY}`, `south_${DAY}`],
    notifications: ['nt-n', 'nt-s'], menuItems: ['north_TEA', 'south_TEA'],
    cashReconciliations: [`north_${DAY}`, 'south_2026-11-01'],
  };
  for (const [c, [mine, theirs]] of Object.entries(docs)) {
    test(`${c}: own branch readable, other branch not, queries must be scoped`, async () => {
      const db = N(cand);
      await ok(getDoc(doc(db, `${c}/${mine}`)));
      await no(getDoc(doc(db, `${c}/${theirs}`)));
      const own = await assertSucceeds(getDocs(query(collection(db, c), where('canteenId', '==', 'north'))));
      assert.ok(own.size >= 1);
      assert.ok(own.docs.every((d) => (d.data().canteenId ?? 'main') === 'north'));
      await no(getDocs(query(collection(db, c), where('canteenId', '==', 'south'))));
      await no(getDocs(collection(db, c)));
    });
    test(`${c}: admin reads every branch`, async () => {
      const all = await assertSucceeds(getDocs(collection(A(cand), c)));
      assert.ok(all.size >= 2);
    });
  }
  test('creating records for another branch is denied (bills, expenses, repayments, customers, closings, items)', async () => {
    const db = N(cand);
    await no(setDoc(doc(db, 'expenses/x'), { canteenId: 'south', userId: 'cashier-north', amount: 5, timestamp: ago(0) }));
    await no(setDoc(doc(db, 'repayments/x'), { canteenId: 'south', amount: 5, timestamp: serverTimestamp() }));
    await no(setDoc(doc(db, 'creditCustomers/south_1'), { canteenId: 'south', phone: '1', totalPending: 0 }));
    await no(setDoc(doc(db, 'menuItems/x'), { canteenId: 'south', name: 'x' }));
    await no(setDoc(doc(db, 'cashReconciliations/south_x'), { canteenId: 'south', date: DAY, actualCash: 1, submittedByUid: 'cashier-north', timestamp: serverTimestamp() }));
    await no(setDoc(doc(db, 'bills/x'), { canteenId: 'south', createdBy: 'cashier-north', items: [], totalAmount: 1, paymentMode: 'Cash', timestamp: serverTimestamp() }));
    await no(setDoc(doc(db, 'dailyStats/south_2026-11-03'), { canteenId: 'south', date: '2026-11-03', totalSales: 1 }));
    await no(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 1 }));
  });
  test('moving a record to another branch by update is denied', async () => {
    await no(updateDoc(doc(N(cand), 'menuItems/north_TEA'), { canteenId: 'south' }));
    await no(updateDoc(doc(N(cand), 'creditCustomers/north_900'), { canteenId: 'south' }));
    await no(updateDoc(doc(N(cand), 'bills/n-credit'), { canteenId: 'south' }));
  });
  test('a staff record WITHOUT canteenId has no branch at all: no implicit main, nothing readable or writable', async () => {
    const m = as(cand, 'cashier-main', 'cashier-main@x.com');
    await no(getDocs(query(collection(m, 'bills'), where('canteenId', '==', 'main'))));
    await no(getDoc(doc(m, 'bills/m1')));
    await no(getDoc(doc(m, 'bills/legacy1')));
    await no(setDoc(doc(m, 'expenses/z'), { canteenId: 'main', userId: 'cashier-main', amount: 5, timestamp: ago(0) }));
    await no(getDoc(doc(m, 'counters/billCounter_main')));
  });
  test('branch "main" (explicit canteenId): scoped queries work, legacy untagged records are admin-only', async () => {
    for (const uid of ['cashier-main-explicit']) {
      const m = as(cand, uid, `${uid}@x.com`);
      const own = await assertSucceeds(getDocs(query(collection(m, 'bills'), where('canteenId', '==', 'main'))));
      assert.ok(own.docs.every((d) => d.data().canteenId === 'main'));
      await no(getDoc(doc(m, 'bills/legacy1')));                // untagged: no longer readable by non-admins
      await no(getDoc(doc(m, 'bills/n1')));
      await no(getDocs(query(collection(m, 'bills'), where('canteenId', '==', 'north'))));
    }
    await ok(getDoc(doc(A(cand), 'bills/legacy1')));            // admin still can (and will tag them in the backfill)
  });
  test('REGRESSION (found in this review): branch "main" staff cannot list other branches by omitting the filter', async () => {
    const collections = ['bills', 'expenses', 'creditCustomers', 'repayments', 'cashReconciliations', 'dailyStats', 'notifications', 'menuItems'];
    for (const uid of ['cashier-main', 'cashier-main-explicit']) {
      const m = as(cand, uid, `${uid}@x.com`);
      for (const c of collections) {
        await no(getDocs(collection(m, c)));
        await no(getDocs(query(collection(m, c), orderBy('canteenId'))));
        await no(getDocs(query(collection(m, c), where('canteenId', '!=', 'main'))));
        await no(getDocs(query(collection(m, c), where('canteenId', 'in', ['main', 'north']))));
      }
    }
  });
  test('the same unfiltered list WAS allowed by the repository rules for branch main (documents why the helper changed)', async () => {
    const repoEnv = await mk('demo-sec-repo-main', read('firestore.rules'));
    await seed(repoEnv);
    await repoEnv.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'canteenStaff/cashier-main-explicit'), { role: 'cashier', canteenId: 'main' }); });
    const all = await assertSucceeds(getDocs(collection(as(repoEnv, 'cashier-main-explicit', 'x@x.com'), 'bills')));
    assert.ok(new Set(all.docs.map((d) => d.data().canteenId)).size > 1, 'it returned several branches');
    await repoEnv.cleanup();
  });
});

// ===========================================================================
describe('E. Every cashier operation of the app, with its real payload (candidate)', () => {
  test('sign-in: own staff record; connection probe; role lookup', async () => {
    await ok(getDoc(doc(N(cand), 'canteenStaff/cashier-north')));      // role_splash_page / canteen_provider
  });

  test('dashboard: today card query, notices query, budget banner (fund + expenses)', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'dailyStats'), where('canteenId', '==', 'north'), where('date', '==', DAY), limit(1))));
    await ok(getDocs(query(collection(db, 'notifications'), where('canteenId', '==', 'north'), orderBy('timestamp', 'desc'), limit(1))));
    await ok(getDoc(doc(db, 'monthlyFunds/2026-11')));
    const missingFund = await assertSucceeds(getDoc(doc(db, 'monthlyFunds/2030-01'))); // month without a fund: allowed, not found
    assert.equal(missingFund.exists(), false);
    await ok(getDocs(query(collection(db, 'expenses'), where('canteenId', '==', 'north'), ...RANGE)));
  });

  test('bill lists: today, daily report, history, monthly breakdown, bill detail', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'north'), ...RANGE, orderBy('timestamp', 'desc'))));
    await ok(getDoc(doc(db, 'bills/n1')));
  });

  test('menu: list, billing screen fetch, add, edit; delete is denied', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'menuItems'), where('canteenId', '==', 'north'), orderBy('name'))));     // add_item list
    await ok(getDocs(query(collection(db, 'menuItems'), where('canteenId', '==', 'north'))));                     // print_bill / menu_view
    const item = { code: 'VADA', name: 'Vada', canteenId: 'north', canteenName: 'North', fullPrice: 12, costPrice: 5, halfPrice: 7 };
    await ok(setDoc(doc(db, 'menuItems/north_VADA'), item));                                                       // add
    await ok(setDoc(doc(db, 'menuItems/north_VADA'), { ...item, fullPrice: 15 }));                                  // edit (set on existing)
    await no(deleteDoc(doc(db, 'menuItems/north_VADA')));                                                          // business decision
    await no(deleteDoc(doc(db, 'menuItems/north_TEA')));
  });

  test('notices: list and mark as read (arrayUnion of own uid only)', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'notifications'), where('canteenId', '==', 'north'), orderBy('timestamp', 'desc'))));
    await ok(updateDoc(doc(db, 'notifications/nt-n'), { readBy: arrayUnion('cashier-north') }));
    await no(updateDoc(doc(db, 'notifications/nt-n'), { readBy: arrayUnion('somebody-else') }));
    await no(updateDoc(doc(db, 'notifications/nt-n'), { title: 'tampered' }));
    await no(updateDoc(doc(db, 'notifications/nt-s'), { readBy: arrayUnion('cashier-north') }));
  });

  test('expense: create with the exact payload (userId == uid, positive amount); cannot edit or delete', async () => {
    const db = N(cand);
    const e = { category: 'Gas', description: 'Gas', amount: 80.75, proofImageBase64: 'AAAA', timestamp: Timestamp.fromDate(new Date()), userId: 'cashier-north', canteenId: 'north', canteenName: 'North' };
    await ok(setDoc(doc(db, 'expenses/new-exp'), e));
    await no(setDoc(doc(db, 'expenses/new-exp'), e));                       // repeat = update: denied (the app then confirms by read)
    await ok(getDoc(doc(db, 'expenses/new-exp')));
    await no(updateDoc(doc(db, 'expenses/new-exp'), { amount: 1 }));
    await no(deleteDoc(doc(db, 'expenses/new-exp')));
  });

  test('credit: customer list (scoped), customer doc, customer-exists check, repayment history', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'creditCustomers'), where('canteenId', '==', 'north'))));
    await ok(getDoc(doc(db, 'creditCustomers/north_900')));
    await ok(getDocs(query(collection(db, 'creditCustomers'), where('canteenId', '==', 'north'), where('phone', '==', '900'), limit(1))));
    await ok(getDocs(query(collection(db, 'repayments'), where('customerPhone', '==', '900'), where('canteenId', '==', 'north'))));
    await ok(getDocs(query(collection(db, 'bills'), where('customerPhone', '==', '900'), where('canteenId', '==', 'north'), where('creditStatus', '==', 'Pending'))));
  });

  test('cash closing: today queries, create with the exact (new) payload; cannot be edited or deleted', async () => {
    const db = N(cand);
    await ok(getDocs(query(collection(db, 'cashReconciliations'), where('canteenId', '==', 'north'), where('date', '==', '2026-12-31'), limit(1))));
    await ok(getDocs(query(collection(db, 'cashReconciliations'), where('canteenId', '==', 'north'), orderBy('timestamp', 'desc'), limit(30))));
    const payload = { date: '2026-12-31', canteenId: 'north', canteenName: 'North', systemCash: 500, actualCash: 500, discrepancy: 0, note: '', submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: serverTimestamp() };
    await ok(runTransaction(db, async (tx) => { tx.set(doc(db, 'cashReconciliations/north_2026-12-31'), payload); }));
    await no(updateDoc(doc(db, 'cashReconciliations/north_2026-12-31'), { actualCash: 1 }));
    await no(deleteDoc(doc(db, 'cashReconciliations/north_2026-12-31')));
  });
});

// ===========================================================================
// Ports of the bill / repayment transactions (identical to transactions.test.mjs)
async function billTx(db, { id, mode = 'Cash', total, phone, name, exists = false, uid = 'cashier-north', branch = 'north', timestamp = serverTimestamp(), extra = {} }) {
  await runTransaction(db, async (tx) => {
    const counterRef = doc(db, 'counters', `billCounter_${branch}`);
    const c = await tx.get(counterRef);
    let num;
    if (c.exists()) num = c.data().lastNumber + 1;
    else if (branch === 'main') {               // print_bill_page.dart: continue the legacy global sequence
      const legacy = await tx.get(doc(db, 'counters', 'billCounter'));
      num = legacy.exists() ? legacy.data().lastNumber + 1 : 1;
    } else num = 1;
    const bill = { billId: `BILL-${num}`, billNumber: num, clientRequestId: id, canteenId: branch, canteenName: branch, totalAmount: total, paymentMode: mode, createdBy: uid, createdByEmail: 'n@x.com', timestamp, items: [{ code: 'A', name: 'A', type: 'Full', quantity: 1, price: total, costPrice: 0, subtotal: total }] };
    if (mode === 'Credit') {
      Object.assign(bill, { customerName: name, customerPhone: phone, creditStatus: 'Pending', pendingAmount: total });
      const cref = doc(db, 'creditCustomers', `${branch}_${phone}`);
      if (exists) tx.update(cref, { totalPending: increment(total), lastUpdated: serverTimestamp(), name });
      else tx.set(cref, { phone, name, canteenId: branch, canteenName: branch, totalPending: increment(total), lastUpdated: serverTimestamp() }, { merge: true });
    }
    Object.assign(bill, extra); // deliberate tampering by the caller wins
    tx.set(doc(db, 'bills', id), bill);
    tx.set(doc(db, 'dailyStats', `${branch}_${DAY}`), { canteenId: branch, canteenName: branch, date: DAY, totalSales: increment(total), totalBills: increment(1), ...(mode === 'Cash' ? { totalCash: increment(total) } : {}), ...(mode === 'UPI' ? { totalUpi: increment(total) } : {}), ...(mode === 'Credit' ? { totalCredit: increment(total) } : {}), lastUpdated: serverTimestamp() }, { merge: true });
    tx.set(counterRef, { canteenId: branch, lastNumber: num });
  });
}

describe('F. Financial protections (bills, repayments, expenses, closings, counters) in the candidate', () => {
  test('a normal cash / UPI / credit bill is accepted (new customer, then existing customer)', async () => {
    const db = N(cand);
    await ok(billTx(db, { id: 'b-cash', mode: 'Cash', total: 50 }));
    await ok(billTx(db, { id: 'b-upi', mode: 'UPI', total: 20.25 }));
    await ok(billTx(db, { id: 'b-cr1', mode: 'Credit', total: 30, phone: '901', name: 'K', exists: false }));
    await ok(billTx(db, { id: 'b-cr2', mode: 'Credit', total: 10, phone: '901', name: 'K', exists: true }));
    const st = (await getDoc(doc(A(cand), `dailyStats/north_${DAY}`))).data();
    assert.equal(st.totalBills, 6); // 2 seeded + 4
  });
  test('bills: back-dating, unknown payment mode, negative total, foreign createdBy, inconsistent credit are all rejected', async () => {
    const db = N(cand);
    await no(billTx(db, { id: 'x1', total: 5, timestamp: ago(10) }));                       // back-dated
    await no(billTx(db, { id: 'x2', total: 5, mode: 'Cash', extra: { paymentMode: 'Barter' } }));
    await no(billTx(db, { id: 'x3', total: -5 }));
    await no(billTx(db, { id: 'x4', total: 5, uid: 'cashier-south' }));                       // signed as someone else
    await no(billTx(db, { id: 'x5', mode: 'Credit', total: 5, phone: '902', name: 'Z', extra: { creditStatus: 'Paid' } }));     // credit bill born "Paid"
    await no(billTx(db, { id: 'x6', mode: 'Credit', total: 5, phone: '903', name: 'Z', extra: { pendingAmount: 0 } }));        // credit bill born with nothing pending
  });
  test('bills: nobody but an admin can delete, and a paid-off bill cannot be re-opened or inflated by a cashier', async () => {
    const db = N(cand);
    await no(deleteDoc(doc(db, 'bills/n1')));
    await no(updateDoc(doc(db, 'bills/n1'), { totalAmount: 1 }));
    await no(updateDoc(doc(db, 'bills/n1'), { pendingAmount: 0 }));                          // not a credit bill
    await ok(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: 60 }));                   // repayment part
    await no(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: 80 }));                   // raising the pending amount
    await ok(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: 0, creditStatus: 'Paid' }));
    await no(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: 50, creditStatus: 'Pending' })); // reopening a paid bill
    await no(updateDoc(doc(db, 'bills/n-credit'), { creditStatus: 'Whatever' }));
    await ok(deleteDoc(doc(A(cand), 'bills/n1')));
  });
  test('bills: "Paid" with money still pending is rejected; negative pending is rejected', async () => {
    const db = N(cand);
    await no(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: 10, creditStatus: 'Paid' }));
    await no(updateDoc(doc(db, 'bills/n-credit'), { pendingAmount: -1 }));
  });
  test('bills: totals, items and customer fields cannot be changed by a cashier', async () => {
    const db = N(cand);
    for (const patch of [{ totalAmount: 1 }, { items: [{ name: 'x' }] }, { customerPhone: '1' }, { paymentMode: 'Cash' }, { createdBy: 'x' }, { timestamp: serverTimestamp() }]) {
      await no(updateDoc(doc(db, 'bills/n-credit'), patch));
    }
  });
  test('bill numbers: only +1 per branch, other branches and resets are denied, no listing', async () => {
    const db = N(cand);
    await no(setDoc(doc(db, 'counters/billCounter_north'), { canteenId: 'north', lastNumber: 99 }));
    await no(setDoc(doc(db, 'counters/billCounter_north'), { canteenId: 'north', lastNumber: 1 }));
    await no(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 1 }));
    await no(getDocs(collection(db, 'counters')));
    await ok(getDoc(doc(db, 'counters/billCounter')));                                       // legacy sequence for main
    await no(getDoc(doc(db, 'counters/billCounter_south')));
    await ok(updateDoc(doc(db, 'counters/billCounter_north'), { lastNumber: 6 }));
    await no(deleteDoc(doc(db, 'counters/billCounter_north')));
  });
  test('daily statistics can only grow for a cashier, keep their keys, and are never deleted', async () => {
    const db = N(cand);
    await no(updateDoc(doc(db, `dailyStats/north_${DAY}`), { totalSales: 1 }));
    await no(updateDoc(doc(db, `dailyStats/north_${DAY}`), { totalCash: 0 }));
    await no(updateDoc(doc(db, `dailyStats/north_${DAY}`), { canteenId: 'south' }));
    await no(updateDoc(doc(db, `dailyStats/north_${DAY}`), { date: '2020-01-01' }));
    await no(updateDoc(doc(db, `dailyStats/north_${DAY}`), { secretField: 1 }));
    await no(deleteDoc(doc(db, `dailyStats/north_${DAY}`)));
    await ok(updateDoc(doc(db, `dailyStats/north_${DAY}`), { totalSales: increment(10), totalBills: increment(1) }));
  });
  test('credit customers: a cashier cannot change phone or branch, cannot delete, cannot create a negative balance', async () => {
    const db = N(cand);
    await no(updateDoc(doc(db, 'creditCustomers/north_900'), { phone: '1' }));
    await no(updateDoc(doc(db, 'creditCustomers/north_900'), { canteenId: 'south' }));
    await no(updateDoc(doc(db, 'creditCustomers/north_900'), { totalPending: -5 }));
    await no(deleteDoc(doc(db, 'creditCustomers/north_900')));
    await no(setDoc(doc(db, 'creditCustomers/north_7'), { phone: '7', canteenId: 'north', totalPending: -1 }));
    await ok(updateDoc(doc(db, 'creditCustomers/north_900'), { totalPending: 50, lastUpdated: serverTimestamp(), name: 'Ravi K' }));
  });
  test('repayments: positive, server-timed, own branch; never edited or deleted by a cashier', async () => {
    const db = N(cand);
    const rep = { customerPhone: '900', customerName: 'Ravi', canteenId: 'north', canteenName: 'North', amount: 25, paymentMode: 'Cash', timestamp: serverTimestamp(), clientRequestId: 'req_1', processedBy: 'n@x.com' };
    await ok(setDoc(doc(db, 'repayments/req_1'), rep));
    await no(setDoc(doc(db, 'repayments/req_1'), rep));                                     // duplicate id = update
    await no(setDoc(doc(db, 'repayments/req_2'), { ...rep, amount: 0 }));
    await no(setDoc(doc(db, 'repayments/req_3'), { ...rep, amount: -5 }));
    await no(setDoc(doc(db, 'repayments/req_4'), { ...rep, timestamp: ago(20) }));          // back-dated
    await no(updateDoc(doc(db, 'repayments/req_1'), { amount: 1 }));
    await no(deleteDoc(doc(db, 'repayments/r-n')));
    await ok(deleteDoc(doc(A(cand), 'repayments/r-n')));
  });
  test('expenses: signed by the caller, positive amount, branch bound', async () => {
    const db = N(cand);
    const e = { canteenId: 'north', userId: 'cashier-north', amount: 5, description: 'x', timestamp: ago(0) };
    await no(setDoc(doc(db, 'expenses/y1'), { ...e, userId: 'cashier-south' }));            // signed as someone else
    await no(setDoc(doc(db, 'expenses/y2'), { ...e, amount: 0 }));
    await no(setDoc(doc(db, 'expenses/y3'), { ...e, amount: -9 }));
    await no(setDoc(doc(db, 'expenses/y4'), { ...e, amount: 'five' }));
    await ok(setDoc(doc(db, 'expenses/y5'), e));
  });
  test('cash closing: must be signed by the caller; back-dating, other identities and edits are rejected', async () => {
    const db = N(cand);
    const base = { date: '2027-01-05', canteenId: 'north', systemCash: 10, actualCash: 10, discrepancy: 0, note: '' };
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-01-05'), { ...base, submittedBy: 's@x.com', submittedByUid: 'cashier-south', timestamp: serverTimestamp() })));
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-01-05'), { ...base, submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: ago(5) })));
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-01-05'), { ...base, actualCash: -1, submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: serverTimestamp() })));
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-01-05'), { ...base, timestamp: serverTimestamp() }))); // anonymous closing
    await no(updateDoc(doc(db, `cashReconciliations/north_${DAY}`), { actualCash: 1 }));
    await ok(updateDoc(doc(A(cand), `cashReconciliations/north_${DAY}`), { note: 'audited' })); // admin audit stays possible
  });
  test('monthly fund and canteens: read by active staff / admin only; written by admin only', async () => {
    await ok(getDoc(doc(N(cand), 'monthlyFunds/2026-11')));
    await no(setDoc(doc(N(cand), 'monthlyFunds/2026-11'), { fundAmount: 5 }));
    await no(deleteDoc(doc(N(cand), 'monthlyFunds/2026-11')));
    await ok(setDoc(doc(A(cand), 'monthlyFunds/2026-12'), { fundAmount: 5000, lastUpdated: serverTimestamp(), updatedBy: 'admin@x.com', monthLabel: 'December 2026' })); // funds_received_page payload
    await ok(setDoc(doc(A(cand), 'monthlyFunds/2026-11'), { fundAmount: 7000, lastUpdated: Timestamp.now(), monthYear: '2026-11' }, { merge: true })); // admin_monthly_cashflow payload
    await no(setDoc(doc(A(cand), 'monthlyFunds/2027-01'), { fundAmount: -1 }));
  });
  test('notices: only an admin can send or delete', async () => {
    const n = { title: 'Hi', message: 'Msg', timestamp: Timestamp.now(), sentBy: 'admin@x.com', canteenId: 'north', canteenName: 'North' };
    await no(setDoc(doc(N(cand), 'notifications/x'), n));
    await ok(setDoc(doc(A(cand), 'notifications/x'), n));                                    // send_notification_page payload
    await no(deleteDoc(doc(N(cand), 'notifications/nt-n')));
    await ok(deleteDoc(doc(A(cand), 'notifications/nt-n')));
  });
});

// ===========================================================================
describe('E2. Branch "main" works end to end (staff record with canteenId: "main")', () => {
  for (const [uid, label] of [['cashier-main-explicit', 'explicit main']]) {
    test(`${label}: bill (cash, UPI, credit), repayment, expense, closing, menu, queries`, async () => {
      const email = `${uid}@x.com`;
      const db = as(cand, uid, email);
      // bills continue the legacy sequence (counters/billCounter = 40 -> first bill is 41)
      await ok(billTx(db, { id: `m-cash-${uid}`, branch: 'main', uid, mode: 'Cash', total: 80 }));
      assert.equal((await getDoc(doc(A(cand), `bills/m-cash-${uid}`))).data().billNumber, 41);
      await ok(billTx(db, { id: `m-upi-${uid}`, branch: 'main', uid, mode: 'UPI', total: 20.5 }));
      await ok(billTx(db, { id: `m-cr1-${uid}`, branch: 'main', uid, mode: 'Credit', total: 60, phone: '950', name: 'M', exists: false }));
      await ok(billTx(db, { id: `m-cr2-${uid}`, branch: 'main', uid, mode: 'Credit', total: 15, phone: '950', name: 'M', exists: true }));
      // repayment: oldest bill first (bill update + customer update + repayment + stats), as _processRepayment does
      await ok(runTransaction(db, async (tx) => {
        const b1 = doc(db, `bills/m-cr1-${uid}`); const b2 = doc(db, `bills/m-cr2-${uid}`); const cust = doc(db, 'creditCustomers/main_950');
        await tx.get(b1); await tx.get(b2); await tx.get(cust);
        tx.update(b1, { pendingAmount: 0.0, creditStatus: 'Paid' });
        tx.update(b2, { pendingAmount: 10 });
        tx.update(cust, { totalPending: increment(-65), lastUpdated: serverTimestamp() });
        tx.set(doc(db, `repayments/rep-${uid}`), { customerPhone: '950', customerName: 'M', canteenId: 'main', canteenName: 'Main Canteen', amount: 65, paymentMode: 'Cash', timestamp: serverTimestamp(), clientRequestId: `rep-${uid}`, processedBy: email });
        tx.set(doc(db, `dailyStats/main_${DAY}`), { canteenId: 'main', canteenName: 'Main Canteen', date: DAY, totalCash: increment(65), creditReceived: increment(65), lastUpdated: serverTimestamp() }, { merge: true });
      }));
      assert.equal((await getDoc(doc(A(cand), 'creditCustomers/main_950'))).data().totalPending, 10);
      // expense, closing (new payload), menu, queries
      await ok(setDoc(doc(db, `expenses/exp-${uid}`), { category: 'Gas', description: 'Gas', amount: 40, timestamp: Timestamp.now(), userId: uid, canteenId: 'main', canteenName: 'Main Canteen' }));
      await ok(runTransaction(db, async (tx) => tx.set(doc(db, `cashReconciliations/main_${DAY}_${uid}`), { date: DAY, canteenId: 'main', canteenName: 'Main Canteen', systemCash: 145, actualCash: 145, discrepancy: 0, note: '', submittedBy: email, submittedByUid: uid, timestamp: serverTimestamp() })));
      await ok(setDoc(doc(db, `menuItems/main_T-${uid}`), { code: 'T', name: 'Tea', canteenId: 'main', canteenName: 'Main Canteen', fullPrice: 10, costPrice: 4 }));
      await no(deleteDoc(doc(db, `menuItems/main_T-${uid}`)));
      for (const c of ['bills', 'expenses', 'creditCustomers', 'repayments', 'dailyStats', 'cashReconciliations', 'menuItems']) {
        const r = await assertSucceeds(getDocs(query(collection(db, c), where('canteenId', '==', 'main'))));
        assert.ok(r.docs.every((d) => d.data().canteenId === 'main'), c);
      }
      await ok(getDocs(query(collection(db, 'dailyStats'), where('canteenId', '==', 'main'), where('date', '==', DAY), limit(1))));
      await ok(getDocs(query(collection(db, 'notifications'), where('canteenId', '==', 'main'), orderBy('timestamp', 'desc'))));
      await ok(getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'main'), ...RANGE, orderBy('timestamp', 'desc'))));
      await ok(getDoc(doc(db, 'counters/billCounter_main')));
      await no(getDoc(doc(db, 'counters/billCounter_north')));
    });
  }
});

// ===========================================================================
describe('G. Admin operations of the app (candidate), exact queries', () => {
  test('dashboard, analytics, export and reports read every branch', async () => {
    const a = A(cand);
    await ok(getDocs(query(collection(a, 'bills'), ...RANGE)));                                       // admin_dashboard today/month
    await ok(getDocs(query(collection(a, 'bills'), orderBy('timestamp', 'desc'), limit(4))));
    await ok(getDocs(collection(a, 'creditCustomers')));
    await ok(getDocs(query(collection(a, 'dailyStats'), where('date', '>=', '2026-10-01'))));
    await ok(getDocs(query(collection(a, 'expenses'), orderBy('timestamp', 'desc'))));                // expense report
    await ok(getDocs(query(collection(a, 'creditCustomers'), orderBy('totalPending', 'desc'))));
    await ok(getDocs(query(collection(a, 'bills'), where('paymentMode', '==', 'Credit'))));           // master credit ledger
    await ok(getDocs(collection(a, 'monthlyFunds')));
    await ok(getDocs(collection(a, 'canteens')));
    await ok(getDocs(query(collection(a, 'repayments'), orderBy('timestamp', 'desc'))));             // export
    await ok(getDocs(query(collection(a, 'cashReconciliations'), orderBy('timestamp', 'desc'), limit(30))));
    await ok(getDocs(query(collection(a, 'bills'), where('canteenId', '==', 'north'), where('timestamp', '>=', ago(30)), orderBy('timestamp', 'desc')))); // analytics, branch
  });
  test('admin can delete menu items, bills and every other record (the single place deletion is allowed)', async () => {
    const a = A(cand);
    await ok(deleteDoc(doc(a, 'menuItems/north_TEA')));
    await ok(deleteDoc(doc(a, 'menuItems/south_TEA')));
    await ok(deleteDoc(doc(a, 'bills/s1')));
    await ok(deleteDoc(doc(a, 'expenses/e-s')));
    await ok(deleteDoc(doc(a, 'creditCustomers/south_800')));
  });
  test('admin can edit a legacy menu item without a canteenId (needed by the later backfill)', async () => {
    await cand.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), 'menuItems/legacy-item'), { name: 'Old', fullPrice: 5 }); });
    await ok(updateDoc(doc(A(cand), 'menuItems/legacy-item'), { canteenId: 'main' }));
    await ok(updateDoc(doc(A(cand), 'creditCustomers/north_900'), { canteenId: 'north', totalPending: 5 }));
  });
});

// ===========================================================================
describe('H. Anything not explicitly allowed is denied (candidate)', () => {
  for (const who of ['cashier', 'admin']) {
    const db = (e) => (who === 'admin' ? A(e) : N(e));
    test(`${who}: unknown collections, sub-collections and root documents`, async () => {
      await no(getDoc(doc(db(cand), 'secrets/x')));
      await no(setDoc(doc(db(cand), 'secrets/x'), { a: 1 }));
      await no(getDocs(collection(db(cand), 'secrets')));
      await no(getDoc(doc(db(cand), 'bills/n1/audit/a1')));
      await no(setDoc(doc(db(cand), 'bills/n1/audit/a1'), { a: 1 }));
      await no(setDoc(doc(db(cand), 'canteenStaff/cashier-north/private/p'), { a: 1 }));
      await no(getDocs(collection(db(cand), 'bills/n1/items')));
    });
  }
  test('collection-group queries are denied for everyone, including admins', async () => {
    const { collectionGroup } = await import('firebase/firestore');
    await no(getDocs(collectionGroup(N(cand), 'bills')));
    await no(getDocs(collectionGroup(A(cand), 'bills')));
  });
});

// ===========================================================================
describe('I. B-32: reading a document that does not exist', () => {
  const missing = ['bills/none', 'creditCustomers/north_none', 'dailyStats/north_2099-01-01', 'cashReconciliations/north_2099-01-01', 'expenses/none', 'repayments/none', 'menuItems/none', 'notifications/none'];
  test('cashiers are denied a get of a missing document (the rules cannot judge its branch)', async () => {
    for (const p of missing) await no(getDoc(doc(N(cand), p)));
  });
  test('admins may read missing documents', async () => {
    for (const p of missing) {
      const s = await assertSucceeds(getDoc(doc(A(cand), p)));
      assert.equal(s.exists(), false);
    }
  });
  test('the exceptions: the fund, own staff record and counters can be read when missing', async () => {
    for (const p of ['monthlyFunds/2099-01', 'canteenStaff/cashier-north', 'counters/billCounter_north', 'counters/billCounter']) {
      await ok(getDoc(doc(N(cand), p)));
    }
  });
  test('the app avoids missing-document reads by querying: own-branch queries return empty instead of failing', async () => {
    const db = N(cand);
    for (const c of ['dailyStats', 'cashReconciliations']) {
      const r = await assertSucceeds(getDocs(query(collection(db, c), where('canteenId', '==', 'north'), where('date', '==', '2099-01-01'), limit(1))));
      assert.equal(r.size, 0);
    }
    const none = await assertSucceeds(getDocs(query(collection(db, 'creditCustomers'), where('canteenId', '==', 'north'), where('phone', '==', 'nobody'), limit(1))));
    assert.equal(none.size, 0);
  });
  test('the rules were NOT loosened to make these reads pass: another branch still cannot be probed', async () => {
    await no(getDoc(doc(N(cand), 'creditCustomers/south_800')));
    await no(getDoc(doc(N(cand), 'creditCustomers/south_none')));
  });
});

// ===========================================================================
describe('J. App builds already in the field (compatibility and known breakage)', () => {
  test('the older e-mail-only closing payload is REFUSED (no fallback): builds without submittedByUid must be gone before phase 2', async () => {
    const db = N(cand);
    const old = { date: '2027-02-01', canteenId: 'north', canteenName: 'North', systemCash: 5, actualCash: 5, discrepancy: 0, note: '', submittedBy: 'n@x.com', timestamp: serverTimestamp() };
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-02-01'), old)));
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-02-02'), { ...old, date: '2027-02-02', submittedBy: 's@x.com' })));
    // the current payload (with the caller's uid) is accepted
    await ok(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-02-04'), { ...old, date: '2027-02-04', submittedByUid: 'cashier-north' })));
  });
  test('the repository rules (without the compatibility clause) would reject that older payload', async () => {
    const repoEnv = await mk('demo-sec-repo', read('firestore.rules'));
    await seed(repoEnv);
    const db = as(repoEnv, 'cashier-north', 'n@x.com');
    await no(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-02-01'), { date: '2027-02-01', canteenId: 'north', systemCash: 5, actualCash: 5, submittedBy: 'n@x.com', timestamp: serverTimestamp() })));
    await repoEnv.cleanup();
  });
  test('KNOWN BREAKAGE for old builds: cashier screens that query by date without canteenId are denied', async () => {
    const db = N(cand);
    await no(getDocs(query(collection(db, 'bills'), ...RANGE)));                                         // old dashboard / today / daily / history / monthly
    await no(getDocs(query(collection(db, 'bills'), ...RANGE, orderBy('timestamp', 'desc'))));
    await no(getDocs(query(collection(db, 'expenses'), ...RANGE)));                                      // old budget banner / funds page
    await no(getDocs(query(collection(db, 'cashReconciliations'), orderBy('timestamp', 'desc'), limit(30)))); // old build forgot the scope only for admins; cashier code is scoped
  });
  test('KNOWN BREAKAGE for old builds: reading missing documents (first credit customer, first closing)', async () => {
    const db = N(cand);
    await no(runTransaction(db, async (tx) => { await tx.get(doc(db, 'creditCustomers/north_newcustomer')); }));
    await no(getDoc(doc(N(cand), `cashReconciliations/north_2099-05-05`)));
  });
});

// ===========================================================================
describe('K. Residual risks that rules alone cannot close (documented, asserted)', () => {
  test('a cashier can still set a customer balance of their own branch to any value >= 0', async () => {
    // The app legitimately raises it (credit sale) and lowers it (repayment) from
    // the client. Rules cannot tell a real repayment from an arbitrary edit
    // without extra data from the app. Mitigation today: every change leaves a
    // bill/repayment trail and the admin master ledger reconciles; see
    // PRODUCTION_SECURITY_MIGRATION.md (phase-2 hardening).
    await ok(updateDoc(doc(N(cand), 'creditCustomers/north_900'), { totalPending: 0 }));
  });
  test('a cashier can still raise their own branch daily totals (they can only never lower them)', async () => {
    await ok(updateDoc(doc(N(cand), `dailyStats/north_${DAY}`), { totalSales: 999999 }));
  });
  test('the closing amounts (systemCash, discrepancy) are client-supplied and not cross-checked by the rules', async () => {
    const db = N(cand);
    await ok(runTransaction(db, async (tx) => tx.set(doc(db, 'cashReconciliations/north_2027-03-01'), { date: '2027-03-01', canteenId: 'north', systemCash: 1, actualCash: 1, discrepancy: 0, submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: serverTimestamp() })));
  });
});

// ===========================================================================
describe('L. Staff lifecycle and invalid payloads (candidate)', () => {
  test('admin deactivates a cashier: access stops at once; reactivation restores it; the cashier cannot undo it', async () => {
    const a = A(cand);
    const n = () => getDocs(query(collection(N(cand), 'bills'), where('canteenId', '==', 'north')));
    await ok(n());
    await ok(updateDoc(doc(a, 'canteenStaff/cashier-north'), { active: false }));       // deactivation (Console or admin tool)
    await no(n());
    await no(updateDoc(doc(N(cand), 'canteenStaff/cashier-north'), { active: true }));   // cannot reactivate themselves
    await ok(getDoc(doc(N(cand), 'canteenStaff/cashier-north')));                        // can still read their own record to be told why
    await ok(updateDoc(doc(a, 'canteenStaff/cashier-north'), { active: true }));
    await ok(n());
  });
  test('admin changes a cashier\'s branch: access follows the trusted staff record immediately', async () => {
    const a = A(cand);
    await ok(updateDoc(doc(a, 'canteenStaff/cashier-north'), { canteenId: 'south', canteenName: 'South' }));
    await no(getDocs(query(collection(N(cand), 'bills'), where('canteenId', '==', 'north'))));
    await ok(getDocs(query(collection(N(cand), 'bills'), where('canteenId', '==', 'south'))));
  });
  test('admin removes the staff record: the user is locked out; the Auth login alone grants nothing', async () => {
    await ok(deleteDoc(doc(A(cand), 'canteenStaff/cashier-north')));
    await no(getDocs(query(collection(N(cand), 'bills'), where('canteenId', '==', 'north'))));
    await no(getDocs(collection(N(cand), 'bills')));
  });
  test('bills: wrong types and missing parts are rejected', async () => {
    const db = N(cand);
    const base = { canteenId: 'north', createdBy: 'cashier-north', items: [], totalAmount: 10, paymentMode: 'Cash', timestamp: serverTimestamp() };
    await ok(setDoc(doc(db, 'bills/inv-ok'), base));
    await no(setDoc(doc(db, 'bills/inv-1'), { ...base, totalAmount: '10' }));            // text, not a number
    await no(setDoc(doc(db, 'bills/inv-2'), { ...base, items: 'x' }));                    // not a list
  });
  test('bills: a bill missing any required field (mode, branch, time, creator, total, items) is rejected', async () => {
    const db = N(cand);
    const full = { canteenId: 'north', createdBy: 'cashier-north', items: [], totalAmount: 10, paymentMode: 'Cash', timestamp: serverTimestamp() };
    for (const drop of ['paymentMode', 'canteenId', 'timestamp', 'createdBy', 'totalAmount', 'items']) {
      const d = { ...full }; delete d[drop];
      await no(setDoc(doc(db, `bills/inv-drop-${drop}`), d));
    }
  });
  test('expenses, repayments, customers, menu items: invalid payloads are rejected', async () => {
    const db = N(cand);
    await no(setDoc(doc(db, 'expenses/i1'), { canteenId: 'north', userId: 'cashier-north' }));                                   // no amount
    await no(setDoc(doc(db, 'expenses/i2'), { userId: 'cashier-north', amount: 5 }));                                           // no canteenId
    await no(setDoc(doc(db, 'repayments/i3'), { canteenId: 'north', timestamp: serverTimestamp() }));                           // no amount
    await no(setDoc(doc(db, 'repayments/i4'), { canteenId: 'north', amount: 5 }));                                              // no server time
    await no(setDoc(doc(db, 'creditCustomers/north_i5'), { canteenId: 'north', phone: 12345, totalPending: 0 }));               // phone not text
    await no(setDoc(doc(db, 'creditCustomers/north_i6'), { canteenId: 'north', phone: '1', totalPending: '5' }));               // balance not a number
    await no(setDoc(doc(db, 'menuItems/i7'), { name: 'x', fullPrice: 1 }));                                                     // no canteenId
    await no(setDoc(doc(db, 'menuItems/i8'), { canteenId: 5, name: 'x' }));                                                     // canteenId not text
  });
  test('daily stats: an unknown key or a missing date/canteen is rejected on create', async () => {
    const db = N(cand);
    await no(setDoc(doc(db, 'dailyStats/north_2027-05-01'), { canteenId: 'north', date: '2027-05-01', totalSales: 1, evil: 1 }));
    await no(setDoc(doc(db, 'dailyStats/north_2027-05-02'), { canteenId: 'north', totalSales: 1 }));
    await no(setDoc(doc(db, 'dailyStats/x_2027-05-03'), { date: '2027-05-03', totalSales: 1 }));
    await ok(setDoc(doc(db, 'dailyStats/north_2027-05-04'), { canteenId: 'north', canteenName: 'North', date: '2027-05-04', totalSales: 1, totalBills: 1, totalCash: 1, lastUpdated: serverTimestamp() }));
  });
  test('counters: extra fields, non-integer or zero numbers are rejected', async () => {
    const db = as(cand, 'cashier-south', 's@x.com');
    await no(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 1, extra: true }));
    await no(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 1.5 }));
    await no(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 0 }));
    await ok(setDoc(doc(db, 'counters/billCounter_south'), { canteenId: 'south', lastNumber: 1 }));
  });
  test('duplicate request ids: a second create of the same bill or repayment is refused for cashiers', async () => {
    const db = N(cand);
    const bill = { canteenId: 'north', createdBy: 'cashier-north', items: [], totalAmount: 10, paymentMode: 'Cash', timestamp: serverTimestamp() };
    await ok(setDoc(doc(db, 'bills/req_dup'), bill));
    await no(setDoc(doc(db, 'bills/req_dup'), bill));
    const rep = { canteenId: 'north', amount: 5, timestamp: serverTimestamp() };
    await ok(setDoc(doc(db, 'repayments/req_dup'), rep));
    await no(setDoc(doc(db, 'repayments/req_dup'), rep));
  });
});
