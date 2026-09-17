#!/usr/bin/env node
/*
 * verify-runner.mjs — giip issue 의 "기계 실행 가능한 완료조건"을 실제로 실행해 통과 여부를 판정한다.
 *
 * 배경(2026-09-14, 사용자 지시): "난 단지 불편함을 던지면 개선하고 내 불편함이 진짜로 덜어졌는지를
 * 네가 확인하도록 시스템을 만들어줘." 지금까지 완료 판정은 (a) PR 머지 여부, (b) 자연어 완료조건에
 * 대한 LLM 자기보고에 의존했고, 그 결과 giip #2393/#2395 처럼 프론트 PR 은 머지됐지만 SP 미배포로
 * 화면이 죽어 있는 상태를 "정상 진행 중"이라고 보고하는 사고가 났다(k-layer KNOW-021).
 *
 * 해결: 이슈 본문/코멘트에 ```verify 코드블록으로 **재현 가능한 검증 명령**을 적어두면, 이 러너가
 * 그 명령을 실제로 실행하고 exit code 로 PASS/FAIL 을 판정한다. 판정 근거(명령·exit·출력 발췌)를
 * 그대로 이슈 코멘트에 남기므로, 자기보고가 아니라 실행 결과가 증거가 된다.
 *
 * 사용:
 *   node scripts/gissue/verify-runner.mjs <isn> [csn] [--comment] [--json]
 *     --comment : 판정 결과를 이슈 코멘트로 등록한다(기본은 콘솔 출력만)
 *     --json    : 결과를 JSON 으로 출력(스케줄러 연동용)
 *
 * 종료코드: 0=PASS, 1=FAIL, 2=verify 블록 없음, 3=조회 실패
 *
 * ── 종료 규약(giip #2586, 2026-09-16) ────────────────────────────────────────────
 * **`process.exit(n)` 을 즉시 호출하지 않는다.** 이 러너는 `await fetch()`(undici) 로 이슈를
 * 조회하는데, 그 응답 소켓이 닫히는 중에 `process.exit()` 가 불리면 Windows/Node v24.13.0 에서
 * libuv 가 abort 한다:
 *
 *     Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 76
 *
 * abort 되면 종료코드가 의도한 0/1/2/3 이 아니라 **127** 이 되고, 이 러너를 게이트로 쓰는
 * `review-done-audit.ps1` 의 VERIFY-GATE 가 "실행 오류 → 기존 판정 유지"(fail-open)로 빠진다.
 * 실제로 2026-09-16 전수 진단에서 PASS→DONE 예정 10건 전부가 이 경로로 검증 없이 통과했다.
 *
 * 그래서 모든 종료 경로는 (a) `main()` 이 종료코드를 **return** 하고(깊은 곳에서는 `ExitRequest`
 * 를 throw), (b) 진입점이 그 값을 `process.exitCode` 에만 넣은 뒤, (c) 이벤트 루프가 자연
 * 종료하게 둔다. 자연 종료가 undici keep-alive 소켓 때문에 지연되지 않도록 진입점이
 * `closeHttpPool()` 로 전역 디스패처를 먼저 닫는다.
 * ────────────────────────────────────────────────────────────────────────────────
 *
 * verify 블록 형식(이슈 본문 또는 아무 코멘트에나 넣으면 된다):
 *   ```verify
 *   curl -sf https://example.com/health
 *   node -e "process.exit(0)"
 *   ```
 *   ```verify:pwsh
 *   if ((Get-Content x.json | Measure-Object -Line).Lines -lt 1) { exit 1 }
 *   ```
 *   - 한 줄 = 한 명령. 빈 줄과 `#` 주석은 무시한다.
 *   - 모든 명령이 exit 0 이어야 PASS. 하나라도 실패하면 FAIL 이고, 실패 지점에서 멈추지 않고
 *     나머지도 전부 실행한다(부분 성공/실패를 한 번에 보기 위함).
 *   - 태그: `verify`(기본, bash) / `verify:bash` / `verify:pwsh`(PowerShell)
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const API_BASE = 'https://giipfaw.azurewebsites.net/api';
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..', '..');
/**
 * SK 저장소 위치. 워크트리에서 실행되면 `.secrets/`(git 비추적)가 없으므로 메인 체크아웃으로 폴백한다.
 * 우선순위: 환경변수 → 현재 레포 루트 → git common dir 의 부모(= 메인 체크아웃 루트).
 */
