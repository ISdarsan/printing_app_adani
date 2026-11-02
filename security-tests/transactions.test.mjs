// Integration tests for the financial workflows against the real Firestore
// emulator AND the real firestore.rules, with fault injection.
//
// IMPORTANT: this is a line-by-line PORT of the Dart logic (print_bill_page.dart
// _saveBill, credit_detail_page.dart _processRepayment, cash_reconciliation_page
// .dart _submitReconciliation, lib/sync_status.dart createOnce) using the
// Firestore JS SDK. It proves rules, data semantics and the protocol; it does
// NOT execute the Dart code. Synthetic data only.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, disableNetwork, doc, enableNetwork, getDoc, getDocs, increment, query, runTransaction,
  serverTimestamp, setDoc, waitForPendingWrites, where, limit, getDocsFromServer,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
let env;

before(async () => {
  const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-canteen-tx',
    firestore: {
      host: hp[0], port: Number(hp[1]),
      rules: fs.readFileSync(path.join(here, '..', process.env.RULES_FILE || 'firestore.rules'), 'utf8'),
    },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'canteenStaff/cashier-north'), { role: 'cashier', canteenId: 'north', email: 'n@x.com' });
    await setDoc(doc(db, 'canteenStaff/cashier-south'), { role: 'cashier', canteenId: 'south' });
    await setDoc(doc(db, 'canteenStaff/admin-1'), { role: 'admin', canteenId: 'main' });
  });
});

const cashier = (uid = 'cashier-north') => env.authenticatedContext(uid).firestore();
const toPaise = (v) => Math.round(v * 100);
const fromPaise = (p) => p / 100;
const dateKey = '2026-11-02';
const adm = () => env.authenticatedContext('admin-1').firestore();
// Cashiers are DENIED when reading a document that does not exist, so existence
// checks in these tests go through an admin context.
const adminSnap = async (p) => { const s = await getDoc(doc(adm(), p)); return s.exists() ? s.data() : null; };

// ---- port of lib/money.dart planRepayment ---------------------------------
function planRepayment(pending, amount) {
  let remaining = toPaise(amount);
  const out = [];
  for (let i = 0; i < pending.length; i++) {
    if (remaining <= 0) break;
    const p = toPaise(pending[i]);
    if (remaining >= p) { remaining -= p; out.push({ index: i, newPending: 0.0, paid: true }); }
    else { out.push({ index: i, newPending: fromPaise(p - remaining), paid: false }); remaining = 0; }
  }
  return { allocations: out, unallocated: fromPaise(remaining) };
}

// ---- port of lib/sync_status.dart AttemptTracker + createOnce -------------
class AttemptTracker {
  constructor() { this.key = null; this.id = null; this.attempted = false; this.n = 0; }
  idFor(k) { if (this.key !== k || !this.id) { this.key = k; this.id = `req_${Date.now().toString(36)}_${(this.n++).toString(36)}${Math.random().toString(36).slice(2, 8)}`; this.attempted = false; } return this.id; }
  succeeded() { this.key = null; this.id = null; this.attempted = false; }
}
async function createOnce(a, findExisting, create) {
  if (a.attempted) { const e = await findExisting(); if (e != null) { a.succeeded(); return e; } }
  a.attempted = true;
  const r = await create();
  a.succeeded();
  return r;
}

