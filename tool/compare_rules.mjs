// Compare the Firestore rules deployed in production with firestore.rules in
// this repository. READ-ONLY. Never deploys, never writes to Firebase.
//
// Two ways to supply the deployed rules (neither involves service-account keys):
//
//  A) Copy/paste from Firebase Console (Firestore > Rules) into a file:
//       node tool/compare_rules.mjs --deployed-file deployed.rules
//
//  B) Short-lived access token of YOUR OWN signed-in Google account. The token
//     is read from the environment only (never from disk, never printed):
//       gcloud auth print-access-token   # in your own shell
//       set FIREBASE_ACCESS_TOKEN=<token>   (PowerShell: $env:FIREBASE_ACCESS_TOKEN="<token>")
//       node tool/compare_rules.mjs --project canteen-app-adani
//
// Exit code: 0 identical (ignoring line endings / trailing spaces), 1 different,
// 2 usage or network error.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRules = path.join(here, '..', 'firestore.rules');

const args = process.argv.slice(2);
const arg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

const normalize = (t) =>
  t.replace(/\r\n/g, '\n').split('\n').map((l) => l.replace(/\s+$/, '')).join('\n').replace(/\n+$/, '') + '\n';

async function fetchDeployed(project) {
  const token = process.env.FIREBASE_ACCESS_TOKEN;
  if (!token) {
    console.error('Set FIREBASE_ACCESS_TOKEN (see header of this file) or use --deployed-file.');
    process.exit(2);
  }
  const base = 'https://firebaserules.googleapis.com/v1';
  const headers = { Authorization: `Bearer ${token}` };
  const rel = await fetch(`${base}/projects/${project}/releases/cloud.firestore`, { headers });
  if (!rel.ok) {
    console.error(`Could not read the release (HTTP ${rel.status}). Token expired or no access?`);
    process.exit(2);
  }
  const { rulesetName } = await rel.json();
  const rs = await fetch(`${base}/${rulesetName}`, { headers });
  if (!rs.ok) {
    console.error(`Could not read the ruleset (HTTP ${rs.status}).`);
    process.exit(2);
  }
  const body = await rs.json();
  const file = body.source.files.find((f) => f.name === 'firestore.rules') || body.source.files[0];
  console.log(`Deployed ruleset: ${rulesetName} (created ${body.createTime})`);
  return file.content;
}

let deployed;
const dFile = arg('--deployed-file');
if (dFile) {
  deployed = fs.readFileSync(dFile, 'utf8');
} else if (arg('--project')) {
  deployed = await fetchDeployed(arg('--project'));
} else {
  console.error('Usage: node tool/compare_rules.mjs --deployed-file <file> | --project <id>');
  process.exit(2);
}

const repo = normalize(fs.readFileSync(arg('--repo-file') || repoRules, 'utf8'));
const dep = normalize(deployed);
if (repo === dep) {
  console.log('IDENTICAL: deployed rules match firestore.rules.');
  process.exit(0);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rules-'));
const a = path.join(tmp, 'deployed.rules');
const b = path.join(tmp, 'repository.rules');
fs.writeFileSync(a, dep);
fs.writeFileSync(b, repo);
const d = spawnSync('git', ['diff', '--no-index', '--no-color', '--unified=2', a, b], { encoding: 'utf8' });
console.log('DIFFERENT (- deployed, + repository):\n');
console.log(d.stdout || '(diff unavailable)');
fs.rmSync(tmp, { recursive: true, force: true });
process.exit(1);
