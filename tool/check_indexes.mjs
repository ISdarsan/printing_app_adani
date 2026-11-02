// Derives the composite indexes the app's queries need and checks them against
// firestore.indexes.json. Also verifies that every registered query still exists
// in its source file, so the registry cannot silently go stale.
//
//   node tool/check_indexes.mjs            # exit 0 = registry, source and index file agree
//   node tool/check_indexes.mjs --markdown # print the Query -> Index -> Screen -> Role table
//
// Firestore rule used (documented behaviour of composite indexes): a query with
// equality filters on some fields and a range/orderBy on one other field needs an
// index on [equality fields..., that field in the query's direction]. A range
// filter without an explicit orderBy is ordered by the range field ASCENDING.
// A query whose only filters are equality filters on several fields, or a single
// field range/order, is served by single-field indexes (no composite needed).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');

// One entry per distinct query call site. `must` strings are searched in `file`.
const Q = [
  // ---- the six scoped cashier screens (B-14) -------------------------------
  { screen: 'Cashier dashboard: budget banner (month expenses)', role: 'cashier',
    file: 'lib/billing_dashboard_page.dart', coll: 'expenses', eq: ['canteenId'], range: 'timestamp',
    must: ["collection('expenses')", "isLessThan: month.end"] },
  { screen: "Today's Sales", role: 'cashier',
    file: 'lib/today_sales_page.dart', coll: 'bills', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["collection('bills')", "orderBy('timestamp', descending: true)"] },
  { screen: 'Daily Sales Report', role: 'cashier',
    file: 'lib/daily_sales_report_page.dart', coll: 'bills', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["collection('bills')", "orderBy('timestamp', descending: true)"] },
  { screen: 'Bills History', role: 'cashier',
    file: 'lib/all_bills_page.dart', coll: 'bills', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["collection('bills')", "orderBy('timestamp', descending: true)"] },
  { screen: 'Monthly Breakdown', role: 'cashier',
    file: 'lib/monthly_sales_breakdown_page.dart', coll: 'bills', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["collection('bills')", "orderBy('timestamp', descending: true)"] },
  { screen: 'Funds Received (month expenses)', role: 'cashier',
    file: 'lib/funds_received_page.dart', coll: 'expenses', eq: ['canteenId'], range: 'timestamp',
    must: ["collection('expenses')", "isLessThan: month.end"] },
  // ---- the three B-19 screens (existing queries) ---------------------------
  { screen: 'Daily Cash Closing history', role: 'cashier',
    file: 'lib/cash_reconciliation_page.dart', coll: 'cashReconciliations', eq: ['canteenId'], order: ['timestamp', 'desc'],
    must: ["historyQuery.where('canteenId'", "orderBy('timestamp', descending: true)", '.limit(30)'] },
  { screen: 'Notices list', role: 'cashier + admin (selected branch)',
    file: 'lib/notifications_page.dart', coll: 'notifications', eq: ['canteenId'], order: ['timestamp', 'desc'],
    must: ["where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)", "orderBy('timestamp', descending: true)"] },
  { screen: 'Cashier dashboard: new-notice alert (limit 1)', role: 'cashier',
    file: 'lib/billing_dashboard_page.dart', coll: 'notifications', eq: ['canteenId'], order: ['timestamp', 'desc'],
    must: ["collection('notifications')", "where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)", '.limit(1)'] },
  { screen: 'Menu list (Add Item)', role: 'cashier + admin (selected branch)',
    file: 'lib/add_item_page.dart', coll: 'menuItems', eq: ['canteenId'], order: ['name', 'asc'],
    must: ["collection('menuItems')", "orderBy('name')"] },
  // ---- admin analytics, concrete branch (B-08) ----------------------------
  { screen: 'Analytics bills (concrete branch)', role: 'admin',
    file: 'lib/analytics_loader.dart', coll: 'bills', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["db.collection('bills')", "bq.orderBy('timestamp', descending: true)"] },
  { screen: 'Analytics expenses (concrete branch)', role: 'admin',
    file: 'lib/analytics_loader.dart', coll: 'expenses', eq: ['canteenId'], range: 'timestamp', order: ['timestamp', 'asc'],
    must: ["db.collection('expenses')", "eq.orderBy('timestamp')"] },
  // ---- queries that need NO composite index (documented, guarded) ---------
  { screen: 'Cashier dashboard: today card (own-branch query, 2 equality filters)', role: 'cashier',
    file: 'lib/billing_dashboard_page.dart', coll: 'dailyStats', eq: ['canteenId', 'date'],
    must: ["collection('dailyStats')", ".where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)", ".where('date', isEqualTo: BusinessTime.dateKey(DateTime.now()))"] },
  { screen: 'Cash closing: today stats + today closing (own-branch queries)', role: 'cashier',
    file: 'lib/cash_reconciliation_page.dart', coll: 'dailyStats', eq: ['canteenId', 'date'],
    must: [".where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)", ".where('date', isEqualTo: _todayId)"] },
  { screen: 'Bill save: customer-exists check (2 equality filters)', role: 'cashier',
    file: 'lib/print_bill_page.dart', coll: 'creditCustomers', eq: ['canteenId', 'phone'],
    must: [".where('phone', isEqualTo: customerPhone)"] },
  { screen: 'Bill save: create-once check by request id (2 equality filters)', role: 'cashier',
    file: 'lib/print_bill_page.dart', coll: 'bills', eq: ['canteenId', 'clientRequestId'],
    must: [".where('clientRequestId', isEqualTo: requestId)"] },
  { screen: 'Repayment: create-once check by request id (2 equality filters)', role: 'cashier',
    file: 'lib/credit_detail_page.dart', coll: 'repayments', eq: ['canteenId', 'clientRequestId'],
    must: [".where('clientRequestId', isEqualTo: requestId)"] },
  { screen: 'Export: bills (unscoped, admin)', role: 'admin',
    file: 'lib/report_data_loader.dart', coll: 'bills', eq: [], range: 'timestamp', order: ['timestamp', 'desc'],
    must: ["orderBy('timestamp', descending: true)", "isLessThan: r.end"] },
  { screen: 'Credit detail: pending bills (3 equality filters)', role: 'cashier',
    file: 'lib/credit_detail_page.dart', coll: 'bills', eq: ['customerPhone', 'canteenId', 'creditStatus'],
    must: ["where('creditStatus', isEqualTo: 'Pending')"] },
];

