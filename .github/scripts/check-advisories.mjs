// Check things Dependabot cannot see, and report them as markdown.
//
// 1. Advisories published in the upstream projects' own repositories (not all become
//    Dependabot alerts) against the versions in both package-lock.json files.
// 2. Node.js core vulnerabilities (nodejs/security-wg) against the Node version in the
//    published Docker image.
// 3. Licences in the lockfiles that are not on the allow-list.
//
// Fails loudly (non-zero exit) if any source cannot be read: a silent gap would look
// like "all clear". Findings are written to OUTPUT_FILE and printed; exit status is 0
// when the checks ran, whether or not they found anything.
//
// Env: GITHUB_TOKEN (read access to public repos), SEMVER_FROM (directory where `semver`
// is installed), OUTPUT_FILE, NODE_VERSION (version string from the published image,
// e.g. v26.13.0), LOCKFILES (optional, comma-separated, default both lockfiles).

import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const need = (name) => {
  const v = process.env[name];
  if (!v) throw new Error(`${ name } is not set`);
  return v;
};

const token = need('GITHUB_TOKEN');
const semver = createRequire(path.join(need('SEMVER_FROM'), 'package.json'))('semver');
const outputFile = need('OUTPUT_FILE');
const nodeVersion = need('NODE_VERSION').replace(/^v/, '');
const lockfiles = (process.env.LOCKFILES || 'package-lock.json,app/package-lock.json').split(',');

// package name prefix -> repository that publishes its advisories
const WATCHED_REPOS = [
  'expressjs/express', 'expressjs/body-parser', 'expressjs/morgan', 'expressjs/compression',
  'expressjs/cors', 'ljharb/qs', 'axios/axios', 'archiverjs/node-archiver', 'pugjs/pug',
  'napi-rs/node-rs', 'tus/tus-js-client', 'vuejs/core', 'vuejs/vuex', 'webpack/webpack',
  'FortAwesome/vue-fontawesome',
];

// Packages whose licence field is missing or unusual but that were checked by hand.
// Keyed by name@version so a new version is looked at again.
const REVIEWED_LICENCES = {
  'combine-errors@3.0.3': 'MIT, stated in its README (package.json has no licence field). Reviewed 2026-10-30.',
};

const ALLOWED_LICENCES = new Set([
  'MIT', 'ISC', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', '0BSD', 'CC0-1.0',
  'CC-BY-4.0', 'BlueOak-1.0.0', 'Python-2.0', 'Unlicense',
]);

async function get(url, parse = 'json') {
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${ token }`, accept: 'application/vnd.github+json', 'user-agent': 'burnbox-advisory-watch' },
  });
  if (!res.ok) throw new Error(`GET ${ url } returned ${ res.status }`);
  return parse === 'json' ? res.json() : res.text();
}

// name -> [{ version, where, dev }]
const installed = new Map();
const licences = [];
for (const file of lockfiles) {
  const lock = JSON.parse(readFileSync(file, 'utf8'));
  for (const [key, info] of Object.entries(lock.packages || {})) {
    if (!key) continue;
    const name = key.slice(key.lastIndexOf('node_modules/') + 'node_modules/'.length);
    if (!installed.has(name)) installed.set(name, []);
    installed.get(name).push({ version: info.version, where: file, dev: !!info.dev });
    if (!info.dev) licences.push({ name, version: info.version, where: file, licence: info.license });
  }
}

const findings = [];

// 1. Upstream repository advisories
for (const repo of WATCHED_REPOS) {
  const advisories = await get(`https://api.github.com/repos/${ repo }/security-advisories?state=published&per_page=100`);
  for (const adv of advisories) {
    if (adv.withdrawn_at || /^REJECTED/i.test(adv.summary || '')) continue;
    for (const vuln of adv.vulnerabilities || []) {
      if (vuln.package?.ecosystem !== 'npm' || !vuln.vulnerable_version_range) continue;
      const range = vuln.vulnerable_version_range.replace(/,\s*/g, ' ');
      // Upstream repositories often give an open-ended vulnerable range (">=1.0.0") and
      // put the fix in patched_versions (">=1.18.0"), so a version in the patched range is safe.
      const patched = /^\s*[<>]=?\s*[\d.]+\s*$/.test(vuln.patched_versions || '') ? vuln.patched_versions : null;
      for (const copy of installed.get(vuln.package.name) || []) {
        if (patched && semver.satisfies(copy.version, patched, { includePrerelease: true })) continue;
        if (semver.satisfies(copy.version, range, { includePrerelease: true })) {
          findings.push(
            `- **${ vuln.package.name } ${ copy.version }** (${ copy.where }${ copy.dev ? ', build-time only' : '' }) ` +
            `is affected by [${ adv.ghsa_id }](${ adv.html_url }) (${ adv.severity }): ${ adv.summary }. ` +
            `Fixed in ${ vuln.patched_versions || 'no fixed version listed' }.`
          );
        }
      }
    }
  }
}

// 2. Node.js core vulnerabilities against the shipped runtime
const nodeDb = await get('https://raw.githubusercontent.com/nodejs/security-wg/main/vuln/core/index.json', 'json');
for (const entry of Object.values(nodeDb)) {
  if (!entry.vulnerable || !semver.satisfies(nodeVersion, entry.vulnerable)) continue;
  if (entry.patched && semver.satisfies(nodeVersion, entry.patched)) continue;
  findings.push(
    `- **Node.js ${ nodeVersion }** in the published image is affected by ${ (entry.cve || []).join(', ') || 'a core vulnerability' }: ` +
    `${ entry.description } ([details](${ entry.ref })). Patched in ${ entry.patched || 'no fixed version listed' }.`
  );
}

// 3. Licences outside the allow-list (SPDX expressions: every named licence must be allowed)
const seen = new Set();
for (const { name, version, where, licence } of licences) {
  const key = `${ name }@${ version }`;
  if (seen.has(key) || REVIEWED_LICENCES[key]) continue;
  seen.add(key);
  const tokens = String(licence || 'UNKNOWN').split(/\s+(?:AND|OR)\s+|[()]/).map((t) => t.trim()).filter(Boolean);
  if (!tokens.every((t) => ALLOWED_LICENCES.has(t))) {
    findings.push(`- **${ key }** (${ where }) has licence \`${ licence || 'none declared' }\`, which is not on the allow-list. Check we may still use it freely.`);
  }
}

const body = findings.length
  ? `The daily advisory watch found ${ findings.length } thing(s) that apply to Burnbox:\n\n${ findings.join('\n') }\n`
  : '';
writeFileSync(outputFile, body);
console.log(body || 'No findings: the checks ran and nothing applies.');
