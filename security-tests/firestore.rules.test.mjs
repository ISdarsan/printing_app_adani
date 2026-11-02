import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId: 'demo-canteen-security',
    firestore: {
      // `firebase emulators:exec` exports FIRESTORE_EMULATOR_HOST; default to
      // the port in firebase.json when run by hand.
      host: (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':')[0],
      port: Number((process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':')[1]),
      rules: fs.readFileSync(path.join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'canteenStaff/cashier-north'), {
        role: 'cashier',
        canteenId: 'north',
      }),
      setDoc(doc(db, 'canteenStaff/cashier-south'), {
        role: 'cashier',
        canteenId: 'south',
      }),
      setDoc(doc(db, 'canteenStaff/admin-1'), {
        role: 'admin',
        canteenId: 'main',
      }),
      setDoc(doc(db, 'bills/bill-north'), {
        canteenId: 'north',
        createdBy: 'cashier-north',
        totalAmount: 25,
        items: [],
      }),
      setDoc(doc(db, 'bills/bill-south'), {
        canteenId: 'south',
        createdBy: 'cashier-south',
        totalAmount: 35,
        items: [],
      }),
      setDoc(doc(db, 'notifications/notice-north'), {
        canteenId: 'north',
        title: 'North notice',
        message: 'Test',
        readBy: [],
      }),
      setDoc(doc(db, 'notifications/notice-south'), {
        canteenId: 'south',
        title: 'South notice',
        message: 'Test',
        readBy: [],
      }),
    ]);
  });
});

test('cashiers can read only their branch and must scope collection queries', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(getDoc(doc(db, 'bills/bill-north')));
  await assertFails(getDoc(doc(db, 'bills/bill-south')));
  await assertSucceeds(
    getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'north'))),
  );
  await assertFails(getDocs(collection(db, 'bills')));
});

test('cashier date-range queries on bills/expenses need a canteenId filter (B-14)', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  const from = new Date('2026-01-01');
  const to = new Date('2026-12-31');
  // Shape used today by billing_dashboard, today_sales, daily_sales_report,
  // all_bills, monthly_sales_breakdown and the cashier expense/fund views.
  for (const name of ['bills', 'expenses']) {
    await assertFails(
      getDocs(query(collection(db, name), where('timestamp', '>=', from), where('timestamp', '<=', to))),
    );
    await assertSucceeds(
      getDocs(query(collection(db, name), where('canteenId', '==', 'north'), where('timestamp', '>=', from), where('timestamp', '<=', to))),
    );
  }
});

// Exact query shapes the six cashier screens now use (scopeQuery + half-open
// range [start, nextStart) + optional orderBy). Note: the emulator does not
// enforce composite indexes; see FIRESTORE_INDEX_AUDIT.md.
test('scoped half-open day/month queries behave correctly per branch and boundary', async () => {
  const istMidnight = (d) => new Date(`${d}T00:00:00+05:30`);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const mk = (id, canteenId, iso, amount) =>
      setDoc(doc(db, `bills/${id}`), {
        canteenId, createdBy: 'x', items: [], totalAmount: amount,
        timestamp: new Date(iso),
      });
    await Promise.all([
      mk('n-last-ms', 'north', '2026-11-02T23:59:59.999+05:30', 10),
      mk('n-late',    'north', '2026-11-02T23:59:59.500+05:30', 20),
      mk('n-first',   'north', '2026-11-03T00:00:00.000+05:30', 40),
      mk('n-prev',    'north', '2026-11-01T23:59:59.999+05:30', 80),
      mk('s-same',    'south', '2026-11-02T12:00:00+05:30', 160),
    ]);
  });
  const north = testEnvironment.authenticatedContext('cashier-north').firestore();
  const q = (db, from, to, extra = []) => query(
    collection(db, 'bills'),
    where('canteenId', '==', 'north'),
    where('timestamp', '>=', istMidnight(from)),
    where('timestamp', '<', istMidnight(to)),
    ...extra,
  );
  const ids = async (p) => (await assertSucceeds(p)).docs.map((d) => d.id).sort();

  // 2 Nov business day: includes 23:59:59.5 and 23:59:59.999, excludes 3 Nov 00:00 and 1 Nov.
  assert.deepEqual(await ids(getDocs(q(north, '2026-11-02', '2026-11-03'))), ['n-last-ms', 'n-late']);
  // 3 Nov starts exactly at midnight and contains only the first bill.
  assert.deepEqual(await ids(getDocs(q(north, '2026-11-03', '2026-11-04'))), ['n-first']);
  // Month range spanning the month end loses and double counts nothing.
  assert.deepEqual(
    await ids(getDocs(q(north, '2026-11-01', '2026-12-01'))),
    ['n-first', 'n-last-ms', 'n-late', 'n-prev'],
  );
  // orderBy variant used by Today's Sales / Daily Report / Bills History.
  await assertSucceeds(getDocs(q(north, '2026-11-02', '2026-11-03', [orderBy('timestamp', 'desc')])));
  // A cashier cannot widen the scope to another branch.
  await assertFails(getDocs(query(
    collection(testEnvironment.authenticatedContext('cashier-north').firestore(), 'bills'),
    where('canteenId', '==', 'south'),
    where('timestamp', '>=', istMidnight('2026-11-02')),
    where('timestamp', '<', istMidnight('2026-11-03')),
  )));
  // Admin keeps the unscoped query (all branches).
  const admin = testEnvironment.authenticatedContext('admin-1').firestore();
  const all = await assertSucceeds(getDocs(query(
    collection(admin, 'bills'),
    where('timestamp', '>=', istMidnight('2026-11-02')),
    where('timestamp', '<', istMidnight('2026-11-03')),
  )));
  assert.deepEqual(all.docs.map((d) => d.id).sort(), ['n-last-ms', 'n-late', 's-same']);
});

