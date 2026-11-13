#!/usr/bin/env node
///////////////////////////////////////////////////////////////////////////
// list-issues.js — CSN + status 로 giip issue 목록을 조회한다 (giipfaw API 경유,
// DB 직접접근 불필요). giipdb/mgmt/list*.ps1(csn47 giipprj 전용, DB-direct) 의
// 이식 가능한 대체품 — 이 레포(giip-fde-agent)를 그대로 복사해 쓰는 모든 배포
// 대상(csn-projects.json 에 자기 project/workdir 만 채운 곳)에서 동일하게 동작한다.
//
// SK 출처: get-issue.sh 와 동일 — <RepoRoot>/slack-bot/.secrets/giip-accounts.json
// (.channels[*].sk, csn 필드로 매칭. 없으면 .default 사용).
//
// "얼마나 오래 그 상태였는가"(-min-age-minutes)는 DB 타임스탬프가 없으므로,
// giip-api.js issueUpdate() 가 상태 전이마다 자동으로 남기는
//   "## [actor] ISN <isn> 状態遷移: OLD -> NEW" + "**日時(When)**: <ISO>"
// 코멘트를 giipIssueComments 에서 역순으로 찾아 "-> <현재상태>" 로 끝나는 가장
// 최근 전이 코멘트의 시각을 그 상태 진입 시각으로 추정한다. 매칭되는 전이 코멘트가
// 없으면(예: 생성 즉시 그 상태) age=null 로 두고 무조건 대상에 포함시킨다(누락 방지 우선).
//
// 사용:
//   node list-issues.js --csn <N> --status PENDING[,READY,IN_PROGRESS] [--min-age-minutes <N>] [--json]
//   node list-issues.js --csn <N> --status REVIEW --hours-back <N>   # [H] 최근 코멘트 재검증용
//   node list-issues.js --csn <N> --queue --json                     # 스케줄러 우선순위 큐(아래)
//
// 출력(기본): 한 줄에 하나, "isn=<n> status=<s> age=<분|?> title=<제목>"
// 출력(--json): [{isn, status, ageMinutes, title, cSn}, ...]
//   cSn = 응답이 실제로 돌려준 이슈의 csn(요청한 csn 이 아니다 — giip #4116).
//
// ── --queue 모드 (giip #2645) ────────────────────────────────────────────
// run-gissue-claude.ps1 의 Get-GissueIssueQueue 가 쓰는 "단일 우선순위 큐"를 돌려준다.
// lowyworkenv 운영 러너는 같은 큐를 giipdb 직접접속(execSQLFile.ps1 + 단일 T-SQL, giip
// #1472/#1560/#1564/#1651)으로 뽑지만, 이 레포에는 DB 직접접근이 없으므로 **같은 정렬
// 계약을 giipfaw API 로 재현**한다(혼용 금지 — docs/60-operations/hourly-issue-scheduler.md §4).
//
// 대상과 상태 라벨(SQL 의 UNION ALL 각 항과 1:1):
//   PENDING            : 전부(시간 조건 없음)
//   READY              : elapsed >= 60분
//   IN_PROGRESS        : elapsed >= 60분 → 라벨을 STALE_IN_PROGRESS 로 바꿔 반환
//   REVIEW / TESTED    : 최신 코멘트가 '[ACTIONFLOW-TEST]' 로 시작하지 않는 것만([G] dedup)
// elapsed 기준: 최신 코멘트 시각(없으면 이슈 등록일). 단 [USER-REQUEST] 코멘트가 있는 이슈는
//   등록일 기준(사용자 직접 요청이 봇 코멘트로 계속 젊어지지 않게 — SQL 의 is_user_req CASE 동일).
// 정렬: qprio(0=STALE_IN_PROGRESS, 1=PENDING, 2=READY, 3=REVIEW/TESTED — 재확인은 READY 실작업 이후)
//       → is_user_req DESC → has_comment ASC(코멘트 없는 신생 이슈 우선, giip #1651)
//       → elapsedMin DESC(가장 오래 정지/대기한 것 우선)
// 출력(--queue --json): [{isn, title, status, elapsedMin, lastAuthor, cSn}, ...]
//   (qprio/is_user_req/has_comment 는 정렬 전용이라 출력에 포함하지 않는다 — 호출부 계약 유지)
// 코멘트 조회 비용: 이슈 목록 API 가 last_comment_date/last_comment_author 를 이미 주므로
//   elapsed/lastAuthor/has_comment 는 추가 호출 없이 계산한다. 코멘트 본문이 실제로 필요한
//   경우(REVIEW/TESTED dedup, [USER-REQUEST] 판정)에만, 그리고 코멘트가 1건이라도 있는
//   이슈에 한해 giipIssueComments 를 1회 조회한다.
//
// ── 자동 감지(무소식) 이슈의 큐 제외 (giip #4907) ─────────────────────────
// `[OPS] gissue 처리 무소식 감지` 는 **자동 등록된 "감지 기록"** 이지 "작업"이 아니다.
//   기본 상태가 PENDING 이고 코멘트가 없으므로, 그 제목만으로 큐(PENDING 우선순위 1)에
//   걸려 러너 세션 1회분이 감지 건마다 소모된다(큐 오염).
// ⇒ **조회(큐) 계층에서만** 제외한다. 아래 경로들은 **의도적으로 영향받지 않는다**:
//   · `--status <S>` 직접 조회 — 감지 이슈를 직접 조회·정리하려면 필요
//   · check-gissue-liveness.ps1 → lib/liveness-ops-issue.js find() — 열린 감지 이슈를
//     찾아 회복 코멘트 후 DONE 으로 닫는 경로(여기가 막히면 무소식 에피소드가 영원히 안 끝난다)
// 제외 판정은 **제목 접두사** 기준이다 — 제목 문자열에 "[OPS]" 가 *포함*된 후속 이슈(예:
//   "[후속] [큐 오염] 무소식 감지 [OPS] 이슈가 …") 를 잘못 잡지 않도록 접두사 전체 일치로 좁힌다.
///////////////////////////////////////////////////////////////////////////
const https = require('https');
const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) { out[key] = true; }
      else { out[key] = next; i++; }
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const CSN = args.csn;
const API_BASE = args['api-base'] || 'https://giipfaw.azurewebsites.net/api';
const SCRIPT_DIR = __dirname;
const ACCOUNTS_FILE = args['accounts-file'] || path.join(SCRIPT_DIR, '..', '..', 'slack-bot', '.secrets', 'giip-accounts.json');
const STATUSES = String(args.status || '').split(',').map((s) => s.trim()).filter(Boolean);
const MIN_AGE_MIN = args['min-age-minutes'] ? Number(args['min-age-minutes']) : 0;
const HOURS_BACK = args['hours-back'] ? Number(args['hours-back']) : 0;
// --queue 전용(선택): >0 이면 REVIEW/TESTED 중 elapsed 가 이 값(분)을 넘은 것은 큐에서 뺀다. 미지정=제한 없음.
const REVIEW_TESTED_MAX_AGE_MIN = args['review-tested-max-age-minutes'] ? Number(args['review-tested-max-age-minutes']) : 0;
const AS_JSON = !!args.json;
const QUEUE_MODE = !!args.queue;