// ---- port of print_bill_page.dart _saveBill transaction -------------------
async function saveBillTx(db, { uid = 'cashier-north', branch = 'north', requestId, mode, total, phone, name, customerExists, items = [] }) {
  let generatedBillId;
  await runTransaction(db, async (tx) => {
    const counterRef = doc(db, 'counters', `billCounter_${branch}`);
    const counterSnap = await tx.get(counterRef);
    const newNum = counterSnap.exists() ? counterSnap.data().lastNumber + 1 : 1;
    const billRef = doc(db, 'bills', requestId);                         // id == request id
    generatedBillId = `BILL-${dateKey.replaceAll('-', '')}${String(newNum).padStart(2, '0')}`;
    const bill = {
      billId: generatedBillId, billNumber: newNum, clientRequestId: requestId, canteenId: branch,
      canteenName: branch, totalAmount: total, paymentMode: mode, createdBy: uid, createdByEmail: 'n@x.com',
      timestamp: serverTimestamp(), items,
    };
    if (mode === 'Credit' && phone) {
      bill.customerName = name; bill.customerPhone = phone; bill.creditStatus = 'Pending'; bill.pendingAmount = total;
      const customerRef = doc(db, 'creditCustomers', `${branch}_${phone}`);
      if (customerExists) {
        tx.update(customerRef, { totalPending: increment(total), lastUpdated: serverTimestamp(), name });
      } else {
        tx.set(customerRef, { phone, name, canteenId: branch, canteenName: branch, totalPending: increment(total), lastUpdated: serverTimestamp() }, { merge: true });
      }
    }
    tx.set(billRef, bill);
    tx.set(doc(db, 'dailyStats', `${branch}_${dateKey}`), {
      canteenId: branch, canteenName: branch, date: dateKey,
      totalSales: increment(total), totalBills: increment(1),
      ...(mode === 'Cash' ? { totalCash: increment(total) } : {}),
      ...(mode === 'UPI' ? { totalUpi: increment(total) } : {}),
      ...(mode === 'Credit' ? { totalCredit: increment(total) } : {}),
      lastUpdated: serverTimestamp(),
    }, { merge: true });
    tx.set(counterRef, { canteenId: branch, lastNumber: newNum });
  });
  return generatedBillId;
}

// the OLD pattern: read the customer document inside the transaction
async function saveCreditBillOldPattern(db, { branch = 'north', requestId, total, phone, name }) {
  await runTransaction(db, async (tx) => {
    const customerRef = doc(db, 'creditCustomers', `${branch}_${phone}`);
    const snap = await tx.get(customerRef);   // missing doc => denied for cashiers
    if (snap.exists()) tx.update(customerRef, { totalPending: increment(total), lastUpdated: serverTimestamp(), name });
    else tx.set(customerRef, { phone, name, canteenId: branch, canteenName: branch, totalPending: total, lastUpdated: serverTimestamp() });
    tx.set(doc(db, 'bills', requestId), { canteenId: branch, createdBy: 'cashier-north', items: [], totalAmount: total, paymentMode: 'Credit' });
  });
}

const findBill = (db, branch, requestId) => async () => {
  const q = await getDocsFromServer(query(collection(db, 'bills'), where('canteenId', '==', branch), where('clientRequestId', '==', requestId), limit(1)));
  return q.empty ? null : (q.docs[0].data().billId ?? q.docs[0].id);
};
const snapData = async (db, p) => { const s = await getDoc(doc(db, p)); return s.exists() ? s.data() : null; };
const count = async (db, c, branch) => (await getDocs(query(collection(db, c), where('canteenId', '==', branch)))).size;

// ===========================================================================
test('BILL: a cash bill is saved once with number 1, bill id == request id, and consistent stats', async () => {
  const db = cashier();
  const id = await saveBillTx(db, { requestId: 'req_a', mode: 'Cash', total: 120.5 });
  assert.match(id, /^BILL-/);
  const bill = await snapData(db, 'bills/req_a');
  assert.equal(bill.billNumber, 1);
  assert.equal(bill.clientRequestId, 'req_a');
  assert.equal(bill.totalAmount, 120.5);
  assert.equal((await snapData(db, 'counters/billCounter_north')).lastNumber, 1);
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalSales, 120.5); assert.equal(st.totalBills, 1); assert.equal(st.totalCash, 120.5);
});

test('BILL: sequential bills get 1, 2, 3 and stats accumulate', async () => {
  const db = cashier();
  for (const [i, amt] of [10, 20.25, 30].entries()) await saveBillTx(db, { requestId: `req_${i}`, mode: 'UPI', total: amt });
  assert.equal((await snapData(db, 'counters/billCounter_north')).lastNumber, 3);
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalBills, 3); assert.equal(st.totalUpi, 60.25); assert.equal(st.totalSales, 60.25);
});

