#!/usr/bin/env node
'use strict';
/**
 * get-github-configs.js — CSN 의 GitHub Actions 설정(repo+PAT) 스코프드 조회 (giip 5783)
 *
 * 배경: 인스턴스 초기 설정에서 그 CSN 으로 콘솔 GitHub Actions 에 등록된 repo 를
 * 전부 내려받으려면, 목록과 PAT 를 프로그램으로 읽을 경로가 필요하다. 읽기 계약은
 * giip 5782(스코프드 조회 API)가 정본이고, 패턴은 giip 5665(CsnMapping)와 같다:
 *
 *   GET {apiBase}/giipGithubConfigs?csn=<n>   header: x-api-key: <그 CSN 의 SK>
 *   → 그 CSN 의 Active 설정만 [{ name, owner, repo, pat }]
 *
 * 사용: node get-github-configs.js <apiBase> <sk> <csn>
 *   조회가 끝까지 수행되면(설정 있음/없음 포함) stdout 에 JSON 1줄 + exit 0.
 *   전송/해석 오류면 stderr 에 사유 + exit 1.
 *   ★ stdout 의 JSON 에는 PAT 가 포함된다 — 호출자는 이 출력을 로그에 남기지 않는다.
 *
 * 스코프 방어: 응답에 csn 이 실려 오면 요청 csn 과 대조하고, 어긋나면 채택하지
 * 않는다(scope_mismatch). 큐의 cSn 대조(giip 4116)와 같은 원칙이다.
 */
const https = require('https');

function truthyActive(v) {
  if (v === undefined || v === null) return true; // 필드가 없으면 서버가 이미 Active 만 골라 보낸 것으로 본다
  return v === true || v === 1 || v === '1' || String(v).toLowerCase() === 'true';
}

function pickRow(raw) {
  if (!raw || typeof raw !== 'object') return null;
  let owner = raw.owner || raw.repoOwner || raw.ggcRepoOwner || null;
  let repo = raw.repo || raw.repoName || raw.ggcRepoName || null;
  const slug = raw.slug || raw.repository || raw.ggcRepository || null;
  if ((!owner || !repo) && slug && String(slug).includes('/')) {
    const parts = String(slug).split('/');
    owner = owner || parts[0];
    repo = repo || parts.slice(1).join('/');
  }
  if (!owner || !repo) return null;
  if (!truthyActive(raw.active !== undefined ? raw.active : (raw.ggcActive !== undefined ? raw.ggcActive : raw.isActive))) return null;
  return {
    name: raw.name || raw.configName || raw.ggcName || `${owner}/${repo}`,
    owner: String(owner),
    repo: String(repo),
    slug: `${owner}/${repo}`,
    pat: raw.pat || raw.token || raw.ggcPat || '',
  };
}

// 순수 함수(테스트 대상): HTTP 상태와 본문 문자열 → 판정 객체.
function parseGithubConfigsResponse(statusCode, bodyText, requestedCsn) {
  if (statusCode === 403) return { ok: false, status: 'scope_mismatch', configs: [] };
  if (statusCode === 404) return { ok: true, status: 'not_found', configs: [] };
  if (statusCode !== 200) return { ok: false, status: `http_${statusCode}`, configs: [] };
  let parsed;
  try { parsed = JSON.parse(bodyText); } catch { return { ok: false, status: 'parse_error', configs: [] }; }
  let rows = parsed;
  if (parsed && !Array.isArray(parsed)) {
    const csnField = parsed.csn !== undefined ? parsed.csn : parsed.ggcCsn;
    if (csnField !== undefined && csnField !== null && String(csnField) !== String(requestedCsn)) {
      return { ok: false, status: 'scope_mismatch', configs: [] };
    }
    rows = parsed.configs || parsed.rows || parsed.data || [];
  }
  if (!Array.isArray(rows)) return { ok: false, status: 'parse_error', configs: [] };
  const configs = [];
  for (const raw of rows) {
    const rowCsn = raw && (raw.csn !== undefined ? raw.csn : raw.ggcCsn);
    if (rowCsn !== undefined && rowCsn !== null && String(rowCsn) !== String(requestedCsn)) {
      return { ok: false, status: 'scope_mismatch', configs: [] };
    }
    const picked = pickRow(raw);
    if (picked) configs.push(picked);
  }
  return { ok: true, status: configs.length > 0 ? 'found' : 'empty', configs };
}

function main() {
  const [, , apiBase, sk, csn] = process.argv;
  if (!apiBase || !sk || !csn) {
    process.stderr.write('usage: node get-github-configs.js <apiBase> <sk> <csn>\n');
    process.exit(2);
  }
  const url = new URL(`${String(apiBase).replace(/\/+$/, '')}/giipGithubConfigs`);
  url.searchParams.set('csn', String(csn));
  const req = https.request(url, { method: 'GET', headers: { 'x-api-key': sk } }, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => {
      const result = parseGithubConfigsResponse(res.statusCode, Buffer.concat(chunks).toString('utf-8'), csn);
      if (!result.ok) {
        process.stderr.write(`get-github-configs: ${result.status}\n`);
        process.exit(1);
      }
      process.stdout.write(JSON.stringify(result) + '\n');
    });
  });
  req.on('error', (e) => { process.stderr.write(`get-github-configs: ${e.message}\n`); process.exit(1); });
  req.end();
}

if (require.main === module) main();

module.exports = { parseGithubConfigsResponse };
