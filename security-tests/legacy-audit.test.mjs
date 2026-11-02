// Validates the legacy audit on a synthetic legacy dataset (emulator, real rules).
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDocs, collection, setDoc } from 'firebase/firestore';
import { classifyCanteen, classifyDate, istDateKey, runAudit, runStaffAudit, staffReadiness } from './legacy-audit.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
let env;
const ts = (iso) => new Date(iso);

before(async () => {
  const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-legacy-audit-test',
    firestore: { host: hp[0], port: Number(hp[1]), rules: fs.readFileSync(path.join(here, '..', process.env.RULES_FILE || 'firestore.rules'), 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (p, d) => setDoc(doc(db, p), d);
    await Promise.all([
      put('canteens/north', { name: 'North Campus' }),
      put('canteens/south', { name: 'South Block' }),
      put('canteenStaff/admin-1', { role: 'admin', canteenId: 'main', email: 'admin@x.com' }),
      put('canteenStaff/cn', { role: 'cashier', canteenId: 'north', email: 'cn@x.com' }),
      put('canteenStaff/old', { role: 'cashier', email: 'old@x.com' }), // staff with no branch
      put('canteenStaff/weird', { role: 'Admin', canteenId: 'north', email: 'w@x.com' }),   // wrong-case role: locked out by the new rules
      put('canteenStaff/off', { role: 'cashier', canteenId: 'north', active: false }),       // deactivated
      put('canteenStaff/ghost', { role: 'cashier', canteenId: 'nowhere' }),                  // branch that does not exist
      put('canteenStaff/strtrue', { role: 'cashier', canteenId: 'north', active: 'true' }),  // active stored as a string
      // bills: 7 docs
      put('bills/b1', { canteenId: 'main', createdBy: 'cn', totalAmount: 1 }),                      // fine
      put('bills/b2', { createdBy: 'cn', totalAmount: 2 }),                                          // missing -> staff-uid north (medium)
      put('bills/b3', { canteenName: 'North Campus', totalAmount: 3 }),                              // missing -> canteen-name north (high)
      put('bills/b4', { createdBy: 'admin-1', totalAmount: 4 }),                                     // missing -> admin-creator main (low)
      put('bills/b5', { totalAmount: 5 }),                                                           // missing, nothing -> unrecoverable
      put('bills/b6', { canteenId: '', createdBy: 'cn', totalAmount: 6 }),                           // empty string counts as missing
      put('bills/b7', { createdBy: 'old', totalAmount: 7 }),                                         // staff without branch -> unrecoverable
      // customers
      put('creditCustomers/north_900', { phone: '900', name: 'R' }),                                 // missing -> id-prefix north (high)
      put('creditCustomers/777', { phone: '777', name: 'Z' }),                                       // legacy id -> unrecoverable
      put('creditCustomers/south_800', { phone: '800', canteenId: 'south', name: 'S' }),             // fine
      // repayments
      put('repayments/r1', { customerPhone: '800', amount: 5 }),                                     // missing -> phone-link south (medium)
      put('repayments/r2', { processedBy: 'cn@x.com', amount: 6 }),                                  // missing -> staff by email north (medium)
      put('repayments/r3', { canteenId: 'north', amount: 7 }),                                       // fine
      // dailyStats
      put('dailyStats/north_2026-10-01', { canteenId: 'north', totalSales: 1 }),                     // missing DATE -> id-suffix (high)
      put('dailyStats/2026-09-01', { totalSales: 2, lastUpdated: ts('2026-09-01T20:00:00Z') }),      // missing canteen (unrecoverable) + date from timestamp (IST: 2 Sep)
      put('dailyStats/main_oops', { canteenId: 'main', totalSales: 3 }),                             // date unrecoverable
      put('dailyStats/main_2026-10-02', { canteenId: 'main', date: '2026-10-02', totalSales: 4 }),   // fine
      // closings, expenses, notices, menu
      put('cashReconciliations/north_2026-10-03', { date: '2026-10-03', submittedByUid: 'cn' }),     // missing canteen -> id-prefix (high)
      put('expenses/e1', { userId: 'cn', amount: 1 }),                                               // staff-uid north (medium)
      put('notifications/n1', { sentBy: 'admin@x.com', title: 't' }),                                // admin-creator main (low)
      put('menuItems/m1', { name: 'Tea' }),                                                          // unrecoverable
    ]);
  });
});
after(async () => { await env.cleanup(); });

