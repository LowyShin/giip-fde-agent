#!/usr/bin/env node
/**
 * live-api-probe.js — 라이브 실측용 읽기 전용 API 조회 도우미 (giip 4116 완료 기준 2)
 *
 * 왜 필요한가: "봇 유저가 멤버가 아닌 csn 을 일부러 조회" 하는 상황을 **실측**으로 확인하려면
 *   (1) 그 csn 의 이슈가 조회 요청과 무관하게 **다른 csn 의 것**으로 보이거나,
 *   (2) 아무것도 안 보이거나,
 *   둘 중 하나를 실제 서버 응답으로 확인해야 한다. 그리고 가드가 실행 전후에 **원래 이슈에
 *   코멘트를 남기지 않았는지**(0건)를 비교해야 한다 — 그 비교는 코멘트 개수 조회로 한다.
 *
 * 이 도우미는 **읽기 전용**이다 (GET 만). 쓰기 호출은 없다 — 실측이 남의 CSN 에 글을 남기는
 * 일이 없도록 설계했다.
 *
 * 사용:
 *   node live-api-probe.js comments <apiBase> <sk> <isn>
 *     → 해당 isn 의 코멘트 개수 1줄 (숫자)
 *   node live-api-probe.js commentlist <apiBase> <sk> <isn>
 *     → 코멘트 배열(JSON): [{ cSn, content }] — "[UNMAPPED-CSN-WARN]" 잔존 확인용
 *   node live-api-probe.js issues <apiBase> <sk> <csn> [status,...]
 *     → 해당 csn 의 이슈 배열(JSON). cSn 필드를 그대로 둔다(가드 대조 게이트의 입력 재료).
 *
 * 종료코드: 0 = 조회 성공 / 1 = 실패(사유는 stderr).
 * SK 는 표준출력에 절대 찍지 않는다.
 */
const https = require('https');
const { URL } = require('url');

function request(url, apiKey) {
  return new Promise((resolve) => {
    const u = new URL(url);
    const req = https.get(url, { headers: { 'x-api-key': apiKey }, timeout: 30000 }, (res) => {
      let d = '';
      res.on('data', (c) => { d += c; });
      res.on('end', () => {
        let j = null;
        try { j = JSON.parse(d); } catch { /* raw 유지 */ }
        resolve({ status: res.statusCode, json: j, text: d });
      });
    });
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, json: null, text: 'timeout' }); });
    req.on('error', (e) => resolve({ status: 0, json: null, text: String(e && e.message || e) }));
  });
}

/** isn 의 코멘트 배열 조회 (실패하면 예외 — 호출부가 판단한다). */
async function fetchComments(apiBase, apiKey, isn) {
  const r = await request(`${apiBase}/giipIssueComments?isn=${encodeURIComponent(isn)}`, apiKey);
  if (r.status !== 200 || !r.json || !Array.isArray(r.json.comments)) {
    throw new Error(`코멘트 조회 실패 (HTTP ${r.status}): ${String(r.text).slice(0, 300)}`);
  }
  return r.json.comments;
}

/**
 * csn 의 이슈 행 조회. 응답이 실제로 돌려준 cSn 을 그대로 둔다 —
 * 이 값이 가드의 대조 게이트(SKIP-CLAMP) 입력 재료다(giip 4116).
 */
async function fetchIssues(apiBase, apiKey, csn, statuses) {
  const rows = [];
  for (const st of statuses) {
    const r = await request(`${apiBase}/giipIssues?csn=${encodeURIComponent(csn)}&status=${encodeURIComponent(st)}`, apiKey);
    if (r.status !== 200) {
      throw new Error(`이슈 조회 실패 (HTTP ${r.status}, status=${st}): ${String(r.text).slice(0, 300)}`);
    }
    for (const issue of (r.json && r.json.issues) || []) {
      const isn = issue.isn ?? issue.Isn;
      if (isn == null) continue;
      rows.push({
        isn,
        status: st,
        title: issue.title ?? issue.Title ?? '',
        // 응답이 실제로 돌려준 csn — 요청값이 아니다(giip 4116 대조 게이트의 재료).
        cSn: issue.cSn ?? issue.CSn ?? null,
      });
    }
  }
  return rows;
}

async function main() {
  // process.argv[0]=node, [1]=이 스크립트 경로 → 실제 인자는 [2] 부터다.
  const [cmd, apiBase, apiKey, a3, a4] = process.argv.slice(2);
  if (!cmd || !apiBase || !apiKey) {
    console.error('사용법: live-api-probe.js <comments|commentlist|issues> <apiBase> <sk> <인자...>');
    process.exit(2);
  }
  if (cmd === 'comments') {
    const list = await fetchComments(apiBase, apiKey, a3);
    process.stdout.write(String(list.length) + '\n');
    process.exit(0);
  }
  if (cmd === 'commentlist') {
    const list = await fetchComments(apiBase, apiKey, a3);
    process.stdout.write(JSON.stringify(list.map(c => ({ cSn: c.cSn ?? null, content: c.content ?? '' }))));
    process.exit(0);
  }
  if (cmd === 'issues') {
    const statuses = String(a4 || 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED')
      .split(',').map(s => s.trim()).filter(Boolean);
    const rows = await fetchIssues(apiBase, apiKey, a3, statuses);
    process.stdout.write(JSON.stringify(rows));
    process.exit(0);
  }
  console.error(`알 수 없는 명령: ${cmd}`);
  process.exit(2);
}

if (require.main === module) { main(); }

module.exports = { fetchComments, fetchIssues };
