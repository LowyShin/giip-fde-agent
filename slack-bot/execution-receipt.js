/** Runtime-only record of the inputs and observable outcome of a bot task. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const runtimePaths = require('./runtime-paths');

function receiptPath(baseDir, taskId) {
  return path.join(runtimePaths.runtimeRoot(baseDir), 'receipts', `${runtimePaths.safeTaskId(taskId)}.json`);
}

function write(baseDir, taskId, data) {
  const target = receiptPath(baseDir, taskId);
  if (!runtimePaths.ensureDir(path.dirname(target))) throw new Error('receipt 디렉터리를 만들 수 없음');
  const tmp = `${target}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, target);
  return target;
}

function begin(baseDir, taskId, { project, branch, taskContent, bindingInstructions, contextFiles }) {
  return write(baseDir, taskId, {
    task_id: String(taskId), project, branch,
    started_at: new Date().toISOString(), status: 'running',
    task_sha256: crypto.createHash('sha256').update(taskContent).digest('hex'),
    instruction_sha256: crypto.createHash('sha256').update(bindingInstructions).digest('hex'),
    context_files: (contextFiles || []).map(f => ({ path: f.path, hash: f.hash, chars: f.chars })),
    // A report or model assertion is not proof of verification.
    verification: 'unconfirmed',
  });
}

function finish(baseDir, taskId, { exitCode, sourceFiles, resultFile }) {
  const target = receiptPath(baseDir, taskId);
  let record = {};
  try { record = JSON.parse(fs.readFileSync(target, 'utf8')); } catch {}
  record.finished_at = new Date().toISOString();
  record.exit_code = exitCode;
  record.status = exitCode === 0 ? 'process-exited-zero' : 'process-failed';
  record.source_files_changed = (sourceFiles || []).map(String);
  record.result_file_exists = !!resultFile && fs.existsSync(resultFile);
  return write(baseDir, taskId, record);
}

module.exports = { receiptPath, begin, finish };
