// node --test slack-bot/tests/intent.test.js  (LLM 을 호출하지 않는다)
const test = require('node:test');
const assert = require('node:assert');
const { isForceTaskCmd, isConfirmationQuery } = require('../intent');

// 라우팅과 동일한 안전 순서: force-task 먼저, 아니면 결정적 question.
const route = t => (isForceTaskCmd(t) ? 'task' : isConfirmationQuery(t) ? 'question' : 'llm');

const QUESTIONS = [
  '지금 폴더 구조 재조정 했거든 123 의 처리 결과 파일의 github url찾아서 보여줘.',
  '123 처리 결과 알려줘',
  '123 의 처리 결과 파일의 github url 알려줘',
  '지금 배포 상태 어때?',
  '배포 상태 확인 가능해?',
];
const TASKS = [
  'azure-cost 페이지에 이번 달 예상 금액을 계산해서 보여줘',
  '사양서 만들어 저장해줘',
  '문서로 저장해줘',
  '이슈 등록해줘',
  '태스크 등록 foo 수정',
  '구현해줘',
  '찾아서 파일로 저장해줘',
  '123 처리 결과 파일 경로 찾아서 파일로 저장해줘',
];

for (const q of QUESTIONS) {
  test(`question: ${q}`, () => {
    assert.strictEqual(route(q), 'question');
  });
}
for (const t of TASKS) {
  test(`task-not-question: ${t}`, () => {
    assert.strictEqual(isConfirmationQuery(t) && !isForceTaskCmd(t), false);
  });
}
