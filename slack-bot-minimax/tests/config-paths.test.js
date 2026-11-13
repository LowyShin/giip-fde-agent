// node --test slack-bot-minimax/tests/config-paths.test.js
//
// giip 5174 회귀 테스트 — slack-bot-minimax/config.js 의 경로 해석 규칙을 고정한다.
//
// 왜 이 테스트가 필요한가:
//   config.js 에 드라이브 루트 아래 사용자 계정 폴더(= 사용자 홈 절대경로)와 특정 프로젝트
//   폴더명을 하드코딩하면, 봇을 어디서 기동하든 그 경로(= 이 PC 에만 있는 경로)를 그대로
//   써버린다. giip 5174 에서 실제로 그렇게 되어 있었고, 수정 후에는 다음 규칙이 보장되어야 한다.
//     1) JS 소스에 사용자 홈 절대경로·프로젝트 폴더명 리터럴이 없다.
//     2) BASE_DIR = 봇 폴더의 상위, PROJECTS_ROOT = 그 상위 (기동 위치 기준).
//     3) WORKSPACE_DIR / PROJECTS_ROOT 환경변수로 재정의된다.
//
// 검증 방식: 진짜 임시 디렉터리 구조(<tmp>/projects/<ws>/slack-bot-minimax/config.js)를 만들고
// 그 위치에서 봇을 "기동"한 것과 같은 조건으로 경로 해석 결과를 관찰한다.
// (require 캐시가 아니라 새 기동을 보려면 서브프로세스로 띄운다.)

const { test, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const BOT_DIR = path.join(__dirname, '..');
const CONFIG_SRC = path.join(BOT_DIR, 'config.js');

const tempDirs = [];

after(() => {
  for (const d of tempDirs) {
    try { fs.rmSync(d, { recursive: true, force: true }); } catch {}
  }
});

// 임시 디렉터리 구조를 만들고, 그 안에 봇 폴더(= config.js 위치)를 둔다.
function makeTempTree() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'slackbot-minimax-paths-'));
  tempDirs.push(tmp);
  const projectsRoot = path.join(tmp, 'projects');
  const workspace = path.join(projectsRoot, 'demo-workspace');
  const botDir = path.join(workspace, 'slack-bot-minimax');
  fs.mkdirSync(botDir, { recursive: true });
  fs.copyFileSync(CONFIG_SRC, path.join(botDir, 'config.js'));
  return { tmp, projectsRoot, workspace, botDir };
}

// 봇을 기동한 것과 같은 조건(= 그 위치의 config.js 를 로드)으로 해석 결과를 관찰한다.
function resolvePaths(botDir, env = {}) {
  const script =
    `const c = require(${JSON.stringify(path.join(botDir, 'config.js'))});` +
    `process.stdout.write(JSON.stringify({` +
    `BASE_DIR: c.BASE_DIR, PROJECTS_ROOT: c.PROJECTS_ROOT, AGENT_DIR: c.AGENT_DIR}));`;
  const out = execFileSync(process.execPath, ['-e', script], {
    encoding: 'utf8',
    env: { ...process.env, WORKSPACE_DIR: '', PROJECTS_ROOT: '', ...env },
  });
  return JSON.parse(out);
}

test('환경변수가 없으면 BASE_DIR/PROJECTS_ROOT 는 봇 폴더의 기동 위치 기준으로 결정된다', () => {
  const t = makeTempTree();
  const r = resolvePaths(t.botDir);
  assert.strictEqual(r.BASE_DIR, t.workspace, 'BASE_DIR 은 봇 폴더(slack-bot-minimax)의 상위여야 한다');
  assert.strictEqual(r.PROJECTS_ROOT, t.projectsRoot, 'PROJECTS_ROOT 은 BASE_DIR 의 상위여야 한다');
  assert.strictEqual(r.AGENT_DIR, path.join(t.workspace, '.agent'), 'AGENT_DIR 은 BASE_DIR/.agent 여야 한다');
});

test('WORKSPACE_DIR 로 기본 작업 폴더를 재정의하면 PROJECTS_ROOT 도 그 상위로 따라간다', () => {
  const t = makeTempTree();
  const ws = path.join(t.tmp, 'elsewhere', 'my-workspace');
  fs.mkdirSync(ws, { recursive: true });
  const r = resolvePaths(t.botDir, { WORKSPACE_DIR: ws });
  assert.strictEqual(r.BASE_DIR, ws, 'BASE_DIR 은 WORKSPACE_DIR 이어야 한다');
  assert.strictEqual(r.PROJECTS_ROOT, path.dirname(ws), 'PROJECTS_ROOT 은 WORKSPACE_DIR 의 상위여야 한다');
});

test('PROJECTS_ROOT 로 프로젝트 루트를 재정의할 수 있다', () => {
  const t = makeTempTree();
  const pr = path.join(t.tmp, 'elsewhere', 'my-projects');
  fs.mkdirSync(pr, { recursive: true });
  const r = resolvePaths(t.botDir, { PROJECTS_ROOT: pr });
  assert.strictEqual(r.PROJECTS_ROOT, pr, 'PROJECTS_ROOT 은 지정값이어야 한다');
  assert.strictEqual(r.BASE_DIR, t.workspace, 'PROJECTS_ROOT 만 주면 BASE_DIR 은 기동 위치 기준을 유지한다');
});

// giip 5174 의 원인이 되었던 형태 — 소스에 박힌 사용자 홈 절대경로·프로젝트 루트 리터럴.
const HARD_CODED_PATH_PATTERNS = [
  { name: 'Windows 사용자 홈 경로', re: /[A-Za-z]:[\\/]+Users[\\/]+/i },
  { name: 'macOS 사용자 홈 경로', re: /\/Users\/[A-Za-z0-9._-]+/ },
  { name: 'Linux 사용자 홈 경로', re: /\/home\/[A-Za-z0-9._-]+/ },
  { name: '프로젝트 루트 절대경로', re: /[A-Za-z]:[\\/]+[^'"\n]*[\\/]+projects[\\/]+[A-Za-z0-9._-]+/i },
];

function collectJsFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    // node_modules/.git 는 제외. tests/ 는 "예시 경로를 적어둔 픽스처"를 허용하는 영역이라
    // 검사 대상에서 뺀다 (이 테스트 파일 자신의 주석이 오탐으로 잡히지 않도록).
    if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'tests') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectJsFiles(full, out);
    else if (entry.name.endsWith('.js')) out.push(full);
  }
  return out;
}

test('JS 소스에 사용자 홈 절대경로·프로젝트 폴더명 하드코딩이 없다', () => {
  const files = collectJsFiles(BOT_DIR);
  assert.ok(files.length > 0, '검사 대상 JS 파일이 0건 — 검사기가 아무것도 검사하지 않았다');
  const offenders = [];
  for (const file of files) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      for (const { name, re } of HARD_CODED_PATH_PATTERNS) {
        if (re.test(line)) {
          offenders.push(`${path.relative(BOT_DIR, file)}:${i + 1} [${name}] ${line.trim()}`);
        }
      }
    });
  }
  assert.deepStrictEqual(offenders, [], `하드코딩된 사용자 경로 발견:\n${offenders.join('\n')}`);
});
