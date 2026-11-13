#!/usr/bin/env node
/**
 * test-queue-ops-exclude.mjs — `list-issues.js --queue` 의 자동 감지 [OPS] 이슈 제외 회귀 테스트 (giip 4907)
 *
 * 고정 대상 (두 층):
 *   ① 순수 규칙 — 제목 접두사 판정(isAutoDetectionOpsTitle).
 *      · 자동 감지 제목(`[OPS] gissue 처리 무소식 감지`) → 제외(true)
 *      · 제목에 "[OPS]" 가 **포함**된 후속 이슈 → 유지(false) — 접두사 전체 일치로 좁혔는지
 *      · 다른 [OPS] 운영 이슈 → 유지(false)
 *   ② 실제 경로 — API 전송 계층만 바꿔 `--queue` 와 `--status` 를 **둘 다 실제로 실행**해 비교한다.
 *      · `--queue`  → 자동 감지 이슈가 빠지고 일반 PENDING/READY 만 남는다
 *      · `--status` → 자동 감지 이슈가 **그대로 조회된다**(조회 계층 한정 — 회복 경로 생존)
 *
 * 왜 ②가 필요한가 — "제외가 들어갈 자리가 runQueue 안쪽뿐"을 소스 문자열로 눈으로 확인하는 것은
 *   증거가 아니다. 같은 API 응답을 두 경로에 넣고 **출력 차이**로 증명한다.
 *   (list-issues.js 는 https 전용 클라이언트라 로컬 http 서버를 쓸 수 없다 →
 *    `https.get` 만 테스트 안에서 갈아끼운다. 프로덕션 코드는 건드리지 않는다.)
 *
 * 실행: node scripts/gissue/tests/test-queue-ops-exclude.mjs
 *   (rule 42 — 게이트(run-repo-gates.ps1)는 이 파일을 node 로 직접 돌려 종료코드를 본다)
 */
import { createRequire } from 'node:module';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const https = require('https');

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..', '..');
const SCRIPT = path.join(REPO_ROOT, 'scripts', 'gissue', 'list-issues.js');

// 픽스처 CSN — 실제 고객/프로젝트 CSN 이 아닌 가짜 값(rule 54).
const FAKE_CSN = 9999;
const OPS_TITLE = '[OPS] gissue 처리 무소식 감지';

// ── ① 순수 규칙: 제목 접두사 판정 ───────────────────────────────────────────
{
  const { isAutoDetectionOpsTitle, AUTO_OPS_TITLE_PREFIX } = require(SCRIPT);

  assert.strictEqual(AUTO_OPS_TITLE_PREFIX, OPS_TITLE, '상수 값이 정본 감지 제목과 동일하다');
  assert.ok(isAutoDetectionOpsTitle(OPS_TITLE), '자동 감지 제목은 제외된다');
  assert.ok(isAutoDetectionOpsTitle(`  ${OPS_TITLE}  `), '앞뒤 공백은 무시하고 제외된다');
  assert.ok(isAutoDetectionOpsTitle(`${OPS_TITLE} [긴급]`), '뒤에 덧붙인 말은 같은 제목으로 보고 제외된다');

  // 일반 작업 이슈는 남아야 한다.
  assert.ok(!isAutoDetectionOpsTitle('[후속] [큐 오염] 무소식 감지 [OPS] 이슈가 작업 큐에 남는다 — list-issues.js --queue 에서 자동 감지 이슈 제외'),
    '제목에 "[OPS]" 가 포함된 후속 이슈는 제외하지 않는다(접두사 전체 일치)');
  assert.ok(!isAutoDetectionOpsTitle('[OPS] csn 9999 담당 배포 없음'), '다른 [OPS] 운영 이슈는 제외하지 않는다');
  assert.ok(!isAutoDetectionOpsTitle('[OPSX] gissue 처리 무소식 감지'), '한 글자 다른 제목은 제외하지 않는다');
  assert.ok(!isAutoDetectionOpsTitle('gissue 처리 무소식 감지'), '앞부분만 같은 제목은 제외하지 않는다');
  assert.ok(!isAutoDetectionOpsTitle(''), '빈 제목은 제외하지 않는다');
  assert.ok(!isAutoDetectionOpsTitle(null), 'null 제목은 제외하지 않는다');
  assert.ok(!isAutoDetectionOpsTitle(undefined), 'undefined 제목은 제외하지 않는다');
}

// ── ①-2 커플링: 정본 생성처(check-gissue-liveness.ps1 의 $title)와 동일해야 한다 ──
// 한쪽만 고치면 큐 제외가 조용히 깨진다(감지 이슈가 다시 큐에 걸린다) — 문자열 일치를 고정한다.
{
  const livenessPs = fs.readFileSync(path.join(REPO_ROOT, 'scripts', 'gissue', 'check-gissue-liveness.ps1'), 'utf8');
  const titleMatch = livenessPs.match(/\$title\s*=\s*'([^']+)'/);
  assert.ok(titleMatch, 'check-gissue-liveness.ps1 에 $title 정의를 찾았다');
  assert.strictEqual(titleMatch[1], OPS_TITLE,
    'list-issues.js 의 AUTO_OPS_TITLE_PREFIX 와 check-gissue-liveness.ps1 의 $title 이 동일하다');
}