function required(q) {
  if (q.docGet) return null;
  const orderField = q.order ? q.order[0] : q.range;
  const dir = q.order ? q.order[1] : 'asc';
  if (q.eq.length === 0) return null; // single-field index (range/order on one field)
  if (!orderField) return null;       // equality filters only: merged single-field indexes
  return {
    coll: q.coll,
    fields: [...q.eq.map((f) => [f, 'ASCENDING']), [orderField, dir === 'desc' ? 'DESCENDING' : 'ASCENDING']],
  };
}
const keyOf = (i) => `${i.coll}(${i.fields.map(([f, d]) => `${f} ${d === 'ASCENDING' ? 'ASC' : 'DESC'}`).join(', ')})`;

let ok = true;
const fail = (m) => { ok = false; console.error('FAIL ' + m); };

// 1. registry vs source
for (const q of Q) {
  const src = read(q.file);
  for (const m of q.must) if (!src.includes(m)) fail(`${q.screen}: "${m}" not found in ${q.file} (registry stale or query changed)`);
}

// 2. derived vs file
const derived = new Map();
for (const q of Q) {
  const r = required(q);
  if (r) derived.set(keyOf(r), [...(derived.get(keyOf(r)) || []), q]);
}
const file = JSON.parse(read('firestore.indexes.json'));
const declared = new Set(file.indexes.map((i) => keyOf({
  coll: i.collectionGroup, fields: i.fields.map((f) => [f.fieldPath, f.order]),
})));
for (const k of derived.keys()) if (!declared.has(k)) fail(`required index missing from firestore.indexes.json: ${k}`);
for (const k of declared) if (!derived.has(k)) fail(`firestore.indexes.json declares an index no registered query needs: ${k}`);

if (process.argv.includes('--markdown')) {
  console.log('| # | Query / screen | Role | Required composite index |');
  console.log('|---|---|---|---|');
  Q.forEach((q, n) => {
    const r = required(q);
    console.log(`| ${n + 1} | ${q.screen} (\`${q.file}\`) | ${q.role} | ${r ? keyOf(r) : 'none (single-field / document get)'} |`);
  });
  console.log('\n| Index | Serves |');
  console.log('|---|---|');
  for (const [k, qs] of derived) console.log(`| \`${k}\` | ${qs.length} queries: ${qs.map((q) => q.screen).join('; ')} |`);
}

console.log(`${Q.length} registered queries -> ${derived.size} required composite indexes; file declares ${declared.size}.`);
console.log(ok ? 'OK: registry, source and firestore.indexes.json agree.' : 'MISMATCH (see FAIL lines).');
process.exit(ok ? 0 : 1);
