import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
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