test('BILL: first credit bill for a NEW customer works with the new pattern, the old read-a-missing-doc pattern is denied', async () => {
  const db = cashier();
  await assertFails(saveCreditBillOldPattern(db, { requestId: 'req_old', total: 200, phone: '900', name: 'Ravi' }));
  assert.equal(await adminSnap('bills/req_old'), null, 'the failed attempt left nothing behind');
  await saveBillTx(db, { requestId: 'req_c1', mode: 'Credit', total: 200, phone: '900', name: 'Ravi', customerExists: false });
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 200);
  // second credit bill: customer exists => update path, balance ADDED
  await saveBillTx(db, { requestId: 'req_c2', mode: 'Credit', total: 50.5, phone: '900', name: 'Ravi', customerExists: true });
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 250.5);
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalCredit, 250.5); assert.equal(st.totalSales, 250.5);
});

test('BILL: another device created the customer in between: balance is added, never overwritten', async () => {
  const db = cashier();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'creditCustomers/north_901'), { phone: '901', name: 'Meena', canteenId: 'north', canteenName: 'north', totalPending: 100 });
  });
  // this device believed the customer was new
  await saveBillTx(db, { requestId: 'req_race', mode: 'Credit', total: 40, phone: '901', name: 'Meena', customerExists: false });
  assert.equal((await snapData(db, 'creditCustomers/north_901')).totalPending, 140);
});

test('DOUBLE TAP / duplicate: the same request id cannot create a second bill (sequential)', async () => {
  const db = cashier();
  await saveBillTx(db, { requestId: 'req_dup', mode: 'Cash', total: 100 });
  await assertFails(saveBillTx(db, { requestId: 'req_dup', mode: 'Cash', total: 100 }));
  assert.equal(await count(db, 'bills', 'north'), 1);
  assert.equal((await snapData(db, 'counters/billCounter_north')).lastNumber, 1, 'counter not advanced by the rejected duplicate');
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalSales, 100); assert.equal(st.totalBills, 1);
});

