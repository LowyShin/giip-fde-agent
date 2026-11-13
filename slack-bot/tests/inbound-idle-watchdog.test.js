// node --test slack-bot/tests/inbound-idle-watchdog.test.js
//
// LLM·네트워크 없음 — Slack Web API 는 주입한 fake 로 대체한다.
// 대상: slack-bot 의 "소켓은 연결됐는데 인바운드 프레임이 한 건도 안 오는" (무수신) 감지·자가복구.
//
// 배경(giip #5141, 2026-11-13):
//   기존 self-heal 워치독은 (1) 재연결 실패 (2) ack 연속 실패 만 감지했다.
//   소켓이 connected 인데 이벤트 프레임이 오지 않는 상태는 어떤 타이머도 울리지 않아
//   pm2 가 프로세스 생존만 보고 "정상"으로 취급했고, 봇은 무한 무응답이 되었다.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { EventEmitter } = require('node:events');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const {
  createInboundIdleWatchdog,
  attachInboundIdleWatchdog,
  DEFAULT_IDLE_MS,
  DEFAULT_PROBE_INTERVAL_MS,
} = require('../inbound-idle-watchdog');
const { createInboundProbe } = require('../inbound-probe');

// ── 공통 픽스처 ────────────────────────────────────────────────────────────────
const BOT_USER = 'U_BOT';
const BOT_ID = 'B_BOT';

function fakeClock(start = 1_700_000_000_000) {
  let t = start;
  return {
    now: () => t,
    advance: (ms) => { t += ms; return t; },
    set: (ms) => { t = ms; },
  };
}

/** 인바운드 프레임 0건 + "봇이 반드시 이벤트를 받았어야 하는" 메시지가 도착한 상황. */
function trafficApiGet(clock, { channelType = 'channel', text = '<@U_BOT> !help' } = {}) {
  return async (method, params) => {
    if (method === 'auth.test') return { ok: true, user_id: BOT_USER };
    if (method === 'conversations.history') {
      const ts = String((clock.now() + 60_000) / 1000); // 마지막 수신 이후 도착한 메시지
      return {
        ok: true,
        messages: [{ ts, user: 'U_HUMAN', text, channel_type: channelType, ...(params && params.channel ? {} : {}) }],
      };
    }
    return { ok: false, error: 'unknown_method' };
  };
}

function makeWatchdog(overrides = {}) {
  const clock = overrides.clock || fakeClock();
  const suspects = [];
  const idles = [];
  const logs = [];
  const watchdog = createInboundIdleWatchdog({
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    log: (level, msg) => logs.push([level, msg]),
    onIdle: (info) => idles.push(info),
    onSuspect: (why) => suspects.push(why),
    ...overrides,
  });
  return { clock, watchdog, suspects, idles, logs };
}

// ── 1. 워치독: 감지 판정 ──────────────────────────────────────────────────────
test('무수신 임계 초과 + 최근 트래픽 존재 → 자가 재시작(onSuspect) 사유에 "no inbound" 가 들어간다', async () => {
  const { clock, watchdog, suspects } = makeWatchdog({
    probe: async () => ({ apiOk: true, hasTraffic: true, detail: '채널 C1 에 메시지 도착' }),
  });
  watchdog.noteConnected();
  watchdog.noteInbound();
  clock.advance(1500); // 임계(1000ms) 초과

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'suspect');
  assert.strictEqual(suspects.length, 1);
  assert.match(suspects[0], /no inbound frames/);
  assert.match(suspects[0], /socket silently stuck/);
});

test('무수신 임계 초과 + 트래픽 없음(진짜 무트래픽 시간대) → 자가 재시작하지 않는다(오탐 방지)', async () => {
  const { clock, watchdog, suspects, idles } = makeWatchdog({
    probe: async () => ({ apiOk: true, hasTraffic: false, detail: '대조 1개 채널 — 수신 대상 메시지 없음' }),
  });
  watchdog.noteConnected();
  watchdog.noteInbound();
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'idle');
  assert.strictEqual(suspects.length, 0);
  assert.strictEqual(idles.length, 1);
});

