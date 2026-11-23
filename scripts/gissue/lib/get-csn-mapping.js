#!/usr/bin/env node
/**
 * CSN 1건의 GIIP 프로젝트 매핑(tGissueCsnMapping)을 giipfaw API로 조회한다.
 *
 * 배경: 러너는 이슈의 작업 환경을 로컬 csn-projects.json에서만 결정해 왔고, 항목이
 * 없거나 placeholder인 CSN은 GIIP 쪽 정본 매핑을 확인할 길이 없었다(빈 폴더에서
 * 세션이 시작하는 사고의 구조적 원인). 이 헬퍼가 그 조회 경로다. 판정·캐시 반영은
 * lib/csn-mapping.ps1이 맡고, 이 파일은 전송+응답 해석만 한다.
 *
 * 엔드포인트 계약 (giip #5665 의 SP·엔드포인트가 이 계약으로 구현된다):
 *   GET {apiBase}/giipGissueCsnMapping?csn=<n>   헤더 x-api-key: <그 CSN의 SK>
 *   → AK에서 도출되는 CSN과 요청 CSN이 일치할 때만 그 CSN의 행 1건을 돌려준다.
 *     { csn, projectName, workdir, enabled } (필드명은 gcm* 접두사가 있어도 허용)
 *   → 불일치/없음: 403/404. sysadmin 전용 전체 반환 List와는 별개 경로다.
 *
 * 사용: node get-csn-mapping.js <apiBase> <sk> <csn>
 * stdout: JSON 1건 —
 *   { "found": true,  "csn": <n>, "projectName": "...", "workdir": "...", "enabled": true|false }
 *   { "found": false, "reason": "not_found" | "scope_mismatch" | "invalid_row" | "error", "detail": "..." }
 * 종료코드: 조회가 끝났으면(found 여부 무관) 0, 전송/파싱 실패면 1.
 *   호출측은 어느 경우든 fail-soft로 다룬다(폴백 불가 = 현행 동작 유지).
 *
 * 응답의 csn이 요청 csn과 다르면 절대 신뢰하지 않는다(scope_mismatch) — 큐 조회의
 * cSn 대조(giip 4116)와 같은 방어다.
 *
 * [giip 4116 · 2026-11-23 실측] 라이브 응답 형식은 **배열 컨테이너**다:
 *   { "message":"OK", "ok":true, "count":1,
 *     "mapping": [ { "gcmCsn":47, "gcmEnabled":true, "gcmProjectName":"giipprj", "gcmWorkdir":"..." } ] }
 *   (단일 행 객체 · rows/data 컨테이너도 허용한다 — 아래 selectMappingRows 가 정규화한다.)
 */
const https = require('https');
const http = require('http');
const { URL } = require('url');

// 응답 해석(순수 함수 — 회귀 테스트가 전송 없이 검증한다).
// 반환: { found, reason?, row? }  row = { csn, projectName, workdir, enabled }
//
// [giip 4116] 실측 반영(2026-11-23): 라이브 엔드포인트는 행을 **배열**로 돌려준다.
//   { "message":"OK", "ok":true, "count":1,
//     "mapping": [ { "gcmCsn":47, "gcmEnabled":true, "gcmProjectName":"giipprj", "gcmWorkdir":"..." } ] }
// 이전 해석은 j.mapping 을 "한 행 객체"로 가정했다 → 배열이면 row.csn 이 undefined 가 되어
//   전부 scope_mismatch 로 오판되었다. 결과적으로 **정본에 등록된 csn 을 미매핑으로 오인**했고,
//   그 오판이 미매핑 CSN 가드의 거짓 "담당 배포 없음" 게시로 이어질 뻔했다.
// → 컨테이너가 배열이면 그중 요청 csn 과 일치하는 행만 고른다(일치 행이 없으면 scope_mismatch).
function selectMappingRows(body) {
  let container = body;
  for (const key of ['mapping', 'rows', 'data', 'row']) {
    if (body && Object.prototype.hasOwnProperty.call(body, key)) { container = body[key]; break; }
  }
  if (Array.isArray(container)) return container.filter(r => r && typeof r === 'object');
  if (container && typeof container === 'object') return [container];
  return [];
}

