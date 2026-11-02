import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { compareRules, parseRules, renderMarkdown } from './rules_diff.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = fs.readFileSync(path.join(here, '..', 'firestore.rules'), 'utf8').split('\r\n').join('\n');
const statusOf = (res, name) => res.rows.find((r) => r.name === name)?.status;

test('parses the real repository rules: helper functions and every collection', () => {
  const p = parseRules(repo);
  for (const f of ['signedIn', 'staffPath', 'staffExists', 'staffData', 'activeStaff', 'isAdmin',
    'staffCanteenId', 'canReadBranch', 'canWriteBranch', 'nonDecreasing']) {
    assert.ok(p.functions.has(f), `function ${f}`);
  }
  for (const c of ['canteenStaff', 'canteens', 'menuItems', 'bills', 'dailyStats', 'expenses',
    'creditCustomers', 'repayments', 'cashReconciliations', 'notifications', 'monthlyFunds', 'counters']) {
    assert.ok([...p.matches.keys()].some((k) => k.startsWith(`/${c}/`)), `match /${c}/`);
  }
  assert.ok(p.matches.get('/bills/{billId}').allows.length >= 4);
});

test('identical file, CRLF and comment/whitespace-only changes are IDENTICAL', () => {
  const noisy = '// header comment\r\n' + repo.replace(/\n/g, '\r\n').replace(/allow /g, 'allow   ') + '\r\n/* trailing */';
  const res = compareRules(noisy, repo);
  assert.equal(res.identical, true);
  assert.ok(res.rows.length > 20);
});

test('a loosened rule is reported on the exact collection and operation', () => {
  const deployed = repo.replace('allow delete: if isAdmin();\n    }\n\n    match /dailyStats', 'allow delete: if activeStaff();\n    }\n\n    match /dailyStats');
  assert.notEqual(deployed, repo);
  const res = compareRules(deployed, repo);
  assert.equal(res.identical, false);
  assert.equal(statusOf(res, '/bills/{billId}'), 'CHANGED');
  const row = res.rows.find((r) => r.name === '/bills/{billId}');
  assert.ok(row.details.some((l) => l.startsWith('- allow delete: if activeStaff()')));
  assert.ok(row.details.some((l) => l.startsWith('+ allow delete: if isAdmin()')));
  // everything else untouched
  assert.equal(res.rows.filter((r) => r.status !== 'IDENTICAL').length, 1);
});

test('a collection only in production, and one only in the repository', () => {
  const deployed = repo.replace(/match \/dailyStats\/\{statsId\} \{[\s\S]*?\n    \}\n\n    match \/expenses/, 'match /expenses')
    .replace('match /{document=**} {', 'match /legacyLogs/{id} {\n      allow read: if true;\n    }\n\n    match /{document=**} {');
  const res = compareRules(deployed, repo);
  assert.equal(statusOf(res, '/dailyStats/{statsId}'), 'ONLY_REPOSITORY');
  assert.equal(statusOf(res, '/legacyLogs/{id}'), 'ONLY_DEPLOYED');
});

test('a changed helper function is reported by name', () => {
  const deployed = repo.replace("staffData().get('active', true) == true", "true");
  const res = compareRules(deployed, repo);
  assert.equal(statusOf(res, 'activeStaff'), 'CHANGED');
});

test('the catch-all deny rule is compared too', () => {
  const deployed = repo.replace('allow read, write: if false;', 'allow read, write: if true;');
  const res = compareRules(deployed, repo);
  assert.equal(res.identical, false);
  const row = res.rows.find((r) => r.status === 'CHANGED');
  assert.ok(row.name.includes('document'), row.name);
});

test('markdown report lists every rule and the differences', () => {
  const deployed = repo.replace("allow delete: if canReadBranch(resource.data);", "allow delete: if isAdmin();");
  const md = renderMarkdown(compareRules(deployed, repo));
  assert.match(md, /\| match \| `\/menuItems\/\{itemId\}` \| CHANGED \|/);
  assert.match(md, /```diff/);
  assert.match(md, /\| function \| `isAdmin` \| IDENTICAL \|/);
});

test('REGRESSION: a long comment header (blank lines after stripping) does not hide the rules', () => {
  const header = ['// line one', '//', '// line three', '', '', ''].join('\n');
  const inner = ["rules_version = '2';", '// comment', '', '// another', ''].join('\n');
  const withHeader = header + repo.replace("rules_version = '2';\n", inner);
  const p = parseRules(withHeader);
  assert.equal(p.functions.size, 10);
  assert.equal(p.matches.size, 13);
  assert.equal(compareRules(withHeader, repo).identical, true);
});

test('an empty or garbage source parses to nothing and is reported as different from real rules', () => {
  const res = compareRules('', repo);
  assert.equal(res.identical, false);
  assert.ok(res.rows.every((r) => r.status === 'ONLY_REPOSITORY'));
});