test('pure classification: canteenId', () => {
  const ctx = {
    canteenIds: new Set(['main', 'north']), nameToIds: new Map([['north campus', ['north']], ['dup', ['north', 'main']]]),
    staffByUid: new Map([['u', { role: 'cashier', canteenId: 'north' }], ['a', { role: 'admin', canteenId: 'main' }]]),
    staffByEmail: new Map(), phoneToBranches: new Map([['1', new Set(['north'])], ['2', new Set(['north', 'main'])]]),
  };
  assert.deepEqual(classifyCanteen('bills', 'x', { canteenId: 'north' }, ctx), { missing: false, recovery: null });
  assert.equal(classifyCanteen('bills', 'x', { canteenId: '   ' }, ctx).missing, true);
  assert.equal(classifyCanteen('bills', 'x', { canteenId: 5 }, ctx).missing, true);
  assert.equal(classifyCanteen('dailyStats', 'north_2026-01-01', {}, ctx).recovery.evidence, 'id-prefix');
  assert.equal(classifyCanteen('dailyStats', 'ghost_2026-01-01', {}, ctx).recovery, null, 'unknown prefix is not trusted');
  assert.equal(classifyCanteen('bills', 'x', { canteenName: 'dup' }, ctx).recovery, null, 'ambiguous name is not trusted');
  assert.equal(classifyCanteen('bills', 'x', { createdBy: 'u' }, ctx).recovery.confidence, 'medium');
  assert.equal(classifyCanteen('bills', 'x', { createdBy: 'a' }, ctx).recovery.confidence, 'low');
  assert.equal(classifyCanteen('repayments', 'x', { customerPhone: '1' }, ctx).recovery.branch, 'north');
  assert.equal(classifyCanteen('repayments', 'x', { customerPhone: '2' }, ctx).recovery, null, 'phone in two branches is ambiguous');
});

test('pure classification: date', () => {
  assert.deepEqual(classifyDate('dailyStats', 'a', { date: '2026-01-02' }), { missing: false, recovery: null });
  assert.equal(classifyDate('dailyStats', 'a', { date: '02/01/2026' }).missing, true);
  assert.equal(classifyDate('dailyStats', 'north_2026-03-04', {}).recovery.date, '2026-03-04');
  assert.equal(classifyDate('dailyStats', '2026-03-04', {}).recovery.evidence, 'id-suffix');
  assert.equal(classifyDate('dailyStats', 'x', { lastUpdated: new Date('2026-03-04T20:00:00Z') }).recovery.date, '2026-03-05', 'IST day, not UTC');
  assert.equal(classifyDate('dailyStats', 'x', {}).recovery, null);
  assert.equal(classifyDate('bills', 'x', {}).missing, false, 'only dailyStats / cashReconciliations carry a date field');
  assert.equal(istDateKey(new Date('2026-10-31T18:29:59Z')), '2026-10-31');
  assert.equal(istDateKey(new Date('2026-10-31T18:30:00Z')), '2026-11-01');
});

test('audit of the synthetic legacy dataset: counts, evidence and samples', async () => {
  const admin = env.authenticatedContext('admin-1').firestore();
  const r = await runAudit(admin);
  const c = r.collections;
  assert.equal(r.readOnly, true);

  assert.equal(c.bills.total, 7);
  assert.equal(c.bills.missingCanteenId, 6);            // b2..b7
  assert.deepEqual(c.bills.recoverable, { high: 1, medium: 2, low: 1 }); // b3 | b2,b6 | b4
  assert.equal(c.bills.unrecoverableDefaultMain, 2);    // b5, b7
  assert.deepEqual(c.bills.samples.unrecoverable.sort(), ['b5', 'b7']);

  assert.equal(c.creditCustomers.missingCanteenId, 2);
  assert.equal(c.creditCustomers.recoverable.high, 1);  // north_900
  assert.deepEqual(c.creditCustomers.samples.unrecoverable, ['777']);

  assert.equal(c.repayments.missingCanteenId, 2);
  assert.equal(c.repayments.recoverable.medium, 2);     // phone-link, staff email
  assert.deepEqual(c.repayments.byEvidence, { 'phone-link': 1, 'staff-uid': 1 });

  assert.equal(c.dailyStats.total, 4);
  assert.equal(c.dailyStats.missingCanteenId, 1);       // '2026-09-01'
  assert.equal(c.dailyStats.unrecoverableDefaultMain, 1);
  assert.equal(c.dailyStats.missingDate, 3);            // north_2026-10-01, 2026-09-01, main_oops
  // north_2026-10-01 and the legacy date-only id 2026-09-01 both carry the date in their id
  assert.deepEqual(c.dailyStats.dateRecoverable, { high: 2, medium: 0 });
  assert.equal(c.dailyStats.dateUnrecoverable, 1);
  assert.deepEqual(c.dailyStats.samples.dateUnrecoverable, ['main_oops']);

  assert.equal(c.cashReconciliations.missingCanteenId, 1);
  assert.equal(c.cashReconciliations.recoverable.high, 1);
  assert.equal(c.cashReconciliations.missingDate, 0);

  assert.equal(c.expenses.recoverable.medium, 1);
  assert.equal(c.notifications.recoverable.low, 1);
  assert.equal(c.menuItems.unrecoverableDefaultMain, 1);
  assert.equal(c.canteenStaff.total, 7);

  // bills 6 + customers 2 + repayments 2 + dailyStats 1 + closings 1 + expenses 1 + notices 1 + menu 1 + staff 1
  assert.equal(r.totals.missingCanteenId, 16);
  // plain-language classes: identifiable + uncertain + unknown covers every missing canteenId
  const cls = r.totals.classification;
  assert.equal(cls.identifiable + cls.uncertain + cls.unknown, 16);
  assert.ok(cls.identifiable > 0 && cls.uncertain > 0 && cls.unknown > 0);
  assert.deepEqual(c.bills.classification, { identifiable: 1, uncertain: 3, unknown: 2 });
  assert.deepEqual(c.dailyStats.classification, { identifiable: 0, uncertain: 0, unknown: 1 });
  assert.equal(r.totals.missingDate, 3);
  assert.equal(r.totals.dateRecoverable, 2);
  assert.equal(r.totals.dateUnrecoverable, 1);
});