function parseMappingResponse(statusCode, bodyText, requestedCsn) {
  if (statusCode === 404) return { found: false, reason: 'not_found' };
  if (statusCode === 403) return { found: false, reason: 'scope_mismatch' };
  if (statusCode !== 200) return { found: false, reason: 'error', detail: `http_${statusCode}` };
  let j;
  try { j = JSON.parse(bodyText); } catch (e) { return { found: false, reason: 'error', detail: 'bad_json' }; }
  const rows = selectMappingRows(j);
  if (rows.length === 0) return { found: false, reason: 'not_found' };
  // 요청 csn 과 일치하는 행만 신뢰한다(타 csn 행을 절대 채택하지 않음).
  const matched = rows.filter(r => {
    const c = r.csn != null ? r.csn : r.gcmCsn;
    return c != null && String(c) === String(requestedCsn);
  });
  if (matched.length === 0) {
    const first = rows[0];
    const c = first.csn != null ? first.csn : first.gcmCsn;
    return { found: false, reason: 'scope_mismatch', detail: `response_csn=${c}` };
  }
  const row = matched[0];
  const csnVal = row.csn != null ? row.csn : row.gcmCsn;
  if (csnVal == null || String(csnVal) !== String(requestedCsn)) {
    return { found: false, reason: 'scope_mismatch', detail: `response_csn=${csnVal}` };
  }
  const projectName = row.projectName != null ? row.projectName : row.gcmProjectName;
  const workdir = row.workdir != null ? row.workdir : row.gcmWorkdir;
  const enabledRaw = row.enabled != null ? row.enabled : row.gcmEnabled;
  if (!workdir) return { found: false, reason: 'invalid_row', detail: 'workdir_empty' };
  const enabled = enabledRaw === true || enabledRaw === 1 || enabledRaw === '1' ||
    String(enabledRaw).toLowerCase() === 'true';
  return {
    found: true,
    row: {
      csn: Number(csnVal),
      projectName: projectName != null ? String(projectName) : '',
      workdir: String(workdir),
      enabled,
    },
  };
}

function fetchMapping(apiBase, sk, csn) {
  return new Promise((resolve) => {
    let u;
    try {
      u = new URL(`${apiBase}/giipGissueCsnMapping?csn=${encodeURIComponent(csn)}`);
    } catch (e) {
      resolve({ found: false, reason: 'error', detail: 'bad_url' });
      return;
    }
    const lib = u.protocol === 'http:' ? http : https;
    const req = lib.get(u, { headers: { 'x-api-key': sk }, timeout: 20000 }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => resolve(parseMappingResponse(res.statusCode, data, csn)));
    });
    req.on('timeout', () => { req.destroy(); resolve({ found: false, reason: 'error', detail: 'timeout' }); });
    req.on('error', (e) => resolve({ found: false, reason: 'error', detail: String(e && e.message || e) }));
  });
}

async function main() {
  const [, , apiBase, sk, csn] = process.argv;
  if (!apiBase || !sk || !csn || !/^\d+$/.test(String(csn))) {
    console.error('사용법: node get-csn-mapping.js <apiBase> <sk> <csn>');
    process.exit(2);
  }
  const r = await fetchMapping(apiBase, sk, csn);
  if (r.found) {
    console.log(JSON.stringify({ found: true, ...r.row }));
    process.exit(0);
  }
  console.log(JSON.stringify({ found: false, reason: r.reason || 'error', detail: r.detail || '' }));
  process.exit(r.reason === 'error' ? 1 : 0);
}

if (require.main === module) { main(); }

module.exports = { parseMappingResponse };