// 자동 감지(무소식) 이슈 제목 접두사 — 이 제목의 이슈는 "작업"이 아니라 "감지 기록"이므로
// **작업 큐(--queue)의 대상이 아니다**(giip #4907 · 큐 오염 2차 방어선).
//
// ⚠ 커플링: 이 문자열은 `scripts/gissue/check-gissue-liveness.ps1` 의 `$title` 과 **반드시
//   동일**해야 한다(그 스크립트가 등록하는 자동 감지 이슈의 제목). 한쪽만 고치면 큐 제외가
//   조용히 깨진다 — 회귀 테스트(test-queue-ops-exclude.mjs)가 두 값의 일치를 함께 고정한다.
// 판정 규칙은 lib/liveness-ops-issue.js 의 titleMatch(rowTitle, canonical) 와 동일하다
//   (정확 일치 또는 그로 시작).
const AUTO_OPS_TITLE_PREFIX = '[OPS] gissue 처리 무소식 감지';

// 인자 검증은 main() 안에서 한다 — 이 파일을 require 하는 회귀 테스트가 모듈 로드 시
// process.exit(2) 로 죽지 않게 하기 위해서다(rule 42 — 검사기가 0건을 보고 PASS 하지 않도록).
function validateArgs() {
  if (!CSN || (!QUEUE_MODE && !STATUSES.length)) {
    console.error('사용법: node list-issues.js --csn <N> (--status PENDING[,READY,...] [--min-age-minutes <N>] [--hours-back <N>] | --queue) [--json]');
    process.exit(2);
  }
}