// ── ② 실제 경로: --queue vs --status ────────────────────────────────────────
const OLD_ISO = new Date(Date.now() - 3 * 3600 * 1000).toISOString(); // READY 진입용(경과 60분 초과)

const ROWS_BY_STATUS = {
  PENDING: [
    { isn: 9001, title: OPS_TITLE, cSn: FAKE_CSN, regdate: OLD_ISO },                                     // 자동 감지 → 제외되어야 함
    { isn: 9002, title: '[후속] [큐 오염] 무소식 감지 [OPS] 이슈가 작업 큐에 남는다', cSn: FAKE_CSN, regdate: OLD_ISO }, // 일반 → 남아야 함
  ],
  READY: [
    { isn: 9003, title: OPS_TITLE, cSn: FAKE_CSN, regdate: OLD_ISO },                                     // 자동 감지 → 제외되어야 함
    { isn: 9004, title: '[OPS] csn 9999 담당 배포 없음', cSn: FAKE_CSN, regdate: OLD_ISO },                 // 일반 → 남아야 함
  ],
  IN_PROGRESS: [],
  REVIEW: [],
  TESTED: [],
};

/** https.get 을 가짜로 갈아끼운다 — API 응답만 흉내 내고 네트워크는 쓰지 않는다. */
function stubHttpsGet() {
  const original = https.get;
  https.get = function (url, options, cb) {
    const u = new URL(url);
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.end = () => {};
    process.nextTick(() => {
      let payload = {};
      if (u.pathname === '/api/giipIssues') {
        const status = u.searchParams.get('status') || '';
        payload = { success: true, issues: ROWS_BY_STATUS[status] || [] };
      } else if (u.pathname === '/api/giipIssueComments') {
        payload = { success: true, comments: [] };
      }
      const res = new EventEmitter();
      res.statusCode = 200;
      cb(res);
      res.emit('data', Buffer.from(JSON.stringify(payload), 'utf8'));
      res.emit('end');
    });
    return req;
  };
  return () => { https.get = original; };
}

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'queue-ops-exclude-'));
const accountsFile = path.join(tmpDir, 'giip-accounts.json');
fs.writeFileSync(accountsFile, JSON.stringify({
  channels: { test: { csn: FAKE_CSN, sk: 'sk-test-only' } },
  default: { csn: FAKE_CSN, sk: 'sk-test-only' },
}), 'utf8');

/** 인자를 바꿔 list-issues.js 를 다시 로드한다(모듈이 argv 를 로드 시점에 읽으므로 캐시를 비운다). */
function loadWithArgv(argv) {
  delete require.cache[require.resolve(SCRIPT)];
  process.argv = [process.argv[0], SCRIPT, ...argv];
  return require(SCRIPT);
}

/** main() 의 stdout(JSON)을 캡처한다. */
async function runMain(argv) {
  const mod = loadWithArgv(argv);
  const orig = console.log;
  const lines = [];
  console.log = (...a) => lines.push(a.join(' '));
  try {
    await mod.main();
  } finally {
    console.log = orig;
  }
  return JSON.parse(lines.join('\n').trim());
}

const restoreHttps = stubHttpsGet();
try {
  const common = ['--csn', String(FAKE_CSN), '--json', '--accounts-file', accountsFile];

  // --queue : 자동 감지 이슈는 빠지고 일반 PENDING/READY 만 남는다.
  const queue = await runMain([...common, '--queue']);
  const queueIsns = queue.map((r) => r.isn).sort((a, b) => a - b);
  assert.deepStrictEqual(queueIsns, [9002, 9004],
    `--queue 에서 자동 감지 이슈가 빠지고 일반 PENDING/READY 만 남는다 (실제: ${JSON.stringify(queueIsns)})`);
  assert.ok(!queue.some((r) => String(r.title).startsWith(OPS_TITLE)), '--queue 결과에 자동 감지 제목이 없다');

  // --status : 자동 감지 이슈가 **그대로 조회된다**(조회 계층 한정 — 회복 경로가 살아 있어야 한다).
  const statusRows = await runMain([...common, '--status', 'PENDING,READY']);
  const statusIsns = statusRows.map((r) => r.isn).sort((a, b) => a - b);
  assert.deepStrictEqual(statusIsns, [9001, 9002, 9003, 9004],
    `--status 직접 조회는 자동 감지 이슈를 그대로 돌려준다 (실제: ${JSON.stringify(statusIsns)})`);
} finally {
  restoreHttps();
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

console.log('ALL PASS (test-queue-ops-exclude.mjs)');
