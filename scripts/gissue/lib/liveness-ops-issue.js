#!/usr/bin/env node
/**
 * liveness-ops-issue.js — gissue 처리 무소식 "[OPS] 에피소드 이슈" 생명주기 도구 (giip 4411 후속)
 *
 * 무엇을: check-gissue-liveness.ps1 가 "무소식" 에피소드 하나를 이슈 1건으로 유지하기 위해 필요한
 *   4가지 동작(열린 이슈 찾기 / 진행 보고 코멘트 / 회복 시 DONE 닫기 / 최초 등록)을 한 곳에 묶는다.
 *   stdout 은 **JSON 한 줄**로만 낸다(성공/실패 모두). 실패하면 ok=false + error, 종료코드 1.
 *
 * 왜 별도 파일인가 — 근본 원인(2026-11-11 중복 등록 #4870/#4874):
 *   등록과 중복 조회가 **다른 주체(계정)와 다른 CSN 스코프**를 쓰고 있었다.
 *     · 등록(register-issue.js)  : default 계정의 SK(AK 경유)로 쓰고, csn=<OpsCsn> 을 요청한다.
 *       서버(giipdb pApiGiipIssuePutbyAK)는 "요청자가 그 CSN 의 멤버가 아니면 홈 CSN 으로 클램프"한다.
 *     · 중복 조회(list-issues.js --csn <OpsCsn>) : 그 CSN 의 SK 로 **i.cSn = <OpsCsn> 인 줄만** 돌려준다.
 *   ⇒ 이슈는 홈 CSN 에 생겼는데 조회는 OpsCsn 을 쳐서 "같은 제목 이슈 없음" 으로 판단 → 매 시간 중복 등록.
 *   (쿨다운 6h 가 6시간 동안만 이 사실을 가려서 05:36(#4870) / 12:37(#4874) 로 7시간 간격으로 드러났다.)
 *   이 파일은 **등록과 조회를 반드시 같은 계정으로** 수행한다(register-issue.js 와 동일 주체:
 *   slack-bot/giip-accounts 의 default 계정). 조회 후보 CSN = {OpsCsn, default 계정의 csn} 둘 다 본다.
 *
 * 쓰기 안전장치:
 *   · 응답 행의 실제 cSn 이 조회 후보 CSN 밖이면 버린다(남의 CSN 이슈에 코멘트/닫기를 걸지 않는다).
 *   · 코멘트/상태변경은 **그 이슈가 실제 위치한 CSN 의 SK** 로만 한다(giipIssueComments 의 인가 게이트는
 *     "이슈의 cSn = SK 의 CSN" 을 요구한다 — pApiGiipIssueCommentPutbyAK). 쓰기에는 폴백을 두지 않는다.
 *   · **조회**만 폴백이 있다: 그 CSN 의 계정이 없으면 등록 주체(default) 계정의 SK 로 조회한다. 서버가
 *     "멤버가 아니면 홈 CSN 으로 클램프"하므로 홈 CSN(등록 결과가 놓이는 곳)의 이슈는 반드시 보이고,
 *     멤버라면 클램프가 없어 그 CSN 의 이슈도 보인다. → 조회 실패로 알림이 죽는 것을 막는다.
 *   · 조회(조회 대상 CSN 목록/상태별)를 하나라도 실패하면 전체를 실패로 본다 → 호출부는 등록하지 않는다.
 *
 * 사용(모두 stdout=JSON 1줄):
 *   node liveness-ops-issue.js find    --title-file <제목파일> --ops-csn <N>
 *   node liveness-ops-issue.js comment --isn <N> --csn <N> --file <본문파일>
 *   node liveness-ops-issue.js close   --isn <N> --csn <N> [--status DONE]
 *   node liveness-ops-issue.js register --title-file <제목파일> --content-file <파일> --csn <N>
 *   (제목·본문은 **파일**로 받는다 — 한글을 커맨드라인 인자로 넘기면 Windows PowerShell 5.1 콘솔
 *    코드페이지로 깨진다(giip #1236/#2404). 파일은 UTF-8(BOM) 로 읽고 BOM 은 strip 한다.)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const { URL } = require('url');

// register-issue.js 와 같은 계정 정본(같은 default 계정 = 같은 쓰기 주체). 경로도 동일하게 맞춘다.
const BOT_DIR = path.resolve(__dirname, '..', '..', '..', 'slack-bot');
const accounts = require(path.join(BOT_DIR, 'giip-accounts'));
const { postCommentVerified } = require('./comment-api');

// "열린" 이슈 상태. DONE 은 종료된 에피소드이므로 제외한다.
const OPEN_STATUSES = ['PENDING', 'READY', 'IN_PROGRESS', 'REVIEW', 'TESTED'];

/** UTF-8 파일을 읽는다(BOM 은 strip — 코멘트/제목 앞의 U+FEFF 가 본문에 붙지 않게). */
function readUtf8(file) {
  return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) { out[key] = true; }
      else { out[key] = next; i++; }
    } else {
      out._.push(a);
    }
  }
  return out;
}

