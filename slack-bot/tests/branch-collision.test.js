// node --test slack-bot/tests/branch-collision.test.js  (LLM·네트워크 없음 — 로컬 bare 원격 + 작업 클론으로 실제 git 재현)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const tm = require('../task-manager');
const bc = require('../branch-collision');

const GENV = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@example.com', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@example.com' };
const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', env: GENV, windowsHide: true });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
};
const write = (root, rel, text) => { const p = path.join(root, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text); };
const lines = (...a) => a.join('\n') + '\n';
const cleanup = [];
test.afterEach(() => tm.restoreTaskBranch(null)); // 단언 실패 시에도 gitTreeBusy 해제
test.after(() => { for (const d of cleanup) { try { fs.rmSync(d, { recursive: true, force: true }); } catch {} } });

// 원격(main: c1) + 작업 클론(c1 상태). 이후 seedFn 으로 원격 main 을 c2 로 전진시킨다.
function setup(seedFn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bc-test-'));
  cleanup.push(root);
  const bare = path.join(root, 'remote.git');
  const seed = path.join(root, 'seed');
  const work = path.join(root, 'work');
  git(root, 'init', '--bare', '-b', 'main', bare);
  git(root, 'clone', bare, seed);
  git(seed, 'checkout', '-B', 'main');
  write(seed, 'README.md', 'hello\n');
  git(seed, 'add', '.'); git(seed, 'commit', '-m', 'c1'); git(seed, 'push', 'origin', 'main');
  git(root, 'clone', bare, work);
  seedFn(seed);
  git(seed, 'add', '-A'); git(seed, 'commit', '-m', 'c2'); git(seed, 'push', 'origin', 'main');
  return work;
}
const finish = (ctx, dir) => { tm.restoreTaskBranch(ctx, dir); if (ctx && ctx.preserved) cleanup.push(ctx.preserved.dir); };

const RT = '.agent/runtime/cost-usage.jsonl';
const TRACKED = lines('l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7');