function resolveSk(csn) {
  if (!fs.existsSync(ACCOUNTS_FILE)) throw new Error(`계정 파일을 찾을 수 없습니다: ${ACCOUNTS_FILE}`);
  const data = JSON.parse(fs.readFileSync(ACCOUNTS_FILE, 'utf-8'));
  const channels = Object.values(data.channels || {});
  const defaultEntry = data.default ? [data.default] : [];
  const match = [...channels, ...defaultEntry].find((c) => String(c.csn) === String(csn));
  if (!match || !match.sk) throw new Error(`csn ${csn} 에 매칭되는 sk 를 찾지 못했습니다 (${ACCOUNTS_FILE})`);
  return match.sk;
}

function httpGet(url, headers) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers }, (res) => {
      let body = '';
      res.on('data', (d) => { body += d; });
      res.on('end', () => {
        let parsed = body;
        try { parsed = JSON.parse(body); } catch { /* keep raw */ }
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => req.destroy(new Error('list-issues.js: giipfaw request timeout')));
  });
}

function extractStatusEnteredAt(comments, status) {
  const transitionRe = new RegExp(`状態遷移:\\s*\\S+\\s*->\\s*${status}\\s*$`, 'm');
  const timeRe = /\*\*日時\(When\)\*\*:\s*(\S+)/;
  for (let i = comments.length - 1; i >= 0; i--) {
    const body = comments[i].content || comments[i].Content || '';
    if (transitionRe.test(body)) {
      const m = body.match(timeRe);
      if (m) {
        const d = new Date(m[1]);
        if (!Number.isNaN(d.getTime())) return d;
      }
    }
  }
  return null;
}

function lastCommentAt(comments) {
  let latest = null;
  for (const c of comments) {
    const when = c.regdate || c.Regdate;
    if (!when) continue;
    const d = new Date(when);
    if (!Number.isNaN(d.getTime()) && (!latest || d > latest)) latest = d;
  }
  return latest;
}

// ── --queue 모드 구현 (giip #2645) ───────────────────────────────────────
const QUEUE_SPEC = [
  // status(API 조회값), label(반환 라벨), qprio, minAgeMin, needsActionflowDedup
  { status: 'IN_PROGRESS', label: 'STALE_IN_PROGRESS', qprio: 0, minAge: 60, dedup: false },
  { status: 'PENDING',     label: 'PENDING',           qprio: 1, minAge: 0,  dedup: false },
  { status: 'READY',       label: 'READY',             qprio: 2, minAge: 60, dedup: false },
  // REVIEW/TESTED 재확인은 READY 실작업 뒤로 보낸다(qprio 3) — 오래된 재확인 백로그가 READY 를 밀어내지 않게.
  { status: 'REVIEW',      label: 'REVIEW',            qprio: 3, minAge: 0,  dedup: true },
  { status: 'TESTED',      label: 'TESTED',            qprio: 3, minAge: 0,  dedup: true },
];

function minutesSince(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return Math.round((Date.now() - d.getTime()) / 60000);
}

function sanitize(text) {
  // SQL 이 REPLACE(...,'|',' ') + 개행 제거로 파이프 구분 계약을 지키던 것과 동등하게 정규화한다
  // (호출부 PowerShell 은 JSON 으로 받지만, 로그/컨텍스트 문자열에서 파이프를 구분자로 쓴다).
  return String(text == null ? '' : text).replace(/\|/g, ' ').replace(/[\r\n]+/g, ' ').slice(0, 120);
}

async function fetchComments(sk, isn) {
  const res = await httpGet(`${API_BASE}/giipIssueComments?isn=${encodeURIComponent(isn)}`, { 'x-api-key': sk });
  return res.status === 200 ? (res.body?.comments || []) : [];
}

/**
 * 자동 감지(무소식) 이슈인가 — 즉 "작업"이 아니라 "감지 기록"인가(giip #4907).
 * 판정 규칙은 lib/liveness-ops-issue.js 의 titleMatch(rowTitle, canonical) 와 동일하다
 *   (제목이 정확히 같거나, 그 문자열로 시작).
 * 제목에 "[OPS]" 가 **포함**된 후속 이슈는 잡지 않는다 — 접두사 전체 일치로 좁힌다.
 *
 * @param {string} title 이슈 제목 (가공 전 원문)
 * @returns {boolean} 자동 감지 이슈면 true
 */
