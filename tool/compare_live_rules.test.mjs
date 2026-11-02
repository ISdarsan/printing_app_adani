import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { compare } from './compare_live_rules.mjs';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const stopgap = read('proposals/firestore.rules.stopgap');
const candidate = read('proposals/firestore.rules.candidate');
const open = read('backups/deployed.rules.2026-11-02.ORIGINAL');

test('identical text matches exactly and semantically', () => {
  assert.deepEqual(compare(stopgap, stopgap), { exact: true, semantic: true });
});

test('Windows line endings and trailing spaces still match', () => {
  const crlf = stopgap.replace(/\r\n/g, '\n').replace(/\n/g, ' \r\n'); // trailing space, then CRLF
  assert.equal(compare(crlf, stopgap).exact, true);
});

test('comments and re-flowed whitespace are semantically equal but not exact', () => {
  const stripped = stopgap.replace(/\/\/.*$/gm, '').replace(/[ \t]+/g, ' ');
  const r = compare(stripped, stopgap);
  assert.equal(r.semantic, true);
  assert.equal(r.exact, false);
});

test('a different rule is detected: stopgap vs candidate vs the open rules', () => {
  assert.equal(compare(candidate, stopgap).semantic, false);
  assert.equal(compare(open, stopgap).semantic, false);
  assert.equal(compare(stopgap, open).semantic, false);
});

test('a single changed character of executable rule text is detected', () => {
  const tampered = stopgap.replace("get('active', true) == true", "get('active', true) == false");
  assert.notEqual(tampered, stopgap);
  assert.equal(compare(tampered, stopgap).semantic, false);
});

test('the open rule can never pass as the stopgap (the dangerous mix-up)', () => {
  const live = 'rules_version = \'2\';\nservice cloud.firestore {\n match /databases/{database}/documents {\n  match /{document=**} {\n   allow read, write: if request.auth != null;\n  }\n }\n}\n';
  assert.equal(compare(live, stopgap).semantic, false);
});