test('무수신 임계 초과 + Web API(auth.test) 응답 불가 → 자가 재시작한다', async () => {
  const { clock, watchdog, suspects } = makeWatchdog({
    probe: async () => ({ apiOk: false, hasTraffic: null, detail: 'auth.test 실패: invalid_auth' }),
  });
  watchdog.noteConnected();
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'suspect');
  assert.strictEqual(suspects.length, 1);
  assert.match(suspects[0], /no inbound frames/);
});

test('트래픽 판정 불가(unknown) 는 오탐 방지를 위해 자가 재시작하지 않는다', async () => {
  const { clock, watchdog, suspects } = makeWatchdog({
    probe: async () => ({ apiOk: true, hasTraffic: null, detail: 'conversations.history 권한 없음' }),
  });
  watchdog.noteConnected();
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'idle');
  assert.strictEqual(suspects.length, 0);
});

test('인바운드 프레임이 계속 들어오면 점검 대상이 아니다(프로브를 아예 부르지 않는다)', async () => {
  let probeCalls = 0;
  const { clock, watchdog, suspects } = makeWatchdog({
    probe: async () => { probeCalls++; return { apiOk: true, hasTraffic: true, detail: 'x' }; },
  });
  watchdog.noteConnected();
  for (let i = 0; i < 5; i++) {
    clock.advance(500);
    watchdog.noteInbound();
    await watchdog.check();
  }

  assert.strictEqual(probeCalls, 0);
  assert.strictEqual(suspects.length, 0);
});

test('소켓이 disconnected 면 점검하지 않는다(기존 재연결 워치독이 담당)', async () => {
  let probeCalls = 0;
  const { clock, watchdog } = makeWatchdog({
    probe: async () => { probeCalls++; return { apiOk: true, hasTraffic: true, detail: 'x' }; },
  });
  watchdog.noteConnected();
  watchdog.noteDisconnected();
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'skipped-disconnected');
  assert.strictEqual(probeCalls, 0);
});

test('connected 이벤트가 오면 무수신 시계가 초기화된다(재연결 직후에는 다시 유예)', async () => {
  const { clock, watchdog, suspects } = makeWatchdog({
    probe: async () => ({ apiOk: true, hasTraffic: true, detail: 'x' }),
  });
  watchdog.noteConnected();
  watchdog.noteInbound();
  clock.advance(1500);
  watchdog.noteConnected(); // 재연결
  const res = await watchdog.check();

  assert.strictEqual(res.status, 'skipped-idle');
  assert.strictEqual(suspects.length, 0);
});

test('기본 임계값은 15분 이상이다(진짜 유휴로 오인될 여지를 넉넉히 둔다)', () => {
  assert.ok(DEFAULT_IDLE_MS >= 15 * 60 * 1000, `DEFAULT_IDLE_MS=${DEFAULT_IDLE_MS}`);
  assert.ok(DEFAULT_PROBE_INTERVAL_MS >= 60 * 1000, `DEFAULT_PROBE_INTERVAL_MS=${DEFAULT_PROBE_INTERVAL_MS}`);
  assert.ok(DEFAULT_PROBE_INTERVAL_MS <= DEFAULT_IDLE_MS);
});

// ── 2. 프로브: Slack Web API 대조 ─────────────────────────────────────────────
test('프로브: auth.test 실패 → apiOk=false (API 경로 자체가 죽음)', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: async () => ({ ok: false, error: 'invalid_auth' }),
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.apiOk, false);
  assert.match(res.detail, /auth\.test/);
});

test('프로브: 채널에 봇 멘션 메시지가 있으면 hasTraffic=true', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: trafficApiGet(clock),
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.apiOk, true);
  assert.strictEqual(res.hasTraffic, true);
  assert.strictEqual(res.channelId, 'C1');
});

test('프로브: 멘션 없는 일반 채널 메시지는 트래픽으로 보지 않는다(오탐 방지)', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: trafficApiGet(clock, { text: '오늘 점심 뭐 먹지' }),
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.apiOk, true);
  assert.strictEqual(res.hasTraffic, false);
});