test('재현: untracked 로그가 startPoint 에 tracked 로 생기면 병합해 checkout 성공(유실 없음)', () => {
  const work = setup(s => write(s, RT, TRACKED));
  write(work, RT, lines('l1', 'l2', 'l3', 'local-a', 'local-b'));
  const ctx = tm.prepareTaskBranch('t1', work);
  assert.strictEqual(ctx.ok, true, ctx.error);
  assert.strictEqual(ctx.branch, 'bot/task-t1');
  assert.strictEqual(fs.readFileSync(path.join(work, RT), 'utf8'), lines('l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'local-a', 'local-b'));
  assert.ok(ctx.preserved && ctx.preserved.files.includes(RT));
  assert.strictEqual(fs.readFileSync(path.join(ctx.preserved.dir, RT), 'utf8'), lines('l1', 'l2', 'l3', 'local-a', 'local-b'));
  finish(ctx, work);
});

test('회귀: 충돌 없는 일반 경우는 기존과 같다(preserved=null)', () => {
  const work = setup(s => write(s, 'docs/a.md', 'x\n'));
  write(work, 'scratch.txt', 'mine\n');
  const ctx = tm.prepareTaskBranch('t2', work);
  assert.strictEqual(ctx.ok, true, ctx.error);
  assert.strictEqual(ctx.preserved, null);
  assert.strictEqual(ctx.stashed, false);
  assert.strictEqual(fs.readFileSync(path.join(work, 'scratch.txt'), 'utf8'), 'mine\n');
  assert.ok(fs.existsSync(path.join(work, 'docs/a.md')));
  finish(ctx, work);
});

test('회귀(②): 태스크 파일 충돌은 현재 요청(untracked)본이 이긴다', () => {
  const rel = '.agent/tasks/t3.md';
  const work = setup(s => write(s, rel, 'OLD\n'));
  write(work, rel, 'NEW REQUEST\n');
  const ctx = tm.prepareTaskBranch('t3', work);
  assert.strictEqual(ctx.ok, true, ctx.error);
  assert.strictEqual(fs.readFileSync(path.join(work, rel), 'utf8'), 'NEW REQUEST\n');
  finish(ctx, work);
});

test('로그성이 아닌 파일 충돌: tracked 버전 유지 + 로컬본은 백업 폴더에만', () => {
  const work = setup(s => write(s, 'notes/x.txt', 'tracked\n'));
  write(work, 'notes/x.txt', 'local only\n');
  const ctx = tm.prepareTaskBranch('t4', work);
  assert.strictEqual(ctx.ok, true, ctx.error);
  assert.strictEqual(fs.readFileSync(path.join(work, 'notes/x.txt'), 'utf8').replace(/\r\n/g, '\n'), 'tracked\n'); // autocrlf 환경 허용
  assert.deepStrictEqual(ctx.preserved.files, ['notes/x.txt']);
  assert.strictEqual(fs.readFileSync(path.join(ctx.preserved.dir, 'notes/x.txt'), 'utf8'), 'local only\n');
  finish(ctx, work);
});

test('checkout 실패 시 치운 파일이 원위치로 복원되고 실패를 반환한다', () => {
  const work = setup(s => write(s, RT, TRACKED));
  const localText = lines('l1', 'local-a');
  write(work, RT, localText);
  fs.writeFileSync(path.join(work, '.git', 'index.lock'), ''); // checkout 을 강제로 실패시킨다
  const ctx = tm.prepareTaskBranch('t5', work);
  assert.strictEqual(ctx.ok, false);
  assert.ok(Array.isArray(ctx.conflictFiles));
  assert.strictEqual(fs.readFileSync(path.join(work, RT), 'utf8'), localText);
  fs.rmSync(path.join(work, '.git', 'index.lock'));
  // 실패 경로는 busy 를 잡지 않으므로 바로 다음 시도가 성공해야 한다.
  const ctx2 = tm.prepareTaskBranch('t5', work);
  assert.strictEqual(ctx2.ok, true, ctx2.error);
  finish(ctx2, work);
});

test('parseConflictFiles: git stderr 의 들여쓴 경로 목록을 파싱', () => {
  const err = 'error: The following untracked working tree files would be overwritten by checkout:\n\t.agent/runtime/cost-usage.jsonl\n\tfoo/bar.txt\nPlease move or remove them before you switch branches.\nAborting\n';
  assert.deepStrictEqual(bc.parseConflictFiles(err), ['.agent/runtime/cost-usage.jsonl', 'foo/bar.txt']);
  assert.deepStrictEqual(bc.parseConflictFiles('fatal: something else'), []);
});

test('mergeLogLines / isMergeableLogPath', () => {
  assert.strictEqual(bc.mergeLogLines(lines('a', 'b'), lines('b', 'c', 'c', 'a')), lines('a', 'b', 'c'));
  assert.strictEqual(bc.mergeLogLines('', ''), '');
  assert.ok(bc.isMergeableLogPath('.agent/runtime/cost-usage.jsonl'));
  assert.ok(bc.isMergeableLogPath('.agent\\runtime\\x.log'));
  assert.ok(!bc.isMergeableLogPath('.agent/tasks/x.md'));
  assert.ok(!bc.isMergeableLogPath('docs/y.jsonl'));
});

test('decideBranchFailAction: 같은 원인이면 즉시 중단, 서명 없는 기존 상태는 기존 동작', () => {
  const f = { error: 'e', conflictFiles: ['b', 'a'] };
  const sig = bc.branchFailSignature(f);
  assert.strictEqual(sig, bc.branchFailSignature({ error: 'other text', conflictFiles: ['a', 'b'] })); // 파일 집합 기준
  assert.strictEqual(bc.decideBranchFailAction({}, f, 3).action, 'retry');
  assert.strictEqual(bc.decideBranchFailAction({ branchFailRetries: 1, lastBranchFailSig: sig }, f, 3).action, 'stop-same-cause');
  assert.strictEqual(bc.decideBranchFailAction({ branchFailRetries: 1, lastBranchFailSig: 'files:zzz' }, f, 3).action, 'retry');
  assert.strictEqual(bc.decideBranchFailAction({ branchFailRetries: 3 }, f, 3).action, 'exhausted'); // 하위호환
  // 충돌 파일이 없으면 오류 문자열(공백 정규화)로 비교
  const g = { error: '브랜치  생성 실패: x' };
  assert.strictEqual(bc.decideBranchFailAction({ lastBranchFailSig: bc.branchFailSignature({ error: '브랜치 생성 실패: x' }) }, g, 3).action, 'stop-same-cause');
});