function isAutoDetectionOpsTitle(title) {
  const t = String(title == null ? '' : title).trim();
  if (!t) return false;
  return t === AUTO_OPS_TITLE_PREFIX || t.startsWith(AUTO_OPS_TITLE_PREFIX);
}

async function runQueue() {
  const sk = resolveSk(CSN);
  const rows = [];
  for (const spec of QUEUE_SPEC) {
    const url = `${API_BASE}/giipIssues?csn=${encodeURIComponent(CSN)}&status=${encodeURIComponent(spec.status)}`;
    const res = await httpGet(url, { 'x-api-key': sk });
    if (res.status !== 200) {
      console.error(`❌ issueList(status=${spec.status}) 실패: ${res.status} ${JSON.stringify(res.body).slice(0, 200)}`);
      process.exit(1);
    }
    for (const issue of (res.body?.issues || [])) {
      const isn = issue.isn ?? issue.Isn;
      if (isn == null) continue;
      // 자동 감지([OPS] 무소식) 이슈는 **작업이 아니라 감지 기록**이므로 작업 큐에서 제외한다.
      // 제외는 **조회(큐) 계층 한정** — `--status` 직접 조회와 liveness 의 find() 경로는 영향받지 않는다.
      // 판정을 코멘트 조회보다 앞에서 한다 — 제외될 이슈마다 코멘트 API 조회가 낭비되지 않게.
      const rawTitle = issue.title ?? issue.Title ?? '';
      if (isAutoDetectionOpsTitle(rawTitle)) continue;
      const regdate = issue.regdate ?? issue.Regdate ?? null;
      const lastCmtDate = issue.last_comment_date ?? issue.lastCommentDate ?? null;
      const lastAuthor = issue.last_comment_author ?? issue.lastCommentAuthor ?? '';
      const hasComment = lastCmtDate ? 1 : 0;

      // 코멘트 본문이 실제로 필요한 경우에만(그리고 코멘트가 1건이라도 있을 때만) 조회한다.
      let isUserReq = 0;
      let latestContent = '';
      if (hasComment) {
        const comments = await fetchComments(sk, isn);
        for (const c of comments) {
          const body = c.content || c.Content || '';
          if (/^\s*\[USER-REQUEST\]/.test(body)) { isUserReq = 1; }
        }
        // 최신 코멘트(= regdate 최대) 본문
        let latest = null;
        for (const c of comments) {
          const when = c.regdate || c.Regdate;
          if (!when) continue;
          const d = new Date(when);
          if (Number.isNaN(d.getTime())) continue;
          if (!latest || d > latest.when) latest = { when: d, body: c.content || c.Content || '' };
        }
        if (latest) latestContent = latest.body;
      }

      // [G] dedup: 최신 코멘트가 '[ACTIONFLOW-TEST]' 로 시작하면 직전 재검증 이후 상황이 바뀌지
      // 않았다는 뜻이므로 큐에서 뺀다(무의미한 반복 실행 금지 — SQL WHERE 절과 동일 조건).
      if (spec.dedup && /^\s*\[ACTIONFLOW-TEST\]/.test(latestContent)) continue;

      const basis = isUserReq ? regdate : (lastCmtDate || regdate);
      let elapsed = minutesSince(basis);
      // 타임스탬프를 전혀 얻지 못하면 age=null → 누락 방지 우선으로 대상에 포함시킨다
      // (이 파일 상단 --min-age-minutes 정책과 동일).
      if (elapsed === null) elapsed = Number.MAX_SAFE_INTEGER;
      if (spec.minAge > 0 && elapsed < spec.minAge) continue;
      // REVIEW/TESTED(dedup 대상) 의 최대 경과시간 제한 — 타임스탬프를 못 얻은 경우(MAX_SAFE_INTEGER)는 누락 방지로 유지.
      if (spec.dedup && REVIEW_TESTED_MAX_AGE_MIN > 0 && elapsed !== Number.MAX_SAFE_INTEGER && elapsed > REVIEW_TESTED_MAX_AGE_MIN) continue;

      rows.push({
        isn,
        title: sanitize(issue.title ?? issue.Title ?? ''),
        status: spec.label,
        // 응답이 실제로 물어낸 csn 이 속한 csn (giip #4116 — 요청값 아님).
        cSn: issue.cSn ?? issue.CSn ?? null,
        elapsedMin: elapsed === Number.MAX_SAFE_INTEGER ? 0 : elapsed,
        lastAuthor: sanitize(lastAuthor),
        _qprio: spec.qprio,
        _isUserReq: isUserReq,
        _hasComment: hasComment,
        _sortElapsed: elapsed,
      });
    }
  }
  rows.sort((a, b) => (
    a._qprio - b._qprio
    || b._isUserReq - a._isUserReq
    || a._hasComment - b._hasComment
    || b._sortElapsed - a._sortElapsed
  ));
  const out = rows.map((r) => ({
    isn: r.isn, title: r.title, status: r.status, elapsedMin: r.elapsedMin, lastAuthor: r.lastAuthor,
    cSn: r.cSn,
  }));
  if (AS_JSON) {
    console.log(JSON.stringify(out));
  } else if (!out.length) {
    console.log(`(csn=${CSN} 처리 대상 없음)`);
  } else {
    for (const r of out) {
      console.log(`isn=${r.isn} status=${r.status} elapsed=${r.elapsedMin}m lastAuthor=${r.lastAuthor} title=${r.title}`);
    }
  }
}

