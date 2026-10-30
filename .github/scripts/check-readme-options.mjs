// Fail if the README and config.js disagree about the settings.
//
// Every setting in config.js must have a table row in the README and its environment
// variable named there, and the README must not mention a BURNBOX_ variable that is not a
// setting. This keeps the configuration reference from drifting out of date.

import { readFileSync } from 'node:fs';

const config = readFileSync('config.js', 'utf8');
const body = config.slice(config.indexOf('const config = {'), config.indexOf('// Load NODE_ENV'));
const settings = [...body.matchAll(/^ {2}"([A-Za-z]+)":/gm)].map((m) => m[1]);
if (settings.length < 20) {
  throw new Error(`Only found ${ settings.length } settings in config.js; the parser needs updating.`);
}

const envName = (setting) => 'BURNBOX_' + setting.replace(/([A-Z])/g, '_$1').toUpperCase();
const readme = readFileSync('README.md', 'utf8');
const problems = [];

for (const setting of settings) {
  if (!readme.includes(`| \`${ setting }\` |`)) {
    problems.push(`${ setting }: no table row in the README`);
  }
  if (!readme.includes(`\`${ envName(setting) }\``)) {
    problems.push(`${ setting }: the README does not name ${ envName(setting) }`);
  }
}

// BURNBOX_VERSION is read by the frontend build, not by config.js.
const known = new Set([...settings.map(envName), 'BURNBOX_VERSION']);
for (const mention of new Set(readme.match(/BURNBOX_[A-Z_]+/g) || [])) {
  if (!known.has(mention)) problems.push(`the README mentions ${ mention }, which is not a setting`);
}

if (problems.length) {
  console.error('README and config.js disagree:\n- ' + problems.join('\n- '));
  process.exit(1);
}
console.log(`README documents all ${ settings.length } settings.`);
