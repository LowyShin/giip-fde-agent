/**
 * lssn-agent.js — 기동 시 GIIP lssn 자동등록 + 처리마다 상태보고 (giip #2349).
 *
 * 목적: 이 템플릿으로 배포되는 slack-bot 이 기동 시 자신을 GIIP lsvr(lssn)로 자동 등록하고,
 *       메시지/태스크를 처리할 때마다 현재 상태를 GIIP KVS 로 보고한다. 사람이 GIIP 콘솔에서
 *       "이 PC의 이 봇이 지금 살아있고 무엇을 처리 중인지"를 볼 수 있게 하는 것.
 *
 * 설계 원칙(본 이슈 §3 회귀 방지):
 *   - **best-effort**: 등록/상태보고 실패(네트워크·SK 미설정·RstVal≠200 등)는 봇 기동이나
 *     메시지 처리 로직을 절대 막지 않는다. 모든 경로를 try/catch 로 감싸 예외를 삼키고 경고만 남긴다.
 *   - **csn/SK 하드코딩 금지**: giip-accounts.resolve() 가 돌려주는 그 배포의 계정(csn/sk/apiBase)을
 *     그대로 쓴다. 물리 호스트명은 os.hostname(). tool-slug 만 봇 변형별로 구분되는 값을 쓰되,
 *     GIIP_TOOL_SLUG 환경변수로 배포마다 오버라이드할 수 있다(다른 PC/CSN 유연성).
 *
 * API 규약(https://giip.littleworld.net/ko/guides/giip-agent-api): 단일 디스패처 giipApiSk2,
 *   항상 HTTP 200 이고 실제 성공여부는 data[0].RstVal(=200) 로 판단.
 *   - AgentAutoRegister: text="AgentAutoRegister hostname jsondata",
 *     jsondata={hostname:"<physical>-<slug>", os, cpu_cores, memory_gb, agent_version}
 *     → data[0].{lssn, action("new"|"update"), RstVal}. hostname(호스트+csn)이 멱등 식별키.
 *   - KVSPut: text="KVSPut kType kKey kFactor",
 *     jsondata={kType:"lssn", kKey:"<lssn>", kFactor:"slackbot_status", kValue:{...}}.
 *     소유권 검사(그 SK 의 csn 소속 lssn 이 아니면 RstVal 411) — 같은 SK 로 등록했으므로 정상 소유.
 */
const os = require('os');
const accounts = require('./giip-accounts');
const giipApi = require('./giip-api');

// 이 봇 변형을 GIIP 상에서 식별하는 tool-slug. 배포마다 GIIP_TOOL_SLUG 로 덮어쓸 수 있다.
// 기본값은 이 봇의 기동 배너 정체성(giipclaude Bot)과 일치시킨다.
const TOOL_SLUG = (process.env.GIIP_TOOL_SLUG || 'giipclaude').trim();
// 상태보고 KVS 의 kFactor — 다른 스크립트(admin_script_status 등)와 충돌하지 않는 이 봇 전용 값.
const STATUS_KFACTOR = 'slackbot_status';

let _lssn = null;      // AgentAutoRegister 로 발급받은 lssn(문자열). 등록 실패 시 null 유지.
let _account = null;   // 등록에 쓴 계정(상태보고에 재사용).

function hostId() {
  return `${os.hostname()}-${TOOL_SLUG}`;
}

function agentVersion() {
  try {
    return require('./package.json').version || null;
  } catch {
    return null;
  }
}

/**
 * 기동 시 1회 호출. 자신을 lssn 으로 등록/heartbeat 하고 발급된 lssn 을 모듈 전역에 보관한다.
 * 절대 throw 하지 않는다(실패는 경고 로그만, null 반환). 반환값은 편의용(lssn|null).
 */
async function registerOnStartup() {
  try {
    const account = accounts.resolve(null); // 대표(기본) 계정 — 멀티채널이면 default/env 기준
    if (!account || !account.sk) {
      console.warn('[lssn-agent] giip 계정(SK) 미설정 — lssn 자동등록 건너뜀(best-effort)');
      return null;
    }
    _account = account;
    const jsondata = {
      hostname: hostId(),
      os: `${os.type()} ${os.release()}`,
      cpu_cores: os.cpus() ? os.cpus().length : null,
      memory_gb: Math.round(os.totalmem() / (1024 * 1024 * 1024)),
      agent_version: agentVersion(),
    };
    const raw = await giipApi.apiCall(account, 'AgentAutoRegister hostname jsondata', jsondata);
    const row = raw && Array.isArray(raw.data) ? raw.data[0] : null;
    const rstVal = row && row.RstVal != null ? Number(row.RstVal) : null;
    if (rstVal === 200 && row && row.lssn != null) {
      _lssn = String(row.lssn);
      console.log(`[lssn-agent] 등록 완료: lssn=${_lssn} action=${row.action || '?'} host=${hostId()}`);
      // 등록 직후 idle 상태 1회 보고(첫 heartbeat).
      await reportStatus('idle', 'bot started');
      return _lssn;
    }
    console.warn(`[lssn-agent] 등록 실패(RstVal=${rstVal}) — 봇은 계속 진행(best-effort). host=${hostId()}`);
    return null;
  } catch (e) {
    console.warn('[lssn-agent] 등록 예외(무시하고 계속):', e && e.message ? e.message : e);
    return null;
  }
}

/**
 * 처리 지점마다 현재 상태를 KVSPut 으로 보고한다. best-effort — 절대 throw 하지 않는다.
 * 메시지 처리 경로에서 await 없이 fire-and-forget 로 호출해도 안전하도록 내부에서 모든 예외를 삼킨다.
 * @param {'idle'|'processing'|'error'} status
 * @param {string} [message] 무엇을 처리 중인지 짧은 요약(민감정보 제외).
 */
async function reportStatus(status, message) {
  try {
    if (!_lssn || !_account) return; // 등록 안 됐으면 조용히 skip(등록 실패 시 상태보고 무의미)
    const kValue = {
      status,
      message: String(message || '').slice(0, 500),
      last_run: new Date().toISOString(),
      hostname: hostId(),
    };
    const jsondata = { kType: 'lssn', kKey: _lssn, kFactor: STATUS_KFACTOR, kValue };
    await giipApi.apiCall(_account, 'KVSPut kType kKey kFactor', jsondata);
  } catch (e) {
    console.warn('[lssn-agent] 상태보고 예외(무시):', e && e.message ? e.message : e);
  }
}

module.exports = { registerOnStartup, reportStatus, hostId, getLssn: () => _lssn, TOOL_SLUG, STATUS_KFACTOR };
