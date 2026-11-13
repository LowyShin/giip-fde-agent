'use strict';

/**
 * inbound-probe.js — 무수신(connected-but-no-inbound) 의심 상태에서의 "능동 점검" 프로브.
 *
 * 왜 필요한가 (giip #5141):
 *   소켓은 connected 인데 인바운드 프레임이 한 건도 오지 않는 상태(half-dead 연결)는
 *   재연결 타이머·ack 실패 카운터 어느 쪽도 울리지 않는다. pm2 는 프로세스 생존만 보므로
 *   재시작하지 않고, 봇은 무한 무응답이 된다(2026-11-13 재시작 직후 !help 무응답).
 *   "소켓이 조용히 죽었는지"를 판정하려면 **슬랙 쪽에 실제로 일어난 일**과 대조해야 한다.
 *
 * 판정 프로토콜 (반환값):
 *   apiOk     : true  = auth.test 응답 정상
 *                false = auth.test 가 API 오류로 응답(토큰 무효 등) → 봇이 구조적으로 못 동작
 *                null  = auth.test 도달 실패(네트워크 단절 등) → 판정 불가
 *   hasTraffic: true  = "우리가 반드시 이벤트를 받았어야 하는" 메시지가 마지막 수신 이후 도착
 *                false = 그런 메시지가 없음(진짜 무트래픽)
 *                null  = 대조 불가(권한 부족 등) → 판정 불가
 *
 * 시간 기준의 함정(중요):
 *   슬랙 메시지 ts 는 **슬랙 서버 시계**이고, 우리 로컬 시계와 어긋날 수 있다.
 *   "우리가 마지막으로 받은 이벤트 ts"(서버 시계) 와 로컬 시계로 만든 창을 섞어 비교하면,
 *   로컬 시계가 서버보다 느린 경우 **우리가 이미 받은 메시지를 놓친 것으로 오인**해
 *   매 무수신 주기마다 자가 재시작하게 된다(오탐이 구조적으로 발생).
 *   → 창은 **서버 ts 영역**에서만 비교한다(sinceTs).
 *   → 서버 ts 기준점을 아직 하나도 모르는 경우(이벤트를 한 번도 못 받은 경우)에만
 *     로컬 시계로 대체 창을 만들며, 그때는 오탐 폭을 5초로 제한한다.
 *
 * 오탐(가짜 무수신) 방지 규칙 — "트래픽"으로 세는 메시지:
 *   1) DM(im) 채널의 사람 메시지                → 반드시 message.im 이벤트로 온다
 *   2) 봇을 멘션한 채널 메시지                    → 반드시 app_mention 이벤트로 온다
 *   3) 앱이 채널 메시지 이벤트를 우리에게 주고 있는 경우(실제로 그런 이벤트를 받은 적이 있음)
 *      그 채널의 사람 메시지 전체                 → 반드시 message 이벤트로 온다
 *   그 외(봇 멘션 없는 일반 잡담 등)는 트래픽으로 세지 않는다.
 *
 * 이 모듈은 외부 의존성이 없다(테스트 가능). Slack Web API 호출은 주입(apiGet)한다.
 */

const DEFAULT_MAX_CHANNELS = 10;   // 점검할 채널 수 상한 (API 호출 폭주 방지)
const DEFAULT_HISTORY_LIMIT = 50;  // 채널당 가져올 최근 메시지 수
const FALLBACK_WINDOW_SLACK_MS = 5000; // 서버 ts 기준점을 모를 때의 로컬 창 오탐 폭 (5초)

/**
 * @param {object} opts
 * @param {(method: string, params: object) => Promise<object>} opts.apiGet Slack Web API 호출자
 * @param {() => string|null} [opts.botUserId]  봇 사용자 ID (U...)
 * @param {() => string|null} [opts.selfBotId]  봇의 bot_id (B...)
 * @param {() => Array<{id: string, channelType: string}>} [opts.channels] 대조 대상 채널 목록
 * @param {(level: string, msg: string) => void} [opts.log]
 */
