// node --test slack-bot/tests/runtime-artifact-guard.test.js  (LLM·네트워크 없음 — 임시 git 저장소로 실제 재현, giip #4300)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const g = require('../runtime-artifact-guard');

const GENV = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@example.com', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@example.com' };
const mk = (cwd) => (args) => spawnSync('git', args, { cwd, encoding: 'utf8', env: GENV, windowsHide: true });
const write = (root, rel, text) => { const p = path.join(root, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text); };
const cleanup = [];
test.after(() => { for (const d of cleanup) { try { fs.rmSync(d, { recursive: true, force: true }); } catch {} } });

function repo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rag-test-'));
  cleanup.push(root);
  const git = mk(root);
  git(['init', '-b', 'main']);
  write(root, 'README.md', 'x\n');
  git(['add', '-A']); git(['commit', '-m', 'c1']);
  return { root, git };
}

test('경로 판정: 런타임 경로와 산출물 경로 구분', () => {
  assert.ok(g.isRuntimePath('.agent/runtime/cost-usage.jsonl'));
  assert.ok(g.isRuntimePath('.agent\\runtime\\a\\b.json'));
  assert.ok(!g.isRuntimePath('.agent/tasks/t.md'));
  assert.ok(!g.isRuntimePath('src/.agent/runtime-x.js'));
  assert.ok(g.isRuntimeOnly(['.agent/runtime/a', '.agent/runtime/b/c']));
  assert.ok(!g.isRuntimeOnly(['.agent/runtime/a', 'app/index.ts']));
  assert.ok(!g.isRuntimeOnly([]));
});

test('stageDeliverables: .agent/runtime/** 는 스테이징되지 않고 산출물은 스테이징된다', () => {
  const { root, git } = repo();
  write(root, '.agent/runtime/progress/p.json', '{}');
  write(root, '.agent/runtime/cost-usage.jsonl', 'a\n');
  write(root, 'app/index.ts', 'export {}\n');
  g.stageDeliverables(git);
  const staged = git(['diff', '--cached', '--name-only']).stdout.split(/\r?\n/).filter(Boolean);
  assert.deepStrictEqual(staged, ['app/index.ts']);
});

test('stageDeliverables: 런타임 전용 변경이면 아무것도 스테이징되지 않는다(= 커밋할 것이 없다)', () => {
  const { root, git } = repo();
  write(root, '.agent/runtime/evidence/e.json', '{}');
  g.stageDeliverables(git);
  assert.strictEqual(git(['diff', '--cached', '--name-only']).stdout.trim(), '');
});

test('stageDeliverables: 이미 index 에 올라간 런타임 경로도 index 에서 빠진다(작업트리는 보존)', () => {
  const { root, git } = repo();
  write(root, '.agent/runtime/receipts/r.json', '{}');
  git(['add', '-f', '.agent/runtime/receipts/r.json']);
  g.stageDeliverables(git);
  assert.strictEqual(git(['diff', '--cached', '--name-only']).stdout.trim(), '');
  assert.ok(fs.existsSync(path.join(root, '.agent/runtime/receipts/r.json')));
});

test('branchHasDeliverables: 런타임 전용 브랜치는 false, 산출물이 하나라도 있으면 true', () => {
  const { root, git } = repo();
  git(['checkout', '-b', 'task-a']);
  write(root, '.agent/runtime/checkpoints/c.json', '{}');
  git(['add', '-f', '-A']); git(['commit', '-m', 'rt only']);
  assert.strictEqual(g.branchHasDeliverables(git, 'main', 'task-a'), false);
  write(root, 'app/index.ts', 'export {}\n');
  git(['add', '-A']); git(['commit', '-m', 'real']);
  assert.strictEqual(g.branchHasDeliverables(git, 'main', 'task-a'), true);
});

test('branchHasDeliverables: git 판정 불가면 기존 동작 유지(true, fail-open)', () => {
  assert.strictEqual(g.branchHasDeliverables(() => ({ status: 128, stdout: '' }), 'main', 'x'), true);
});
