const fs = require('fs');
const en = JSON.parse(fs.readFileSync('lib/l10n/app_en.arb', 'utf8'));
const te = JSON.parse(fs.readFileSync('lib/l10n/app_te.arb', 'utf8'));
let errors = 0;
for (const [key, value] of Object.entries(en)) {
  if (key.startsWith('@')) continue;
  const placeholders = s => [...s.matchAll(/\{(\w+)\}/g)].map(m => m[1]).sort().join(',');
  if (!te[key] || !/[\u0c00-\u0c7f]/u.test(te[key]) || placeholders(value) !== placeholders(te[key])) {
    console.error('Missing translation or mismatched placeholders: ' + key);
    errors++;
  }
}
for (const key of Object.keys(te)) {
  if (!key.startsWith('@') && !(key in en)) { console.error('Unknown key: ' + key); errors++; }
}
if (errors) process.exit(1);
console.log('PASS: English/Telugu keys, Telugu script and placeholders match.');
if (process.argv.includes('--audit')) {
  const copy = new Set(Object.values(en).filter(x => typeof x === 'string'));
  const files = fs.readdirSync('lib/presentation').filter(x => x.endsWith('.dart'))
    .map(x => 'lib/presentation/' + x).concat(['lib/local_demo_app.dart', 'lib/collector_auth/mobile_collector_qr_scanner.dart']);
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    for (const m of source.matchAll(/'((?:\\.|[^'\\])*)'/g)) {
      const value = m[1].replace(/\\'/g, "'");
      if (/^[A-Z][a-z]/.test(value) && !value.includes('$') && !copy.has(value)) {
        console.log(file + ': ' + value);
      }
    }
  }
}