test('프로브: DM 메시지는 멘션 없이도 트래픽이다(message.im 은 반드시 와야 한다)', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: trafficApiGet(clock, { channelType: 'im', text: '안녕하세요' }),
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'D1', channelType: 'im' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.hasTraffic, true);
});

test('프로브: 봇이 보낸 메시지는 트래픽이 아니다(자기 송신으로 오탐하지 않는다)', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [{ ts: String((clock.now() + 60_000) / 1000), bot_id: BOT_ID, user: BOT_USER, text: '<@U_BOT> 결과' }] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.hasTraffic, false);
});

test('프로브: auth.test 도달 실패(응답 없음) 는 판정 불가 — 네트워크 단절로 인한 재시작 루프를 막는다', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: async () => ({ ok: false }), // slack-api.js 는 네트워크 오류를 {ok:false} 로 돌려준다(error 필드 없음)
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.apiOk, null);
  assert.strictEqual(res.hasTraffic, null);
});

test('프로브: conversations.history 권한이 없으면 판정 불가(unknown) 로 되돌린다 — 죽이지 않는다', async () => {
  const clock = fakeClock();
  const probe = createInboundProbe({
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: false, error: 'missing_scope' };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: clock.now(), nowMs: clock.now() });

  assert.strictEqual(res.apiOk, true);
  assert.strictEqual(res.hasTraffic, null);
  assert.match(res.detail, /missing_scope|권한|불가/);
});

test('프로브: 마지막 수신 이전 메시지는 대상에서 제외된다(오래된 트래픽으로 오탐하지 않는다)', async () => {
  const clock = fakeClock();
  const idleSince = clock.now();
  clock.advance(60_000);
  const probe = createInboundProbe({
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [{ ts: String((idleSince - 60_000) / 1000), user: 'U_HUMAN', text: '<@U_BOT> 과거' }] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    channels: () => [{ id: 'C1', channelType: 'channel' }],
  });

  const res = await probe({ idleSinceMs: idleSince, nowMs: clock.now() });

  assert.strictEqual(res.hasTraffic, false);
});

// ── 3. 소켓 배선(attach): 실제 소켓 이벤트 흐름 ───────────────────────────────
test('배선: 소켓 이벤트 구독 후 인바운드 프레임이 끊기면 트래픽 대조 후 자가 재시작한다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: trafficApiGet(clock),
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => ['C1'],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  socket.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socket.emit('connected');
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'suspect');
  assert.strictEqual(suspects.length, 1);
  assert.match(suspects[0], /no inbound frames/);
});

test('배선: 실제로 이벤트를 받은 채널이 트래픽 대조 대상에 포함된다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const seen = [];
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method, params) => {
      seen.push([method, params && params.channel]);
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => [],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: () => {},
  });

  socket.emit('app_mention', { event: { channel: 'C_MENTION', channel_type: 'channel' }, ack: () => {} });
  socket.emit('connected');
  clock.advance(1500);
  await watchdog.check();

  const channels = seen.filter(([m]) => m === 'conversations.history').map(([, c]) => c);
  assert.deepStrictEqual(channels, ['C_MENTION']);
});

test('배선: 대조 대상 채널이 하나도 없으면 판정 불가로 두고 죽이지 않는다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => [],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  socket.emit('connected');
  clock.advance(1500);
  const res = await watchdog.check();

  assert.strictEqual(res.status, 'idle');
  assert.strictEqual(suspects.length, 0);
});

