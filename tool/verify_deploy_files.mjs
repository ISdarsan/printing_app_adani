// Independent verification of the Firebase deployment files. READ-ONLY and OFFLINE:
// it never contacts Firebase and never deploys. Run it before every deployment.
//
//   node tool/verify_deploy_files.mjs stopgap|candidate|rollback|indexes
//   node tool/verify_deploy_files.mjs --update-manifest   # after an intended rules edit
//
// A phase passes only if EVERY check passes; exit code 0 = pass, 1 = fail.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const EXPECTED_PROJECT = 'canteen-app-adani';

/** SHA-256 over LF-normalised text, so Windows (CRLF) and Linux checkouts agree. */
export const hashText = (text) =>
  crypto.createHash('sha256').update(text.replace(/\r\n/g, '\n')).digest('hex');

const PHASES = {
  stopgap: { config: 'firebase.stopgap.json', rules: 'proposals/firestore.rules.stopgap', key: 'stopgap' },
  candidate: { config: 'firebase.candidate.json', rules: 'proposals/firestore.rules.candidate', key: 'candidate' },
  rollback: { config: 'firebase.rollback.json', rules: 'backups/deployed.rules.2026-11-02.ORIGINAL', key: 'originalOpenRules' },
};

export function verify(phase, root) {
  const checks = [];
  const add = (name, ok, detail = '') => checks.push({ name, ok: !!ok, detail });
  const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');
  const exists = (rel) => fs.existsSync(path.join(root, rel));
  const json = (rel) => { try { return JSON.parse(read(rel)); } catch (e) { return null; } };

  // ---- project binding -----------------------------------------------------
  const rc = json('.firebaserc');
  add('.firebaserc exists and is valid JSON', rc !== null);
  add(`.firebaserc default project is ${EXPECTED_PROJECT}`, rc?.projects?.default === EXPECTED_PROJECT, `found "${rc?.projects?.default}"`);

  const manifest = json('proposals/RULES_MANIFEST.json');
  add('hash manifest exists', manifest !== null);

  if (phase === 'indexes') {
    const cfg = json('firebase.indexes.json');
    add('firebase.indexes.json is valid JSON', cfg !== null);
    add('config has only a "firestore" section', cfg && Object.keys(cfg).join() === 'firestore', JSON.stringify(Object.keys(cfg || {})));
    const f = cfg?.firestore || {};
    add('firestore section has only {database, indexes}: NO rules key', Object.keys(f).every((k) => ['database', 'indexes'].includes(k)) && !('rules' in f), JSON.stringify(Object.keys(f)));
    add('target database is (default)', (f.database ?? '(default)') === '(default)', String(f.database));
    add('indexes file is firestore.indexes.json', f.indexes === 'firestore.indexes.json');
    const idx = exists('firestore.indexes.json') ? read('firestore.indexes.json') : '';
    add('firestore.indexes.json hash matches the manifest', manifest && hashText(idx) === manifest.files?.indexes?.sha256);
    const parsed = (() => { try { return JSON.parse(idx); } catch { return null; } })();
    add('exactly 5 composite indexes', parsed?.indexes?.length === 5, `found ${parsed?.indexes?.length}`);
    add('no field overrides (nothing can be removed)', Array.isArray(parsed?.fieldOverrides) && parsed.fieldOverrides.length === 0);
    return { phase, checks, pass: checks.every((c) => c.ok) };
  }

  const spec = PHASES[phase];
  if (!spec) throw new Error(`unknown phase ${phase}`);

  // ---- the deploy config ---------------------------------------------------
  const cfg = json(spec.config);
  add(`${spec.config} exists and is valid JSON`, cfg !== null);
  add('config has only a "firestore" section (no hosting, functions, storage, indexes elsewhere)', cfg && Object.keys(cfg).join() === 'firestore', JSON.stringify(Object.keys(cfg || {})));
  const f = cfg?.firestore || {};
  add('firestore section has only {database, rules}: NO indexes key', Object.keys(f).every((k) => ['database', 'rules'].includes(k)) && !('indexes' in f), JSON.stringify(Object.keys(f)));
  add('target database is explicitly (default)', f.database === '(default)', String(f.database));
  add(`rules path is exactly ${spec.rules}`, f.rules === spec.rules, String(f.rules));

  // ---- the rules file ------------------------------------------------------
  const present = exists(spec.rules);
  add('rules file exists', present);
  const text = present ? read(spec.rules) : '';
  const norm = text.replace(/\r\n/g, '\n');
  // Pattern guards must look at EXECUTABLE rules only: header comments legitimately
  // quote the old open rule and the old helper they replace.
  const code = norm.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  add(`rules file hash matches the manifest (${spec.key})`, present && manifest && hashText(text) === manifest.files?.[spec.key]?.sha256, present ? hashText(text).slice(0, 16) + '…' : '');

  // ---- content guards: this really is the file it claims to be --------------
  const openPattern = /allow\s+[a-z,\s]+:\s*if\s+request\.auth\s*!=\s*null\s*;/;
  if (phase === 'stopgap') {
    add('stopgap requires an active staff record (isActiveStaff)', /function isActiveStaff\(\)/.test(code) && /allow read, write: if isActiveStaff\(\);/.test(code));
    add('stopgap has no "any signed-in user" rule', !openPattern.test(code));
    add('stopgap is not the candidate (no [CANDIDATE] markers)', !norm.includes('[CANDIDATE]'));
    add('stopgap lets a user read their own staff record', /allow get: if request\.auth != null && request\.auth\.uid == uid;/.test(code));
  }
  if (phase === 'candidate') {
    add('candidate ends with deny-all for unmatched paths', /match \/\{document=\*\*\} \{\s*allow read, write: if false;/.test(code));
    add('candidate has no "any signed-in user" rule', !openPattern.test(code));
    add('candidate has NO e-mail fallback for closings', !/auth\.token\.(get\(|email)/.test(code));
    add('candidate has no implicit main (no get(\'canteenId\', \'main\'))', !/get\('canteenId',\s*'main'\)/.test(code));
    add('candidate menu delete is admin-only', /match \/menuItems\/\{itemId\}[\s\S]*?allow delete: if isAdmin\(\);/.test(code));
    add('candidate is not the stopgap', !/function isActiveStaff\(\)/.test(code));
  }
  if (phase === 'rollback') {
    add('rollback file is the preserved ORIGINAL open rules (documented as insecure)', /allow read, write: if request\.auth != null;/.test(code));
    const shaFile = exists(spec.rules + '.sha256') ? read(spec.rules + '.sha256').trim().split(/\s+/)[0] : '';
    add('backup matches its recorded SHA-256 (raw bytes)', crypto.createHash('sha256').update(fs.readFileSync(path.join(root, spec.rules))).digest('hex') === shaFile);
    add('saved deployed.rules is byte-identical to the backup', exists('deployed.rules') && fs.readFileSync(path.join(root, 'deployed.rules')).equals(fs.readFileSync(path.join(root, spec.rules))));
  }

  // ---- cross-checks --------------------------------------------------------
  if (phase !== 'rollback') {
    const other = phase === 'stopgap' ? 'candidate' : 'stopgap';
    const otherFile = PHASES[other].rules;
    add('config does not point at the other phase\'s rules', f.rules !== otherFile);
  }
  add('production firestore.rules is untouched by this phase (config does not reference it)', f.rules !== 'firestore.rules');
  return { phase, checks, pass: checks.every((c) => c.ok) };
}

export function buildManifest(root) {
  const h = (rel) => ({ path: rel, sha256: hashText(fs.readFileSync(path.join(root, rel), 'utf8')) });
  return {
    note: 'SHA-256 of LF-normalised file contents. Regenerate ONLY after an intended edit: node tool/verify_deploy_files.mjs --update-manifest',
    project: EXPECTED_PROJECT,
    files: {
      stopgap: h('proposals/firestore.rules.stopgap'),
      candidate: h('proposals/firestore.rules.candidate'),
      originalOpenRules: h('backups/deployed.rules.2026-11-02.ORIGINAL'),
      indexes: h('firestore.indexes.json'),
    },
  };
}

function main() {
  const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
  const arg = process.argv[2];
  if (arg === '--update-manifest') {
    fs.writeFileSync(path.join(root, 'proposals/RULES_MANIFEST.json'), JSON.stringify(buildManifest(root), null, 2) + '\n');
    console.log('manifest written: proposals/RULES_MANIFEST.json');
    return;
  }
  if (!['stopgap', 'candidate', 'rollback', 'indexes'].includes(arg)) {
    console.error('usage: node tool/verify_deploy_files.mjs stopgap|candidate|rollback|indexes');
    process.exit(2);
  }
  const r = verify(arg, root);
  for (const c of r.checks) console.log(`${c.ok ? 'PASS' : 'FAIL'}  ${c.name}${c.ok || !c.detail ? '' : '   [' + c.detail + ']'}`);
  console.log(r.pass ? `\nALL ${r.checks.length} CHECKS PASSED for "${arg}". This verifies files only; it does not deploy.` : '\nVERIFICATION FAILED: do not deploy.');
  process.exit(r.pass ? 0 : 1);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