test('DOUBLE TAP / concurrency: two simultaneous saves with one request id produce exactly one bill', async () => {
  const a = cashier(); const b = cashier(); // two clients, e.g. a double tap racing across two pages
  const results = await Promise.allSettled([
    saveBillTx(a, { requestId: 'req_race2', mode: 'Cash', total: 75 }),
    saveBillTx(b, { requestId: 'req_race2', mode: 'Cash', total: 75 }),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(await count(a, 'bills', 'north'), 1);
  assert.equal((await snapData(a, 'counters/billCounter_north')).lastNumber, 1);
  const st = await snapData(a, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalSales, 75); assert.equal(st.totalBills, 1);
});

test('DIFFERENT carts at the same moment: both saved, numbers 1 and 2, no collision', async () => {
  const a = cashier(); const b = cashier();
  const r = await Promise.allSettled([
    saveBillTx(a, { requestId: 'req_x', mode: 'Cash', total: 10 }),
    saveBillTx(b, { requestId: 'req_y', mode: 'Cash', total: 20 }),
  ]);
  assert.equal(r.filter((x) => x.status === 'fulfilled').length, 2);
  const nums = [(await snapData(a, 'bills/req_x')).billNumber, (await snapData(a, 'bills/req_y')).billNumber].sort();
  assert.deepEqual(nums, [1, 2]);
});

test('LOST ACKNOWLEDGEMENT: commit succeeded, client saw an error; retry with the same request id finds the bill and creates nothing', async () => {
  const db = cashier();
  const attempts = new AttemptTracker();
  const requestId = attempts.idFor('cart-1');
  let creates = 0;
  // attempt 1: the server commits, but we throw away the result as if the response was lost
  await assert.rejects(createOnce(attempts, findBill(db, 'north', requestId), async () => {
    creates++;
    await saveBillTx(db, { requestId, mode: 'Cash', total: 99 });
    throw new Error('deadline-exceeded (response lost)');
  }));
  assert.equal(await count(db, 'bills', 'north'), 1, 'the bill really is on the server');
  // attempt 2: the cashier taps Save again with the same cart => same request id
  assert.equal(attempts.idFor('cart-1'), requestId);
  const existing = await createOnce(attempts, findBill(db, 'north', requestId), async () => {
    creates++;
    return saveBillTx(db, { requestId, mode: 'Cash', total: 99 });
  });
  assert.match(existing, /^BILL-/);
  assert.equal(creates, 1, 'no second create was attempted');
  assert.equal(await count(db, 'bills', 'north'), 1);
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.totalSales, 99); assert.equal(st.totalBills, 1);
});

test('RETRY with the same request id after a genuine failure creates the bill exactly once', async () => {
  const db = cashier();
  const attempts = new AttemptTracker();
  const requestId = attempts.idFor('cart-2');
  let creates = 0;
  await assert.rejects(createOnce(attempts, findBill(db, 'north', requestId), async () => { creates++; throw new Error('unavailable'); }));
  assert.equal(await count(db, 'bills', 'north'), 0);
  await createOnce(attempts, findBill(db, 'north', requestId), async () => { creates++; return saveBillTx(db, { requestId, mode: 'Cash', total: 55 }); });
  assert.equal(creates, 2);
  assert.equal(await count(db, 'bills', 'north'), 1);
  assert.equal((await snapData(db, `dailyStats/north_${dateKey}`)).totalBills, 1);
});

test('TAMPERING: an existing bill cannot be overwritten by re-creating it with the same id and other numbers', async () => {
  const db = cashier();
  await saveBillTx(db, { requestId: 'req_t', mode: 'Cash', total: 100 });
  await assertFails(setDoc(doc(db, 'bills/req_t'), { canteenId: 'north', createdBy: 'cashier-north', items: [], totalAmount: 1 }));
  assert.equal((await snapData(db, 'bills/req_t')).totalAmount, 100);
});

test('BRANCH ISOLATION: a cashier cannot create bills or stats for another branch', async () => {
  const db = cashier();
  await assertFails(saveBillTx(db, { branch: 'south', requestId: 'req_s', mode: 'Cash', total: 5 }));
  assert.equal(await adminSnap('bills/req_s'), null);
});

// ===========================================================================
async function seedCustomerWithTwoBills(db) {
  await saveBillTx(db, { requestId: 'req_b1', mode: 'Credit', total: 100, phone: '900', name: 'Ravi', customerExists: false });
  await saveBillTx(db, { requestId: 'req_b2', mode: 'Credit', total: 50.5, phone: '900', name: 'Ravi', customerExists: true });
}

// ---- port of credit_detail_page.dart _processRepayment --------------------
async function repayTx(db, { branch = 'north', phone = '900', amount, mode = 'Cash', requestId }) {
  await runTransaction(db, async (tx) => {
    const billsSnap = await getDocs(query(collection(db, 'bills'),
      where('customerPhone', '==', phone), where('canteenId', '==', branch), where('creditStatus', '==', 'Pending')));
    const docs = [];
    for (const d of billsSnap.docs) docs.push(await tx.get(d.ref));
    docs.sort((a, b) => (a.data().timestamp?.toMillis?.() ?? 0) - (b.data().timestamp?.toMillis?.() ?? 0) || a.data().billNumber - b.data().billNumber);
    const customerRef = doc(db, 'creditCustomers', `${branch}_${phone}`);
    const customerSnap = await tx.get(customerRef);
    const plan = planRepayment(docs.map((d) => d.data().pendingAmount ?? d.data().totalAmount ?? 0), amount);
    for (const a of plan.allocations) {
      if (a.paid) tx.update(docs[a.index].ref, { pendingAmount: 0.0, creditStatus: 'Paid' });
      else tx.update(docs[a.index].ref, { pendingAmount: a.newPending });
    }
    if (customerSnap.exists()) tx.update(customerRef, { totalPending: increment(-amount), lastUpdated: serverTimestamp() });
    tx.set(doc(db, 'repayments', requestId), {
      customerPhone: phone, customerName: 'Ravi', canteenId: branch, canteenName: branch, amount, paymentMode: mode,
      timestamp: serverTimestamp(), clientRequestId: requestId, processedBy: 'n@x.com',
    });
    tx.set(doc(db, 'dailyStats', `${branch}_${dateKey}`), {
      canteenId: branch, canteenName: branch, date: dateKey,
      ...(mode === 'Cash' ? { totalCash: increment(amount) } : {}),
      ...(mode === 'UPI' ? { totalUpi: increment(amount) } : {}),
      creditReceived: increment(amount), lastUpdated: serverTimestamp(),
    }, { merge: true });
  });
}
const findRepayment = (db, branch, requestId) => async () => {
  const q = await getDocsFromServer(query(collection(db, 'repayments'), where('canteenId', '==', branch), where('clientRequestId', '==', requestId), limit(1)));
  return q.empty ? null : true;
};

test('REPAYMENT: part payment clears the oldest bill first, balance and stats are exact, sales unchanged', async () => {
  const db = cashier();
  await seedCustomerWithTwoBills(db);
  await repayTx(db, { amount: 120.25, requestId: 'req_r1', mode: 'Cash' });
  const b1 = await snapData(db, 'bills/req_b1'); const b2 = await snapData(db, 'bills/req_b2');
  assert.equal(b1.creditStatus, 'Paid'); assert.equal(b1.pendingAmount, 0);
  assert.equal(b2.creditStatus, 'Pending'); assert.equal(b2.pendingAmount, 30.25); // 50.50 - 20.25
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 30.25);
  const st = await snapData(db, `dailyStats/north_${dateKey}`);
  assert.equal(st.creditReceived, 120.25);
  assert.equal(st.totalCash, 120.25);
  assert.equal(st.totalSales, 150.5, 'a repayment is not a sale');
  assert.equal(st.totalBills, 2);
});

