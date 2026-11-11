#!/usr/bin/env node
/**
 * test-liveness-ops-issue.mjs — lib/liveness-ops-issue.js 순수 규칙 회귀 테스트 (giip 4411 후속)
 *
 * 2026-11-11 중복 등록(#4870/#4874)의 근본 원인은 두 규칙이 어긋난 데 있었다:
 *   (A) **제목 매칭** — 중복 판정이 "같은 제목"을 어떻게认定하는가
 *   (B) **조회 대상 CSN** — 중복 조회·등록이 어느 CSN 을 보는가(서버 클램프 때문에 둘이 어긋날 수 있다)
 * 이 두 규칙은 네트워크 없이 순수 함수로 고정한다(오프라인 테스트).
 *
 * 실행: node scripts/gissue/tests/test-liveness-ops-issue.mjs
 */
import { createRequire } from 'node:module';
import assert from 'node:assert';

const require = createRequire(import.meta.url);
const { titleMatch, candidateCsns, resolveReadSk, toCsn, find, OPEN_STATUSES } = require('../lib/liveness-ops-issue.js');

const TITLE = '[OPS] gissue 처리 무소식 감지';
// 픽스처용 CSN — 실제 고객/프로젝트 CSN 이 아닌 가짜 값(rule 54: 이 레포에 실제 CSN 숫자를 넣지 않는다).
const HOME_CSN = 8100; // 등록 주체(default) 계정의 홈 CSN
const OPS_CSN = 9999;  // 알림 대상 CSN

// ── (A) 제목 매칭 ────────────────────────────────────────────────────────
// 같으면 매칭(중복 판정 대상)
assert.ok(titleMatch(TITLE, TITLE), '정확히 같은 제목은 매칭');
assert.ok(titleMatch(`  ${TITLE}  `, TITLE), '앞뒤 공백은 무시하고 매칭');
assert.ok(titleMatch(`${TITLE} [긴급]`, TITLE), '사람이 뒤에 덧붙인 말은 같은 제목으로 본다');
// 다르면 매칭 안 됨(다른 이슈를 같은 것으로 오인하지 않는다)
assert.ok(!titleMatch('[OPS] gissue 처리 무소식', TITLE), '앞이 다른 제목은 매칭 안 됨');
assert.ok(!titleMatch('gissue 처리 무소식 감지', TITLE), '앞부분만 같은 제목은 매칭 안 됨');
assert.ok(!titleMatch('[OPSX] gissue 처리 무소식 감지', TITLE), '한 글자 다른 제목은 매칭 안 됨');
assert.ok(!titleMatch('', TITLE), '빈 제목은 매칭 안 됨');
assert.ok(!titleMatch(TITLE, ''), '기준 제목이 비면 아무것도 매칭 안 됨');
assert.ok(!titleMatch(null, TITLE), 'null 제목은 매칭 안 됨');

// ── (B) 조회 대상 CSN ────────────────────────────────────────────────────
// 등록 주체가 OpsCsn 의 멤버면 이슈는 OpsCsN 에, 아니면 홈 CSN(=default 계정 csn) 에 놓인다.
// ⇒ 두 곳을 모두 조회해야 "이미 열려 있는 같은 제목 이슈"를 reliably 판정할 수 있다.
assert.deepStrictEqual(candidateCsns(OPS_CSN, HOME_CSN), [OPS_CSN, HOME_CSN], 'OpsCsn 과 홈 CSN 을 모두 조회');
assert.deepStrictEqual(candidateCsns(HOME_CSN, HOME_CSN), [HOME_CSN], '같은 CSN 은 중복 제거');
assert.deepStrictEqual(candidateCsns(OPS_CSN, OPS_CSN), [OPS_CSN], 'OpsCsn 과 홈 CSN 이 같으면 하나');
assert.deepStrictEqual(candidateCsns('', HOME_CSN), [HOME_CSN], 'OpsCsn 이 비면 홈 CSN 만');
assert.deepStrictEqual(candidateCsns(OPS_CSN, ''), [OPS_CSN], '홈 CSN 이 비면 OpsCsn 만');
assert.deepStrictEqual(candidateCsns('', ''), [], '둘 다 없으면 후보 없음');
assert.deepStrictEqual(candidateCsns('abc', HOME_CSN), [HOME_CSN], '숫자가 아닌 OpsCsn 은 버린다');
assert.deepStrictEqual(candidateCsns(OPS_CSN, 0), [OPS_CSN], '0 은 유효한 CSN 이 아니다');

