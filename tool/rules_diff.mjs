// Rule-by-rule comparison of two Firestore rules sources. Pure functions, no I/O.
//
// A rules file is split into:
//   * top-level helper functions   (function name(args) { ... })
//   * match blocks                 (match /collection/{id} { ... }) with their
//     individual `allow` statements
// Comparison is whitespace/comment insensitive.

const stripComments = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
const squash = (t) => t.replace(/\s+/g, ' ').replace(/\s*([(){}\[\],;:])\s*/g, '$1').trim();

function findBlockEnd(text, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < text.length; i++) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Error('Unbalanced braces in rules source');
}

/** Splits `allow a, b: if cond;` statements out of a match body. */
export function parseAllows(body) {
  const out = [];
  const re = /allow\s+([a-z,\s]+?)\s*(?::\s*if\s+([\s\S]*?))?;/g;
  let m;
  while ((m = re.exec(body))) {
    const ops = m[1].split(',').map((s) => s.trim()).filter(Boolean).sort();
    out.push({ ops, cond: squash(m[2] || 'true') });
  }
  return out;
}

/** -> { functions: Map(name -> text), matches: Map(path -> {allows, nested}) } */
export function parseRules(source) {
  const text = stripComments(source);
  const functions = new Map();
  const matches = new Map();

  const walk = (src, prefix, intoFunctions) => {
    let i = 0;
    while (i < src.length) {
      const rest = src.slice(i);
      const f = /^\s*function\s+(\w+)\s*\(([^)]*)\)\s*\{/.exec(rest);
      const mt = /^\s*match\s+((?:[^\s{]|\{[^}]*\})+)\s*\{/.exec(rest);
      if (f) {
        const open = i + f[0].length - 1;
        const end = findBlockEnd(src, open);
        if (intoFunctions) functions.set(f[1], squash(`(${f[2]})${src.slice(open, end + 1)}`));
        i = end + 1;
      } else if (mt) {
        const open = i + mt[0].length - 1;
        const end = findBlockEnd(src, open);
        const inner = src.slice(open + 1, end);
        const path = prefix + mt[1].trim();
        if (/^\/databases\//.test(mt[1].trim()) || /^\/\{database\}/.test(mt[1].trim())) {
          walk(inner, '', true); // the document root: descend
        } else {
          // collect this block's own allows (excluding nested matches)
          const own = inner.replace(/match\s+[^\{]+\{[\s\S]*\}/g, '');
          matches.set(path, { allows: parseAllows(own) });
          walk(inner, path, false); // nested matches
        }
        i = end + 1;
      } else {
        // skip to next token boundary
        const nxt = rest.search(/\n/);
        // advance past this line; a blank line (nxt === 0) must advance by one,
        // not swallow the rest of the file
        i += nxt < 0 ? rest.length : nxt + 1;
      }
    }
  };
  walk(text, '', true);
  return { functions, matches };
}

const allowKey = (a) => `${a.ops.join(',')}`;
const fmtAllow = (a) => `allow ${a.ops.join(', ')}: if ${a.cond}`;

/**
 * Compare. Returns { identical, rows } where each row is
 * { kind: 'function'|'match', name, status, details[] } and status is one of
 * IDENTICAL | CHANGED | ONLY_DEPLOYED | ONLY_REPOSITORY.
 */
export function compareRules(deployedSrc, repoSrc) {
  const d = parseRules(deployedSrc);
  const r = parseRules(repoSrc);
  const rows = [];

  const names = (a, b) => [...new Set([...a.keys(), ...b.keys()])].sort();

  for (const n of names(d.functions, r.functions)) {
    const a = d.functions.get(n), b = r.functions.get(n);
    if (a && !b) rows.push({ kind: 'function', name: n, status: 'ONLY_DEPLOYED', details: [`- function ${n}${a}`] });
    else if (!a && b) rows.push({ kind: 'function', name: n, status: 'ONLY_REPOSITORY', details: [`+ function ${n}${b}`] });
    else if (a === b) rows.push({ kind: 'function', name: n, status: 'IDENTICAL', details: [] });
    else rows.push({ kind: 'function', name: n, status: 'CHANGED', details: [`- ${a}`, `+ ${b}`] });
  }

  for (const n of names(d.matches, r.matches)) {
    const a = d.matches.get(n), b = r.matches.get(n);
    if (a && !b) {
      rows.push({ kind: 'match', name: n, status: 'ONLY_DEPLOYED', details: a.allows.map((x) => `- ${fmtAllow(x)}`) });
    } else if (!a && b) {
      rows.push({ kind: 'match', name: n, status: 'ONLY_REPOSITORY', details: b.allows.map((x) => `+ ${fmtAllow(x)}`) });
    } else {
      const details = [];
      const ak = new Map(a.allows.map((x) => [allowKey(x), x]));
      const bk = new Map(b.allows.map((x) => [allowKey(x), x]));
      for (const k of [...new Set([...ak.keys(), ...bk.keys()])].sort()) {
        const x = ak.get(k), y = bk.get(k);
        if (x && !y) details.push(`- ${fmtAllow(x)}`);
        else if (!x && y) details.push(`+ ${fmtAllow(y)}`);
        else if (x.cond !== y.cond) details.push(`- ${fmtAllow(x)}`, `+ ${fmtAllow(y)}`);
      }
      rows.push({ kind: 'match', name: n, status: details.length ? 'CHANGED' : 'IDENTICAL', details });
    }
  }
  return { identical: rows.every((x) => x.status === 'IDENTICAL'), rows };
}

export function renderMarkdown(result) {
  const lines = ['| Kind | Name | Status |', '|---|---|---|'];
  for (const x of result.rows) lines.push(`| ${x.kind} | \`${x.name}\` | ${x.status} |`);
  const diffs = result.rows.filter((x) => x.status !== 'IDENTICAL');
  if (diffs.length) {
    lines.push('', '### Differences (`-` deployed, `+` repository)', '');
    for (const x of diffs) {
      lines.push(`**${x.kind} \`${x.name}\`: ${x.status}**`, '```diff', ...x.details, '```', '');
    }
  }
  return lines.join('\n');
}
