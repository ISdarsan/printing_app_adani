// Compares rules text you copied from the Firebase Console (Firestore -> Rules)
// with the intended repository rules. OFFLINE and READ-ONLY: it never contacts
// Firebase. The Firebase CLI cannot print the live rules, so this is how a
// deployment is verified afterwards.
//
//   node tool/compare_live_rules.mjs <file-with-copied-rules> stopgap|candidate|rollback
//
// Two comparisons are made:
//   EXACT     - identical after normalising line endings and trailing whitespace
//   SEMANTIC  - identical after also removing comments and all whitespace
//               (the executable rules are the same even if the Console re-flowed text)
// Exit code 0 only if the SEMANTIC comparison passes; EXACT is reported as well.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const TARGETS = {
  stopgap: 'proposals/firestore.rules.stopgap',
  candidate: 'proposals/firestore.rules.candidate',
  rollback: 'backups/deployed.rules.2026-11-02.ORIGINAL',
};

const sha = (t) => crypto.createHash('sha256').update(t).digest('hex');

export const normalizeExact = (t) =>
  t.replace(/\r\n/g, '\n').split('\n').map((l) => l.replace(/[ \t]+$/g, '')).join('\n').replace(/\n+$/g, '') + '\n';

export const normalizeSemantic = (t) =>
  t.replace(/\r\n/g, '\n')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '')
    .replace(/\s+/g, '');

export function compare(liveText, intendedText) {
  const exact = sha(normalizeExact(liveText)) === sha(normalizeExact(intendedText));
  const semantic = sha(normalizeSemantic(liveText)) === sha(normalizeSemantic(intendedText));
  return { exact, semantic };
}

function main() {
  const [file, target] = process.argv.slice(2);
  if (!file || !TARGETS[target]) {
    console.error('usage: node tool/compare_live_rules.mjs <file-with-copied-rules> stopgap|candidate|rollback');
    process.exit(2);
  }
  const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
  const live = fs.readFileSync(file, 'utf8');
  const intended = fs.readFileSync(path.join(root, TARGETS[target]), 'utf8');
  const r = compare(live, intended);
  console.log(`intended file : ${TARGETS[target]}`);
  console.log(`live (copied) : ${file}  [${live.length} chars]`);
  console.log(`EXACT match   : ${r.exact ? 'YES' : 'no'}`);
  console.log(`SEMANTIC match: ${r.semantic ? 'YES (same executable rules)' : 'NO'}`);
  if (!r.semantic) {
    console.log('\nThe copied rules differ from the intended rules. Do NOT assume the deployment is correct.');
    process.exit(1);
  }
  process.exit(0);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
