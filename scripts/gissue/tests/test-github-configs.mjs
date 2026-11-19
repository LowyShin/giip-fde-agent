// test-github-configs.mjs — lib/get-github-configs.js 의 응답 해석 회귀 테스트
// 실행: node scripts/gissue/tests/test-github-configs.mjs
// 네트워크·자격증명을 건드리지 않는다 — 순수 판정 parseGithubConfigsResponse 만 검증한다.
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const { parseGithubConfigsResponse } = require(path.join(here, '..', 'lib', 'get-github-configs.js'));

let pass = 0, fail = 0;
function eq(actual, expected, name) {
  if (String(actual) === String(expected)) { pass++; console.log(`  PASS: ${name}`); }
  else { fail++; console.log(`  FAIL: ${name} (기대=${expected} 실제=${actual})`); }
}

console.log('== 정상 응답 ==');
let r = parseGithubConfigsResponse(200, JSON.stringify([
  { name: 'backend', owner: 'LowyShin', repo: 'giipfaw', pat: 'P1', active: true },
  { name: 'front', owner: 'SHINSEMA', repo: 'giipv3', pat: 'P2' },
]), '47');
eq(r.ok, true, '200 배열 응답 ok');
eq(r.configs.length, 2, '설정 2건 채택');
eq(r.configs[0].slug, 'LowyShin/giipfaw', 'slug 조합');
eq(r.configs[0].pat, 'P1', 'PAT 전달(호출자 내부용)');

console.log('== Active 필터와 래핑 ==');
r = parseGithubConfigsResponse(200, JSON.stringify({ configs: [
  { name: 'off', owner: 'a', repo: 'b', pat: 'P', active: false },
  { slug: 'x/y', pat: 'P3' },
] }), '47');
eq(r.configs.length, 1, '비활성 설정은 제외');
eq(r.configs[0].slug, 'x/y', 'slug 단독 필드도 해석');

console.log('== 스코프 방어 ==');
r = parseGithubConfigsResponse(403, '', '47');
eq(r.status, 'scope_mismatch', '403 은 scope_mismatch');
r = parseGithubConfigsResponse(200, JSON.stringify({ csn: 33, configs: [{ owner: 'a', repo: 'b' }] }), '47');
eq(r.ok, false, '응답 csn 불일치는 채택 거부');
eq(r.status, 'scope_mismatch', '불일치 상태 표기');
r = parseGithubConfigsResponse(200, JSON.stringify([{ csn: 70424, owner: 'a', repo: 'b' }]), '47');
eq(r.ok, false, '행 단위 csn 불일치도 거부');

console.log('== 빈 목록·미배포·오류 ==');
r = parseGithubConfigsResponse(200, '[]', '47');
eq(r.status, 'empty', '빈 배열은 empty');
r = parseGithubConfigsResponse(404, '', '47');
eq(r.ok, true, '404 는 조회 완료로 취급');
eq(r.status, 'not_found', '404 상태 표기');
r = parseGithubConfigsResponse(500, '', '47');
eq(r.ok, false, '500 은 실패');
r = parseGithubConfigsResponse(200, '{broken', '47');
eq(r.status, 'parse_error', '깨진 JSON 은 parse_error');

console.log(`\n결과: PASS=${pass} FAIL=${fail}`);
process.exit(fail > 0 ? 1 : 0);
