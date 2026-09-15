/** Local execution receipt. A successful executor exit is never independent verification. */
const fs = require('fs');
const path = require('path');
const runtimePaths = require('./runtime-paths');
const { maskDeep } = require('./secret-mask');

function receiptPath(taskId, baseDir) {
  const id = String(taskId || '');
  if (!/^[\w.-]{1,120}$/.test(id) || id === '.' || id === '..') throw new Error('invalid task id');
  return path.join(runtimePaths.runtimeRoot(baseDir), 'evidence', `${id}.json`);
}

function read(taskId, baseDir) {
  try { return JSON.parse(fs.readFileSync(receiptPath(taskId, baseDir), 'utf8')); } catch (err) {
    if (err.code === 'ENOENT') return null;
    throw err;
  }
}

function write(taskId, receipt, baseDir) {
  const filename = receiptPath(taskId, baseDir);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  const safe = maskDeep(receipt);
  const content = JSON.stringify(safe, null, 2);
  if (Buffer.byteLength(content) > 4096) throw new Error('evidence receipt exceeds 4096 bytes');
  const temp = `${filename}.${process.pid}.tmp`;
  try { fs.writeFileSync(temp, content, { mode: 0o600 }); fs.renameSync(temp, filename); }
  finally { try { fs.unlinkSync(temp); } catch {} }
  return safe;
}

function recordPrepared(taskId, baseDir) {
  return write(taskId, {
    task_id: taskId, verification_state: 'prepared', prepared_at: new Date().toISOString(),
    started_at: null, executor_exit_code: null, verified_at: null,
  }, baseDir);
}

function recordStarted(taskId, { attempt = 1, provider = null } = {}, baseDir) {
  const receipt = read(taskId, baseDir) || recordPrepared(taskId, baseDir);
  return write(taskId, { ...receipt, verification_state: 'executing', started_at: new Date().toISOString(),
    attempt, provider, executor_exit_code: null, verified_at: null }, baseDir);
}

function recordExit(taskId, exitCode, { attempt = null } = {}, baseDir) {
  const receipt = read(taskId, baseDir);
  if (!receipt || !receipt.started_at) throw new Error('executor start must be observed before exit');
  return write(taskId, { ...receipt, verification_state: exitCode === 0 ? 'executor_reported' : 'failed',
    executor_exit_code: Number.isInteger(exitCode) ? exitCode : null,
    executor_exited_at: new Date().toISOString(), attempt: attempt || receipt.attempt,
    verified_at: null }, baseDir);
}

// Only an independently observed verifier may add a verified transition.
// No such verifier is wired into the Slack worker yet; executor assertions cannot promote it.
module.exports = { receiptPath, read, recordPrepared, recordStarted, recordExit };