// ── (B2) 조회용 SK 선택 ──────────────────────────────────────────────────
// 그 CSN 의 계정이 있으면 그것, 없으면 등록 주체(default) 계정의 SK 로 폴백(읽기 전용).
// (쓰기에는 폴백이 없다 — 인가 게이트가 "이슈의 cSn = SK 의 CSN" 을 요구한다.)
assert.strictEqual(resolveReadSk('sk-exact', 'sk-write'), 'sk-exact', '그 CSN 의 계정 SK 가 있으면 그것을 쓴다');
assert.strictEqual(resolveReadSk(null, 'sk-write'), 'sk-write', '계정이 없으면 등록 주체 SK 로 폴백(조회 전용)');
assert.strictEqual(resolveReadSk('', 'sk-write'), 'sk-write', '빈 문자열 계정 SK 도 폴백으로 간다');
assert.strictEqual(resolveReadSk(null, null), null, '어느 쪽에도 SK 가 없으면 조회 불가(null)');

// ── (C) 열림 상태 목록 ───────────────────────────────────────────────────
// DONE(종료된 에피소드)은 열려 있는 이슈가 아니다. TESTED 는 아직 열린 상태다.
assert.ok(OPEN_STATUSES.includes('PENDING') && OPEN_STATUSES.includes('IN_PROGRESS'), 'PENDING/IN_PROGRESS 포함');
assert.ok(OPEN_STATUSES.includes('TESTED'), 'TESTED 포함');
assert.ok(!OPEN_STATUSES.includes('DONE'), 'DONE 은 열린 이슈가 아니다');

// ── (C2) CSN 값 정규화 ────────────────────────────────────────────────────
// parseArgs 는 값이 없는 플래그를 true 로 만든다 → Number(true) === 1 이므로 CSN 1 이 후보에 들어갈 수 있다.
assert.strictEqual(toCsn(true), null, 'true(값 없는 플래그)는 CSN 이 아니다');
assert.strictEqual(toCsn(false), null, 'false 는 CSN 이 아니다');
assert.strictEqual(toCsn(8100), 8100, '숫자 CSN 은 그대로');
assert.strictEqual(toCsn('8100'), 8100, '숫자 문자열 CSN 은 숫자로');
assert.strictEqual(toCsn('abc'), null, '문자열 오타는 CSN 이 아니다');
assert.strictEqual(toCsn(0), null, '0 은 CSN 이 아니다');
assert.strictEqual(toCsn(-1), null, '음수는 CSN 이 아니다');
assert.deepStrictEqual(candidateCsns(true, HOME_CSN), [HOME_CSN], '값 없는 플래그(true)는 조회 후보에 들어가지 않는다');