// ── 4. 시계 영역 정합성(구조적 오탐 회귀) ──────────────────────────────────────
// 슬랙 ts 는 서버 시계다. 로컬 시계가 서버보다 느리면, 로컬 시각으로 만든 창과
// 서버 ts 를 섞어 비교할 때 **우리가 이미 받은 메시지**가 "놓친 메시지"로 오인된다.
// → 무수신 주기마다(즉, 유휴할 때마다) 자가 재시작하는 구조적 오탐이 된다.
// 창은 반드시 서버 ts 영역에서만 비교해야 한다.
test('시계 어긋남 오탐 회귀: 로컬 시계가 서버보다 느려도 "이미 받은 메시지"는 놓친 것으로 보지 않는다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  // 슬랙 서버 시계가 로컬 시계보다 30초 빠른 상황
  const serverTs = String((clock.now() + 30_000) / 1000);
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [{ ts: serverTs, user: 'U_HUMAN', text: `<@${BOT_USER}> !help` }] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => ['C1'],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  // 봇이 이 메시지를 실제로 받았다(서버 ts 기준)
  socket.emit('message', { event: { channel: 'C1', channel_type: 'channel', ts: serverTs } });
  socket.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socket.emit('connected');
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'idle', '이미 받은 메시지를 놓친 것으로 판정하면 안 된다');
  assert.strictEqual(suspects.length, 0);
});

test('마지막 수신 이벤트 이후 도착한 메시지는 트래픽으로 잡는다(서버 ts 영역 비교)', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  const receivedTs = String((clock.now() + 30_000) / 1000); // 마지막으로 받은 이벤트 ts
  const missedTs = String((clock.now() + 90_000) / 1000);   // 그 이후(놓친) 메시지 ts
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [{ ts: missedTs, user: 'U_HUMAN', text: `<@${BOT_USER}> !help` }] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => ['C1'],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  socket.emit('message', { event: { channel: 'C1', channel_type: 'channel', ts: receivedTs } });
  socket.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socket.emit('connected');
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'suspect');
  assert.strictEqual(suspects.length, 1);
  assert.match(suspects[0], /no inbound frames/);
});

test('앱이 채널 메시지 이벤트를 주고 있으면(받은 적 있으면) 멘션 없는 일반 메시지도 트래픽이다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  const receivedTs = String((clock.now() + 30_000) / 1000);
  const missedTs = String((clock.now() + 90_000) / 1000);
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method) => {
      if (method === 'auth.test') return { ok: true };
      return { ok: true, messages: [{ ts: missedTs, user: 'U_HUMAN', text: '오늘 점심 뭐 먹지' }] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => ['C1'],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  // 채널 message 이벤트를 받은 적이 있다 → 그 채널의 모든 사람 메시지는 기대 대상
  socket.emit('message', { event: { channel: 'C1', channel_type: 'channel', ts: receivedTs } });
  socket.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socket.emit('connected');
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'suspect');
  assert.strictEqual(suspects.length, 1);
});

test('DM 만 받은 경우(채널 message 이벤트를 받은 적 없음)에는 채널 일반 메시지를 트래픽으로 보지 않는다', async () => {
  const clock = fakeClock();
  const socket = new EventEmitter();
  const suspects = [];
  const receivedTs = String((clock.now() + 30_000) / 1000);
  const missedTs = String((clock.now() + 90_000) / 1000);
  const watchdog = attachInboundIdleWatchdog({
    socketClient: socket,
    apiGet: async (method, params) => {
      if (method === 'auth.test') return { ok: true };
      if (params && params.channel === 'C1') {
        return { ok: true, messages: [{ ts: missedTs, user: 'U_HUMAN', text: '오늘 점심 뭐 먹지' }] };
      }
      return { ok: true, messages: [] };
    },
    botUserId: () => BOT_USER,
    selfBotId: () => BOT_ID,
    allowedChannelIds: () => ['C1'],
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: clock.now,
    onSuspect: (why) => suspects.push(why),
  });

  // DM 이벤트만 받은 경우 → 채널 메시지 이벤트는 우리에게 오지 않는다(추정 금지)
  socket.emit('message', { event: { channel: 'D1', channel_type: 'im', ts: receivedTs } });
  socket.emit('ws_message', Buffer.from(JSON.stringify({ type: 'hello' })));
  socket.emit('connected');
  clock.advance(1500);

  const res = await watchdog.check();

  assert.strictEqual(res.status, 'idle');
  assert.strictEqual(suspects.length, 0);
});

