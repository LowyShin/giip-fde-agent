// 자가 재시작(self-heal) 실행 증거용 자식 프로세스 (giip #5141).
//
// 이 파일은 `slack-bot/index.js` 의 `dieAndRestart` 2줄을 그대로 옮긴 것이다.
//   console.error(`[Bot] self-heal: ${why}. Exiting so pm2 restarts.`);
//   process.exit(1);
// index.js 는 `require.main === module` 일 때만 main() 을 실행하고 module.exports 가 없어서
// 그대로 가져올 수 없다. 그래서 "무수신 감지 → 로그 → exit(1)" 을 실제 프로세스로 실행해
// pm2 가 재시작할 수 있는 종료 코드(=1)와 로그를 확인한다.
//
// 사용: node slack-bot/tests/fixtures/inbound-idle-selfheal-child.js
// 기대: exit code 1 + stderr 에 "[Bot] self-heal: no inbound frames ..." + "Exiting so pm2 restarts."
'use strict';

const { EventEmitter } = require('node:events');
const { attachInboundIdleWatchdog } = require('../../inbound-idle-watchdog');

// index.js: dieAndRestart 와 동일
const dieAndRestart = (why) => {
  console.error(`[Bot] self-heal: ${why}. Exiting so pm2 restarts.`);
  process.exit(1);
};

let clockNow = Date.now();
const clock = { now: () => clockNow };

const socketClient = new EventEmitter();

const watchdog = attachInboundIdleWatchdog({
  socketClient,
  // Slack Web API stand-in — 네트워크 없음.
  apiGet: async (method) => {
    if (method === 'auth.test') return { ok: true, user_id: 'U_BOT' };
    if (method === 'conversations.history') {
      // 마지막 인바운드 프레임 이후 사용자가 보낸 멘션 메시지 (= 우리가 받아야 했던 이벤트)
      return {
        ok: true,
        messages: [{ ts: String((clockNow + 60_000) / 1000), user: 'U_HUMAN', text: '<@U_BOT> !help' }],
      };
    }
    return { ok: false, error: 'unknown_method' };
  },
  botUserId: () => 'U_BOT',
  selfBotId: () => 'B_BOT',
  allowedChannelIds: () => ['C_TEST'],
  idleMs: 1000,
  probeIntervalMs: 1000,
  now: clock.now,
  onSuspect: dieAndRestart,
});

(async () => {
  // 소켓 연결 → 인바운드 프레임 1건(연결 직후 hello) 이후로 더 이상 프레임이 오지 않는 상황
  socketClient.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socketClient.emit('connected');
  clockNow += 5000; // 무수신 임계(1000ms) 초과
  await watchdog.check();
  // 여기까지 오면 자가 재시작이 일어나지 않은 것 → 실패
  console.error('[Bot] self-heal 이 발동하지 않았습니다 — 감지 실패');
  process.exit(0);
})();
