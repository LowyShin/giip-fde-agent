'use strict';

/**
 * inbound-idle-watchdog.js — Slack Socket Mode "무수신(connected-but-no-inbound)" 감지 워치독.
 *
 * 문제 (giip #5141, 2026-11-13):
 *   slack-bot 의 기존 self-heal 은 두 가지만 감지했다 —
 *     (1) 재연결 실패 : disconnecting/disconnected/reconnecting 후 2분 안에 복구 안 됨
 *     (2) ack 연속 실패 : ack 6회 연속 실패(송신 불가)
 *   그런데 "소켓은 connected 인데 인바운드 프레임이 한 건도 오지 않는" 상태는
 *   위 두 타이머를 **전혀** 울리지 않는다. pm2 는 프로세스 생존만 보므로 재시작하지 않고,
 *   봇은 무한 무응답이 된다(2026-11-13 13:08 재시작 직후 !help 무응답 실측).
 *
 * 해결:
 *   마지막 인바운드 프레임 수신 시각을 기록하고, 임계(INBOUND_IDLE_MS)를 넘기면
 *   **능동 점검(probe)** 을 먼저 돌린다. "봇이 반드시 이벤트를 받았어야 하는 메시지가
 *   실제로 도착했는데 우리 쪽 프레임이 0건" 이 확인되면 소켓이 조용히 죽은 것으로 보고
 *   자가 재시작(onSuspect → index.js 의 dieAndRestart → exit(1) → pm2 재시작)한다.
 *
 * 오탐 방지(가짜 무수신으로 인한 불필요한 재시작을 막는 조건):
 *   - 임계값은 충분히 크게 잡는다(기본 15분).
 *   - 진짜 무트래픽 시간대에는 프로브가 "트래픽 없음" 으로 판정하고 죽이지 않는다.
 *   - 판정 자체가 불가능한 경우(권한 부족·네트워크 단절)는 **죽이지 않는다**.
 *   - 소켓이 이미 disconnected 면 기존 재연결 워치독이 담당하므로 중복 판정하지 않는다.
 *   - 트래픽 대조 창은 **슬랙 서버 ts 영역**에서만 비교한다(로컬 시계 혼용 금지).
 *     로컬 시계가 서버보다 느리면 "이미 받은 메시지"를 "놓친 메시지"로 오인해
 *     매 무수신 주기마다 재시작하는 구조적 오탐이 발생한다(→ inbound-probe.js 참조).
 *
 * 이 모듈은 외부 의존성이 없다(테스트 가능). Slack Web API 호출은 주입(probe)한다.
 */

const { createInboundProbe } = require('./inbound-probe');

const DEFAULT_IDLE_MS = 15 * 60 * 1000;        // 무수신 감지 임계 (기본 15분)
const DEFAULT_PROBE_INTERVAL_MS = 5 * 60 * 1000; // 점검 주기 (기본 5분)

/**
 * 무수신 워치독을 만든다.
 * @param {object} opts
 * @param {number} [opts.idleMs]           무수신으로 간주하는 임계(ms)
 * @param {number} [opts.probeIntervalMs]   주기 점검 간격(ms)
 * @param {(ctx: {idleSinceMs:number, nowMs:number, idleForMs:number, sinceTs:number|null, channelMessageEventsExpected:boolean}) => Promise<{apiOk:boolean|null, hasTraffic:boolean|null, detail?:string}>} [opts.probe]
 * @param {(why: string) => void} [opts.onSuspect] 자가 재시작 요청 (index.js 의 dieAndRestart)
 * @param {(info: {idleForMs:number, detail:string}) => void} [opts.onIdle] 진짜 유휴/판정 불가 통지
 * @param {() => number} [opts.now]
 * @param {(level: string, msg: string) => void} [opts.log]
 */
