#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const doctor = require('../lib/windows-hook-doctor');

let passed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ok   ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`  FAIL ${name}\n       ${error.stack || error.message}`);
  }
}

function fixture(manifest, files = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fde-hook-doctor-'));
  fs.mkdirSync(path.join(root, 'hooks'), { recursive: true });
  fs.writeFileSync(path.join(root, 'hooks', 'hooks.json'), manifest, 'utf8');
  for (const [relativePath, content] of Object.entries(files)) {
    const target = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, content, 'utf8');
  }
  return root;
}

function manifest(event, command) {
  return JSON.stringify({
    hooks: {
      [event]: [{ hooks: [{ type: 'command', command }] }],
    },
  }, null, 2);
}

console.log('\nWindows Hook Doctor');

test('비-Windows에서는 파일을 읽거나 변경하지 않고 skip한다', () => {
  const root = path.join(os.tmpdir(), 'does-not-exist-fde-agent');
  const result = doctor.run({ root, platform: 'linux', repair: true });
  assert.strictEqual(result.status, 'skipped');
  assert.strictEqual(result.changedFiles.length, 0);
});

test('BOM/CRLF와 PreToolUse 누락 대상을 중요 오류로 진단한다', () => {
  const raw = `\uFEFF${manifest('PreToolUse', 'node ${CLAUDE_PLUGIN_ROOT}/scripts/missing.js').replace(/\n/g, '\r\n')}`;
  const root = fixture(raw);
  const result = doctor.run({ root, platform: 'win32', probeNode: () => true });
  assert.ok(result.issues.some((issue) => issue.code === 'utf8-bom'));
  assert.ok(result.issues.some((issue) => issue.code === 'crlf'));
  assert.ok(result.issues.some((issue) => issue.code === 'missing-target' && issue.severity === 'critical'));
  assert.strictEqual(result.status, 'blocked');
});

test('SessionStart 누락 대상은 경고이며 전체 실행을 막지 않는다', () => {
  const root = fixture(manifest('SessionStart', 'node ${CLAUDE_PLUGIN_ROOT}/hooks/missing.js'));
  const result = doctor.run({ root, platform: 'win32', probeNode: () => true });
  assert.ok(result.issues.some((issue) => issue.code === 'missing-target' && issue.severity === 'warning'));
  assert.strictEqual(result.status, 'warning');
});

test('복구는 BOM/CRLF를 제거하고 원본 백업을 한 번만 만든다', () => {
  const clean = manifest('SessionStart', 'node ${CLAUDE_PLUGIN_ROOT}/hooks/start.js');
  const root = fixture(`\uFEFF${clean.replace(/\n/g, '\r\n')}`, { 'hooks/start.js': '#!/usr/bin/env node\r\nconsole.log("ok");\r\n' });
  const first = doctor.run({ root, platform: 'win32', repair: true, probeNode: () => true });
  const manifestPath = path.join(root, 'hooks', 'hooks.json');
  const backupPath = path.join(root, 'runtime', 'hook-backups', 'hooks', 'hooks.json.bak');
  assert.strictEqual(first.status, 'healthy');
  assert.ok(first.changedFiles.includes('hooks/hooks.json'));
  assert.ok(first.changedFiles.includes('hooks/start.js'));
  assert.ok(fs.existsSync(backupPath));
  const backup = fs.readFileSync(backupPath, 'utf8');
  doctor.run({ root, platform: 'win32', repair: true, probeNode: () => true });
  assert.strictEqual(fs.readFileSync(backupPath, 'utf8'), backup, '기존 백업을 덮어쓰면 안 된다');
  assert.ok(!fs.readFileSync(manifestPath, 'utf8').startsWith('\uFEFF'));
  assert.ok(!fs.readFileSync(manifestPath, 'utf8').includes('\r\n'));
});

test('상태 로그는 절대경로를 남기지 않고 최근 50건만 유지한다', () => {
  const root = fixture(manifest('SessionStart', 'node ${CLAUDE_PLUGIN_ROOT}/hooks/start.js'), { 'hooks/start.js': 'console.log("ok");\n' });
  for (let index = 0; index < 55; index += 1) {
    doctor.run({ root, platform: 'win32', probeNode: () => true });
  }
  const log = fs.readFileSync(path.join(root, 'runtime', 'windows-hook-health.jsonl'), 'utf8');
  const lines = log.trim().split('\n');
  assert.strictEqual(lines.length, 50);
  assert.ok(!log.includes(root), '상태 로그에 절대경로를 남기면 안 된다');
});

test('agent root 밖의 대상은 중요 오류로 차단하고 수정하지 않는다', () => {
  const root = fixture(manifest('PreToolUse', 'node ${CLAUDE_PLUGIN_ROOT}/../outside.js'));
  const result = doctor.run({ root, platform: 'win32', repair: true, probeNode: () => true });
  assert.ok(result.issues.some((issue) => issue.code === 'outside-agent-root' && issue.severity === 'critical'));
  assert.strictEqual(result.status, 'blocked');
});

test('Node 런타임 기능 점검 실패는 모든 훅을 차단한다', () => {
  const root = fixture(manifest('SessionStart', 'node ${CLAUDE_PLUGIN_ROOT}/hooks/start.js'), { 'hooks/start.js': 'console.log("ok");\n' });
  const result = doctor.run({ root, platform: 'win32', probeNode: () => false });
  assert.ok(result.issues.some((issue) => issue.code === 'node-unavailable' && issue.severity === 'critical'));
  assert.strictEqual(result.status, 'blocked');
});

test('수정할 문제가 없으면 repair 모드도 중복 진단하지 않는다', () => {
  const root = fixture(manifest('SessionStart', 'node ${CLAUDE_PLUGIN_ROOT}/hooks/start.js'), { 'hooks/start.js': 'console.log("ok");\n' });
  let probes = 0;
  const result = doctor.run({
    root,
    platform: 'win32',
    repair: true,
    writeLog: false,
    probeNode: () => { probes += 1; return true; },
  });
  assert.strictEqual(result.status, 'healthy');
  assert.strictEqual(probes, 1);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length > 0) process.exitCode = 1;
