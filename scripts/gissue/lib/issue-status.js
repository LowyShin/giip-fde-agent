#!/usr/bin/env node
/**
 * issue-status.js — giip issue 1건의 상태를 조회해 "worktree 삭제 가능 여부" 판정 재료를 1줄 JSON 으로 낸다.
 *
 * 왜 필요한가 (giip #6603 / #6724 — cleanup-worktrees.ps1 -OrphanScan idle 가드 결함):
 *   자동 정리 도구가 "연결된 이슈가 DONE 이어야 삭제" 라는 최종 조건(rule 47)을 검사하려면
 *   이슈 상태를 조회할 수단이 있어야 한다. 이 레포는 DB 직접 접근이 없고 giipfaw API
 *   (x-api-key 인증)만 쓰므로, lib/check-csn.js 가 이미 쓰는 `GET {apiBase}/giipIssues?isn=<isn>`
 *   패턴을 그대로 재사용한다.
 *
 * ★ "이슈 부재(absent)" 와 "권한 없음(no permission)" 은 API 응답으로 **구분되지 않는다**
 *   (둘 다 404 + error_code=ISSUE_NOT_FOUND_OR_NO_PERMISSION 로 돌아온다). 그래서 이 헬퍼는
 *   `absent` 를 별도 판정으로 만들지 않는다 — 판정은 Done | Open | Unknown 3종뿐이고,
 *   **삭제 허용은 Done 이 명시적으로 확인된 경우에만** 성립한다(rule 47 fail-closed).
 *
 * 사용: node issue-status.js <isn> <csn>
 *   <isn> — 조회할 giip issue 번호
 *   <csn> — **SK 선택용** CSN. 조회 대상 CSN 은 이슈 자체의 cSn 을 따른다
 *           (get-issue.sh 헤더 명세와 동일 — CSN 70424 의 SK 로 다른 CSN 이슈를 정상 조회한다).
 * stdout: 판정 결과 1줄 JSON
 *   {"isn":6442,"found":true,"status":"READY","verdict":"Open","detail":"..."}
 *   verdict ∈ Done | Open | Unknown
 * stderr: 진단 메시지 (**SK 는 절대 포함하지 않는다**).
 * 종료코드: 0 = 판정 결과 JSON 을 냈다 / 2 = 사용법 오류.
 *
 * SK 노출 금지: SK 는 resolve-sk.js 로 해석해 요청 헤더에만 넣고, 어떤 출력·메시지에도 남기지 않는다.
 */
const https = require('https');
const path = require('path');
const { URL } = require('url');
const { execFileSync } = require('child_process');

const API_BASE = process.env.GIIP_API_BASE || 'https://giipfaw.azurewebsites.net/api';
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const ACCOUNTS_FILE = process.env.GIIP_ACCOUNTS_FILE
  || path.join(REPO_ROOT, 'slack-bot', '.secrets', 'giip-accounts.json');
const RESOLVE_SK = path.join(__dirname, 'resolve-sk.js');

const [, , isnArg, csnArg] = process.argv;
if (!isnArg || !csnArg) {
  console.error('사용법: node issue-status.js <isn> <csn>');
  process.exit(2);
}
const isn = String(isnArg).trim();
const csn = String(csnArg).trim();

function emit(verdict, found, status, detail) {
  process.stdout.write(`${JSON.stringify({
    isn: Number(isn),
    found: Boolean(found),
    status: status || null,
    verdict,
    detail: detail || '',
  })}\n`);
}

/** SK 해석 — 실패하면 null. SK 값 자체는 어떤 메시지에도 넣지 않는다. */
function resolveSk() {
  try {
    const out = execFileSync(process.execPath, [RESOLVE_SK, ACCOUNTS_FILE, csn], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const sk = String(out || '').trim();
    return sk || null;
  } catch (e) {
    return null;
  }
}

const sk = resolveSk();
if (!sk) {
  emit('Unknown', false, null, `CSN ${csn} 용 SK 해석 실패 — 조회하지 못함(삭제 허용 근거 없음)`);
  process.exit(0);
}

const u = new URL(`${API_BASE}/giipIssues?isn=${encodeURIComponent(isn)}`);
const req = https.get(u, { headers: { 'x-api-key': sk } }, (res) => {
  let data = '';
  res.on('data', (c) => { data += c; });
  res.on('end', () => {
    let j = null;
    try { j = JSON.parse(data); } catch (e) { j = null; }
    if (!j) {
      emit('Unknown', false, null, `응답 JSON 파싱 실패(HTTP ${res.statusCode}) — 조회하지 못함`);
      process.exit(0);
    }
    const issue = j.issue || (j.success === false ? null : j);
    const status = issue && issue.status ? String(issue.status) : null;
    if (status) {
      // DONE 이 **명시적으로** 확인된 경우만 삭제 허용(Done). 나머지는 모두 삭제 불가.
      emit(status === 'DONE' ? 'Done' : 'Open', true, status, `이슈 상태=${status}`);
      process.exit(0);
    }
    const errCode = j.error_code ? String(j.error_code) : '';
    if (errCode === 'ISSUE_NOT_FOUND_OR_NO_PERMISSION' || res.statusCode === 404) {
      // "없음" 과 "권한없음" 이 응답으로 구분되지 않는다 → Unknown(fail-closed).
      emit('Unknown', false, null, `이슈 상태 미확인(error_code=${errCode || '없음'}, HTTP ${res.statusCode}) — 부재와 권한없음이 구분되지 않아 삭제 허용 근거로 쓰지 않음`);
      process.exit(0);
    }
    emit('Unknown', false, null, `이슈 조회 실패(error_code=${errCode || '없음'}, HTTP ${res.statusCode}) — 조회하지 못함`);
    process.exit(0);
  });
});
req.on('error', (e) => {
  emit('Unknown', false, null, `이슈 조회 네트워크 오류(${e.message}) — 조회하지 못함`);
  process.exit(0);
});
req.setTimeout(30000, () => req.destroy(new Error('timeout')));