function createInboundIdleWatchdog(opts = {}) {
  const idleMs = Number.isFinite(opts.idleMs) ? opts.idleMs : DEFAULT_IDLE_MS;
  const probeIntervalMs = Number.isFinite(opts.probeIntervalMs) ? opts.probeIntervalMs : DEFAULT_PROBE_INTERVAL_MS;
  const probe = opts.probe || (async () => ({ apiOk: null, hasTraffic: null, detail: '프로브 미설정' }));
  const onSuspect = opts.onSuspect || (() => {});
  const onIdle = opts.onIdle || (() => {});
  const now = opts.now || (() => Date.now());
  const log = opts.log || (() => {});
  const setIntervalFn = opts.setIntervalFn || setInterval;
  const clearIntervalFn = opts.clearIntervalFn || clearInterval;
  // 소켓 없이 동작하는 재현 모드에서만 true — 점검 타이머가 프로세스를 붙잡는다.
  const keepAlive = !!opts.keepAlive;

  let lastInboundAt = now();
  let connected = false;
  let timer = null;
  let probing = false;
  let stopped = false;
  let probeCount = 0;
  let suspectCount = 0;
  // 마지막으로 **실제로 이벤트를 받은** 메시지의 슬랙 ts (서버 시계).
  // 트래픽 대조 창은 이 값(서버 시계)과만 비교한다 → 로컬 시계 어긋남 영향 없음.
  let lastSeenEventTs = null;
  // 앱이 채널 메시지 이벤트를 우리에게 주는지(실제로 그런 이벤트를 받은 적이 있는지로만 판단).
  let channelMessageEventsExpected = false;
  const observedChannels = new Map(); // channelId -> channelType (실제로 이벤트를 받은 채널)

  /** 인바운드 WebSocket 프레임 수신 — 무수신 시계를 초기화한다. */
  function noteInbound() {
    lastInboundAt = now();
  }

  /** 소켓 연결(또는 재연결) — 무수신 시계를 초기화하고 점검 대상을 활성화한다. */
  function noteConnected() {
    connected = true;
    lastInboundAt = now();
  }

  /** 소켓 단절 — 기존 재연결 워치독이 담당하므로 무수신 점검을 멈춘다. */
  function noteDisconnected() {
    connected = false;
  }

  /**
   * 실제로 이벤트를 받은 채널을 기록한다 (트래픽 대조 대상).
   * @param {string} channelId
   * @param {string} [channelType]
   * @param {string|number} [ts] 메시지의 슬랙 ts (서버 시계) — 마지막 수신 기준점
   * @param {'mention'|'message'} [kind] app_mention 인지 일반 message 인지
   */
  function noteEventChannel(channelId, channelType, ts, kind) {
    if (!channelId) return;
    const type = channelType || guessChannelType(channelId);
    observedChannels.set(channelId, type);

    const tsNum = Number(ts);
    if (Number.isFinite(tsNum) && tsNum > 0) {
      lastSeenEventTs = lastSeenEventTs === null ? tsNum : Math.max(lastSeenEventTs, tsNum);
    }
    // 채널(비 DM) message 이벤트를 받은 적이 있으면 그 채널의 모든 사람 메시지는
    // 반드시 message 이벤트로 도착했어야 한다 → 트래픽으로 계상할 수 있다.
    if (kind === 'message' && type !== 'im' && type !== 'mpim') {
      channelMessageEventsExpected = true;
    }
  }

  function getObservedChannels() {
    return new Map(observedChannels);
  }

  /** 무수신 상태인지 확인하고, 의심되면 자가 재시작을 요청한다. */
  async function check() {
    if (stopped) return { status: 'skipped-stopped' };
    if (probing) return { status: 'skipped-inflight' };
    if (!connected) return { status: 'skipped-disconnected' };

    const idleForMs = now() - lastInboundAt;
    if (idleForMs < idleMs) return { status: 'skipped-idle', idleForMs };

    probing = true;
    probeCount++;
    let result;
    try {
      result = await probe({
        idleSinceMs: lastInboundAt,
        nowMs: now(),
        idleForMs,
        // 마지막 수신 기준점은 **서버 ts** 로 준다 (로컬 시계와 섞지 않는다).
        sinceTs: lastSeenEventTs,
        channelMessageEventsExpected,
      });
    } catch (e) {
      result = { apiOk: null, hasTraffic: null, detail: `프로브 예외: ${e.message}` };
    } finally {
      probing = false;
    }

    const apiOk = result && result.apiOk;
    const hasTraffic = result && result.hasTraffic;
    const detail = (result && result.detail) || '판정 정보 없음';

    // (A) Web API 가 명시적으로 실패(토큰 무효 등) — 봇이 구조적으로 동작 불가
    // (B) API 는 정상인데 "받았어야 할 트래픽"이 있고 우리 프레임은 0건 — 소켓이 조용히 죽음
    if (apiOk === false || (apiOk === true && hasTraffic === true)) {
      suspectCount++;
      const why = `no inbound frames for ${Math.round(idleForMs / 1000)}s (socket silently stuck) — ${detail}`;
      log('error', `[Bot] 무수신 감지: ${why}`);
      onSuspect(why);
      return { status: 'suspect', reason: why, detail, idleForMs };
    }

    // 진짜 유휴이거나 판정 불가 → 자가 재시작하지 않는다 (오탐 방지)
    log('warn', `[Bot] 무수신 점검: ${Math.round(idleForMs / 1000)}s 동안 인바운드 프레임 없음 — ${detail} (자가 재시작 안 함)`);
    onIdle({ idleForMs, detail });
    return { status: 'idle', idleForMs, detail };
  }

  function start() {
    if (timer) return;
    stopped = false;
    timer = setIntervalFn(() => {
      check().catch((e) => log('warn', `[Bot] 무수신 점검 오류: ${e.message}`));
    }, probeIntervalMs);
    // 기본은 unref — 소켓 연결이 이벤트 루프를 붙잡는다(워치독이 프로세스를 살리게 만들지 않는다).
    // 소켓 없이 '연결된 것처럼' 행동하는 재현 모드(keepAlive)에서는 프로세스가 바로 죽지 않도록
    // 참조를 유지한다.
    if (!keepAlive && timer && typeof timer.unref === 'function') timer.unref();
  }

  function stop() {
    stopped = true;
    if (timer) { clearIntervalFn(timer); timer = null; }
  }

  function snapshot() {
    return {
      connected,
      running: !!timer,
      lastInboundAt,
      idleForMs: now() - lastInboundAt,
      idleMs,
      probeIntervalMs,
      observedChannels: [...observedChannels.keys()],
      lastSeenEventTs,
      channelMessageEventsExpected,
      probeCount,
      suspectCount,
    };
  }

  return {
    noteInbound,
    noteConnected,
    noteDisconnected,
    noteEventChannel,
    getObservedChannels,
    check,
    start,
    stop,
    snapshot,
  };
}