function resolveAccountsFile() {
  const candidates = [];
  if (process.env.GIIP_ACCOUNTS_FILE) candidates.push(process.env.GIIP_ACCOUNTS_FILE);
  candidates.push(path.join(REPO_ROOT, 'slack-bot', '.secrets', 'giip-accounts.json'));
  try {
    const commonDir = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
    }).trim();
    candidates.push(path.join(path.dirname(commonDir), 'slack-bot', '.secrets', 'giip-accounts.json'));
  } catch {
    /* git 조회 실패는 무시 — 아래 후보로 계속 */
  }
  return candidates.find((p) => p && fs.existsSync(p)) || candidates[candidates.length - 1];
}
const ACCOUNTS = resolveAccountsFile();
const MAX_OUTPUT = 1200; // 코멘트에 넣을 명령별 출력 상한
const CMD_TIMEOUT_MS = 5 * 60 * 1000;

/**
 * 종료 요청 신호(giip #2586). `process.exit()` 를 즉시 호출하면 undici 핸들이 닫히는 중에
 * libuv assertion 으로 abort 되어 종료코드가 127 로 뭉개진다(파일 상단 "종료 규약" 참조).
 * 그래서 깊은 호출부에서도 exit 대신 이 예외를 던지고, 진입점이 받아 `process.exitCode` 로 옮긴다.
 */
class ExitRequest extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.name = 'ExitRequest';
    this.code = code;
  }
}

function usage(msg) {
  if (msg) console.error(`error: ${msg}`);
  console.error('usage: node verify-runner.mjs <isn> [csn] [--comment] [--json]');
  throw new ExitRequest(3);
}

const args = process.argv.slice(2);
const isn = args.find((a) => /^\d+$/.test(a));
const csn = args.filter((a) => /^\d+$/.test(a))[1] || '';
const doComment = args.includes('--comment');
const asJson = args.includes('--json');

function resolveSk() {
  if (!fs.existsSync(ACCOUNTS)) usage(`계정 파일 없음: ${ACCOUNTS}`);
  const out = execFileSync(
    process.execPath,
    [path.join(SCRIPT_DIR, 'lib', 'resolve-sk.js'), ACCOUNTS, csn || 'null'],
    { encoding: 'utf8' }
  );
  return out.trim();
}

async function getJson(url, sk) {
  const res = await fetch(url, { headers: { 'x-api-key': sk } });
  if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
  return res.json();
}

/** 본문+코멘트 전체에서 ```verify[:lang] 블록을 모아 명령 목록으로 만든다. */
function extractVerifyBlocks(texts) {
  const blocks = [];
  const re = /```verify(?::(bash|pwsh|powershell))?\r?\n([\s\S]*?)```/g;
  for (const { source, text } of texts) {
    if (!text) continue;
    let m;
    while ((m = re.exec(text)) !== null) {
      const lang = (m[1] || 'bash').replace('powershell', 'pwsh');
      const cmds = m[2]
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith('#'));
      if (cmds.length) blocks.push({ source, lang, cmds });
    }
  }
  return blocks;
}

/**
 * 블록 하나를 **스크립트 통째로** 실행한다(줄 단위 아님 — 변수/cd 같은 상태가 줄 사이에 유지되어야
 * PowerShell 다단계 검증을 쓸 수 있다. 2026-09-14 giip #2418 실측으로 드러난 설계 결함 수정).
 * bash 는 `set -euo pipefail` 로 감싸 중간 실패가 묻히지 않게 한다.
 *
 * ── 인코딩 처리 (giip #2589, 2026-09-16) ───────────────────────────────────────
 * Windows PowerShell 5.1 은 리다이렉트된 stdout 에 콘솔 코드페이지(cp949 계열)로 쓴다.
 * Node.js spawnSync 의 `encoding: 'utf8'` 은 이를 UTF-8 로 디코드하려 하지만 cp949 바이트를
 * UTF-8 으로 해석하면 한글은 전부 `?` 로 깨진다.
 *
 * 실측 결과(2026-09-16):
 *   - encoding='utf8' 만: qCount=7 (한글 7글자가 전부 ?로 대체)
 *   - [Console]::OutputEncoding=[Text.Encoding]::UTF8; prefix 추가: qCount=0 (정상 보존)
 *   - bash: UTF-8 정상 (bash는 locale 설정대로 UTF-8 사용)
 *
 * 그래서 PowerShell 스크립트 앞에 해당 prefix 를 삽입해 자식이 UTF-8 로 출력하게 만든다.
 * bash는 영향 없으므로 별도 처리 없음.
 * ───────────────────────────────────────────────────────────────────────────────
 */