// ── 5. 배선 계약: index.js 가 실제로 워치독을 붙였는지 ─────────────────────────
// 모듈 단위 테스트는 "모듈이 정상"까지만 증명한다. index.js 에 배선이 빠지면(리팩터링 실수)
// 모듈은 살아 있는데 봇은 여전히 무수신 상태로 남는다 → 소스 수준 배선 계약을 함께 지킨다.
test('배선 계약: index.js 가 무수신 워치독을 붙이고 자가 재시작 경로를 연결한다', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');

  assert.match(src, /require\('\.\/inbound-idle-watchdog'\)/, 'index.js 가 워치독 모듈을 require 해야 한다');
  assert.match(src, /attachInboundIdleWatchdog\(/, 'index.js 가 워치독을 소켓에 배선해야 한다');
  assert.match(src, /onSuspect:\s*\(why\)\s*=>\s*dieAndRestart\(why\)/, '의심 시 자가 재시작 경로가 연결되어야 한다');
  assert.match(src, /inboundIdle\.start\(\)/, '주기 점검이 시작되어야 한다');
  assert.match(src, /const INBOUND_IDLE_MS =/, '무수신 임계 상수가 정의되어야 한다');
  // 무수신 상태를 인위적으로 만들 수 있어야 검증 가능하다(사양 §5.2 — 테스트 전용 스위치).
  assert.match(src, /SLACKBOT_SIMULATE_NO_INBOUND/, '무수신 재현 스위치가 있어야 한다');
  assert.match(src, /inboundIdle\.noteConnected\(\)/, '재현 모드에서 워치독을 연결 상태로 둬야 한다');
});

// ── 6. 프로세스 수명 — 타이머 unref 정책 ───────────────────────────────────────
// 소켓이 연결돼 있으면 소켓이 이벤트 루프를 붙잡는다. 하지만 "소켓 없이 연결된 것처럼
// 행동하는" 무수신 재현 모드에서는 워치독 타이머가 유일한 핸들이므로 unref 하면
// 프로세스가 즉시 종료돼 재현 자체가 불가능하다 → keepAlive 옵션으로 구분한다.
test('타이머는 기본적으로 unref 한다(워치독이 프로세스를 살리지 않는다)', () => {
  const timers = [];
  createInboundIdleWatchdog({
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: fakeClock().now,
    setIntervalFn: (fn, ms) => {
      const t = { fn, ms, unrefCalled: false, unref() { this.unrefCalled = true; } };
      timers.push(t);
      return t;
    },
    clearIntervalFn: () => {},
  }).start();

  assert.strictEqual(timers.length, 1);
  assert.strictEqual(timers[0].unrefCalled, true);
});

test('재현 모드(keepAlive)에서는 타이머를 unref 하지 않는다(소켓이 없으므로)', () => {
  const timers = [];
  createInboundIdleWatchdog({
    idleMs: 1000,
    probeIntervalMs: 1000,
    now: fakeClock().now,
    setIntervalFn: (fn, ms) => {
      const t = { fn, ms, unrefCalled: false, unref() { this.unrefCalled = true; } };
      timers.push(t);
      return t;
    },
    clearIntervalFn: () => {},
    keepAlive: true,
  }).start();

  assert.strictEqual(timers.length, 1);
  assert.strictEqual(timers[0].unrefCalled, false);
});

// ── 7. 자가 재시작 실행 증거 (exit(1) → pm2 재시작) ───────────────────────────
test('자가 재시작 증거: 무수신 감지 → "[Bot] self-heal" 로그 + 프로세스 exit 1', () => {
  const child = path.join(__dirname, 'fixtures', 'inbound-idle-selfheal-child.js');
  const r = spawnSync(process.execPath, [child], { encoding: 'utf8', windowsHide: true });

  assert.strictEqual(r.status, 1, `exit code 가 1 이어야 한다 (stdout=${r.stdout} stderr=${r.stderr})`);
  assert.match(r.stderr, /\[Bot\] self-heal:/);
  assert.match(r.stderr, /no inbound frames/);
  assert.match(r.stderr, /Exiting so pm2 restarts/);
});