async function main() {
  validateArgs();
  if (QUEUE_MODE) { await runQueue(); return; }
  const sk = resolveSk(CSN);
  const results = [];
  for (const status of STATUSES) {
    const url = `${API_BASE}/giipIssues?csn=${encodeURIComponent(CSN)}&status=${encodeURIComponent(status)}`;
    const res = await httpGet(url, { 'x-api-key': sk });
    if (res.status !== 200) {
      console.error(`❌ issueList(status=${status}) 실패: ${res.status} ${JSON.stringify(res.body).slice(0, 200)}`);
      process.exit(1);
    }
    const issues = res.body?.issues || [];
    for (const issue of issues) {
      const isn = issue.isn ?? issue.Isn;
      if (isn == null) continue;
      let ageMinutes = null;
      let comments = null;
      if (MIN_AGE_MIN > 0 || HOURS_BACK > 0) {
        const cRes = await httpGet(`${API_BASE}/giipIssueComments?isn=${encodeURIComponent(isn)}`, { 'x-api-key': sk });
        comments = cRes.status === 200 ? (cRes.body?.comments || []) : [];
      }
      if (MIN_AGE_MIN > 0) {
        const enteredAt = extractStatusEnteredAt(comments || [], status);
        if (enteredAt) ageMinutes = Math.round((Date.now() - enteredAt.getTime()) / 60000);
        if (ageMinutes !== null && ageMinutes < MIN_AGE_MIN) continue;
      }
      if (HOURS_BACK > 0) {
        const last = lastCommentAt(comments || []);
        if (!last || (Date.now() - last.getTime()) / 3600000 > HOURS_BACK) continue;
      }
      results.push({
        isn,
        status,
        ageMinutes,
        title: issue.title ?? issue.Title ?? '',
        // 응답이 실제로 물어낸 csn 이 속한 csn 을 알려 준다(giip #4116). 요청 csn 을 그대로 붙이면
        // "클램프된 응답"(서버가 다른 csn 의 이슈를 돌려주는 경우)을 구분할 수 없다.
        cSn: issue.cSn ?? issue.CSn ?? null,
      });
    }
  }
  if (AS_JSON) {
    console.log(JSON.stringify(results));
  } else if (!results.length) {
    console.log(`(csn=${CSN} status=${STATUSES.join(',')} 대상 없음)`);
  } else {
    for (const r of results) {
      console.log(`isn=${r.isn} status=${r.status} age=${r.ageMinutes === null ? '?' : r.ageMinutes + 'm'} title=${r.title}`);
    }
  }
}

// 이 파일을 직접 실행할 때만 main() 을 돌린다 — 회귀 테스트가 require 해서 순수 함수만
// 가져올 수 있게 한다(모듈 로드 시점에 인자 검증으로 process.exit 하지 않는다).
if (require.main === module) {
  main().catch((e) => { console.error('❌', e.message); process.exit(1); });
}

// 회귀 테스트 대상(giip #4907).
//   isAutoDetectionOpsTitle — 순수 판정 함수(제외 대상 판정)
//   AUTO_OPS_TITLE_PREFIX  — 판정 기준 문자열(커플링 검증 대상)
//   main / runQueue        — 회귀 테스트가 전송 계층만 바꿔 실제로 돌릴 수 있게 공개
module.exports = { isAutoDetectionOpsTitle, AUTO_OPS_TITLE_PREFIX, main, runQueue };