function runBlock(lang, cmds) {
  const started = Date.now();
  const script = cmds.join('\n');
  const pwshPrefix = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; ';
  const cmd = lang === 'pwsh' ? `${pwshPrefix}${script}` : `set -euo pipefail\n${script}`;
  const r =
    lang === 'pwsh'
      ? spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', cmd], {
          encoding: 'utf8',
          timeout: CMD_TIMEOUT_MS,
          cwd: REPO_ROOT,
        })
      : spawnSync('bash', ['-c', cmd], {
          encoding: 'utf8',
          timeout: CMD_TIMEOUT_MS,
          cwd: REPO_ROOT,
        });
  const out = `${r.stdout || ''}${r.stderr || ''}`.trim();
  return {
    cmd: script,
    lang,
    exit: r.status === null ? 124 : r.status, // null = timeout/kill
    ms: Date.now() - started,
    output: out.length > MAX_OUTPUT ? `${out.slice(0, MAX_OUTPUT)}\n...(생략)` : out,
  };
}

function buildComment(results, pass) {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 16);
  const head =
    `[VERIFY-RUN] ${pass ? 'PASS' : 'FAIL'} — 완료조건 ${results.length}건 실제 실행\n` +
    `**행위자(Actor)**: verify-runner (dp01-console)\n` +
    `**시각(When)**: ${ts} UTC\n` +
    `**사유(Why)**: 자기보고가 아니라 실행 결과로 완료 여부를 판정(k-layer KNOW-021, CLAIM-2026-016)\n` +
    `**상태(Status)**: 판정만 수행 — 상태 전이는 호출자 몫\n` +
    `**역할(Role)**: .agent/rules/57_feature_done_verification.md\n\n`;
  const body = results
    .map((r, i) => {
      const mark = r.exit === 0 ? 'PASS' : 'FAIL';
      return (
        `### ${i + 1}. [${mark}] exit=${r.exit} (${r.ms}ms) · ${r.lang}\n` +
        '```\n' +
        `$ ${r.cmd}\n` +
        `${r.output || '(출력 없음)'}\n` +
        '```'
      );
    })
    .join('\n\n');
  const tail = pass
    ? '\n\n모든 검증 명령이 exit 0 으로 통과했다. 이 결과가 완료의 근거다.'
    : '\n\n**하나 이상 실패했다. 이 이슈는 완료가 아니다.** 위 실패 명령의 출력이 현재 상태다.';
  return head + body + tail;
}

/**
 * 판정 본체. 종료코드를 **return** 한다(0=PASS, 1=FAIL, 2=블록없음, 3=조회실패).
 * 여기서 `process.exit()` 를 부르면 상단 "종료 규약"의 libuv abort 가 재발한다 — 부르지 말 것.
 */
