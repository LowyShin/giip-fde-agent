#!/usr/bin/env node
/**
 * log-ship.js — gissue 스케줄러 로그를 giip 웹 콘솔(Agent Log Viewer)로 보낸다 (giip #3535 후속).
 *
 * 경로: giipApiSk2(익명 디스패처) → pApiAgentLog{StreamRegister,Ingest}BySK. 함수키(authLevel=function)가 필요한
 *   agent-log-* Function 은 쓰지 않는다. 디스패처는 SK 를 `token` 폼 키로 받고, `text` 의 첫 단어에 pApi...bySk 를
 *   자동으로 붙여 호출한다(예: text="AgentLogIngest ..." → pApiAgentLogIngestbySk). `sk`/`proc` 키는 무시된다.
 * 수신 계약: giipdb/docs/30_Specs/AGENT_LOG_COLLECTOR_SPECIFICATION.md §3, §8.
 * 전제: tSchedulerAgent 에 agentKey 가 있어야 한다(없으면 404) — 이 도구가 SchedulerAgentUpsert 를 먼저 호출한다.
 *
 * 사용: node log-ship.js --csn 47 --logs <logDir> --accounts <giip-accounts.json> [--state <file>] [--dry]
 *   전송 대상: <logDir>/gissue_csn<csn>.log (스트림 scheduler_issue_log:gissue_csn<csn>.log)
 * fail-open: 어떤 오류도 exit 0 + 한 줄 경고(스케줄러를 절대 막지 않는다).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const { URL } = require('url');

const API = process.env.GIIP_LOGSHIP_API || 'https://giipfaw.azurewebsites.net/api/giipApiSk2';
const FIRST_RUN_TAIL_BYTES = 256 * 1024; // 처음 보낼 때는 파일 끝 256KB 만(과거 백로그 폭주 방지)
const BATCH_LINES = 300;
const MAX_LINE_CHARS = 4000;
const MAX_LINES_PER_RUN = 6000;

// 명백한 비밀 패턴만 가린다(스펙 §8). 완벽한 DLP 가 아니다.
const MASKS = [
  [/\b(sk|ak|token|password|pwd|secret|api[_-]?key)\s*[=:]\s*("[^"]*"|'[^']*'|[^\s,;&]+)/gi, '$1=***'],
  [/(Authorization\s*:\s*)(Bearer\s+)?\S+/gi, '$1***'],
  [/(x-api-key|x-functions-key)\s*[:=]\s*\S+/gi, '$1=***'],
  [/(Password=)[^;\s]+/gi, '$1***'],
  [/\b(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|[a-f0-9]{32})\b/g, '***'],
];
// 줄 앞의 `[YYYY-MM-DD HH:MM:SS]`(호스트 로컬=UTC) 를 이벤트 시각으로 쓴다. 없으면 전송 시각.
function lineTs(line, fallback) {
  const m = /^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\]/.exec(line);
  return m ? `${m[1]}T${m[2]}Z` : fallback;
}
function maskLine(s) {
  let out = s.length > MAX_LINE_CHARS ? s.slice(0, MAX_LINE_CHARS) + '…(잘림)' : s;
  for (const [re, rep] of MASKS) out = out.replace(re, rep);
  return out;
}

/** 파일의 offset 이후를 읽어 완결된 줄만 돌려준다(마지막 개행 없는 줄은 다음 회차로 미룬다). */
function readNewLines(file, offset, maxBytes) {
  const size = fs.statSync(file).size;
  if (size <= offset) return { lines: [], newOffset: offset, size };
  const fd = fs.openSync(file, 'r');
  try {
    const len = Math.min(size - offset, maxBytes);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, offset);
    const lastNl = buf.lastIndexOf(0x0a);
    if (lastNl < 0) return { lines: [], newOffset: offset, size };
    const text = buf.slice(0, lastNl + 1).toString('utf8');
    const lines = text.split(/\r?\n/).filter((l) => l.length > 0);
    return { lines, newOffset: offset + lastNl + 1, size };
  } finally { fs.closeSync(fd); }
}

function loadState(f) { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return {}; } }
function saveState(f, s) { fs.writeFileSync(f, JSON.stringify(s, null, 2)); }

function resolveSk(accountsFile, csn) {
  const data = JSON.parse(fs.readFileSync(accountsFile, 'utf8'));
  const all = [...Object.values(data.channels || {}), ...(data.default ? [data.default] : [])];
  const m = all.find((c) => String(c.csn) === String(csn) && c.sk);
  return m ? m.sk : null;
}