test('REPAYMENT: paying the exact total closes every bill and leaves a zero balance', async () => {
  const db = cashier();
  await seedCustomerWithTwoBills(db);
  await repayTx(db, { amount: 150.5, requestId: 'req_r2', mode: 'UPI' });
  assert.equal((await snapData(db, 'bills/req_b1')).creditStatus, 'Paid');
  assert.equal((await snapData(db, 'bills/req_b2')).creditStatus, 'Paid');
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 0);
  assert.equal((await snapData(db, `dailyStats/north_${dateKey}`)).totalUpi, 150.5);
});

test('REPEATED REPAYMENT SUBMISSION: same request id twice => balance reduced once', async () => {
  const db = cashier();
  await seedCustomerWithTwoBills(db);
  await repayTx(db, { amount: 50, requestId: 'req_r3' });
  await assertFails(repayTx(db, { amount: 50, requestId: 'req_r3' }));
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 100.5);
  assert.equal((await getDocs(query(collection(db, 'repayments'), where('canteenId', '==', 'north')))).size, 1);
  assert.equal((await snapData(db, `dailyStats/north_${dateKey}`)).creditReceived, 50);
});

test('REPEATED REPAYMENT, concurrent: two simultaneous submissions => exactly one applied', async () => {
  const a = cashier(); const b = cashier();
  await seedCustomerWithTwoBills(a);
  const r = await Promise.allSettled([repayTx(a, { amount: 40, requestId: 'req_r4' }), repayTx(b, { amount: 40, requestId: 'req_r4' })]);
  assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1);
  assert.equal((await snapData(a, 'creditCustomers/north_900')).totalPending, 110.5);
  assert.equal((await snapData(a, `dailyStats/north_${dateKey}`)).creditReceived, 40);
});