function createInboundProbe(opts = {}) {
  const apiGet = opts.apiGet;
  const botUserId = opts.botUserId || (() => null);
  const selfBotId = opts.selfBotId || (() => null);
  const channels = opts.channels || (() => []);
  const log = opts.log || (() => {});
  const maxChannels = Number.isFinite(opts.maxChannels) ? opts.maxChannels : DEFAULT_MAX_CHANNELS;

  if (typeof apiGet !== 'function') {
    throw new Error('createInboundProbe: apiGet 이 필요합니다');
  }

  return async function probe(ctx = {}) {
    // ── 1) Web API 생존 확인 ────────────────────────────────────────────────
    let auth;
    try {
      auth = await apiGet('auth.test', {});
    } catch (e) {
      return { apiOk: null, hasTraffic: null, detail: `auth.test 호출 실패: ${e.message}` };
    }
    if (!auth || auth.ok !== true) {
      const apiError = auth && auth.error;
      if (!apiError) {
        // 응답 자체가 없음(네트워크 단절) → 판정 불가 (오탐 방지)
        return { apiOk: null, hasTraffic: null, detail: 'auth.test 응답 없음(네트워크 단절 등) — 판정 불가' };
      }
      return { apiOk: false, hasTraffic: null, detail: `auth.test 실패: ${apiError}` };
    }

    const list = (channels() || []).filter(c => c && c.id).slice(0, maxChannels);
    if (!list.length) {
      return { apiOk: true, hasTraffic: null, detail: '대조 대상 채널이 없음(관찰/설정된 채널 목록이 비어 있음) — 판정 불가' };
    }

    // ── 2) 최근 트래픽 대조 ──────────────────────────────────────────────────
    const win = resolveWindow(ctx);
    const channelMessageEventsExpected = !!ctx.channelMessageEventsExpected;
    let probed = 0;
    let failed = 0;
    for (const ch of list) {
      let res;
      try {
        res = await apiGet('conversations.history', {
          channel: ch.id,
          limit: DEFAULT_HISTORY_LIMIT,
          oldest: win.oldestSec === null ? undefined : String(win.oldestSec),
        });
      } catch (e) {
        failed++;
        continue;
      }
      if (!res || res.ok !== true || !Array.isArray(res.messages)) {
        failed++;
        continue;
      }
      probed++;
      const hit = res.messages.find(m => isMissedInbound(m, {
        window: win,
        channelType: ch.channelType,
        botUserId: botUserId(),
        selfBotId: selfBotId(),
        channelMessageEventsExpected,
      }));
      if (hit) {
        return {
          apiOk: true,
          hasTraffic: true,
          channelId: ch.id,
          messageTs: hit.ts,
          detail: `채널 ${ch.id} 에 ${new Date(Number(hit.ts) * 1000).toISOString()} 메시지가 도착했는데 인바운드 프레임이 0건`,
        };
      }
    }

    if (probed === 0) {
      return {
        apiOk: true,
        hasTraffic: null,
        detail: `트래픽 대조 불가(conversations.history 실패 ${failed}건 — 권한/채널 오류) — 판정 불가`,
      };
    }
    return {
      apiOk: true,
      hasTraffic: false,
      detail: `대조 ${probed}개 채널 — 마지막 수신 이후 '봇이 반드시 이벤트를 받았어야 하는' 메시지 없음`,
    };
  };
}

/**
 * 대조 창을 정한다.
 *   sinceTs 가 있으면 **서버 ts 영역**에서 정확히 비교한다(시계 어긋남 영향 없음).
 *   없으면(이벤트를 한 번도 못 받은 경우) 로컬 시계로 대체 창을 만들되 오탐 폭을 5초로 제한한다.
 */
function resolveWindow(ctx) {
  const sinceTs = ctx.sinceTs !== undefined && ctx.sinceTs !== null ? Number(ctx.sinceTs) : null;
  if (sinceTs !== null && Number.isFinite(sinceTs)) {
    return { sinceTsSec: sinceTs, oldestSec: sinceTs, strict: true };
  }
  const base = Number(ctx.idleSinceMs) || 0;
  if (base > 0) {
    const oldestSec = (base - FALLBACK_WINDOW_SLACK_MS) / 1000;
    return { sinceTsSec: null, oldestSec, strict: false };
  }
  return { sinceTsSec: null, oldestSec: null, strict: false };
}

/**
 * 이 메시지가 "우리가 받아야 했는데 받지 못한" 것인지 판정한다.
 * @param {object} m Slack 메시지
 * @param {object} ctx { window, channelType, botUserId, selfBotId, channelMessageEventsExpected }
 */
function isMissedInbound(m, ctx) {
  if (!m || !m.ts) return false;
  const tsSec = Number(m.ts);
  if (!Number.isFinite(tsSec)) return false;

  const win = ctx.window || {};
  if (win.sinceTsSec !== null && win.sinceTsSec !== undefined) {
    if (tsSec <= win.sinceTsSec) return false; // 마지막으로 받은 이벤트 이전 = 이미 받은 것
  } else if (win.oldestSec !== null && win.oldestSec !== undefined) {
    if (tsSec < win.oldestSec) return false;
  }

  if (ctx.selfBotId && m.bot_id === ctx.selfBotId) return false; // 우리가 보낸 메시지
  if (ctx.botUserId && m.user === ctx.botUserId) return false;   // 우리 계정으로 보낸 메시지

  const isDm = ctx.channelType === 'im' || ctx.channelType === 'mpim';
  if (isDm) return true;                                   // DM 은 멘션 없이도 message.im 으로 온다
  if (ctx.channelMessageEventsExpected) return true;        // 앱이 이 채널의 메시지 이벤트를 우리에게 준다

  // 채널: 봇을 멘션한 메시지만 app_mention 으로 온다
  const text = String(m.text || '') + ' ' + (Array.isArray(m.blocks) ? JSON.stringify(m.blocks) : '');
  return ctx.botUserId ? text.includes(`<@${ctx.botUserId}>`) : false;
}

module.exports = {
  createInboundProbe,
  isMissedInbound,
  resolveWindow,
  DEFAULT_MAX_CHANNELS,
  DEFAULT_HISTORY_LIMIT,
  FALLBACK_WINDOW_SLACK_MS,
};