async function main() {
  if (!isn) usage('isn 이 필요합니다');

  const sk = resolveSk();
  let issue;
  let comments;
  try {
    const issueRes = await getJson(`${API_BASE}/giipIssues?isn=${isn}`, sk);
    issue = issueRes.issue || issueRes;
    const cmtRes = await getJson(`${API_BASE}/giipIssueComments?isn=${isn}`, sk);
    comments = cmtRes.comments || [];
  } catch (e) {
    console.error(`[ERROR] 이슈 조회 실패(isn=${isn}): ${e.message}`);
    return 3;
  }

  const texts = [
    { source: 'issue-body', text: issue?.content || '' },
    ...comments.map((c, i) => ({ source: `comment#${c.cSn ?? i}`, text: c.content || '' })),
  ];
  const blocks = extractVerifyBlocks(texts);

  if (blocks.length === 0) {
    const msg =
      `[VERIFY-RUN] SKIP — isn=${isn} 에 \`\`\`verify 블록이 없습니다. ` +
      '완료조건을 기계가 실행 가능한 형태로 적어야 이 러너가 검증할 수 있습니다(rule 57).';
    if (asJson) console.log(JSON.stringify({ isn: Number(isn), status: 'NO_VERIFY_BLOCK' }));
    else console.log(msg);
    return 2;
  }

  const results = blocks.map((b) => runBlock(b.lang, b.cmds));
  const pass = results.every((r) => r.exit === 0);

  if (asJson) {
    console.log(JSON.stringify({ isn: Number(isn), status: pass ? 'PASS' : 'FAIL', results }, null, 2));
  } else {
    for (const r of results) {
      console.log(`[${r.exit === 0 ? 'PASS' : 'FAIL'}] exit=${r.exit} (${r.ms}ms) $ ${r.cmd}`);
      if (r.output) console.log(r.output.split('\n').map((l) => `    ${l}`).join('\n'));
    }
    console.log(`\n=> ${pass ? 'PASS' : 'FAIL'} (${results.filter((r) => r.exit === 0).length}/${results.length})`);
  }

  if (doComment) {
    const tmp = path.join(process.env.TEMP || '/tmp', `verify_${isn}_${process.pid}.md`);
    fs.writeFileSync(tmp, buildComment(results, pass), 'utf8');
    // get-issue.sh 는 자기 위치 기준으로 SK 저장소를 찾는다. 워크트리에는 `.secrets/`(git 비추적)가
    // 없으므로, SK 를 실제로 가진 체크아웃의 get-issue.sh 를 쓴다(ACCOUNTS 경로에서 역산).
    const accountsRepoRoot = path.resolve(path.dirname(ACCOUNTS), '..', '..');
    const candidateGetIssue = path.join(accountsRepoRoot, 'scripts', 'gissue', 'get-issue.sh');
    const getIssue = fs.existsSync(candidateGetIssue)
      ? candidateGetIssue
      : path.join(SCRIPT_DIR, 'get-issue.sh');
    const r = spawnSync(
      'bash',
      [getIssue, String(isn), String(csn || ''), '--comment-file', tmp, '--role', 'verify-runner'].filter(Boolean),
      { encoding: 'utf8', cwd: REPO_ROOT }
    );
    process.stdout.write(r.stdout || '');
    if (r.status !== 0) console.error(`[WARN] 코멘트 등록 실패: ${r.stderr || ''}`);
    fs.unlinkSync(tmp);
  }

  return pass ? 0 : 1;
}

/**
 * undici 의 전역 디스패처(fetch 가 쓰는 커넥션 풀)를 닫는다.
 *
 * 왜 필요한가: `fetch()` 가 만든 keep-alive 소켓은 응답을 다 읽은 뒤에도 몇 초 동안 살아 있어
 * 이벤트 루프를 붙잡는다. `process.exit()` 를 못 쓰게 된 이상(상단 종료 규약) 이걸 닫지 않으면
 * 러너가 판정을 끝내고도 수 초 더 떠 있게 되고, 게이트 호출부(review-done-audit.ps1)가 그만큼
 * 느려진다. 공개 API 가 없어 undici 가 globalThis 에 박아두는 심볼로 접근하며, 심볼이 없거나
 * close() 가 없는 런타임에서는 **조용히 무시**한다(그래도 소켓 타임아웃으로 결국 종료된다).
 */
async function closeHttpPool() {
  try {
    const sym = Object.getOwnPropertySymbols(globalThis).find((s) =>
      String(s.description || '').startsWith('undici.globalDispatcher')
    );
    const dispatcher = sym ? globalThis[sym] : null;
    if (dispatcher && typeof dispatcher.close === 'function') await dispatcher.close();
  } catch {
    /* 정리 실패는 판정 결과에 영향을 주지 않는다 — 무시 */
  }
}

// ── 진입점 ──
// 종료코드는 오직 `process.exitCode` 로만 전달하고 이벤트 루프의 자연 종료를 기다린다(giip #2586).
let exitCode = 3;
try {
  exitCode = await main();
} catch (e) {
  if (e instanceof ExitRequest) {
    exitCode = e.code;
  } else {
    console.error(`[ERROR] 예기치 못한 오류: ${e && e.stack ? e.stack : e}`);
    exitCode = 3;
  }
}
await closeHttpPool();
process.exitCode = exitCode;