function post(form) {
  return new Promise((resolve, reject) => {
    const u = new URL(API);
    const body = new URLSearchParams(form).toString();
    const req = https.request({ method: 'POST', hostname: u.hostname, path: u.pathname + u.search, timeout: 60000,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } }, (res) => {
      let d = ''; res.on('data', (c) => (d += c));
      res.on('end', () => { try { const j = JSON.parse(d); resolve((j.data && j.data[0]) || j); } catch { reject(new Error(`HTTP ${res.statusCode} 비JSON 응답`)); } });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.end(body);
  });
}
const rpc = (sk, text, json) => post(json ? { token: sk, text, jsondata: json } : { token: sk, text });
const rstOf = (r) => Number(r.RstVal);

async function main() {
  const a = process.argv.slice(2);
  const get = (k) => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : undefined; };
  const csn = get('--csn'), logDir = get('--logs'), accounts = get('--accounts');
  const dry = a.includes('--dry');
  if (!csn || !logDir || !accounts) { console.log('[LOG-SHIP] 사용법: --csn <N> --logs <dir> --accounts <file>'); return; }
  const statePath = get('--state') || path.join(logDir, '.log-ship-state.json');
  const file = path.join(logDir, `gissue_csn${csn}.log`);
  if (!fs.existsSync(file)) { console.log(`[LOG-SHIP] SKIP: 로그 파일 없음 ${file}`); return; }
  const sk = resolveSk(accounts, csn);
  if (!sk) { console.log(`[LOG-SHIP] SKIP: csn=${csn} SK 없음`); return; }

  const agentKey = `gissue_csn${csn}`;
  const streamKey = `scheduler_issue_log:gissue_csn${csn}.log`;
  const state = loadState(statePath);
  const st = state[streamKey] || { offset: null, seq: 0, rotationGen: 0, registeredGen: -1 };
  const size = fs.statSync(file).size;
  if (st.offset === null) st.offset = Math.max(0, size - FIRST_RUN_TAIL_BYTES);
  if (size < st.offset) { st.rotationGen += 1; st.offset = 0; st.seq = 0; }   // 파일 회전/초기화: 새 세대

  let sent = 0;
  while (sent < MAX_LINES_PER_RUN) {
    const { lines, newOffset } = readNewLines(file, st.offset, 512 * 1024);
    if (!lines.length) { st.offset = newOffset; break; }
    for (let i = 0; i < lines.length && sent < MAX_LINES_PER_RUN; i += BATCH_LINES) {
      const chunk = lines.slice(i, i + BATCH_LINES);
      const now = new Date().toISOString();
      const payload = chunk.map((l, k) => ({ seq: st.seq + 1 + k, ts: lineTs(l, now), content: maskLine(l) }));
      if (dry) { console.log(`[LOG-SHIP][DRY] ${chunk.length}줄 (seq ${payload[0].seq}~${payload[payload.length - 1].seq})`); console.log(payload[0].content); st.seq += chunk.length; sent += chunk.length; continue; }
      if (st.registeredGen !== st.rotationGen) {
        let r = await rpc(sk, `AgentLogStreamRegister ${agentKey} '${streamKey}' scheduler_issue_log NULL ${st.rotationGen}`);
        if (rstOf(r) === 404) {   // 에이전트 행이 없으면 만든다(idempotent)
          const u = await rpc(sk, `SchedulerAgentUpsert ${agentKey} 'GIIP gissue scheduler CSN ${csn}' ${process.env.HOSTNAME || 'gissue-host'} NULL csn${csn} 'cron :07/:27/:47' 1`);
          if (rstOf(u) !== 200) throw new Error(`SchedulerAgentUpsert 실패: ${u.Proc_MSG || u.RstMsg}`);
          r = await rpc(sk, `AgentLogStreamRegister ${agentKey} '${streamKey}' scheduler_issue_log NULL ${st.rotationGen}`);
        }
        if (rstOf(r) !== 200) throw new Error(`StreamRegister 실패: ${r.Proc_MSG || r.RstMsg}`);
        st.registeredGen = st.rotationGen;
      }
      const from = st.seq + 1, to = st.seq + chunk.length;
      const r = await rpc(sk, `AgentLogIngest ${agentKey} '${streamKey}' ${st.rotationGen} ${from} ${to}`, JSON.stringify(payload));
      if (rstOf(r) !== 200) throw new Error(`Ingest 실패: ${r.Proc_MSG || r.RstMsg}`);
      st.seq = to; sent += chunk.length;
    }
    st.offset = newOffset;
    if (!dry) { state[streamKey] = st; saveState(statePath, state); }
    if (newOffset >= size) break;
  }
  if (!dry) { state[streamKey] = st; saveState(statePath, state); }
  console.log(`[LOG-SHIP] OK ${dry ? '(dry) ' : ''}${sent}줄 전송 (stream=${streamKey}, gen=${st.rotationGen}, seq=${st.seq})`);
}

module.exports = { maskLine, readNewLines, lineTs };
if (require.main === module) main().catch((e) => { console.log(`[LOG-SHIP][WARN] ${String(e.message).replace(/[a-f0-9]{32}/g, '***')}`); process.exit(0); });
