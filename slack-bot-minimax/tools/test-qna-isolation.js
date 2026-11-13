// giip 5144(원본 giip 4902): Q&A 프로젝트 격리 회귀 테스트 (실제 Slack·claude·push·gh 호출 없음).
// task-manager.js 의 BASE_DIR 은 __dirname/.. 이라 가짜 PROJECTS_ROOT 를 쓰려면 봇 디렉터리를
// 임시 루트 아래 <base>/<봇 디렉터리명> 으로 복사해서 로드한다(고객·환경 고유 이름 없음).
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const srcDir = path.join(__dirname, '..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'qna-iso-'));
const A = path.join(root, 'base-project'); // 질문의 프로젝트(= task-manager 의 BASE_DIR)
const B = path.join(root, 'sibling-project'); // 형제 프로젝트(다른 세션이 작업 중)
const git = (cwd, ...a) => {
  const r = spawnSync('git', a, { cwd, encoding: 'utf8', env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' } });
  assert.strictEqual(r.status, 0, `git ${a.join(' ')}: ${r.stderr}`);
  return r.stdout;
};
for (const d of [A, B]) {
  fs.mkdirSync(d, { recursive: true });
  git(d, 'init', '-q', '-b', 'main');
  fs.writeFileSync(path.join(d, 'README.md'), 'x\n');
  git(d, 'add', '.');
  git(d, 'commit', '-q', '-m', 'init');
}
const botDir = path.join(A, path.basename(srcDir));
fs.mkdirSync(botDir);
for (const f of fs.readdirSync(srcDir)) if (/\.(js|json)$/.test(f)) fs.copyFileSync(path.join(srcDir, f), path.join(botDir, f));
const tm = require(path.join(botDir, 'task-manager.js'));
const norm = p => path.resolve(p).toLowerCase();
const rootsOf = (m) => [...m.values()].map(norm);

// (a) 후보 범위
const iso = rootsOf(tm.candidateRepoRoots(A, { siblings: false }));
assert.ok(iso.includes(norm(A)), 'A 포함');
assert.ok(!iso.includes(norm(B)), '(a) siblings:false 는 형제 B 를 포함하면 안 됨');
const def = rootsOf(tm.candidateRepoRoots(A));
assert.ok(def.includes(norm(B)), '(a) 기본(siblings:true)은 형제 B 포함(태스크 경로 불변)');
console.log('PASS (a) 후보 범위: siblings:false 는 B 제외, 기본은 B 포함');

// (b) Q&A 스냅샷 이후 B 의 변경은 Q&A 결과에 나타나지 않는다
const snaps = tm.snapshotCandidateRepos(A, { siblings: false });
assert.ok(!snaps.some(s => norm(s.root) === norm(B)));
fs.mkdirSync(path.join(B, 'backend'));
fs.writeFileSync(path.join(B, 'backend', 'other-session.sql'), 'select 1;\n'); // 다른 세션 산출물
const res = tm.commitAndPRChangedRepos('qna-test', 'q', snaps, { projectName: path.basename(A) });
assert.deepStrictEqual([res.prs || [], res.skipped || [], res.blocked || []].map(x => x.length), [0, 0, 0], '(b) PR/skip/blocked 없어야 함');
assert.strictEqual(git(B, 'rev-parse', '--abbrev-ref', 'HEAD').trim(), 'main', 'B 브랜치 불변');
assert.ok(git(B, 'status', '--porcelain').includes('backend/'), 'B 변경은 미커밋 그대로');
assert.strictEqual(git(B, 'branch', '--list', 'bot/*').trim(), '', 'B 에 bot/* 브랜치 없음');
console.log('PASS (b) 형제 B 변경은 Q&A 안전망이 건드리지 않음');

// (c) 대화 키 프로젝트별 분리 (복사본의 handlers/config 로 검증 — BASE_DIR 이름이 환경마다 달라도 동작)
const h = require(path.join(botDir, 'handlers.js'));
const baseName = path.basename(require(path.join(botDir, 'config.js')).BASE_DIR);
const k1 = h.convHistoryKey('D1', 'project-x'), k2 = h.convHistoryKey('D1', 'project-y'), k3 = h.convHistoryKey('D1', baseName);
assert.notStrictEqual(k1, k2);
assert.notStrictEqual(k1, k3);
assert.strictEqual(k3, 'D1', '기본 프로젝트는 기존 키 유지');
console.log('PASS (c) 대화 키 분리:', k1, k2, k3);

// (d) add-dir 롤백 스위치
const { qnaAllProjects } = require(path.join(botDir, 'claude-cli.js'));
assert.strictEqual(qnaAllProjects({}), false);
assert.strictEqual(qnaAllProjects({ SLACKBOT_QNA_ALL_PROJECTS: '1' }), true);
console.log('PASS (d) SLACKBOT_QNA_ALL_PROJECTS 기본 off / =1 on');

try { fs.rmSync(root, { recursive: true, force: true }); } catch { /* 임시 폴더 정리 실패는 무시 */ }