/**
 * Slack Socket Mode 클라이언트에 무수신 감지를 배선한다.
 *   - ws_message / connected / authenticated / disconnecting / disconnected / reconnecting 을 구독한다.
 *   - app_mention / message 로 실제 이벤트를 받은 채널을 대조 대상으로 기록한다.
 *   (이 리스너들은 절대 예외를 밖으로 던지지 않는다 — 같은 이벤트를 쓰는 index.js 의
 *    핸들러까지 막히면 안 되므로 try/catch 로 감싼다. ack 도 건드리지 않는다.)
 */
function attachInboundIdleWatchdog(opts = {}) {
  const socketClient = opts.socketClient;
  if (!socketClient || typeof socketClient.on !== 'function') {
    throw new Error('attachInboundIdleWatchdog: socketClient 가 필요합니다');
  }
  const log = opts.log || (() => {});
  const allowedChannelIds = opts.allowedChannelIds || (() => []);
  const botUserId = opts.botUserId || (() => null);
  const selfBotId = opts.selfBotId || (() => null);

  let watchdog = null;

  const probe = createInboundProbe({
    apiGet: opts.apiGet,
    botUserId,
    selfBotId,
    log,
    channels: () => {
      const map = watchdog ? watchdog.getObservedChannels() : new Map();
      for (const id of (allowedChannelIds() || [])) {
        if (id && !map.has(id)) map.set(id, guessChannelType(id));
      }
      return [...map.entries()].map(([id, channelType]) => ({ id, channelType }));
    },
  });

  watchdog = createInboundIdleWatchdog({ ...opts, probe });

  const safe = (fn) => (payload) => {
    try {
      fn(payload);
    } catch (e) {
      log('warn', `[Bot] 무수신 감지 훅 오류(무시): ${e.message}`);
    }
  };

  socketClient.on('ws_message', safe(() => watchdog.noteInbound()));
  socketClient.on('connected', safe(() => watchdog.noteConnected()));
  socketClient.on('authenticated', safe(() => watchdog.noteConnected()));
  socketClient.on('disconnecting', safe(() => watchdog.noteDisconnected()));
  socketClient.on('disconnected', safe(() => watchdog.noteDisconnected()));
  socketClient.on('reconnecting', safe(() => watchdog.noteDisconnected()));
  socketClient.on('app_mention', safe((p) => {
    const ev = p && p.event;
    if (ev) watchdog.noteEventChannel(ev.channel, ev.channel_type, ev.ts, 'mention');
  }));
  socketClient.on('message', safe((p) => {
    const ev = p && p.event;
    if (ev) watchdog.noteEventChannel(ev.channel, ev.channel_type, ev.ts, 'message');
  }));

  return watchdog;
}

/** 채널 ID 접두사로 채널 종류를 추정한다 (D=DM, G=비공개, 그 외=공개). */
function guessChannelType(channelId) {
  const id = String(channelId || '');
  if (id.startsWith('D')) return 'im';
  if (id.startsWith('G')) return 'private_channel';
  return 'channel';
}

module.exports = {
  createInboundIdleWatchdog,
  attachInboundIdleWatchdog,
  guessChannelType,
  DEFAULT_IDLE_MS,
  DEFAULT_PROBE_INTERVAL_MS,
};