test('REPAYMENT LOST ACKNOWLEDGEMENT: retry finds the repayment, applies nothing twice', async () => {
  const db = cashier();
  await seedCustomerWithTwoBills(db);
  const attempts = new AttemptTracker();
  const requestId = attempts.idFor('rep-1');
  let creates = 0;
  await assert.rejects(createOnce(attempts, findRepayment(db, 'north', requestId), async () => {
    creates++; await repayTx(db, { amount: 70, requestId }); throw new Error('response lost');
  }));
  const again = await createOnce(attempts, findRepayment(db, 'north', requestId), async () => { creates++; await repayTx(db, { amount: 70, requestId }); return true; });
  assert.equal(again, true);
  assert.equal(creates, 1);
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 80.5);
  assert.equal((await snapData(db, 'bills/req_b1')).pendingAmount, 30);
});

test('REPAYMENT: more than the balance is refused by the rules (balance can never go negative)', async () => {
  const db = cashier();
  await seedCustomerWithTwoBills(db);
  await assertFails(repayTx(db, { amount: 200, requestId: 'req_r5' }));
  assert.equal((await snapData(db, 'creditCustomers/north_900')).totalPending, 150.5);
  assert.equal(await adminSnap('repayments/req_r5'), null);
});

test('REPAYMENT balances stay exact to the paisa over many partial payments', async () => {
  const db = cashier();
  await saveBillTx(db, { requestId: 'req_big', mode: 'Credit', total: 100, phone: '902', name: 'K', customerExists: false });
  for (let i = 0; i < 9; i++) await repayTx(db, { phone: '902', amount: 10.1, requestId: `req_p${i}` });
  // 9 x 10.10 = 90.90 paid, 9.10 left
  const bill = await snapData(db, 'bills/req_big');
  assert.equal(toPaise(bill.pendingAmount), 910);
  assert.equal(toPaise((await snapData(db, 'creditCustomers/north_902')).totalPending), 910);
  await repayTx(db, { phone: '902', amount: 9.1, requestId: 'req_plast' });
  assert.equal((await snapData(db, 'bills/req_big')).creditStatus, 'Paid');
  assert.equal(toPaise((await snapData(db, 'creditCustomers/north_902')).totalPending), 0);
});

// ===========================================================================
// ---- port of cash_reconciliation_page.dart _submitReconciliation -----------
async function submitClosing(db, { uid, email, branch = 'north', actual, systemCash }) {
  const prior = await getDocsFromServer(query(collection(db, 'cashReconciliations'),
    where('canteenId', '==', branch), where('date', '==', dateKey), limit(1)));
  if (!prior.empty) {
    const d = prior.docs[0].data();
    if (d.submittedBy === email && toPaise(d.actualCash) === toPaise(actual)) return 'alreadyMine';
    throw new Error('already-reconciled');
  }
  await runTransaction(db, async (tx) => {
    tx.set(doc(db, 'cashReconciliations', `${branch}_${dateKey}`), {
      date: dateKey, canteenId: branch, canteenName: branch, systemCash, actualCash: actual,
      discrepancy: Math.round((actual - systemCash) * 100) / 100, note: '', submittedBy: email,
      submittedByUid: uid, timestamp: serverTimestamp(),
    });
  });
  return 'created';
}

test('CASH CLOSING: first closing succeeds without reading a missing document; second is refused; own lost-ack repeat is recognised', async () => {
  const db = cashier();
  assert.equal(await submitClosing(db, { uid: 'cashier-north', email: 'n@x.com', actual: 500, systemCash: 500 }), 'created');
  // the same cashier repeating the same submission (acknowledgement was lost)
  assert.equal(await submitClosing(db, { uid: 'cashier-north', email: 'n@x.com', actual: 500, systemCash: 500 }), 'alreadyMine');
  // a different amount is a different submission: refused
  await assert.rejects(submitClosing(db, { uid: 'cashier-north', email: 'n@x.com', actual: 450, systemCash: 500 }), /already-reconciled/);
  assert.equal((await snapData(db, `cashReconciliations/north_${dateKey}`)).actualCash, 500);
});

test('CASH CLOSING: the create-only write itself cannot overwrite an existing closing (rules)', async () => {
  const db = cashier();
  await submitClosing(db, { uid: 'cashier-north', email: 'n@x.com', actual: 500, systemCash: 500 });
  await assertFails(runTransaction(db, async (tx) => {
    tx.set(doc(db, 'cashReconciliations', `north_${dateKey}`), {
      date: dateKey, canteenId: 'north', systemCash: 500, actualCash: 1, discrepancy: -499, submittedBy: 'n@x.com', submittedByUid: 'cashier-north', timestamp: serverTimestamp(),
    });
  }));
});

