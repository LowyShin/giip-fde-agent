// giip 4045 결함 B 회귀 테스트 — 실행: node slack-bot/tools/test-mention-engagement.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { classifyMentions } = require('../mention-engagement');

const BOT = 'UBOT0001';
const OTHER_BOT = 'UBOT0002';
const HUMAN = 'UHUMAN01';
const mk = (text, active) => classifyMentions(text, {
  botUserId: BOT,
  hasOtherBotMention: t => t.includes(`<@${OTHER_BOT}>`),
  isActiveTaskThread: () => active,
});

test('활성 스레드에서 다른 사람만 멘션하면 개입하지 않는다 (결함 B)', () => {
  const r = mk(`<@${HUMAN}> 확인되면 클로즈 부탁드립니다`, true);
  assert.equal(r.mentionsOtherHuman, true);
  assert.equal(r.isTaskReply, false);
  assert.equal(r.engage, false);
});
test('봇 멘션은 항상 개입한다', () => assert.equal(mk(`<@${BOT}> 해줘`, false).engage, true));
test('등록된 다른 봇 멘션은 개입한다', () => assert.equal(mk(`<@${OTHER_BOT}> 안녕`, false).engage, true));
test('사람 + 봇 동시 멘션은 개입한다', () => assert.equal(mk(`<@${HUMAN}> <@${BOT}> 봐줘`, true).engage, true));
test('멘션 없는 활성 스레드 답글은 개입한다', () => {
  const r = mk('계속 진행해줘', true);
  assert.equal(r.isTaskReply, true);
  assert.equal(r.engage, true);
});
test('비활성 스레드의 무멘션 메시지는 개입하지 않는다', () => assert.equal(mk('잡담', false).engage, false));
test('다른 사람 멘션이면 활성 스레드 조회 자체를 하지 않는다', () => {
  let called = 0;
  classifyMentions(`<@${HUMAN}> hi`, { botUserId: BOT, hasOtherBotMention: () => false, isActiveTaskThread: () => { called++; return true; } });
  assert.equal(called, 0);
});
