/**
 * giip-api.js — giip API 클라이언트(의존성 없음, 내장 https).
 * 설계: docs/DESIGN_slackbot_giip_issue_integration.md. 규칙: .agent/rules/39(AK 도출),40(생성 우선).
 *
 * 인증: 전용 이슈 엔드포인트는 SK 를 그대로 x-api-key 로 쓴다(익명, 실측 REPORT_giip_issue_api_test_20260708).
 * AK 도출(AdminGetAK) 안 함 — SK 를 AT(token) 자리에 넣으면 401(SK≠AT 혼동 금지, rule 39).
 */
const https = require('https');
const { URL } = require('url');
const accounts = require('./giip-accounts');

const AK_TTL_MS = 20 * 60 * 60 * 1000; // 20h
const akCache = new Map(); // login_id → { ak, csn, usn, fetchedAt }

function request(method, urlStr, { headers = {}, body = null, timeoutMs = 30000 } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const data = body == null ? null : typeof body === 'string' ? body : JSON.stringify(body);
    const opts = {
      method,
      hostname: u.hostname,
      port: u.port || 443,
      path: u.pathname + u.search,
      headers: { ...headers },
    };
    if (data) opts.headers['Content-Length'] = Buffer.byteLength(data);
    const req = https.request(opts, (res) => {
      let chunks = '';
      res.on('data', (d) => (chunks += d));
      res.on('end', () => {
        let parsed = chunks;
        try { parsed = JSON.parse(chunks); } catch { /* keep string */ }
        resolve({ status: res.statusCode, body: parsed, raw: chunks });
      });
    });
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => req.destroy(new Error('giip-api request timeout')));
    if (data) req.write(data);
    req.end();
  });
}

function form(params) {
  return Object.entries(params)
    .filter(([, v]) => v != null)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

/**
 * 인증 토큰 취득. rule 39 + 실측(REPORT_giip_issue_api_test_20260708):
 * 전용 이슈 엔드포인트(/api/giipIssues 등)는 **SK 를 그대로 x-api-key 로** 인증한다(익명).
 * AK 도출(AdminGetAK)은 불필요하며, SK 를 AdminGetAK 의 token(=AT 자리)으로 넣으면 401 이 난다
 * (SK≠AT 혼동 금지). 따라서 네트워크 호출 없이 SK 를 그대로 반환한다.
 */
async function getAK(account) {
  return { ak: account.sk, csn: account.csn ?? null, usn: null, fetchedAt: Date.now() };
}

/** giipIssues(전용함수) 호출. x-api-key=AK, 401 시 1회 강제 갱신 재시도. */
async function issueApi(account, method, { query = '', body = null } = {}) {
  const base = account.apiBase || accounts.apiBase();
  let ak = (await getAK(account)).ak;
  const url = `${base}/giipIssues${query}`;
  let res = await request(method, url, {
    headers: { 'x-api-key': ak, 'Content-Type': 'application/json' },
    body,
  });
  if (res.status === 401) {
    ak = (await getAK(account, { force: true })).ak;
    res = await request(method, url, {
      headers: { 'x-api-key': ak, 'Content-Type': 'application/json' },
      body,
    });
  }
  return res;
}

async function issueGet(account, isn) {
  const res = await issueApi(account, 'GET', { query: `?isn=${encodeURIComponent(isn)}` });
  if (res.status !== 200) throw new Error(`issueGet 실패: ${res.body?.error || res.status}`);
  return res.body?.issue || {};
}

async function issueList(account, { status = '', csn = '' } = {}) {
  const q = [];
  if (status) q.push(`status=${encodeURIComponent(status)}`);
  if (csn) q.push(`csn=${encodeURIComponent(csn)}`);
  const res = await issueApi(account, 'GET', { query: q.length ? `?${q.join('&')}` : '' });
  if (res.status !== 200) throw new Error(`issueList 실패: ${res.body?.error || res.status}`);
  return res.body?.issues || [];
}

async function issueCreate(account, { title, content, status = 'IN_PROGRESS', csn, target_lssn = null, agent_workflow = null }) {
  const res = await issueApi(account, 'POST', {
    body: { title, content, status, csn: csn ?? account.csn, target_lssn, agent_workflow },
  });
  if (res.status !== 200 || !res.body?.isn) throw new Error(`issueCreate 실패: ${res.body?.error || res.status}`);
  return res.body; // { success, isn, message }
}

/** PUT 은 전체 덮어쓰기 → read-modify-write 로 미지정 필드 보존(설계 §6). */
async function issueUpdate(account, fields) {
  const cur = await issueGet(account, fields.isn);
  const merged = {
    isn: fields.isn,
    title: fields.title ?? cur.title,
    content: fields.content ?? cur.content,
    status: fields.status ?? cur.status,
    csn: fields.csn ?? cur.CSn ?? cur.csn ?? account.csn,
    target_lssn: fields.target_lssn ?? cur.target_lssn ?? null,
    agent_workflow: fields.agent_workflow ?? cur.agent_workflow ?? null,
  };
  const res = await issueApi(account, 'PUT', { body: merged });
  if (res.status !== 200) throw new Error(`issueUpdate 실패: ${res.body?.error || res.status}`);
  return res.body;
}

async function issueComment(account, isn, content) {
  const base = account.apiBase || accounts.apiBase();
  let ak = (await getAK(account)).ak;
  const doPost = (token) =>
    request('POST', `${base}/giipIssueComments`, {
      headers: { 'x-api-key': token, 'Content-Type': 'application/json' },
      body: { isn: Number(isn), content },
    });
  let res = await doPost(ak);
  if (res.status === 401) { ak = (await getAK(account, { force: true })).ak; res = await doPost(ak); }
  if (res.status !== 200) throw new Error(`issueComment 실패: ${res.body?.error || res.status}`);
  return res.body;
}

/** 범용: 임의 giip API 를 giipApi 디스패처로 호출(text=Verb). */
async function apiCall(account, verb, jsondata = null) {
  const base = account.apiBase || accounts.apiBase();
  // SK 기반 디스패처(giipApiSk2). SK 를 x-api-key + token 으로 직접 인증(AK 도출 안 함).
  const params = { text: verb, token: account.sk, usertoken: account.sk };
  if (jsondata) params.jsondata = typeof jsondata === 'string' ? jsondata : JSON.stringify(jsondata);
  const res = await request('POST', `${base}/giipApiSk2`, {
    headers: { 'x-api-key': account.sk, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form(params),
  });
  return res.body;
}

module.exports = {
  getAK,
  issueGet,
  issueList,
  issueCreate,
  issueUpdate,
  issueComment,
  apiCall,
  _akCache: akCache,
};