test('TODAY CARD / CLOSING: the branch-scoped "today" queries return nothing (not an error) before the first sale', async () => {
  const db = cashier();
  const s = await assertSucceeds(getDocs(query(collection(db, 'dailyStats'), where('canteenId', '==', 'north'), where('date', '==', dateKey), limit(1))));
  assert.equal(s.size, 0);
  await assertFails(getDoc(doc(db, `dailyStats/north_${dateKey}`)));  // the old document read
  await saveBillTx(db, { requestId: 'req_today', mode: 'Cash', total: 33 });
  const s2 = await getDocs(query(collection(db, 'dailyStats'), where('canteenId', '==', 'north'), where('date', '==', dateKey), limit(1)));
  assert.equal(s2.docs[0].data().totalSales, 33);
});

// ===========================================================================
// Task 5: offline behaviour (JS SDK disableNetwork = the client cannot reach the server)
const settleWithin = (p, ms) => Promise.race([p.then(() => 'settled', () => 'rejected'), new Promise((r) => setTimeout(() => r('pending'), ms))]);

// ---- a genuine network outage: TCP proxy that can be cut and restored --------
// (JS SDK note: disableNetwork() does NOT stop transactions, so it cannot model
// a dead connection for them; cutting the socket does.)
import net from 'node:net';
function makeProxy(targetHost, targetPort) {
  const sockets = new Set();
  let server = null; let port = 0;
  const start = (listenPort = 0) => new Promise((resolve) => {
    server = net.createServer((c) => {
      const t = net.connect(targetPort, targetHost);
      sockets.add(c); sockets.add(t);
      const kill = () => { c.destroy(); t.destroy(); sockets.delete(c); sockets.delete(t); };
      c.on('error', kill); t.on('error', kill); c.on('close', kill); t.on('close', kill);
      c.pipe(t); t.pipe(c);
    });
    server.listen(listenPort, '127.0.0.1', () => { port = server.address().port; resolve(port); });
  });
  const cut = async () => {
    const closed = new Promise((r) => server.close(() => r()));
    for (const x of sockets) x.destroy();   // keep-alive sockets would block close()
    sockets.clear();
    await closed;
  };
  return { start, cut, get port() { return port; } };
}
async function clientBehindProxy(uid) {
  const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  const proxy = makeProxy(hp[0], Number(hp[1]));
  const port = await proxy.start();
  const penv = await initializeTestEnvironment({
    projectId: 'demo-canteen-tx',
    firestore: { host: '127.0.0.1', port, rules: fs.readFileSync(path.join(here, '..', process.env.RULES_FILE || 'firestore.rules'), 'utf8') },
  });
  return { proxy, penv, db: penv.authenticatedContext(uid).firestore(), port };
}

test('NETWORK OUTAGE: a bill transaction fails, nothing is saved or queued; once the network is back the same request id saves exactly once', { timeout: 150000 }, async () => {
  const { proxy, penv, db, port } = await clientBehindProxy('cashier-north');
  try {
    await saveBillTx(db, { requestId: 'req_warm', mode: 'Cash', total: 1 }); // connection established
    await proxy.cut();                                                       // the phone loses the network
    const outcome = await settleWithin(saveBillTx(db, { requestId: 'req_net', mode: 'Cash', total: 60 }), 45000);
    assert.equal(outcome, 'rejected', 'a bill must never look saved while the network is down');
    assert.equal(await adminSnap('bills/req_net'), null, 'nothing reached the server');
    await proxy.start(port);                                                 // network back
    // the app's retry: same request id; first it asks the server (createOnce)
    const attempts = new AttemptTracker(); attempts.attempted = true; attempts.key = 'k'; attempts.id = 'req_net';
    let creates = 0;
    const adminDb = adm();
    await createOnce(attempts,
      async () => { const q = await getDocsFromServer(query(collection(adminDb, 'bills'), where('canteenId', '==', 'north'), where('clientRequestId', '==', 'req_net'), limit(1))); return q.empty ? null : 'x'; },
      async () => { creates++; return saveBillTx(db, { requestId: 'req_net', mode: 'Cash', total: 60 }); });
    assert.equal(creates, 1);
    assert.equal((await adminSnap('bills/req_net')).totalAmount, 60);
    const st = await adminSnap(`dailyStats/north_${dateKey}`);
    assert.equal(st.totalBills, 2); assert.equal(st.totalSales, 61);        // warm-up bill + this one, each once
    assert.equal((await adminSnap('counters/billCounter_north')).lastNumber, 2);
  } finally { await proxy.cut().catch(() => {}); await penv.cleanup().catch(() => {}); }
});

