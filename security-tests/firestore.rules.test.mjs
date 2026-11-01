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
      host: '127.0.0.1',
      port: 8080,
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
