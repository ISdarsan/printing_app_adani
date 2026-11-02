// Exact query shapes used by lib/analytics_loader.dart, run as an admin under
// the real rules against the Firestore emulator. Synthetic data only.
// (The emulator does not enforce composite indexes; see FIRESTORE_INDEX_AUDIT.md.)
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';
import { assertFails, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, doc, documentId, getDocs, limit, orderBy, query, setDoc, startAfter, where,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
let env;
const T = (iso) => new Date(iso);

before(async () => {
  const hostPort = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  env = await initializeTestEnvironment({
    projectId: 'demo-canteen-analytics',
    firestore: {
      host: hostPort.split(':')[0],
      port: Number(hostPort.split(':')[1]),
      rules: fs.readFileSync(path.join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'canteenStaff/admin-1'), { role: 'admin', canteenId: 'main' });
    await setDoc(doc(db, 'canteenStaff/cashier-n'), { role: 'cashier', canteenId: 'north' });
    const bill = (id, canteenId, iso, amt) =>
      setDoc(doc(db, 'bills', id), {
        ...(canteenId ? { canteenId } : {}),
        createdBy: 'x', items: [], totalAmount: amt, timestamp: T(iso),
      });
    await Promise.all([
      bill('m-old', 'main', '2026-04-10T10:00:00+05:30', 1),   // before the 6-month window
      bill('m-in', 'main', '2026-06-01T00:00:00+05:30', 2),    // first instant of the window
      bill('m-edge', 'main', '2026-05-31T23:59:59.999+05:30', 4), // last ms before window
      bill('m-legacy', null, '2026-09-01T10:00:00+05:30', 8),  // untagged legacy => main
      bill('n-in', 'north', '2026-09-02T10:00:00+05:30', 16),
      bill('n-old', 'north', '2026-01-02T10:00:00+05:30', 32),
      bill('s-in', 'south', '2026-09-03T10:00:00+05:30', 64),
    ]);
    const stat = (id, data) => setDoc(doc(db, 'dailyStats', id), data);
    await Promise.all([
      stat('main_2026-05-31', { canteenId: 'main', date: '2026-05-31', totalSales: 1 }),
      stat('main_2026-06-01', { canteenId: 'main', date: '2026-06-01', totalSales: 2 }),
      stat('north_2026-09-02', { canteenId: 'north', date: '2026-09-02', totalSales: 3 }),
      stat('2020-01-05', { totalSales: 10 }), // legacy: no date field, no canteenId
    ]);
    const exp = (id, canteenId, iso) =>
      setDoc(doc(db, 'expenses', id), {
        ...(canteenId ? { canteenId } : {}), userId: 'u', amount: 5, timestamp: T(iso),
      });
    await Promise.all([
      exp('e-main-in', 'main', '2026-07-01T10:00:00+05:30'),
      exp('e-north-in', 'north', '2026-08-01T10:00:00+05:30'),
      exp('e-north-old', 'north', '2026-02-01T10:00:00+05:30'),
      exp('e-legacy', null, '2026-07-05T10:00:00+05:30'),
    ]);
  });
});

after(async () => { await env.cleanup(); });

const ids = (snap) => snap.docs.map((d) => d.id).sort();
const START = T('2026-06-01T00:00:00+05:30');

test('bills, window only (branch main is read unscoped, filtered on the device)', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const snap = await getDocs(query(collection(db, 'bills'),
    where('timestamp', '>=', START), orderBy('timestamp', 'desc')));
  // 1 Jun 00:00 IST is inside, 31 May 23:59:59.999 is outside, old bills outside
  assert.deepEqual(ids(snap), ['m-in', 'm-legacy', 'n-in', 's-in']);
  // device-side filter for branch main keeps untagged legacy, drops other branches
  const mine = snap.docs.filter((d) => (d.data().canteenId || 'main') === 'main').map((d) => d.id).sort();
  assert.deepEqual(mine, ['m-in', 'm-legacy']);
});

test('bills, concrete branch is scoped on the server', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const snap = await getDocs(query(collection(db, 'bills'),
    where('canteenId', '==', 'north'), where('timestamp', '>=', START), orderBy('timestamp', 'desc')));
  assert.deepEqual(ids(snap), ['n-in']);
});

test('server branch filter cannot see legacy untagged bills (why main stays unscoped)', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const snap = await getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'main')));
  assert.ok(!ids(snap).includes('m-legacy'));
});

test('dailyStats windowed by the `date` field excludes dateless legacy docs', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const snap = await getDocs(query(collection(db, 'dailyStats'),
    where('date', '>=', '2026-06-01'), orderBy('date')));
  assert.deepEqual(ids(snap), ['main_2026-06-01', 'north_2026-09-02']);
});

test('dailyStats all-time pages by document id and DOES include dateless legacy docs', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const all = [];
  let cursor = null;
  for (;;) {
    const snap = await getDocs(query(collection(db, 'dailyStats'), orderBy(documentId()),
      ...(cursor ? [startAfter(cursor)] : []), limit(2)));
    snap.docs.forEach((d) => all.push(d.id));
    if (snap.docs.length < 2) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  assert.deepEqual([...all].sort(), ['2020-01-05', 'main_2026-05-31', 'main_2026-06-01', 'north_2026-09-02']);
  assert.equal(new Set(all).size, all.length);
});

test('expenses: scoped branch + window, ascending order', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const north = await getDocs(query(collection(db, 'expenses'),
    where('canteenId', '==', 'north'), where('timestamp', '>=', START), orderBy('timestamp')));
  assert.deepEqual(ids(north), ['e-north-in']);
  const unscoped = await getDocs(query(collection(db, 'expenses'),
    where('timestamp', '>=', START), orderBy('timestamp')));
  assert.deepEqual(ids(unscoped), ['e-legacy', 'e-main-in', 'e-north-in']);
});

test('a cashier cannot read other branches through analytics-style queries', async () => {
  const db = env.authenticatedContext('cashier-n').firestore();
  await assertFails(getDocs(query(collection(db, 'bills'), where('timestamp', '>=', START), orderBy('timestamp', 'desc'))));
  await assertFails(getDocs(query(collection(db, 'bills'), where('canteenId', '==', 'south'))));
  await assertFails(getDocs(query(collection(db, 'dailyStats'), where('date', '>=', '2026-06-01'), orderBy('date'))));
});