function apiBase() {
  return accounts.apiBase() || 'https://giipfaw.azurewebsites.net/api';
}

/** csn 에 매칭되는 계정 엔트리(전체). list-issues.js 의 resolveSk 와 같은 규칙(channels → default). */
function accountEntryForCsn(csn) {
  const cfg = accounts.load();
  const channels = Object.values(cfg.channels || {});
  const defaultEntry = cfg.default ? [cfg.default] : [];
  const match = [...channels, ...defaultEntry].find((c) => String(c.csn) === String(csn));
  return match && match.sk ? match : null;
}

/**
 * 쓰기용 SK — 이슈가 **실제로 위치한 CSN** 의 계정만 허용한다.
 * (인가 게이트: pApiGiipIssueCommentPutbyAK / pApiGiipIssuePutbyAK 는 "이슈의 cSn = SK 의 CSN" 을 요구한다.
 *  다른 CSN 의 SK 를 쓰면 404(no permission) 다 — 그래서 폴백을 두지 않는다.)
 */
function skForCsn(csn) {
  const e = accountEntryForCsn(csn);
  if (!e) throw new Error(`csn ${csn} 에 매칭되는 sk 를 찾지 못했습니다`);
  return e.sk;
}

/**
 * 조회용 SK 선택 규칙(순수 함수 — 계정 파일 조회 없이 정책만 고정한다).
 *   exactSk 있으면 그것, 없으면 등록 주체(default) 계정의 SK 로 폴백, 둘 다 없으면 null(조회 불가).
 * 폴백이 안전한 이유: 서버는 "요청자가 그 CSN 의 멤버가 아니면 홈 CSN 으로 클램프"한다 →
 *   · 홈 CSN(등록 결과가 놓이는 곳)의 이슈는 반드시 보인다.
 *   · 멤버라면 클램프가 없어 그 CSN 의 이슈도 보인다.
 *   · 둘 다 아니라면 그 CSN 에는 우리 계정으로 등록될 수 없다 → 볼 것이 없다.
 * 그리고 응답 행의 실제 cSn 이 조회 후보 밖이면 버린다 → 남의 CSN 이슈는 건드리지 않는다.
 */
function resolveReadSk(exactSk, writeSk) {
  return exactSk || writeSk || null;
}

/**
 * 제목 매칭: 정규식 제목과 **완전히 같거나 그로 시작**하면 같은 제목으로 본다.
 * (사람이 뒤에 "[긴급]" 같은 말을 덧붙여도 같은 에피소드 이슈로 취급한다. 앞부분 일치는 허용하지 않는다.)
 */
function titleMatch(rowTitle, canonical) {
  const t = String(rowTitle == null ? '' : rowTitle).trim();
  const c = String(canonical == null ? '' : canonical).trim();
  if (!c) return false;
  return t === c || t.startsWith(c);
}

/**
 * CSN 값 정규화 — 숫자 또는 숫자 문자열만 받는다.
 * (parseArgs 는 값이 없는 플래그를 true 로 만들며 Number(true) === 1 이므로, 그대로 Number() 로
 *  변환하면 "CSN 1" 이 후보에 들어간다 — 실제 CSN 을 잘못 건드릴 수 있으므로 명시적으로 막는다.)
 */
