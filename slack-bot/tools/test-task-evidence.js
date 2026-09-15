const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fde-evidence-'));
process.env.FDE_RUNTIME_DIR = dir;
const evidence = require('../task-evidence');

try {
  const id = 'giip-9981';
  evidence.recordPrepared(id);
  assert.strictEqual(evidence.read(id).verification_state, 'prepared');
  assert.strictEqual(evidence.read(id).started_at, null);

  evidence.recordStarted(id, { attempt: 1, provider: 'claude' });
  assert.strictEqual(evidence.read(id).verification_state, 'executing');
  assert.ok(evidence.read(id).started_at);

  evidence.recordExit(id, 0, { attempt: 1 });
  assert.strictEqual(evidence.read(id).verification_state, 'executor_reported');
  assert.strictEqual(evidence.read(id).verified_at, null);
  assert.strictEqual(evidence.recordVerified, undefined, 'caller-supplied observation cannot promote a receipt');
  assert.strictEqual(evidence.read(id).verification_state, 'executor_reported');

  const failed = 'giip-9982';
  evidence.recordPrepared(failed);
  evidence.recordStarted(failed, { attempt: 1 });
  evidence.recordExit(failed, 1, { attempt: 1 });
  assert.strictEqual(evidence.read(failed).verification_state, 'failed');
  evidence.recordStarted(failed, { attempt: 2 });
  evidence.recordExit(failed, 0, { attempt: 2 });
  assert.strictEqual(evidence.read(failed).verification_state, 'executor_reported');

  const secret = 'xoxb-abcdefghijklmnopqrstuvwxyz';
  evidence.recordStarted(failed, { provider: secret, attempt: 3 });
  const raw = fs.readFileSync(evidence.receiptPath(failed), 'utf8');
  assert.ok(!raw.includes(secret), 'secret must not persist in receipt');
  assert.throws(() => evidence.recordPrepared('../escape'), /task id/i);
  delete process.env.FDE_RUNTIME_DIR;
  const baseDir = path.join(dir, 'workspace');
  evidence.recordPrepared('giip-9983', baseDir);
  assert.strictEqual(evidence.read('giip-9983', baseDir).verification_state, 'prepared');
  assert.ok(evidence.receiptPath('giip-9983', baseDir).startsWith(path.join(baseDir, '.agent', 'runtime')));
  console.log('task evidence lifecycle: PASS');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
