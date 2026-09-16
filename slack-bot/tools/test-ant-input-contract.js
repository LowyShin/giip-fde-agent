const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const ctx = require('../context-builder');
const ledger = require('../instruction-ledger');
const prompts = require('../prompt-templates');
const receipts = require('../execution-receipt');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fde-input-'));
try {
  fs.mkdirSync(path.join(root, '.agent', 'rules'), { recursive: true });
  fs.writeFileSync(path.join(root, '.agent', 'rules', 'scope.md'), '# Scope\nDo only the stated work.');
  const selected = [{ path: '.agent/rules/scope.md', reason: 'scope', max_chars: 1000 }];
  const first = ctx.readSelectedContext(selected, root);
  assert.strictEqual(first.filesRead.length, 1);
  const yaml = ctx.formatContextFilesYaml(first.filesRead);
  const pinned = ctx.parseContextFiles(`---\n${yaml}\n---\n`);
  assert.strictEqual(pinned[0].hash, first.filesRead[0].hash);
  assert.strictEqual(ctx.readSelectedContext(pinned, root).filesRead.length, 1);
  fs.writeFileSync(path.join(root, '.agent', 'rules', 'scope.md'), '# Scope\nChanged.');
  assert.throws(() => ctx.readSelectedContext(pinned, root), /재분석 필요/);
  assert.throws(() => ctx.readSelectedContext([{ path: '../outside.md' }], root), /범위를 벗어남/);

  const spec = '---\nrequest: "원래 지시"\n---\n\n## 개정 (today)\n\n### 추가 요청\n중요한 개정 조건\n## 요청 안의 제목\n제목 아래의 조건\n\n### 갱신된 계획\nAI의 요약\n\n## 추가 지시 (Slack, now)\n삭제 금지\n## Slack 원문 제목\n제목 아래 지시\n';
  const bindingInstructions = ledger.render(spec);
  assert.ok(bindingInstructions.includes('원래 지시'));
  assert.ok(bindingInstructions.includes('중요한 개정 조건'));
  assert.ok(bindingInstructions.includes('삭제 금지'));
  assert.ok(bindingInstructions.includes('제목 아래의 조건'));
  assert.ok(bindingInstructions.includes('제목 아래 지시'));
  assert.ok(!bindingInstructions.includes('AI의 요약'));
  assert.strictEqual(ledger.extract(`request: ${JSON.stringify('첫 줄\n둘째 줄')}`)[0].text, '첫 줄\n둘째 줄');
  const resumed = prompts.buildResumeExecutionPrompt({
    taskClass: 'standard', taskSummary: '짧은 요약', bindingInstructions,
    initialPromptChars: 5000,
  });
  assert.ok(resumed.includes('삭제 금지'));
  assert.ok(resumed.includes('중요한 개정 조건'));
  const largeInstruction = '삭제 금지: ' + '범위 준수. '.repeat(800);
  const protectedResume = prompts.buildResumeExecutionPrompt({
    taskClass: 'standard', taskSummary: '짧은 요약',
    bindingInstructions: largeInstruction, initialPromptChars: 5000,
  });
  assert.ok(protectedResume.includes(largeInstruction.trim()));

  receipts.begin(root, 'task-1', {
    project: 'demo', branch: 'test', taskContent: spec, bindingInstructions,
    contextFiles: first.filesRead,
  });
  receipts.finish(root, 'task-1', { exitCode: 0, sourceFiles: ['src/a.js'] });
  const record = JSON.parse(fs.readFileSync(receipts.receiptPath(root, 'task-1'), 'utf8'));
  assert.strictEqual(record.status, 'process-exited-zero');
  assert.strictEqual(record.verification, 'unconfirmed');
  assert.deepStrictEqual(record.source_files_changed, ['src/a.js']);
  receipts.finish(root, 'task-1', { exitCode: 1, sourceFiles: [] });
  assert.strictEqual(JSON.parse(fs.readFileSync(receipts.receiptPath(root, 'task-1'), 'utf8')).status, 'process-failed');
  console.log('PASS: pinned inputs, instruction ledger, resume, receipt');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
