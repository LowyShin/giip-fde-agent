/**
 * gair-accounts.js — gair(giip ai api router, giip #5671)를 채팅 1순위 실행 경로로 쓰기 위한 pseudo-account.
 * CSN 70424 #5858. minimax-accounts.js 와 같은 자리(ANTHROPIC_BASE_URL/API_KEY 바꿔치기)에 앉는다.
 *
 * 설계 (Lowy님 지시 2026-11-19):
 *  - 봇은 모델을 고정하지 않는다. 엔드포인트·인증만 gair 로 바꾸고, 모델 선택은 gair 의
 *    JEV 판정 + 프로파일 매핑에 맡긴다. 그래서 envFor 는 ANTHROPIC_MODEL 을 제거하고,
 *    호출측은 --model 을 붙이지 않는다.
 *  - 단, 콘솔의 shadow_mode 가 켜져 있으면 gair 는 요청 모델을 그대로 쓰므로, 실제 라우팅이
 *    걸리려면 해당 CSN 의 시스템 파라미터(category=gair)에 shadow_mode=false 가 필요하다.
 *
 * 인증: 채널→계정(giip-accounts.resolve)으로 SK 를 얻고, AdminGetAK(SK+uloginid 2요소,
 * scripts/gissue/get-ak.sh 와 동일 경로 — 백엔드 pApiAdminGetAKbyAK)로 AK 를 파생한다.
 * AK 는 메모리 캐시(20h)만 유지한다. SK/AK 는 파일·로그 어디에도 남기지 않는다.
 *
 * fail-soft: 계정 없음·AK 파생 실패·gair 호출 실패 시 resolve() 가 null 이거나 호출측이
 * 기존 경로(MiniMax → Claude 풀)로 폴백한다. gair 장애가 채팅을 막지 않는다.
 */

const http = require('http');
const https = require('https');
const { URL } = require('url');
const giipAccounts = require('./giip-accounts');

const GAIR_BASE_URL = 'https://giipfaw.azurewebsites.net/api/gair';
const AK_TTL_MS = 20 * 60 * 60 * 1000; // 20h — AdminGetAK 가 24h 활성 AK 를 재사용하므로 그 안쪽으로 잡는다
const DEFAULT_COOLDOWN_MS = 10 * 60 * 1000; // gair 실패 시 재시도 간격(기본 10분, GAIR_COOLDOWN_MS 로 조정)

// giipApi 디스패처는 Function Key(code)가 필요하다. 값은 코드에 넣지 않고 호스트 env
// GIIP_AZURE_CODE 로만 받는다(값 자체는 scripts/gissue/get-ak.sh 의 기본값 참조 —
// giipv3 클라이언트 번들에 배포되는 Function 접근키). env 가 없으면 파생 실패로
// 처리해 기존 경로로 폴백한다(fail-soft).

const akCache = new Map(); // login_id → { ak, csn, fetchedAt }
let cooldownUntil = 0;