// ── (D) find() 조회 흐름(네트워크 주입) ───────────────────────────────────
// 중복 등록 사고의 핵심 경로다 — 조회 후보 CSN · SK 선택 · 응답 cSn 가드 · 제목 매칭 · 실패 전파를 고정한다.
const requests = [];
const ROWS = {
  [OPS_CSN]: [{ isn: 5002, title: TITLE, cSn: OPS_CSN, regdate: '2026-11-10 22:00:00' }],
  [HOME_CSN]: [
    { isn: 5001, title: TITLE, cSn: HOME_CSN },              // 찾을 대상(홈 CSN — 클램프된 등록 결과)
    { isn: 5003, title: TITLE, cSn: 7777 },                  // 후보 밖 CSN → 버려야 한다
    { isn: 5004, title: '[OPS] 다른 제목', cSn: HOME_CSN },  // 제목 다름 → 제외
  ],
};
const fakeRequest = async (method, url, opts) => {
  requests.push({ method, url, apiKey: opts.apiKey });
  const csn = Number(new URL(url).searchParams.get('csn'));
  return { status: 200, text: '', json: { issues: ROWS[csn] || [] } };
};
const fakeAccounts = { resolve: () => ({ login_id: 'u', sk: 'sk-write', csn: HOME_CSN }) };
const noAccount = () => null;

const found = await find({ title: TITLE, opsCsn: OPS_CSN }, { request: fakeRequest, accounts: fakeAccounts, accountEntryForCsn: noAccount });
assert.deepStrictEqual(found.candidates, [OPS_CSN, HOME_CSN], '조회 후보 = OpsCsn + 홈 CSN');
assert.deepStrictEqual(found.issues.map((i) => i.isn), [5001, 5002], '후보 CSN 안의 같은 제목 이슈만 isn 오름차순으로 반환');
assert.ok(!found.issues.some((i) => i.isn === 5003), '후보 밖 CSN(cSn=7777) 이슈는 버린다 — 남의 CSN 에 손대지 않는다');
assert.ok(!found.issues.some((i) => i.isn === 5004), '제목이 다른 이슈는 제외한다');
assert.ok(requests.some((r) => r.url.includes(`csn=${OPS_CSN}`)), 'OpsCsn 을 조회한다');
assert.ok(requests.some((r) => r.url.includes(`csn=${HOME_CSN}`)), '홈 CSN 도 조회한다 — 클램프된 등록 결과를 봐야 한다');
assert.ok(requests.every((r) => r.apiKey === 'sk-write'), '계정 항목이 없는 CSN 조회는 등록 주체 SK 로 폴백(조회 전용)');
assert.strictEqual(found.issues[1].regdate, '2026-11-10 22:00:00', '회복 보고 기준 시각(regdate)을 함께 돌려준다');

// 그 CSN 의 계정이 있으면 그 계정 SK 를 쓴다(정확한 SK 우선).
requests.length = 0;
await find({ title: TITLE, opsCsn: OPS_CSN }, {
  request: fakeRequest, accounts: fakeAccounts,
  accountEntryForCsn: (csn) => (csn === OPS_CSN ? { sk: 'sk-ops' } : null),
});
assert.ok(requests.some((r) => r.apiKey === 'sk-ops'), '그 CSN 의 계정 SK 가 있으면 그것으로 조회한다');
assert.ok(requests.some((r) => r.apiKey === 'sk-write'), '계정이 없는 후보는 등록 주체 SK 로 조회한다');

// 조회 실패(비 200)는 전체 조회 실패 → 호출부는 등록하지 않는다(중복 등록 방지 우선).
await assert.rejects(
  () => find({ title: TITLE, opsCsn: OPS_CSN }, { request: async () => ({ status: 500, text: 'boom', json: null }), accounts: fakeAccounts, accountEntryForCsn: noAccount }),
  /issueList/,
  '조회 실패는 예외로 전파된다 — 호출부가 등록하지 않도록'
);

// 홈 CSN 을 모르면 조회 후보가 불완전하다 → 등록하지 않는다(안전 쪽).
await assert.rejects(
  () => find({ title: TITLE, opsCsn: OPS_CSN }, { request: fakeRequest, accounts: { resolve: () => ({ sk: 'sk-write', csn: 0 }) }, accountEntryForCsn: noAccount }),
  /홈 CSN/,
  'default 계정에 csn 이 없으면 조회 대신 명확히 실패한다'
);

console.log('ALL PASS (test-liveness-ops-issue.mjs)');