test('NETWORK OUTAGE: a repayment fails cleanly during the outage and changes no balance', { timeout: 150000 }, async () => {
  const direct = cashier();
  await seedCustomerWithTwoBills(direct);
  const { proxy, penv, db } = await clientBehindProxy('cashier-north');
  try {
    await getDocsFromServer(query(collection(db, 'bills'), where('canteenId', '==', 'north'), limit(1))); // connect
    await proxy.cut();
    const outcome = await settleWithin(repayTx(db, { amount: 20, requestId: 'req_roff' }), 45000);
    assert.equal(outcome, 'rejected');
    assert.equal((await adminSnap('creditCustomers/north_900')).totalPending, 150.5);
    assert.equal(await adminSnap('repayments/req_roff'), null);
  } finally { await proxy.cut().catch(() => {}); await penv.cleanup().catch(() => {}); }
});

test('OFFLINE: an expense (set with a chosen id) stays PENDING, is not reported as saved, and is delivered once on reconnect', async () => {
  const db = cashier();
  const ref = doc(db, 'expenses', 'exp_offline');
  await disableNetwork(db);
  const write = setDoc(ref, { canteenId: 'north', userId: 'cashier-north', amount: 80, description: 'Gas' });
  assert.equal(await settleWithin(write, 1500), 'pending', 'no acknowledgement => not saved');
  assert.equal(await settleWithin(waitForPendingWrites(db), 500), 'pending');
  // another client (online) cannot see it yet
  assert.equal(await adminSnap('expenses/exp_offline'), null);
  await enableNetwork(db);
  assert.equal(await settleWithin(write, 10000), 'settled', 'acknowledged after reconnecting');
  await waitForPendingWrites(db);
  assert.equal((await adminSnap('expenses/exp_offline')).amount, 80);
  assert.equal((await getDocs(query(collection(db, 'expenses'), where('canteenId', '==', 'north')))).size, 1);
});

test('OFFLINE: two taps on the same offline expense id still deliver exactly one expense (idempotent)', async () => {
  const db = cashier();
  const ref = doc(db, 'expenses', 'exp_twice');
  const data = { canteenId: 'north', userId: 'cashier-north', amount: 25, description: 'Tea leaves' };
  await disableNetwork(db);
  const w1 = setDoc(ref, data); const w2 = setDoc(ref, data);
  await enableNetwork(db);
  await Promise.allSettled([w1, w2]);
  await waitForPendingWrites(db);
  assert.equal((await getDocs(query(collection(cashier(), 'expenses'), where('canteenId', '==', 'north')))).size, 1);
});

test('SYNC: confirmedSet semantics: a repeat after a committed create is denied, a server read confirms it', async () => {
  const db = cashier();
  const ref = doc(db, 'expenses', 'exp_conf');
  const data = { canteenId: 'north', userId: 'cashier-north', amount: 12, description: 'x' };
  await setDoc(ref, data);
  let ambiguous = false;
  try { await setDoc(ref, data); } catch (e) { ambiguous = /permission/i.test(String(e)); }
  assert.equal(ambiguous, true);
  assert.equal((await getDoc(ref)).exists(), true);
});