function form(params) {
  return Object.entries(params)
    .filter(([, v]) => v != null)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

function postForm(urlStr, bodyStr, timeoutMs = 15000) {
  return new Promise((resolvePromise, reject) => {
    const u = new URL(urlStr);
    const lib = u.protocol === 'http:' ? http : https;
    const req = lib.request(
      {
        method: 'POST',
        hostname: u.hostname,
        port: u.port || (u.protocol === 'http:' ? 80 : 443),
        path: u.pathname + u.search,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(bodyStr),
        },
      },
      (res) => {
        let chunks = '';
        res.on('data', (d) => (chunks += d));
        res.on('end', () => {
          let parsed = chunks;
          try { parsed = JSON.parse(chunks); } catch { /* keep string */ }
          resolvePromise({ status: res.statusCode, body: parsed });
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => req.destroy(new Error('AdminGetAK request timeout')));
    req.write(bodyStr);
    req.end();
  });
}

/**
 * SK + login_id 로 AK 파생(AdminGetAK). 성공 시 AK 문자열, 실패 시 null.
 * 응답 규약(get-ak.sh 실측): { RstVal:200, ak, usn, csn } 또는 그 배열.
 */
async function deriveAK(account) {
  const key = account.login_id;
  const cached = akCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < AK_TTL_MS) return cached.ak;

  const base = account.apiBase || giipAccounts.apiBase();
  const code = process.env.GIIP_AZURE_CODE;
  if (!code) throw new Error('GIIP_AZURE_CODE env 미설정 — AdminGetAK 호출 불가');
  const res = await postForm(
    `${base}/giipApi?code=${encodeURIComponent(code)}`,
    form({
      text: 'AdminGetAK',
      token: account.sk,
      jsondata: JSON.stringify({ uloginid: account.login_id }),
    })
  );
  const row = Array.isArray(res.body) ? res.body[0] : res.body;
  if (res.status !== 200 || !row || Number(row.RstVal) !== 200 || !row.ak) {
    throw new Error(`AdminGetAK 실패: HTTP ${res.status}${row && row.Proc_MSG ? ` ${row.Proc_MSG}` : ''}`);
  }
  akCache.set(key, { ak: row.ak, csn: row.csn ?? account.csn ?? null, fetchedAt: Date.now() });
  return row.ak;
}

/**
 * 채널에 대한 gair pseudo-account 해석. 비활성(GAIR_CHAT=0)·쿨다운·계정 없음·파생 실패면 null
 * (호출측은 기존 MiniMax/Claude 경로로 폴백). 비동기인 이유: AK 파생이 네트워크 호출이다.
 */
async function resolve(channelId) {
  if (String(process.env.GAIR_CHAT || '').trim() === '0') return null;
  if (cooldownUntil && cooldownUntil > Date.now()) return null;
  const account = giipAccounts.resolve(channelId);
  if (!account) return null;
  let ak;
  try {
    ak = await deriveAK(account);
  } catch (e) {
    console.log(`[gair-accounts] AK 파생 실패 → 기존 경로로 폴백: ${e.message}`);
    noteFailure();
    return null;
  }
  if (!ak) return null;
  return { name: 'gair', provider: 'gair', ak, csn: account.csn ?? null, login_id: account.login_id };
}

/** claude CLI spawn 용 env. 모델은 고정하지 않는다(ANTHROPIC_MODEL 제거 — 라우터가 정한다). */
function envFor(account) {
  const env = { ...process.env };
  delete env.CLAUDE_CONFIG_DIR; // minimax-accounts 와 동일: OAuth 세션 혼선 방지
  delete env.ANTHROPIC_MODEL; // 모델 고정 금지 — gair 의 라우팅(JEV+프로파일 매핑)이 정한다
  env.ANTHROPIC_BASE_URL = GAIR_BASE_URL;
  env.ANTHROPIC_API_KEY = account.ak; // gair 는 x-api-key / Bearer 양쪽을 받는다
  // giipAiRouter 는 Azure Function Key(authLevel=function)를 요구한다. 키가 호스트 env 에
  // 프로비저닝돼 있을 때만 커스텀 헤더로 실어 보낸다. 없으면 호출이 401 로 실패하고
  // 호출측이 기존 경로로 폴백한다(fail-soft).
  if (process.env.GAIR_FUNCTION_KEY) {
    env.ANTHROPIC_CUSTOM_HEADERS = `x-functions-key: ${process.env.GAIR_FUNCTION_KEY}`;
  } else {
    delete env.ANTHROPIC_CUSTOM_HEADERS;
  }
  return env;
}

/** gair 실패 시 쿨다운 설정 — 그동안 resolve() 가 null 이라 기존 경로를 바로 탄다. */
function noteFailure() {
  const ms = Number(process.env.GAIR_COOLDOWN_MS) || DEFAULT_COOLDOWN_MS;
  cooldownUntil = Date.now() + ms;
  console.log(`[gair-accounts] gair 실패 감지 → cooldown ${Math.round(ms / 60000)}분 (기존 경로로 폴백)`);
}

module.exports = { resolve, envFor, noteFailure, GAIR_BASE_URL, _deriveAK: deriveAK, _akCache: akCache };
