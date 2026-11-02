// READ-ONLY audit of legacy documents: missing `canteenId` and missing `date`.
//
// Reads with the Firestore client SDK as an ADMIN user under the normal security
// rules (admins may list every collection). It imports no write functions and
// performs no writes. It uses no service-account key.
//
// Against production (run by you, with your own admin login; nothing is stored):
//   $env:FIREBASE_API_KEY="<web api key from firebase_options.dart>"
//   $env:FIREBASE_AUDIT_EMAIL="<your admin email>"; $env:FIREBASE_AUDIT_PASSWORD="<password>"
//   node security-tests/legacy-audit.mjs --project canteen-app-adani --out legacy-audit.json
// Against the emulator (how it is tested):   --emulator 127.0.0.1:8080
//
// Output contains counts and DOCUMENT IDS only (no names, phones or amounts).
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, connectAuthEmulator } from 'firebase/auth';
import {
  collection, connectFirestoreEmulator, documentId, getDocs, getFirestore, limit, orderBy, query, startAfter,
} from 'firebase/firestore';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const IST_MS = (5 * 60 + 30) * 60 * 1000;
const isNonEmptyString = (v) => typeof v === 'string' && v.trim().length > 0;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function istDateKey(date) {
  const w = new Date(date.getTime() + IST_MS);
  return w.toISOString().slice(0, 10);
}
const toDate = (v) => (v && typeof v.toDate === 'function' ? v.toDate() : v instanceof Date ? v : null);

/** Which field names carry each collection's "who did this" link. */
export const LINKS = {
  bills: { uid: ['createdBy'], email: ['createdByEmail'], idPrefix: false, phone: 'customerPhone' },
  expenses: { uid: ['userId'], email: [], idPrefix: false },
  repayments: { uid: [], email: ['processedBy'], idPrefix: false, phone: 'customerPhone' },
  cashReconciliations: { uid: ['submittedByUid'], email: ['submittedBy'], idPrefix: true },
  creditCustomers: { uid: [], email: [], idPrefix: true },
  dailyStats: { uid: [], email: [], idPrefix: true },
  notifications: { uid: [], email: ['sentBy'], idPrefix: false },
  menuItems: { uid: [], email: [], idPrefix: false },
  canteenStaff: { uid: [], email: [], idPrefix: false },
};

/**
 * Classify one document.  Returns { missing, recovery } where recovery is
 * { branch, evidence, confidence } or null.
 *
 * Evidence, strongest first:
 *   id-prefix       "<canteenId>_<date|phone>" document id            -> high
 *   canteen-name    canteenName equals exactly one known canteen name  -> high
 *   staff-uid       creator is a non-admin staff member of one branch  -> medium
 *   phone-link      customer phone belongs to one branch only          -> medium
 *   admin-creator   creator is an admin (admin branch != record branch)-> low
 * No evidence -> null (the app already treats such a record as branch 'main').
 */
export function classifyCanteen(collectionName, id, data, ctx) {
  if (collectionName === 'canteens') return { missing: false, recovery: null };
  const present = isNonEmptyString(data.canteenId);
  if (present) return { missing: false, recovery: null };
  const cfg = LINKS[collectionName] || {};
  const known = ctx.canteenIds;

  if (cfg.idPrefix) {
    const m = /^(.+)_[^_]+$/.exec(id);
    if (m && known.has(m[1])) return { missing: true, recovery: { branch: m[1], evidence: 'id-prefix', confidence: 'high' } };
  }
  if (isNonEmptyString(data.canteenName)) {
    const hits = ctx.nameToIds.get(data.canteenName.trim().toLowerCase()) || [];
    if (hits.length === 1) return { missing: true, recovery: { branch: hits[0], evidence: 'canteen-name', confidence: 'high' } };
  }
  const creators = [];
  for (const f of cfg.uid || []) if (isNonEmptyString(data[f])) creators.push(ctx.staffByUid.get(data[f]));
  for (const f of cfg.email || []) if (isNonEmptyString(data[f])) creators.push(ctx.staffByEmail.get(String(data[f]).toLowerCase()));
  const staff = creators.find(Boolean);
  if (staff && isNonEmptyString(staff.canteenId)) {
    return { missing: true, recovery: staff.role === 'admin'
      ? { branch: staff.canteenId, evidence: 'admin-creator', confidence: 'low' }
      : { branch: staff.canteenId, evidence: 'staff-uid', confidence: 'medium' } };
  }
  if (cfg.phone && isNonEmptyString(data[cfg.phone])) {
    const branches = ctx.phoneToBranches.get(String(data[cfg.phone]).trim());
    if (branches && branches.size === 1) return { missing: true, recovery: { branch: [...branches][0], evidence: 'phone-link', confidence: 'medium' } };
  }
  return { missing: true, recovery: null };
}

