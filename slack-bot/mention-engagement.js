'use strict';
// 메시지 한 건이 "봇에게 하는 말"인지 판정하는 순수 함수 (handlers.processMessage 에서 분리, 동작 불변).
// 외부 상태(Slack 설정·태스크 상태 파일)를 인자로 주입받으므로 단위 테스트가 가능하다.

/**
 * @param {string} text  Slack 원문 (멘션 토큰 <@U…> 포함)
 * @param {object} deps
 * @param {string} [deps.botUserId]               봇 자신의 user id
 * @param {(text:string)=>boolean} deps.hasOtherBotMention  OTHER_BOT_IDS allowlist 판정
 * @param {()=>boolean} deps.isActiveTaskThread   활성(pending/running) 태스크 스레드 여부(필요할 때만 호출)
 * @returns {{mentionsBot:boolean, mentionsOtherBot:boolean, mentionsOtherHuman:boolean, isTaskReply:boolean, engage:boolean}}
 */
function classifyMentions(text, deps) {
  const mentionsBot = !!(deps.botUserId && text.includes(`<@${deps.botUserId}>`));
  const mentionsOtherBot = !mentionsBot && !!deps.hasOtherBotMention(text);
  // giip 4045 결함 B: 봇/등록된 다른 봇이 아닌 "다른 사람"을 명시적으로 멘션한 메시지는
  // 그 사람에게 보내는 것이므로 활성 태스크 스레드 자동 개입(isTaskReply)을 억제한다.
  const mentionsOtherHuman = !mentionsBot && !mentionsOtherBot && /<@[A-Z0-9]+>/.test(text);
  const isTaskReply = !mentionsOtherHuman && !!deps.isActiveTaskThread();
  return { mentionsBot, mentionsOtherBot, mentionsOtherHuman, isTaskReply, engage: mentionsBot || mentionsOtherBot || isTaskReply };
}

module.exports = { classifyMentions };