function toCsn(value) {
  if (typeof value === 'number') return Number.isInteger(value) && value > 0 ? value : null;
  if (typeof value === 'string' && /^\d+$/.test(value.trim())) {
    const n = Number(value.trim());
    return n > 0 ? n : null;
  }
  return null;
}

/**
 * 조회 후보 CSN. 이슈가 실제로 놓일 수 있는 곳은 두 군데다:
 *   1) 요청한 OpsCsn — 등록 주체가 그 CSN 의 멤버면 서버가 그대로 들어준다
 *   2) 등록 주체(default) 계정의 홈 CSN — 멤버가 아니면 서버가 홈 CSN 으로 클램프한다
 *   ⇒ 둘 다 봐야 "같은 제목 이슈가 이미 있다"를 reliably 판정할 수 있다(2026-11-11 중복 등록 사고).
 */
function candidateCsns(opsCsn, writeCsn) {
  const out = [];
  const ops = toCsn(opsCsn);
  if (ops) out.push(ops);
  const w = toCsn(writeCsn);
  if (w && !out.includes(w)) out.push(w);
  return out;
}

function request(method, url, { apiKey, body } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const headers = { 'x-api-key': apiKey };
    let payload = null;
    if (body !== undefined && body !== null) {
      payload = Buffer.from(body, 'utf8');
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = payload.length;
    }
    const req = https.request(
      { hostname: u.hostname, port: u.port || 443, path: u.pathname + u.search, method, headers },
      (res) => {
        const chunks = [];
        res.on('data', (d) => chunks.push(d));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try { json = JSON.parse(text); } catch { /* 비-JSON 응답은 raw 로만 */ }
          resolve({ status: res.statusCode, text, json });
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(30000, () => req.destroy(new Error('timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

/**
 * 열린 같은 제목 이슈를 찾는다.
 * 조회 후보 CSN = {OpsCsn, 등록 주체(default) 계정의 csn}.
 *   - OpsCsn 에 실제로 등록되는 경우(멤버십이 있을 때)
 *   - 서버가 홈 CSN 으로 클램프한 경우(멤버십이 없을 때) → default 계정의 csn 에 등록된다
 * 응답 행의 cSn 은 후보 CSN 밖이면 버린다.
 *
 * @param {object} args { title, titleFile, opsCsn }
 * @param {object} [deps] 테스트 주입점 — { request, accounts, accountEntryForCsn } (기본값은 실제 모듈)
 */
async function find({ title, titleFile, opsCsn }, deps = {}) {
  const requestFn = deps.request || request;
  const accountsApi = deps.accounts || accounts;
  const entryFor = deps.accountEntryForCsn || accountEntryForCsn;
  const write = accountsApi.resolve(null); // register-issue.js 와 동일 주체
  if (!write) throw new Error('giip 계정 미설정(default) — 등록 주체를 알 수 없음');
  const writeCsn = toCsn(write.csn);
  if (!writeCsn) {
    // 홈 CSN 을 모르면 "클램프되어 홈 CSN 에 생긴 이슈"를 볼 수 없다 → 조회 결과가 불완전하다.
    // 불완전한 조회 위로는 등록하지 않는다(중복 등록 방지 우선).
    throw new Error(
      'default 계정에 csn 이 없어 홈 CSN 을 알 수 없음 — 조회 후보가 불완전하므로 등록하지 않는다. ' +
      'slack-bot/.secrets/giip-accounts.json 의 default.csn 을 실제 CSN 으로 채우십시오.'
    );
  }

  const canonical = titleFile ? readUtf8(titleFile).trim() : String(title || '').trim();
  if (!canonical) throw new Error('비교 기준 제목이 비어 있음');

  const candidates = candidateCsns(opsCsn, writeCsn);

  const found = new Map();
  for (const c of candidates) {
    // 조회용 SK: 그 CSN 의 계정이 있으면 그것, 없으면 등록 주체(default) 계정의 SK(읽기 전용 폴백).
    const sk = resolveReadSk((entryFor(c) || {}).sk, write.sk);
    if (!sk) throw new Error(`csn ${c} 조회 SK 를 정할 수 없음(계정도 없고 등록 주체 SK 도 없음)`);
    for (const status of OPEN_STATUSES) {
      const url = `${apiBase()}/giipIssues?csn=${encodeURIComponent(c)}&status=${encodeURIComponent(status)}`;
      const res = await requestFn('GET', url, { apiKey: sk });
      if (res.status !== 200) {
        throw new Error(`issueList(csn=${c}, status=${status}) 실패: HTTP ${res.status} ${String(res.text || '').slice(0, 200)}`);
      }
      const rows = (res.json && res.json.issues) || [];
      for (const r of rows) {
        const isn = r.isn ?? r.Isn;
        if (isn == null) continue;
        const rowTitle = r.title ?? r.Title ?? '';
        if (!titleMatch(rowTitle, canonical)) continue;
        const rowCsn = r.cSn ?? r.CSn ?? r.csn ?? null;
        if (rowCsn === null || rowCsn === undefined || rowCsn === '') continue; // cSn 을 못 읽으면 신뢰하지 않는다
        if (!candidates.includes(Number(rowCsn))) continue;                  // 우리 CSN 이 아닌 이슈는 건드리지 않는다
        // 같은 이슈가 여러 상태 조회에서 잡힐 수 있다 — 처음 발견한 상태를 유지한다(뒤 status 로 덮어쓰지 않는다).
        if (found.has(Number(isn))) continue;
        found.set(Number(isn), {
          isn: Number(isn), status, cSn: Number(rowCsn), title: String(rowTitle),
          // 이슈 자체의 시각 — 에피소드 기록이 없는 기존 이슈의 회복 보고 기준 시각으로 쓴다.
          regdate: r.regdate ?? r.Regdate ?? null,
          lastCommentDate: r.last_comment_date ?? r.lastCommentDate ?? null,
        });
      }
    }
  }
  const issues = Array.from(found.values()).sort((a, b) => a.isn - b.isn);
  return { ok: true, writeCsn, candidates, issues };
}

/** 진행 보고/회복 코멘트. 본문은 파일로 받아 UTF-8 그대로 넣는다(mojibake 회피는 comment-api 가 담당). */
async function comment({ isn, csn, file }) {
  if (!file || !fs.existsSync(file)) throw new Error(`코멘트 본문 파일 없음: ${file}`);
  // 쓰기이므로 폴백하지 않는다 — 이슈가 실제 위치한 CSN 의 계정으로만 남긴다(타 CSN 쓰기 금지 가드).
  const sk = skForCsn(csn);
  const content = readUtf8(file);
  const r = await postCommentVerified({ apiBase: apiBase(), apiKey: sk, isn: Number(isn), content, issuetype: 'note' });
  (r.log || []).forEach((l) => console.error(`[post-comment] ${l}`));
  // commentCsn = 방금 만든 **코멘트**의 cSn(코멘트 테이블 PK). 이슈가 위치한 CSN 과는 다른 값이다.
  return { ok: true, isn: Number(isn), commentCsn: r.csn, verified: r.verified, attempts: r.attempts };
}

/** 상태 전이(회복 시 DONE). status-only PUT — pApiGiipIssuePutbyAK 가 title/content 를 보존한다. */
async function close({ isn, csn, status }) {
  const sk = skForCsn(csn);
  const target = status || 'DONE';
  const res = await request('PUT', `${apiBase()}/giipIssues`, {
    apiKey: sk,
    body: JSON.stringify({ isn: Number(isn), status: target }),
  });
  if (res.status !== 200) {
    throw new Error(`상태전이 실패(HTTP ${res.status}): ${String(res.text || '').slice(0, 300)}`);
  }
  return { ok: true, isn: Number(isn), status: target };
}

/**
 * 최초 등록. register-issue.js 와 **같은 계정·같은 API 호출**을 쓴다(계정 resolution 은 accounts.resolve(null)).
 * 제목/본문은 파일로 받아 UTF-8 로 넣는다 — 한글 제목을 커맨드라인 인자로 넘기면 Windows PowerShell 5.1 의
 * 콘솔 코드페이지로 깨져 저장된다(giip #1236/#2404 계열). 등록 출력 계약 "giip issue #<n> 등록 완료" 은 유지한다.
 */
async function register({ title, titleFile, contentFile, csn }) {
  if (!contentFile || !fs.existsSync(contentFile)) throw new Error(`등록 본문 파일 없음: ${contentFile}`);
  const acct = accounts.resolve(null);
  if (!acct) throw new Error('giip 계정 미설정(default)');
  const titleText = titleFile ? readUtf8(titleFile).trim() : String(title || '').trim();
  if (!titleText) throw new Error('등록 제목이 비어 있음');
  const content = readUtf8(contentFile).trim();
  if (!content) throw new Error('등록 본문이 비어 있음');
  // giip-api 의 issueCreate 는 register-issue.js 가 쓰던 것과 같은 호출이다(계정·제목·본문·상태·csn).
  const giip = require(path.join(BOT_DIR, 'giip-api'));
  const r = await giip.issueCreate(acct, { title: titleText, content: content.slice(0, 8000), status: 'PENDING', csn: Number(csn) });
  const isn = r && r.isn ? Number(r.isn) : null;
  if (!isn) throw new Error(`등록 응답에 isn 이 없습니다: ${JSON.stringify(r).slice(0, 200)}`);
  // 실제 놓인 CSN 을 다시 읽는다 — 서버가 "멤버가 아니면 홈 CSN 으로 클램프"하면 요청한 csn 과 다를 수 있다.
  // (요청값을 그대로 기록하면 상태 파일에 "있지 않은 CSN" 이 남는다 — 다음 변경이 그 값을 신뢰하면 위험하다.)
  const placed = await readIssuePlacement(isn);
  const actualCsn = placed.cSn || toCsn(csn) || null;
  const line = `✅ giip issue #${isn} 등록 완료 (status=PENDING, csn=${actualCsn})`;
  return {
    ok: true, isn, stdout: line,
    cSn: actualCsn, requestedCsn: toCsn(csn), regdate: placed.regdate || null,
  };
}

/** 등록 직후 그 이슈가 실제로 어느 CSN 에 놓였는지 읽는다(실패해도 등록 자체는 성공 — 값만 모른다). */
async function readIssuePlacement(isn) {
  try {
    const sk = (accounts.resolve(null) || {}).sk;
    if (!sk) return { cSn: null, regdate: null };
    const res = await request('GET', `${apiBase()}/giipIssues?isn=${encodeURIComponent(isn)}`, { apiKey: sk });
    if (res.status !== 200) return { cSn: null, regdate: null };
    const issue = (res.json && (res.json.issue || res.json.issues?.[0])) || {};
    const cSn = toCsn(issue.cSn ?? issue.CSn ?? issue.csn);
    return { cSn, regdate: issue.regdate ?? issue.Regdate ?? null };
  } catch {
    return { cSn: null, regdate: null };
  }
}

if (require.main === module) {
  (async () => {
    const args = parseArgs(process.argv.slice(2));
    const verb = args._[0];
    try {
      let result;
      if (verb === 'find') {
        result = await find({ title: args.title, titleFile: args['title-file'], opsCsn: args['ops-csn'] });
      } else if (verb === 'comment') {
        result = await comment({ isn: args.isn, csn: args.csn, file: args.file });
      } else if (verb === 'close') {
        result = await close({ isn: args.isn, csn: args.csn, status: args.status });
      } else if (verb === 'register') {
        result = await register({ title: args.title, titleFile: args['title-file'], contentFile: args['content-file'], csn: args.csn });
      } else {
        console.error('사용법: liveness-ops-issue.js find|comment|close|register ...');
        process.stdout.write(JSON.stringify({ ok: false, error: 'unknown verb' }) + '\n');
        process.exit(2);
      }
      process.stdout.write(JSON.stringify(result) + '\n');
    } catch (e) {
      const msg = e && e.message ? e.message : String(e);
      console.error(`❌ ${msg}`);
      process.stdout.write(JSON.stringify({ ok: false, error: msg }) + '\n');
      process.exit(1);
    }
  })();
}

module.exports = { titleMatch, candidateCsns, resolveReadSk, toCsn, find, OPEN_STATUSES };