/** `date` audit for dailyStats and cashReconciliations. */
export function classifyDate(collectionName, id, data) {
  if (collectionName !== 'dailyStats' && collectionName !== 'cashReconciliations') return { missing: false, recovery: null };
  if (typeof data.date === 'string' && DATE_RE.test(data.date)) return { missing: false, recovery: null };
  const m = /_(\d{4}-\d{2}-\d{2})$/.exec(id) || /^(\d{4}-\d{2}-\d{2})$/.exec(id);
  if (m) return { missing: true, recovery: { date: m[1], evidence: 'id-suffix', confidence: 'high' } };
  const ts = toDate(data.lastUpdated) || toDate(data.timestamp);
  if (ts) return { missing: true, recovery: { date: istDateKey(ts), evidence: 'timestamp-ist', confidence: 'medium' } };
  return { missing: true, recovery: null };
}

async function readAll(db, name, pageSize = 500) {
  const out = [];
  let cursor = null;
  for (;;) {
    const q = query(collection(db, name), orderBy(documentId()), ...(cursor ? [startAfter(cursor)] : []), limit(pageSize));
    const snap = await getDocs(q);
    snap.docs.forEach((d) => out.push(d));
    if (snap.docs.length < pageSize) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  return out;
}

/**
 * Lock-out check for the stricter production rules. Under them a person keeps
 * access only if their staff record exists, is not `active: false`, and has
 * role 'admin' or 'cashier' (exactly). Output is document ids and counts only.
 */
export function staffReadiness(staffDocs, canteenIds) {
  const r = { total: staffDocs.length, admins: 0, activeAdmins: 0, cashiers: 0, activeCashiers: 0,
    invalidRole: [], inactive: [], cashierWithoutCanteen: [], adminWithoutCanteen: [], missingCanteenId: [],
    unknownCanteen: [], nonBooleanActive: [], lockoutRisk: false };
  for (const d of staffDocs) {
    const x = d.data();
    const active = x.active !== false; // the app's own rule: only an explicit false deactivates
    const role = x.role;
    // The stopgap and candidate rules test `active == true`; anything else that is
    // not a real boolean would be locked out by them although the app lets it in.
    if ('active' in x && typeof x.active !== 'boolean') r.nonBooleanActive.push(d.id);
    if (role !== 'admin' && role !== 'cashier') { r.invalidRole.push(d.id); continue; }
    if (!active) r.inactive.push(d.id);
    if (role === 'admin') { r.admins++; if (active) r.activeAdmins++; }
    else { r.cashiers++; if (active) r.activeCashiers++; }
    if (!isNonEmptyString(x.canteenId)) {
      r.missingCanteenId.push(d.id);
      if (role === 'cashier') r.cashierWithoutCanteen.push(d.id); // acts as branch 'main'
      else r.adminWithoutCanteen.push(d.id);
    } else if (role === 'cashier' && !canteenIds.has(x.canteenId)) {
      r.unknownCanteen.push(d.id);
    }
  }
  r.lockoutRisk = r.activeAdmins === 0;
  return r;
}

/** Minimal read: only `canteens` and `canteenStaff`. Output: counts and document ids. */
export async function runStaffAudit(db) {
  const [canteenDocs, staffDocs] = await Promise.all([readAll(db, 'canteens'), readAll(db, 'canteenStaff')]);
  const ids = new Set(['main', ...canteenDocs.map((d) => d.id)]);
  const staff = staffReadiness(staffDocs, ids);
  return {
    generatedAt: new Date().toISOString(), readOnly: true, collectionsRead: ['canteens', 'canteenStaff'],
    knownCanteens: [...ids].sort(),
    // Document ids (= Authentication UIDs) only, so you can compare them with
    // Authentication > Users: a UID there that is NOT listed here has no staff
    // record and will lose access once the stopgap is deployed.
    staffIdsByRole: {
      admin: staffDocs.filter((d) => d.data().role === 'admin').map((d) => d.id).sort(),
      cashier: staffDocs.filter((d) => d.data().role === 'cashier').map((d) => d.id).sort(),
      other: staffDocs.filter((d) => d.data().role !== 'admin' && d.data().role !== 'cashier').map((d) => d.id).sort(),
    },
    staff,
    answers: {
      totalStaffAccounts: staff.total,
      activeAdmins: staff.activeAdmins,
      activeCashiers: staff.activeCashiers,
      inactiveStaff: staff.inactive.length,
      invalidOrUnexpectedRoles: staff.invalidRole.length,
      missingCanteenId: staff.missingCanteenId.length,
      atLeastOneActiveAdmin: staff.activeAdmins > 0,
      staffThatWouldBeLockedOutByStopgap: [...new Set([...staff.inactive, ...staff.nonBooleanActive])].sort(),
    },
  };
}

export async function runAudit(db, { sampleSize = 10 } = {}) {
  const [canteenDocs, staffDocs] = await Promise.all([readAll(db, 'canteens'), readAll(db, 'canteenStaff')]);
  const ctx = {
    canteenIds: new Set(['main', ...canteenDocs.map((d) => d.id)]),
    nameToIds: new Map(),
    staffByUid: new Map(),
    staffByEmail: new Map(),
    phoneToBranches: new Map(),
  };
  const addName = (n, id) => { const k = String(n).trim().toLowerCase(); ctx.nameToIds.set(k, [...new Set([...(ctx.nameToIds.get(k) || []), id])]); };
  addName('Main Canteen', 'main');
  canteenDocs.forEach((d) => { if (d.data().name) addName(d.data().name, d.id); });
  staffDocs.forEach((d) => {
    const s = d.data();
    ctx.staffByUid.set(d.id, s);
    if (s.email) ctx.staffByEmail.set(String(s.email).toLowerCase(), s);
  });
  // customer phone -> branches (only customers that DO have a branch)
  const customers = await readAll(db, 'creditCustomers');
  customers.forEach((d) => {
    const x = d.data();
    const b = isNonEmptyString(x.canteenId) ? x.canteenId : (/^(.+)_[^_]+$/.exec(d.id) || [])[1];
    if (b && isNonEmptyString(x.phone)) {
      const k = String(x.phone).trim();
      ctx.phoneToBranches.set(k, new Set([...(ctx.phoneToBranches.get(k) || []), b]));
    }
  });

  const report = { generatedAt: new Date().toISOString(), readOnly: true, collections: {}, totals: {} };
  report.staff = staffReadiness(staffDocs, ctx.canteenIds);
  const names = ['bills', 'expenses', 'repayments', 'cashReconciliations', 'creditCustomers', 'dailyStats', 'notifications', 'menuItems', 'canteenStaff'];
  for (const name of names) {
    const docs = name === 'creditCustomers' ? customers : name === 'canteenStaff' ? staffDocs : await readAll(db, name);
    const c = {
      total: docs.length,
      missingCanteenId: 0,
      recoverable: { high: 0, medium: 0, low: 0 },
      unrecoverableDefaultMain: 0,
      byEvidence: {},
      missingDate: 0,
      dateRecoverable: { high: 0, medium: 0 },
      dateUnrecoverable: 0,
      samples: { missingCanteenId: [], unrecoverable: [], missingDate: [], dateUnrecoverable: [] },
    };
    for (const d of docs) {
      const data = d.data();
      const k = classifyCanteen(name, d.id, data, ctx);
      if (k.missing) {
        c.missingCanteenId++;
        if (c.samples.missingCanteenId.length < sampleSize) c.samples.missingCanteenId.push(d.id);
        if (k.recovery) {
          c.recoverable[k.recovery.confidence]++;
          c.byEvidence[k.recovery.evidence] = (c.byEvidence[k.recovery.evidence] || 0) + 1;
        } else {
          c.unrecoverableDefaultMain++;
          if (c.samples.unrecoverable.length < sampleSize) c.samples.unrecoverable.push(d.id);
        }
      }
      const dk = classifyDate(name, d.id, data);
      if (dk.missing) {
        c.missingDate++;
        if (c.samples.missingDate.length < sampleSize) c.samples.missingDate.push(d.id);
        if (dk.recovery) c.dateRecoverable[dk.recovery.confidence]++;
        else {
          c.dateUnrecoverable++;
          if (c.samples.dateUnrecoverable.length < sampleSize) c.samples.dateUnrecoverable.push(d.id);
        }
      }
    }
    report.collections[name] = c;
  }
  const sum = (f) => Object.values(report.collections).reduce((t, c) => t + f(c), 0);
  report.totals = {
    documents: sum((c) => c.total),
    missingCanteenId: sum((c) => c.missingCanteenId),
    recoverableHigh: sum((c) => c.recoverable.high),
    recoverableMedium: sum((c) => c.recoverable.medium),
    recoverableLow: sum((c) => c.recoverable.low),
    unrecoverableDefaultMain: sum((c) => c.unrecoverableDefaultMain),
    missingDate: sum((c) => c.missingDate),
    dateRecoverable: sum((c) => c.dateRecoverable.high + c.dateRecoverable.medium),
    dateUnrecoverable: sum((c) => c.dateUnrecoverable),
  };
  return report;
}

// ---- CLI ------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);
  const arg = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
  const emulator = arg('--emulator');
  const project = arg('--project') || 'demo-legacy-audit';
  const app = initializeApp({ projectId: project, apiKey: process.env.FIREBASE_API_KEY || 'demo-key' });
  const db = getFirestore(app);
  if (emulator) {
    const [h, p] = emulator.split(':');
    connectFirestoreEmulator(db, h, Number(p));
  } else {
    const email = process.env.FIREBASE_AUDIT_EMAIL; const pw = process.env.FIREBASE_AUDIT_PASSWORD;
    if (!email || !pw || !process.env.FIREBASE_API_KEY) {
      console.error('Set FIREBASE_API_KEY, FIREBASE_AUDIT_EMAIL, FIREBASE_AUDIT_PASSWORD (your own admin login), or use --emulator.');
      process.exit(2);
    }
    await signInWithEmailAndPassword(getAuth(app), email, pw);
  }
  const staffOnly = args.includes('--staff-only');
  const report = staffOnly ? await runStaffAudit(db) : await runAudit(db);
  const out = arg('--out');
  if (out) fs.writeFileSync(out, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(staffOnly ? report.answers : report.totals, null, 2));
  if (staffOnly) console.log('\nIn the saved file: staff.invalidRole / inactive / missingCanteenId / nonBooleanActive / unknownCanteen list the staff document ids to look up in Authentication > Users.');
  process.exit(staffOnly && !report.answers.atLeastOneActiveAdmin ? 3 : 0);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
void connectAuthEmulator;
