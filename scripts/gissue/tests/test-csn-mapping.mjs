// test-csn-mapping.mjs — lib/get-csn-mapping.js 의 응답 해석 회귀 테스트 (giip 5664)
// 실행: node scripts/gissue/tests/test-csn-mapping.mjs
// 네트워크를 건드리지 않는다 — parseMappingResponse 순수 함수와 엔드포인트 계약 문자열만 검증한다.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const { parseMappingResponse } = require(path.join(here, '..', 'lib', 'get-csn-mapping.js'));

let pass = 0, fail = 0;
function eq(actual, expected, name) {
  if (String(actual) === String(expected)) { pass++; console.log(`  PASS: ${name}`); }
  else { fail++; console.log(`  FAIL: ${name} (기대=${expected} 실제=${actual})`); }
}
function ok(cond, name) { eq(!!cond, true, name); }

console.log('== 200 정상 행 ==');
let r = parseMappingResponse(200, JSON.stringify({ csn: 70500, projectName: 'proj-sample', workdir: 'C:/proj-sample', enabled: true }), '70500');
ok(r.found, 'camelCase 행 found');
eq(r.row.projectName, 'proj-sample', 'projectName 해석');
eq(r.row.workdir, 'C:/proj-sample', 'workdir 해석');
eq(r.row.enabled, true, 'enabled true');
r = parseMappingResponse(200, JSON.stringify({ gcmCsn: '47', gcmProjectName: 'giipprj', gcmWorkdir: 'C:/giipprj', gcmEnabled: 1 }), '47');
ok(r.found, 'gcm 접두사 행도 found');
eq(r.row.enabled, true, 'gcmEnabled 1 → true');
r = parseMappingResponse(200, JSON.stringify({ mapping: { csn: 33, projectName: 'lowy', workdir: 'C:/lowy', enabled: 'false' } }), '33');
ok(r.found, '래핑된(mapping) 행 found');
eq(r.row.enabled, false, "enabled 'false' → false");

console.log('== 스코프/부재/이상 행 ==');
r = parseMappingResponse(200, JSON.stringify({ csn: 47, projectName: 'x', workdir: 'C:/x', enabled: true }), '70500');
eq(r.found, false, '응답 csn 불일치는 found 아님');
eq(r.reason, 'scope_mismatch', '불일치 사유 scope_mismatch (타 CSN 행을 절대 채택하지 않음)');
r = parseMappingResponse(200, JSON.stringify({ csn: 47, projectName: 'x', workdir: '', enabled: true }), '47');
eq(r.reason, 'invalid_row', 'workdir 빈 행은 invalid_row');
r = parseMappingResponse(404, '', '47');
eq(r.reason, 'not_found', '404 → not_found');
r = parseMappingResponse(403, '', '47');
eq(r.reason, 'scope_mismatch', '403 → scope_mismatch');
r = parseMappingResponse(500, 'err', '47');
eq(r.reason, 'error', '500 → error');
r = parseMappingResponse(200, 'not-json', '47');
eq(r.reason, 'error', '깨진 JSON → error');

console.log('== 엔드포인트 계약 커플링 ==');
const src = fs.readFileSync(path.join(here, '..', 'lib', 'get-csn-mapping.js'), 'utf-8');
ok(src.includes('/giipGissueCsnMapping'), '헬퍼가 계약 경로 /giipGissueCsnMapping 을 호출');
ok(src.includes("'x-api-key'"), 'x-api-key 헤더로 SK 인증');

console.log(`\n결과: PASS=${pass} FAIL=${fail}`);
process.exit(fail > 0 ? 1 : 0);
