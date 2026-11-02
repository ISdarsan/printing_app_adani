import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { verify } from './verify_deploy_files.mjs';

const real = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const files = [
  '.firebaserc', 'firestore.indexes.json', 'deployed.rules',
  'firebase.stopgap.json', 'firebase.candidate.json', 'firebase.rollback.json', 'firebase.indexes.json',
  'proposals/firestore.rules.stopgap', 'proposals/firestore.rules.candidate', 'proposals/RULES_MANIFEST.json',
  'backups/deployed.rules.2026-11-02.ORIGINAL', 'backups/deployed.rules.2026-11-02.ORIGINAL.sha256',
];

/** A scratch copy of the deployment files that a test may damage. */
function sandbox() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'deploychk-'));
  for (const f of files) {
    const dst = path.join(root, f);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(real, f), dst);
    try { fs.chmodSync(dst, 0o644); } catch {}
  }
  return root;
}
const edit = (root, rel, fn) => {
  const p = path.join(root, rel);
  fs.writeFileSync(p, fn(fs.readFileSync(p, 'utf8')));
};
const failing = (r) => r.checks.filter((c) => !c.ok).map((c) => c.name);

test('the real repository files pass for every phase', () => {
  for (const phase of ['stopgap', 'candidate', 'rollback', 'indexes']) {
    const r = verify(phase, real);
    assert.deepEqual(failing(r), [], phase);
    assert.equal(r.pass, true);
  }
});

test('a stopgap config that also names indexes FAILS (could deploy indexes by accident)', () => {
  const root = sandbox();
  edit(root, 'firebase.stopgap.json', (t) => JSON.stringify({ firestore: { database: '(default)', rules: 'proposals/firestore.rules.stopgap', indexes: 'firestore.indexes.json' } }));
  const r = verify('stopgap', root);
  assert.equal(r.pass, false);
  assert.ok(failing(r).some((n) => n.includes('NO indexes key')));
});

test('a stopgap config pointing at the candidate (or at the production rules) FAILS', () => {
  for (const wrong of ['proposals/firestore.rules.candidate', 'firestore.rules']) {
    const root = sandbox();
    edit(root, 'firebase.stopgap.json', () => JSON.stringify({ firestore: { database: '(default)', rules: wrong } }));
    assert.equal(verify('stopgap', root).pass, false, wrong);
  }
});

test('a config for another database or with extra services FAILS', () => {
  const root = sandbox();
  edit(root, 'firebase.stopgap.json', () => JSON.stringify({ firestore: { database: 'other-db', rules: 'proposals/firestore.rules.stopgap' } }));
  assert.equal(verify('stopgap', root).pass, false);
  const root2 = sandbox();
  edit(root2, 'firebase.stopgap.json', () => JSON.stringify({ firestore: { database: '(default)', rules: 'proposals/firestore.rules.stopgap' }, hosting: { public: 'build' } }));
  assert.equal(verify('stopgap', root2).pass, false);
});

test('ANY edit of the rules file changes its hash and FAILS until the manifest is deliberately updated', () => {
  const root = sandbox();
  edit(root, 'proposals/firestore.rules.stopgap', (t) => t + '\n// innocent-looking comment\n');
  const r = verify('stopgap', root);
  assert.equal(r.pass, false);
  assert.ok(failing(r).some((n) => n.includes('hash matches the manifest')));
});

test('line-ending differences alone do NOT fail (Windows checkouts)', () => {
  const root = sandbox();
  edit(root, 'proposals/firestore.rules.candidate', (t) => t.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n'));
  assert.equal(verify('candidate', root).pass, true);
});

test('a stopgap that was swapped for the open rules FAILS', () => {
  const root = sandbox();
  edit(root, 'proposals/firestore.rules.stopgap', () => fs.readFileSync(path.join(real, 'deployed.rules'), 'utf8'));
  const r = verify('stopgap', root);
  assert.equal(r.pass, false);
  assert.ok(failing(r).some((n) => n.includes('any signed-in user')) || failing(r).some((n) => n.includes('isActiveStaff')));
});

test('a wrong or missing Firebase project binding FAILS', () => {
  const root = sandbox();
  edit(root, '.firebaserc', () => JSON.stringify({ projects: { default: 'some-other-project' } }));
  assert.equal(verify('stopgap', root).pass, false);
  const root2 = sandbox();
  fs.rmSync(path.join(root2, '.firebaserc'));
  assert.equal(verify('stopgap', root2).pass, false);
});

test('candidate guards: e-mail fallback, implicit main or an open catch-all FAIL', () => {
  for (const [label, mutate] of [
    ['email fallback', (t) => t.replace("request.resource.data.get('submittedByUid', '') == request.auth.uid &&", "(request.resource.data.get('submittedByUid', '') == request.auth.uid || request.auth.token.email == request.resource.data.submittedBy) &&")],
    ['implicit main', (t) => t.replace('return staffData().canteenId;', "return staffData().get('canteenId', 'main');")],
    ['open catch-all', (t) => t.replace('allow read, write: if false;', 'allow read, write: if request.auth != null;')],
    ['cashier menu delete', (t) => t.replace('allow delete: if isAdmin();\n    }\n\n    match /bills', 'allow delete: if activeStaff();\n    }\n\n    match /bills')],
  ]) {
    const root = sandbox();
    edit(root, 'proposals/firestore.rules.candidate', mutate);
    assert.equal(verify('candidate', root).pass, false, label);
  }
});

test('indexes: a rules key, a changed index file or an index count other than 5 FAILS', () => {
  const root = sandbox();
  edit(root, 'firebase.indexes.json', () => JSON.stringify({ firestore: { database: '(default)', indexes: 'firestore.indexes.json', rules: 'firestore.rules' } }));
  assert.equal(verify('indexes', root).pass, false);
  const root2 = sandbox();
  edit(root2, 'firestore.indexes.json', (t) => { const j = JSON.parse(t); j.indexes.pop(); return JSON.stringify(j, null, 2); });
  assert.equal(verify('indexes', root2).pass, false);
});

test('rollback: a tampered backup FAILS', () => {
  const root = sandbox();
  const b = path.join(root, 'backups/deployed.rules.2026-11-02.ORIGINAL');
  fs.writeFileSync(b, fs.readFileSync(b, 'utf8') + '\n// edited\n');
  assert.equal(verify('rollback', root).pass, false);
});
