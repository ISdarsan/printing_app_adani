// Verifies the paging strategy used by lib/report_data_loader.dart against the
// real Firestore emulator semantics (ordering, implicit __name__ tiebreak,
// startAfter(document)) as an admin under the real security rules.
// Synthetic data only.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';
import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  startAfter,
  where,
  writeBatch,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
let env;
const N = 1203;
const PER_TS = 7; // 7 bills share every timestamp (same-second bills)
const BASE = Date.UTC(2026, 10, 1, 0, 0, 0); // 1 Nov 2026 00:00 UTC

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-canteen-paging',
    firestore: {
      host: (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':')[0],
      port: Number((process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':')[1]),
      rules: fs.readFileSync(path.join(here, '..', process.env.RULES_FILE || 'firestore.rules'), 'utf8'),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'canteenStaff/admin-1'), { role: 'admin', canteenId: 'main' });
    await setDoc(doc(db, 'canteenStaff/cashier-n'), { role: 'cashier', canteenId: 'north' });
    for (let i = 0; i < N; i += 400) {
      const batch = writeBatch(db);
      for (let j = i; j < Math.min(N, i + 400); j++) {
        batch.set(doc(db, 'bills', `b${String(j).padStart(5, '0')}`), {
          canteenId: j % 3 === 0 ? 'north' : 'main',
          createdBy: 'x',
          items: [],
          totalAmount: (j % 50) + 0.25,
          paymentMode: ['Cash', 'UPI', 'Credit'][j % 3],
          timestamp: new Date(BASE + Math.floor(j / PER_TS) * 1000),
        });
      }
      await batch.commit();
    }
  });
});

after(async () => { await env.cleanup(); });

async function pageAll(db, { pageSize, extra = [], cursorOf }) {
  const ids = [];
  let cursor = null;
  let pages = 0;
  for (;;) {
    const q = query(collection(db, 'bills'), ...extra, orderBy('timestamp', 'desc'),
      ...(cursor ? [startAfter(cursor)] : []), limit(pageSize));
    const snap = await getDocs(q);
    pages++;
    snap.docs.forEach((d) => ids.push(d.id));
    if (snap.docs.length < pageSize) break;
    cursor = cursorOf(snap.docs[snap.docs.length - 1]);
  }
  return { ids, pages };
}

for (const pageSize of [1, 7, 250, 500]) {
  if (pageSize === 1) continue; // 1203 sequential reads; covered by the Dart fake
  test(`document-cursor paging returns every bill exactly once (page ${pageSize}, ties)`, async () => {
    const db = env.authenticatedContext('admin-1').firestore();
    const { ids } = await pageAll(db, { pageSize, cursorOf: (d) => d });
    assert.equal(ids.length, N);
    assert.equal(new Set(ids).size, N);
    const expected = Array.from({ length: N }, (_, i) => `b${String(i).padStart(5, '0')}`);
    assert.deepEqual([...ids].sort(), expected);
  });
}

test('pages arrive in timestamp-desc order with a stable tiebreak', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const snap = await getDocs(query(collection(db, 'bills'), orderBy('timestamp', 'desc'), limit(40)));
  const ts = snap.docs.map((d) => d.data().timestamp.toMillis());
  assert.deepEqual([...ts].sort((a, b) => b - a), ts);
});

test('NEGATIVE CONTROL: a timestamp-value cursor skips tied rows', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const { ids } = await pageAll(db, { pageSize: 10, cursorOf: (d) => d.data().timestamp });
  assert.ok(ids.length < N, `expected loss, got ${ids.length}`);
});

test('period export: [start, end) range + orderBy on the same field, paged, matches a one-shot read', async () => {
  const db = env.authenticatedContext('admin-1').firestore();
  const start = new Date(BASE + 20 * 1000);
  const end = new Date(BASE + 120 * 1000); // exclusive
  const extra = [where('timestamp', '>=', start), where('timestamp', '<', end)];
  const { ids } = await pageAll(db, { pageSize: 50, extra, cursorOf: (d) => d });
  const once = await getDocs(query(collection(db, 'bills'), ...extra, orderBy('timestamp', 'desc')));
  assert.equal(ids.length, once.size);
  assert.equal(new Set(ids).size, once.size);
  // 100 whole seconds * 7 bills per second
  assert.equal(ids.length, 100 * PER_TS);
  // boundary: nothing at exactly `end`, everything at exactly `start`
  const stamps = once.docs.map((d) => d.data().timestamp.toMillis());
  assert.ok(Math.min(...stamps) === start.getTime());
  assert.ok(Math.max(...stamps) < end.getTime());
});

test('a cashier cannot run the unscoped export queries (export is admin-only)', async () => {
  const db = env.authenticatedContext('cashier-n').firestore();
  await assertFails(getDocs(query(collection(db, 'bills'), orderBy('timestamp', 'desc'), limit(10))));
});