test('cashier can read exactly their own dailyStats doc by id (no index needed)', async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'dailyStats/north_2026-11-02'), {
      canteenId: 'north', date: '2026-11-02', totalCash: 100,
    });
  });
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(getDoc(doc(db, 'dailyStats/north_2026-11-02')));
  await assertFails(getDoc(doc(db, 'dailyStats/south_2026-11-02')));
});

test('cashiers can create branch records but cannot change another branch', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'expenses/expense-north'), {
      canteenId: 'north',
      userId: 'cashier-north',
      amount: 10,
      timestamp: new Date(),
    }),
  );
  await assertFails(
    setDoc(doc(db, 'expenses/expense-south'), {
      canteenId: 'south',
      userId: 'cashier-north',
      amount: 10,
      timestamp: new Date(),
    }),
  );
  await assertFails(deleteDoc(doc(db, 'bills/bill-north')));
});

test('cashiers can manage menu only for their assigned branch', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'menuItems/north-tea'), {
      canteenId: 'north',
      name: 'Tea',
      fullPrice: 10,
    }),
  );
  await assertFails(
    setDoc(doc(db, 'menuItems/south-tea'), {
      canteenId: 'south',
      name: 'Tea',
      fullPrice: 10,
    }),
  );
});

test('cashiers cannot promote themselves or list staff records', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(getDoc(doc(db, 'canteenStaff/cashier-north')));
  await assertFails(getDocs(collection(db, 'canteenStaff')));
  await assertFails(
    updateDoc(doc(db, 'canteenStaff/cashier-north'), { role: 'admin' }),
  );
});

test('notice access and read receipts are limited to the assigned branch', async () => {
  const db = testEnvironment.authenticatedContext('cashier-north').firestore();
  await assertSucceeds(getDoc(doc(db, 'notifications/notice-north')));
  await assertFails(getDoc(doc(db, 'notifications/notice-south')));
  await assertSucceeds(
    updateDoc(doc(db, 'notifications/notice-north'), {
      readBy: ['cashier-north'],
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'notifications/notice-north'), {
      title: 'Tampered title',
    }),
  );
});

test('admins can inspect all branches and manage staff', async () => {
  const db = testEnvironment.authenticatedContext('admin-1').firestore();
  await assertSucceeds(getDoc(doc(db, 'bills/bill-north')));
  await assertSucceeds(getDoc(doc(db, 'bills/bill-south')));
  await assertSucceeds(getDocs(collection(db, 'canteenStaff')));
  await assertSucceeds(
    updateDoc(doc(db, 'canteenStaff/cashier-north'), { role: 'admin' }),
  );
});

test('unauthenticated clients cannot read or write business data', async () => {
  const db = testEnvironment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'bills/bill-north')));
  await assertFails(
    setDoc(doc(db, 'expenses/anonymous'), {
      canteenId: 'north',
      amount: 1,
    }),
  );
});
