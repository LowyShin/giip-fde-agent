#!/usr/bin/env node
/**
 * lssn-heartbeat.js — OpenClaw 변형용 GIIP lssn 자동등록 + 주기적 상태보고 companion (giip #2349).
 *
 * 왜 companion 인가:
 *   slack-bot / slack-bot-minimax 는 우리가 짠 Node 런타임이라 index.js 안에서 메시지 처리 지점마다
 *   직접 상태보고를 넣을 수 있다(각 폴더의 lssn-agent.js). 반면 이 openclaw 변형은 외부 OpenClaw
 *   게이트웨이 프로세스를 그대로 구동할 뿐 자체 런타임 코드가 없고, 이 폴더 설계상 OpenClaw 본체
 *   소스는 건드리지 않는다(README §"왜 이 폴더가 별도인가"). 따라서 "매 메시지 처리마다"의 세밀한
 *   상태보고는 OpenClaw 소스를 고치지 않고는 불가능하다. 그 대신 이 companion 을 게이트웨이와 나란히
 *   OS 서비스로 띄워, 기동 시 1회 등록 + 일정 주기(HEARTBEAT_SEC, 기본 60s)로 살아있음/처리대기
 *   상태를 보고한다. 이렇게 하면 GIIP 콘솔에서 이 봇의 생존/최근 heartbeat 를 다른 두 변형과 동일하게
 *   볼 수 있다.
 *
 * 의존성 없음: Node 내장 https/os 만 사용(OpenClaw 폴더는 자체 node_modules 를 두지 않으므로).
 *
 * 설정(환경변수 — csn/SK 하드코딩 금지, 배포마다 주입):
 *   GIIP_SK        (필수) 이 배포의 Secret Key.
 *   GIIP_CSN       (선택) 참고용. hostname 식별키에는 안 들어가지만 소유권은 SK 로 판정된다.
 *   GIIP_API_BASE  (선택) 기본 https://giipfaw.azurewebsites.net/api
 *   GIIP_TOOL_SLUG (선택) 기본 'openclaw'. 물리호스트명-<slug> 형태의 식별키에 쓰인다.
 *   HEARTBEAT_SEC  (선택) 상태보고 주기(초). 기본 60. 0 이하면 등록만 하고 즉시 종료.
 *
 * API 규약: https://giip.littleworld.net/ko/guides/giip-agent-api (giipApiSk2 단일 디스패처,
 *   항상 HTTP 200, 실제 성공은 data[0].RstVal===200).
 */
const https = require('https');
const os = require('os');
const { URL } = require('url');

const SK = process.env.GIIP_SK || '';
const API_BASE = process.env.GIIP_API_BASE || 'https://giipfaw.azurewebsites.net/api';
const TOOL_SLUG = (process.env.GIIP_TOOL_SLUG || 'openclaw').trim();
const HEARTBEAT_SEC = process.env.HEARTBEAT_SEC != null ? Number(process.env.HEARTBEAT_SEC) : 60;
const STATUS_KFACTOR = 'slackbot_status';

let _lssn = null;

function hostId() {
  return `${os.hostname()}-${TOOL_SLUG}`;
}

function form(params) {
  return Object.entries(params)
    .filter(([, v]) => v != null)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

function apiCall(verb, jsondata) {
  return new Promise((resolve) => {
    try {
      const u = new URL(`${API_BASE}/giipApiSk2`);
      const params = { text: verb, token: SK, usertoken: SK };
      if (jsondata) params.jsondata = JSON.stringify(jsondata);
      const body = form(params);
      const req = https.request(
        {
          method: 'POST',
          hostname: u.hostname,
          port: u.port || 443,
          path: u.pathname + u.search,
          headers: {
            'x-api-key': SK,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Content-Length': Buffer.byteLength(body),
          },
        },
        (res) => {
          let chunks = '';
          res.on('data', (d) => (chunks += d));
          res.on('end', () => {
            try { resolve(JSON.parse(chunks)); } catch { resolve(null); }
          });
        }
      );
      req.on('error', (e) => { console.warn('[lssn-heartbeat] 요청 오류(무시):', e.message); resolve(null); });
      req.setTimeout(30000, () => req.destroy(new Error('timeout')));
      req.write(body);
      req.end();
    } catch (e) {
      console.warn('[lssn-heartbeat] apiCall 예외(무시):', e && e.message ? e.message : e);
      resolve(null);
    }
  });
}

async function register() {
  const jsondata = {
    hostname: hostId(),
    os: `${os.type()} ${os.release()}`,
    cpu_cores: os.cpus() ? os.cpus().length : null,
    memory_gb: Math.round(os.totalmem() / (1024 * 1024 * 1024)),
  };
  const raw = await apiCall('AgentAutoRegister hostname jsondata', jsondata);
  const row = raw && Array.isArray(raw.data) ? raw.data[0] : null;
  const rstVal = row && row.RstVal != null ? Number(row.RstVal) : null;
  if (rstVal === 200 && row && row.lssn != null) {
    _lssn = String(row.lssn);
    console.log(`[lssn-heartbeat] 등록 완료: lssn=${_lssn} action=${row.action || '?'} host=${hostId()}`);
    return _lssn;
  }
  console.warn(`[lssn-heartbeat] 등록 실패(RstVal=${rstVal}) host=${hostId()}`);
  return null;
}

async function heartbeat(status) {
  if (!_lssn) return;
  const kValue = { status, message: 'openclaw gateway heartbeat', last_run: new Date().toISOString(), hostname: hostId() };
  await apiCall('KVSPut kType kKey kFactor', { kType: 'lssn', kKey: _lssn, kFactor: STATUS_KFACTOR, kValue });
}

async function main() {
  if (!SK) {
    console.warn('[lssn-heartbeat] GIIP_SK 미설정 — 등록/보고 건너뜀(best-effort 종료).');
    return;
  }
  await register();
  await heartbeat('idle');
  if (!Number.isFinite(HEARTBEAT_SEC) || HEARTBEAT_SEC <= 0) return; // 등록만 하고 종료
  setInterval(() => { heartbeat('idle').catch(() => {}); }, HEARTBEAT_SEC * 1000);
  console.log(`[lssn-heartbeat] ${HEARTBEAT_SEC}s 주기 상태보고 시작 (host=${hostId()})`);
}

if (require.main === module) {
  main().catch((e) => console.warn('[lssn-heartbeat] main 예외(무시):', e && e.message ? e.message : e));
}

module.exports = { register, heartbeat, hostId };