test('the audit is read-only: it cannot write, and nothing changed', async () => {
  const admin = env.authenticatedContext('admin-1').firestore();
  const before = (await getDocs(collection(admin, 'bills'))).size;
  await runAudit(admin);
  assert.equal((await getDocs(collection(admin, 'bills'))).size, before);
  const src = fs.readFileSync(path.join(here, 'legacy-audit.mjs'), 'utf8');
  for (const w of ['setDoc', 'addDoc', 'updateDoc', 'deleteDoc', 'writeBatch', 'runTransaction']) {
    assert.ok(!new RegExp(`\\b${w}\\b`).test(src.replace(/\/\/.*$/gm, '')), `${w} must not appear in the audit`);
  }
});

test('it also works for a non-admin only in the sense that it fails loudly (cashiers cannot list collections)', async () => {
  const cashier = env.authenticatedContext('cn').firestore();
  await assert.rejects(runAudit(cashier));
});

test('staff readiness (lock-out check for the stricter rules)', async () => {
  const admin = env.authenticatedContext('admin-1').firestore();
  const r = (await runAudit(admin)).staff;
  assert.equal(r.total, 7);
  assert.equal(r.admins, 1);
  assert.equal(r.activeAdmins, 1);
  assert.equal(r.cashiers, 5);
  assert.equal(r.activeCashiers, 4);                       // old, cn, ghost, strtrue (off is inactive)
  assert.deepEqual(r.invalidRole, ['weird']);
  assert.deepEqual(r.inactive, ['off']);
  assert.deepEqual(r.cashierWithoutCanteen, ['old']);
  assert.deepEqual(r.adminWithoutCanteen, []);
  assert.deepEqual(r.missingCanteenId, ['old']);
  assert.deepEqual(r.unknownCanteen, ['ghost']);
  assert.deepEqual(r.nonBooleanActive, ['strtrue']);
  assert.equal(r.lockoutRisk, false);
});

test('staff readiness flags the catastrophic case: no active admin', () => {
  const mkDoc = (id, data) => ({ id, data: () => data });
  const r = staffReadiness([mkDoc('a', { role: 'admin', active: false }), mkDoc('b', { role: 'Admin' }), mkDoc('c', { role: 'cashier', canteenId: 'main' })], new Set(['main']));
  assert.equal(r.activeAdmins, 0);
  assert.equal(r.lockoutRisk, true);
  assert.deepEqual(r.invalidRole, ['b']);
});

test('--staff-only reads only canteens and canteenStaff and answers the pre-deployment questions', async () => {
  const admin = env.authenticatedContext('admin-1').firestore();
  const r = await runStaffAudit(admin);
  assert.deepEqual(r.collectionsRead, ['canteens', 'canteenStaff']);
  assert.equal(r.readOnly, true);
  assert.deepEqual(r.answers, {
    totalStaffAccounts: 7,
    activeAdmins: 1,
    activeCashiers: 4,
    inactiveStaff: 1,
    invalidOrUnexpectedRoles: 1,
    missingCanteenId: 1,
    atLeastOneActiveAdmin: true,
    staffThatWouldBeLockedOutByStopgap: ['off', 'strtrue'],
  });
  assert.deepEqual(r.staffIdsByRole.admin, ['admin-1']);
  assert.deepEqual(r.staffIdsByRole.other, ['weird']);
  assert.equal(r.staffIdsByRole.cashier.length, 5);
  // the report contains ids and counts only: no e-mail address anywhere
  assert.ok(!JSON.stringify(r).includes('@'));
});

test('--staff-only fails loudly for a non-admin login (cashiers cannot list staff)', async () => {
  await assert.rejects(runStaffAudit(env.authenticatedContext('cn').firestore()));
});
