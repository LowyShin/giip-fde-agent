// node --test slack-bot/tests/no-pr-report.test.js  (LLM·네트워크 없음, giip 4231)
const test = require('node:test');
const assert = require('node:assert');
const nrr = require('../no-pr-report');
const { t } = require('../i18n-ui');

const REQ = '상태를 점검해 주세요.\n- 서비스 A 가동 여부\n- 서비스 B 로그 오류 건수\n1. 결과 요약';

test('독립 코멘트의 첫 줄은 [NO-PR-REASON] 이고 사유가 1줄 이상 있다 (게이트 계약)', () => {
  for (const lang of ['ko', 'en', 'ja']) {
    const body = nrr.buildNoPrReasonComment({ requestText: REQ, resultContent: '모두 정상', taskId: 'giip-1' }, t(lang, 'noPrReasonLabels'));
    const lines = body.split('\n');
    assert.strictEqual(lines[0], '[NO-PR-REASON]');
    assert.ok(body.slice(lines[0].length).trim().length > 0);
    assert.ok(body.includes('모두 정상'));
  }
});

test('요청 항목이 번호로 매핑되고 결론·최종 판정이 포함된다', () => {
  const body = nrr.buildNoPrReasonComment({ requestText: REQ, resultContent: '결론 본문' }, t('ko', 'noPrReasonLabels'));
  assert.ok(body.includes('1. 서비스 A 가동 여부 ->'));
  assert.ok(body.includes('2. 서비스 B 로그 오류 건수 ->'));
  assert.ok(body.includes('## 실행자 결론\n결론 본문'));
  assert.ok(body.includes('## 최종 판정'));
});

test('항목 목록이 없는 단일 요청은 fallback 문구', () => {
  const body = nrr.buildNoPrReasonComment({ requestText: '단일 질문', resultContent: 'x' }, t('en', 'noPrReasonLabels'));
  assert.ok(body.includes('single ask'));
});

test('결론은 4000자로 잘린다', () => {
  const body = nrr.buildNoPrReasonComment({ requestText: 'r', resultContent: 'a'.repeat(5000) }, t('ko', 'noPrReasonLabels'));
  assert.ok(body.includes('(1000자 생략)'));
  assert.strictEqual(nrr.buildConclusionBlock('').length, 0);
  assert.ok(nrr.buildConclusionBlock('결론', t('ko', 'conclusionHeading')).startsWith('\n\n## 실행자 결론\n결론'));
});

test('isReportOnlyCompletion: PR 없고 결론 있을 때만 true (코드 변경 태스크는 회귀 없음)', () => {
  assert.strictEqual(nrr.isReportOnlyCompletion([], '결론'), true);
  assert.strictEqual(nrr.isReportOnlyCompletion([], '  '), false);
  assert.strictEqual(nrr.isReportOnlyCompletion(['https://github.com/o/r/pull/1'], '결론'), false);
});
