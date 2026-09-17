const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { searchKLayer } = require('../k-layer');

function workspace(t, name) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `klayer-${name}-`));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, '.agent', 'knowledge', 'notes'), { recursive: true });
  return root;
}
function note(root, content) {
  fs.writeFileSync(path.join(root, '.agent', 'knowledge', 'notes', 'api-patterns.md'), content);
}
const claim = (id, label, fields = '') => `CLAIM-${id}: ${label}\n- **invalidated_at**: null\n${fields}\n`;

test('scoped recall reads only the requested workspace, project and CSN', t => {
  const a = workspace(t, 'a');
  const b = workspace(t, 'b');
  note(a, [claim('001', 'own', '- **project**: alpha\n- **csn**: 47'), claim('002', 'foreign project', '- **project**: beta\n- **csn**: 47'), claim('003', 'foreign CSN', '- **project**: alpha\n- **csn**: 99'), claim('004', 'legacy')].join('\n'));
  note(b, claim('001', 'other workspace', '- **project**: alpha\n- **csn**: 47'));
  const result = searchKLayer('api', { workspaceDir: a, project: 'alpha', csn: 47 });
  assert.equal(result.length, 1);
  assert.match(result[0], /own/);
});

test('expired, invalidated and changed-source claims are withheld', t => {
  const root = workspace(t, 'fresh');
  const source = path.join(root, 'source.txt');
  fs.writeFileSync(source, 'current');
  const digest = crypto.createHash('sha256').update('current').digest('hex');
  note(root, [
    claim('001', 'fresh', `- **project**: alpha\n- **expires_at**: 2027-01-01\n- **source_file**: source.txt\n- **source_hash**: ${digest}`),
    claim('002', 'expired', '- **project**: alpha\n- **expires_at**: 2026-01-01'),
    claim('003', 'changed', '- **project**: alpha\n- **source_file**: source.txt\n- **source_hash**: deadbeef'),
    'CLAIM-004: invalidated\n- **project**: alpha\n- **invalidated_at**: 20260901',
  ].join('\n'));
  assert.deepEqual(searchKLayer('api', { workspaceDir: root, project: 'alpha', now: '2026-09-15' }).map(x => x.match(/CLAIM-\d+/)[0]), ['CLAIM-001']);
  fs.writeFileSync(source, 'modified');
  assert.equal(searchKLayer('api', { workspaceDir: root, project: 'alpha', now: '2026-09-15' }).length, 0);
});

test('legacy headings are parsed but unscoped notes stay in the agent repo', t => {
  const customer = workspace(t, 'customer');
  note(customer, '## CLAIM-007: legacy heading\n- **invalidated_at**: null\n');
  assert.deepEqual(searchKLayer('api', { workspaceDir: customer, project: path.basename(customer) }), []);
  const own = path.join(__dirname, '..', '..');
  assert.ok(searchKLayer('api', { workspaceDir: own, project: 'giip-fde-agent' }).some(x => /CLAIM-/.test(x)));
});

test('recall is limited by count and characters', t => {
  const root = workspace(t, 'bound');
  note(root, Array.from({ length: 20 }, (_, i) => claim(String(i + 1).padStart(3, '0'), `item-${i}`, '- **project**: alpha')).join('\n'));
  const result = searchKLayer('api', { workspaceDir: root, project: 'alpha', maxClaims: 3, maxChars: 100 });
  assert.ok(result.length <= 3);
  assert.ok(result.join('\n').length <= 100);
});

test('unknown CSN cannot retrieve CSN-specific claims', t => {
  const root = workspace(t, 'csn');
  note(root, claim('001', 'restricted', '- **project**: alpha\n- **csn**: 47'));
  assert.deepEqual(searchKLayer('api', { workspaceDir: root, project: 'alpha' }), []);
});

test('source digest cannot read files outside its workspace', t => {
  const root = workspace(t, 'outside');
  const secret = path.join(path.dirname(root), 'outside-source.txt');
  fs.writeFileSync(secret, 'outside');
  t.after(() => fs.rmSync(secret, { force: true }));
  const digest = crypto.createHash('sha256').update('outside').digest('hex');
  note(root, claim('001', 'outside source', `- **project**: alpha\n- **source_file**: ../outside-source.txt\n- **source_hash**: ${digest}`));
  assert.deepEqual(searchKLayer('api', { workspaceDir: root, project: 'alpha' }), []);
});

test('a notes symlink cannot import another workspace claims', t => {
  const a = workspace(t, 'a');
  const b = workspace(t, 'b');
  note(b, claim('001', 'borrowed', '- **project**: alpha'));
  const notes = path.join(a, '.agent', 'knowledge', 'notes');
  fs.rmSync(notes, { recursive: true });
  fs.symlinkSync(path.join(b, '.agent', 'knowledge', 'notes'), notes, 'dir');
  assert.deepEqual(searchKLayer('api', { workspaceDir: a, project: 'alpha' }), []);
});

test('claims awaiting review and malformed review dates are withheld', t => {
  const root = workspace(t, 'review');
  note(root, [
    claim('001', 'future review', '- **project**: alpha\n- **review_due_at**: 2026-10-01'),
    claim('002', 'review overdue', '- **project**: alpha\n- **review_due_at**: 2026-09-01'),
    claim('003', 'bad review date', '- **project**: alpha\n- **review_due_at**: 2026-13-01'),
  ].join('\n'));
  assert.deepEqual(searchKLayer('api', { workspaceDir: root, project: 'alpha', now: '2026-09-15' }).map(x => x.match(/CLAIM-\d+/)[0]), ['CLAIM-001']);
});

test('a very large hashed source is withheld without unbounded reading', t => {
  const root = workspace(t, 'large');
  fs.writeFileSync(path.join(root, 'large.bin'), Buffer.alloc(3 * 1024 * 1024));
  const digest = crypto.createHash('sha256').update(Buffer.alloc(3 * 1024 * 1024)).digest('hex');
  note(root, claim('001', 'large source', `- **project**: alpha\n- **source_file**: large.bin\n- **source_hash**: ${digest}`));
  assert.deepEqual(searchKLayer('api', { workspaceDir: root, project: 'alpha' }), []);
});
