#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monitor.py — secwatch lightweight intrusion monitor (Linux/Windows, stdlib only).

Reads **sk** from the giipAgentWin/giipAgentLinux config (giipAgent.cfg|.cnf) to resolve **csn**,
then polls security-check **verdict results** (`tKVSSecurityCheck`) over AJAX and renders a local web page.
Read SP: `pApiKVSSecurityCheckWindowbySk` (giipApiSk4 text='KVSSecurityCheckWindow minutes').
rev.3 (gateway model): reads the result table, not tKVS (giip #3833, SPEC_JEV_SQLI_DETECTION.md §13·§17).

Security design: **sk lives only in this Python process (server) and is never sent to the browser.**
The page calls the local backend (`/api/events`) only; the backend calls giipApiSk4 with sk on its behalf. Binds to 127.0.0.1 only.

Usage:
  python3 monitor.py                 # 127.0.0.1:8787, sk/csn auto from config, last 24h
  python3 monitor.py --port 9000 --minutes 180
  python3 monitor.py --self-test     # run one query and exit (connectivity check)

sk/csn resolution (auto): sk = env GIIP_SK -> nearest giipAgent.cfg|.cnf 'sk='.  csn = env GIIP_CSN -> cfg 'csn=' (display only; sk identifies).
The sk value is never included in responses, logs, or HTML.
"""
import sys, os, re, json, argparse, urllib.request, urllib.parse, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API_SK4_URL = os.environ.get("GIIP_API_SK4_URL", "https://giipfaw.azurewebsites.net/api/giipApiSk4")

def _cfg(key):
    starts = [os.getcwd(), os.path.dirname(os.path.abspath(__file__))]
    seen = set()
    for start in starts:
        d = start
        while d and d not in seen:
            seen.add(d)
            for name in ("giipAgent.cfg", "giipAgent.cnf"):
                p = os.path.join(d, name)
                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        for line in f:
                            m = re.match(r"\s*%s\s*=\s*(.+)" % re.escape(key), line)
                            if m:
                                return m.group(1).strip().strip('"').strip()
                except (OSError, IOError):
                    pass
            parent = os.path.dirname(d)
            if parent == d:
                break
            d = parent
    return None

def resolve():
    sk = os.environ.get("GIIP_SK") or _cfg("sk")
    csn = os.environ.get("GIIP_CSN") or _cfg("csn")  # display only (sk identifies)
    return sk, csn

def fetch_results(sk, minutes=60):
    """giipApiSk4 KVSSecurityCheckWindow — read result rows for that sk (=csn) scope within a time window."""
    jsondata = json.dumps({"minutes": int(minutes)}, ensure_ascii=False, separators=(",", ":"))
    form = urllib.parse.urlencode({"token": sk, "text": "KVSSecurityCheckWindow minutes",
                                   "jsondata": jsondata}).encode("utf-8")
    req = urllib.request.Request(API_SK4_URL, data=form,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8", "replace")
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        return {"error": "non-JSON response", "raw": body[:200]}
    rows = parsed.get("data", parsed) if isinstance(parsed, dict) else parsed
    if not isinstance(rows, list):
        rows = [rows]
    if rows and isinstance(rows[0], dict) and "kscFactor" not in rows[0] and "RstVal" in rows[0]:
        return {"error": "query failed (RstVal=%s) — check sk/permission" % rows[0].get("RstVal")}
    events = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        origin = r.get("kscOriginRef")
        if isinstance(origin, str):
            try: origin = json.loads(origin)
            except json.JSONDecodeError: origin = {}
        if not isinstance(origin, dict):
            origin = {}
        events.append({
            "ts": r.get("kscRegdt"), "kscsn": r.get("kscsn"),
            "route": r.get("kscRoutedTo"), "factor": r.get("kscFactor"),
            "inj": r.get("kscIsInjection"), "sev": r.get("kscSeverity"),
            "attack": r.get("kscAttackType"), "engine": r.get("kscEngine"),
            "status": r.get("kscStatus"), "lssn": r.get("kscKey"),
            "why": r.get("kscWhy"),  # routing reason (gateway verdict.why) — shown on alert/review rows
            "origin": origin,  # {source,system,location,ref,ts} — client renders + builds download command
            "origincmd": r.get("kscOriginCmd"),  # giipdb 저장 커맨드(fnKVSSecOriginCmd) — 있으면 클라 재생성보다 우선(giip #3833)
        })
    return {"events": events}

def fetch_health(sk):
    """giipApiSk4 AgentHealthCheck — agent liveness (tLSvr.lsChkdt) for this sk's csn group.

    Independent of verdict data: a quiet server (no candidate events, so 0 rows in
    tKVSSecurityCheck) still reports here as long as its giipAgent keeps checking in.
    """
    form = urllib.parse.urlencode({"token": sk, "text": "AgentHealthCheck"}).encode("utf-8")
    req = urllib.request.Request(API_SK4_URL, data=form,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8", "replace")
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        return {"error": "non-JSON response"}
    rows = parsed.get("data", parsed) if isinstance(parsed, dict) else parsed
    if not isinstance(rows, list):
        rows = [rows]
    row = rows[0] if rows and isinstance(rows[0], dict) else {}
    if str(row.get("RstVal")) not in ("200", "None", "") and "report_data" not in row:
        return {"error": "query failed (RstVal=%s)" % row.get("RstVal")}
    rd = row.get("report_data")
    if isinstance(rd, str):
        try: rd = json.loads(rd)
        except json.JSONDecodeError: rd = {}
    if not isinstance(rd, dict):
        rd = {}
    return {
        "total": rd.get("total_servers"), "active": rd.get("active_agents"),
        "inactive": rd.get("inactive_agents"), "errors": rd.get("agents_with_errors"),
        "critical": rd.get("critical_issues") or [], "warning": rd.get("warning_issues") or [],
    }

PAGE = """<!doctype html><html lang="%LANG%"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>secwatch — Threat Monitor</title>
<style>
 :root{--bg:#0d1117;--panel:#151a21;--bd:#232b36;--tx:#d4dae2;--mut:#7d8895;
   --red:#cf6b7f;--amber:#d4a24c;--grn:#5b9d77}
 *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--tx);
   font:14px/1.5 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif}
 header{display:flex;gap:16px;align-items:baseline;padding:14px 18px;border-bottom:1px solid var(--bd);flex-wrap:wrap}
 h1{font-size:15px;margin:0;font-weight:650} .meta{color:var(--mut);font-size:12px;font-family:ui-monospace,monospace}
 .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--grn);margin-right:6px}
 .dot.stale{background:var(--amber)} .dot.err{background:var(--red)}
 .stats{margin-left:auto;display:flex;gap:8px}
 .stat{background:var(--panel);border:1px solid var(--bd);border-radius:7px;padding:6px 10px;font-size:12px}
 .stat b{font-size:16px;font-variant-numeric:tabular-nums}
 table{width:100%;border-collapse:collapse;font-size:13px}
 th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--bd);vertical-align:top}
 th{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.08em;position:sticky;top:0;background:var(--bg)}
 td.sc{font-variant-numeric:tabular-nums;font-weight:650}
 tr.alert td.rt{color:var(--red);font-weight:650} tr.review td.rt{color:var(--amber)} tr.log td.rt{color:var(--grn)}
 td.rt .why{font-weight:400;font-size:11px;color:var(--mut);margin-top:3px;max-width:34ch;white-space:normal;line-height:1.35}
 .factor span,.origin{font-family:ui-monospace,monospace;font-size:11px;color:#aeb6c0}
 .empty{color:var(--mut);padding:30px;text-align:center}
 .osrc{font-family:ui-monospace,monospace;font-size:11px;color:#8b94a0;display:block;margin-bottom:3px}
 .cp{font:600 11px/1 ui-monospace,monospace;background:#1b222c;color:#9fd3b6;border:1px solid var(--bd);
     border-radius:5px;padding:3px 8px;cursor:pointer}
 .cp:hover{border-color:var(--grn);color:#bfe8cf} .cp.nocmd{color:var(--mut);cursor:default;border-style:dashed}
 .cp.done{color:#fff;background:var(--grn);border-color:var(--grn)}
 .cmd{font-family:ui-monospace,monospace;font-size:10.5px;color:#6f7985;max-width:46ch;overflow:hidden;
     text-overflow:ellipsis;white-space:nowrap;margin-top:3px}
 #toast{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:var(--grn);color:#06130c;
     font:600 12px/1 sans-serif;padding:8px 14px;border-radius:8px;opacity:0;transition:opacity .2s;pointer-events:none}
 #toast.show{opacity:1}
 #pager{display:flex;gap:10px;align-items:center;justify-content:center;padding:14px;color:var(--mut);font-size:12px}
 #pager:empty{display:none}
 #pager button{font:600 12px/1 ui-sans-serif,-apple-system,sans-serif;background:var(--panel);color:var(--tx);
     border:1px solid var(--bd);border-radius:6px;padding:6px 12px;cursor:pointer}
 #pager button:hover:not(:disabled){border-color:var(--mut)}
 #pager button:disabled{opacity:.4;cursor:default}
 #pager .pginfo{font-variant-numeric:tabular-nums}
 .stat.live{display:flex;align-items:center;gap:6px}
 .stat.live .lv{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--grn)}
 .stat.live.warn .lv{background:var(--amber)} .stat.live.down .lv{background:var(--red)} .stat.live.unk .lv{background:var(--mut)}
 #agents{padding:0 18px}
 #agents:empty{display:none}
 #agents .ag{display:flex;gap:10px;align-items:baseline;padding:6px 0;border-bottom:1px solid var(--bd);font-size:12px}
 #agents .ag .st{font-weight:650;width:52px} #agents .ag.down .st{color:var(--red)} #agents .ag.stale .st{color:var(--amber)}
 #agents .ag .host{font-family:ui-monospace,monospace;color:var(--tx)} #agents .ag .ago{color:var(--mut);margin-left:auto;font-variant-numeric:tabular-nums}
 a.help{color:var(--mut);font-size:12px;text-decoration:none;border:1px solid var(--bd);border-radius:6px;padding:4px 9px}
 a.help:hover{color:var(--tx);border-color:var(--mut)}
</style></head><body>
<header>
 <h1><span id="dot" class="dot"></span><span id="title"></span></h1>
 <span class="meta" id="who"></span>
 <span class="meta" id="upd">—</span>
 <span class="meta" id="hb" title="secwatch sweep heartbeat (secevt_run)">—</span>
 <a class="help" href="/help" target="_blank" rel="noopener">? Help</a>
 <div class="stats">
   <span class="stat live unk" id="live" title="agent liveness (tLSvr heartbeat)"><span class="lv"></span><span id="live_txt">—</span></span>
   <span class="stat"><span id="l_total"></span> <b id="n">0</b></span>
   <span class="stat">🔴 <b id="na">0</b></span>
   <span class="stat">🟠 <b id="nr">0</b></span>
   <span class="stat">⚪ <b id="nl">0</b></span>
 </div>
</header>
<div id="agents"></div>
<table><thead><tr id="hdr"></tr></thead>
<tbody id="rows"></tbody></table>
<div id="pager"></div>
<div id="toast"></div>
<script>
const POLL=%POLL%, MIN=%MIN%, PAGE_SIZE=%PAGESIZE%, LANG="%LANG%";
let allEvents=[], curPage=0;
// i18n: add languages here; UI picks I18N[LANG] (falls back to en). (multilingual: later)
const I18N={
  en:{title:"secwatch Threat Monitor (verdicts)",total:"Total",last:"last",min:"min",
      updated:"Updated",loading:"Loading…",empty:"No recent verdicts",
      copy:"copy AI prompt",copied:"copied!",nocmd:"no origin to investigate",
      prev:"\\u2039 Prev",next:"Next \\u203a",page:"Page",
      agents:"Agents",alive:"alive",live_none:"no agents",live_unknown:"agents ?",
      st_down:"DOWN",st_stale:"STALE",ago_min:"min ago",
      swept:"swept",ago:"ago",checked:"checked",cand:"cand",sweep_none:"no sweep yet",
      cols:["Time","Route","Type","inj","sev","Attack","Engine","Origin → AI prompt"]}
};
const T=I18N[LANG]||I18N.en;
document.getElementById('title').textContent=T.title;
document.getElementById('l_total').textContent=T.total;
document.getElementById('hdr').innerHTML=T.cols.map(c=>'<th>'+c+'</th>').join('');
document.getElementById('rows').innerHTML='<tr><td colspan=8 class=empty>'+T.loading+'</td></tr>';
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
// origin (source record location) -> a command to paste into the analyst's own terminal to download it. Per source type.
function originCmd(o){
 if(!o||typeof o!='object') return '';
 const loc=String(o.location||''), ref=String(o.ref||'');
 const q=s=>String(s).replace(/"/g,''), fsafe=s=>String(s).replace(/[^A-Za-z0-9._-]/g,'_');
 if(/^s3:\\/\\//i.test(loc)){                       // WAF/CloudFront: S3 object
   const base=loc.split('/').pop()||('origin_'+fsafe(ref));
   return 'aws s3 cp "'+q(loc)+'" "./'+q(base)+'"';
 }
 const m=loc.match(/^(.+?)\\s*:\\s*(.+)$/);          // Aurora audit: CloudWatch "log-group : stream"
 if(m && /^\\/aws\\//.test(m[1].trim())){
   return 'aws logs get-log-events --log-group-name "'+q(m[1].trim())+'" --log-stream-name "'+q(m[2].trim())+
          '" --start-from-head --output text > "audit_'+fsafe(ref)+'.txt"';
 }
 return '';                                         // other sources: no command (label only)
}
// Build a paste-ready AI investigation instruction (Korean) for one verdict row.
// The analyst copies this and hands it to an AI agent instead of running a raw shell command.
// Embeds the verdict facts + origin pointer + (when known) the fetch command; '' when there is no origin.
function aiPrompt(e){
 const o=(e&&e.origin)||{};
 if(!o.location && !o.source && !o.ref) return '';
 const g=(v,d)=>(v==null||v==='')?(d||'-'):v;
 const inj=(e.inj!=null)?Number(e.inj).toFixed(2):'-';
 const cmd=e.origincmd||originCmd(o);  // giipdb 저장 커맨드(origincmd) 우선, 없으면 클라 재생성(giip #3833, #174 의도 보존)
 const fetchLine=cmd?('   '+cmd):('   (아래 location 을 보고 적절한 방법으로 원본을 조회)');
 const ksclink=e.kscsn?('판정레코드 kscsn='+e.kscsn+' 와 '):'';
 return '[secwatch 보안 판정 조사 요청]\\n'+
  'secwatch 의 1차 전단필터+2차 Jev 게이트웨이가 아래 이벤트를 \\''+g(e.route)+'\\' 로 분류했다. 실제 공격인지 원본으로 확인하고 대응하라.\\n'+
  '\\n판정 요약\\n'+
  '- 시각(KST): '+g(e.ts)+'\\n'+
  '- 라우팅: '+g(e.route)+' — '+g(e.why,'(사유 없음)')+'\\n'+
  '- 유형: '+g(e.factor)+'   공격종별: '+g(e.attack)+'\\n'+
  '- 인젝션 확률: '+inj+'   중대도: '+g(e.sev)+' (0 노이즈 ~ 4 쓰기/권한)\\n'+
  '- 판정엔진: '+g(e.engine)+'   lssn: '+g(e.lssn)+'\\n'+
  '\\n원본 위치 (마스킹 전 증거는 소스에만 있음 — kscOriginRef)\\n'+
  '- source / system: '+g(o.source)+' / '+g(o.system)+'\\n'+
  '- location: '+g(o.location)+'\\n'+
  '- ref / ts: '+g(o.ref)+' / '+g(o.ts)+'\\n'+
  '\\n할 일\\n'+
  '1. 원본 로그 레코드를 가져온다:\\n'+fetchLine+'\\n'+
  '2. 원본에서 공격 성립 여부를 확인한다 — 인증정보(pass·admin·mysql.user 등) 대상 여부, 실제 데이터 추출(응답크기·retcode) 여부, 쓰기/파일/권한 시도 여부.\\n'+
  '3. 판정한다 — 공격이면 중대도와 피해범위를, 데이터추출/쓰기 정황이 있으면 대상 테이블 피해까지 확인한다.\\n'+
  '4. 대응한다 — SPEC_JEV_SQLI_DETECTION.md \\u00a77 에 따라 통지하고, 사람 리뷰가 필요하면 '+ksclink+'연결된 giip 이슈를 만든다. 오탐이면 근거와 함께 benign 으로 기록한다.\\n'+
  '\\n참고: 정본 giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md \\u00b7 운영 giip-fde-agent/docs/60-operations/secwatch-ai-onboarding.md \\u00b7 이슈 giip 3833.';
}
function fallback(text,done){const ta=document.createElement('textarea');ta.value=text;document.body.appendChild(ta);ta.select();try{document.execCommand('copy');done();}catch(e){}document.body.removeChild(ta);}
function toast(msg){const t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),1400);}
function cp(i,btn){
 const prompt=(window.__prompts||[])[i]; if(!prompt) return;
 const orig=btn.textContent, done=()=>{btn.textContent='\\u2713 '+T.copied;btn.classList.add('done');toast(T.copied);setTimeout(()=>{btn.textContent=orig;btn.classList.remove('done');},1500);};
 if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(prompt).then(done,()=>fallback(prompt,done));}
 else fallback(prompt,done);
}
function pageCount(){return Math.max(1, Math.ceil(allEvents.length/PAGE_SIZE));}
function renderPager(){
 const el=document.getElementById('pager'); const pages=pageCount();
 if(allEvents.length<=PAGE_SIZE){el.innerHTML='';return}
 el.innerHTML='<button id=pgprev'+(curPage<=0?' disabled':'')+'>'+T.prev+'</button>'+
   '<span class=pginfo>'+T.page+' '+(curPage+1)+' / '+pages+'</span>'+
   '<button id=pgnext'+(curPage>=pages-1?' disabled':'')+'>'+T.next+'</button>';
 const p=document.getElementById('pgprev'), n=document.getElementById('pgnext');
 if(p)p.onclick=()=>{if(curPage>0){curPage--;renderPage();}};
 if(n)n.onclick=()=>{if(curPage<pages-1){curPage++;renderPage();}};
}
function renderPage(){
 const rowsEl=document.getElementById('rows');
 if(!allEvents.length){rowsEl.innerHTML='<tr><td colspan=8 class=empty>'+T.empty+'</td></tr>';renderPager();return}
 const pages=pageCount();
 if(curPage>=pages)curPage=pages-1; if(curPage<0)curPage=0;
 const start=curPage*PAGE_SIZE, slice=allEvents.slice(start, start+PAGE_SIZE);
 const fshort=f=>(f||'').replace(/^secevt_/,'');
 rowsEl.innerHTML=slice.map((e,j)=>{
  const i=start+j;  // global index — matches window.__prompts (built from full list)
  const inj=(e.inj!=null)?Number(e.inj).toFixed(2):'-';
  const o=e.origin||{}, label=esc((o.source||'')+' '+(o.ref||o.location||'')), prompt=window.__prompts[i];
  const whyHtml=((e.route=='alert'||e.route=='review')&&e.why)?'<div class=why>'+esc(e.why)+'</div>':'';
  const oc=prompt
    ? '<span class=osrc>'+label+'</span><button class=cp onclick="cp('+i+',this)">\\u29c9 '+T.copy+'</button><div class=cmd title="'+esc(prompt)+'">'+esc(prompt)+'</div>'
    : '<span class=osrc>'+label+'</span><button class="cp nocmd" title="'+esc(T.nocmd)+'">\\u2014</button>';
  return '<tr class="'+(e.route||'')+'"><td>'+esc(e.ts||'')+'</td><td class=rt>'+esc(e.route||'')+whyHtml+
   '</td><td class=factor><span>'+esc(fshort(e.factor))+'</span></td><td class=sc>'+inj+
   '</td><td class=sc>'+(e.sev??'')+'</td><td>'+esc(e.attack||'')+'</td><td>'+esc(e.engine||'')+
   '</td><td class=origin>'+oc+'</td></tr>';
 }).join('');
 renderPager();
}
// liveness: agent heartbeat (tLSvr.lsChkdt) for this sk's csn — shows even when there are 0 verdicts.
async function beat(){
 const el=document.getElementById('live'), txt=document.getElementById('live_txt'), ag=document.getElementById('agents');
 try{
  const r=await fetch('/api/health'); const h=await r.json();
  if(h.error||h.total==null){el.className='stat live unk';txt.textContent=T.live_unknown;ag.innerHTML='';return}
  const total=Number(h.total)||0, active=Number(h.active)||0;
  const crit=Array.isArray(h.critical)?h.critical:[], warn=Array.isArray(h.warning)?h.warning:[];
  if(total===0){el.className='stat live unk';txt.textContent=T.live_none;ag.innerHTML='';return}
  let cls='stat live';
  if(crit.length)cls+=' down'; else if(warn.length||active<total)cls+=' warn';
  el.className=cls;
  txt.textContent=T.agents+' '+active+'/'+total+' '+T.alive;
  ag.innerHTML=
   crit.map(c=>'<div class="ag down"><span class=st>'+T.st_down+'</span><span class=host>'+esc(String(c.hostname||c.lssn||'?'))+'</span><span class=ago>'+esc(c.minutes_ago!=null?c.minutes_ago+' '+T.ago_min:'')+'</span></div>').join('')+
   warn.map(w=>'<div class="ag stale"><span class=st>'+T.st_stale+'</span><span class=host>'+esc(String(w.hostname||w.lssn||'?'))+'</span><span class=ago>'+esc(String(w.last_checkin_kst||''))+'</span></div>').join('');
 }catch(err){el.className='stat live unk';txt.textContent=T.live_unknown;}
}
async function tick(){
 try{
  const r=await fetch('/api/events?minutes='+MIN); const d=await r.json();
  document.getElementById('who').textContent='csn '+(d.csn||'?')+' · '+T.last+' '+MIN+' '+T.min;
  document.getElementById('upd').textContent=T.updated+' '+new Date().toLocaleTimeString();
  const dot=document.getElementById('dot');
  if(d.error){dot.className='dot err';allEvents=[];document.getElementById('rows').innerHTML='<tr><td colspan=8 class=empty>'+d.error+'</td></tr>';document.getElementById('pager').innerHTML='';return}
  dot.className='dot';
  const ev=d.events||[];
  allEvents=ev;
  document.getElementById('n').textContent=ev.length;
  document.getElementById('na').textContent=ev.filter(e=>e.route=='alert').length;
  document.getElementById('nr').textContent=ev.filter(e=>e.route=='review').length;
  document.getElementById('nl').textContent=ev.filter(e=>e.route=='log').length;
  window.__cmds=ev.map(e=>e.origincmd||originCmd(e.origin));  // giipdb 저장 커맨드 우선, 없으면 클라 재생성(giip #3833)
  window.__prompts=ev.map(e=>aiPrompt(e));
  renderPage();  // keeps curPage across polls; clamped if the list shrank
 }catch(err){document.getElementById('dot').className='dot err';}
}
// 생존신호(항목 5): secevt_run 이 남긴 로컬 하트비트를 읽어 "마지막 스윕 N분전 · 확인 M · 후보 K"를 표시.
// 보낼 이벤트가 0건이라 목록이 비어도 "멈춘 건지 이상이 없는 건지"를 구분할 수 있게 한다.
async function beatRun(){
 const el=document.getElementById('hb');
 try{
  const r=await fetch('/api/heartbeat'); const h=await r.json();
  if(!h||!h.ts){el.textContent=T.sweep_none;return}
  const agoMin=Math.max(0,Math.round((Date.now()/1000-h.ts)/60));
  el.textContent=T.swept+' '+agoMin+' '+T.min+' '+T.ago+' · '+T.checked+' '+(h.parsed!=null?h.parsed:'?')+' · '+T.cand+' '+(h.candidates!=null?h.candidates:'?');
 }catch(err){el.textContent=T.sweep_none;}
}
tick(); beat(); beatRun(); setInterval(tick, POLL*1000); setInterval(beat, POLL*1000); setInterval(beatRun, POLL*1000);
</script></body></html>"""

HELP = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>secwatch — Column Help</title>
<style>
 :root{--bg:#0d1117;--panel:#151a21;--bd:#232b36;--tx:#d4dae2;--mut:#7d8895;--red:#cf6b7f;--amber:#d4a24c;--grn:#5b9d77}
 *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--tx);
   font:14px/1.6 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif}
 .wrap{max-width:860px;margin:0 auto;padding:32px 22px 70px}
 h1{font-size:19px;margin:0 0 4px} .sub{color:var(--mut);font-size:13px;margin:0 0 24px}
 h2{font-size:15px;margin:26px 0 8px;border-bottom:1px solid var(--bd);padding-bottom:6px}
 table{width:100%;border-collapse:collapse;font-size:13px;margin:6px 0}
 th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--bd);vertical-align:top}
 th{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.06em}
 code{font-family:ui-monospace,monospace;font-size:12px;background:#1b222c;border:1px solid var(--bd);border-radius:4px;padding:1px 5px}
 .a{color:var(--red)} .r{color:var(--amber)} .l{color:var(--grn)}
 a{color:#7fb6d4} .back{display:inline-block;margin-bottom:18px;font-size:13px}
 p{color:#c3cad3}
</style></head><body><div class="wrap">
<a class="back" href="/">&larr; back to monitor</a>
<h1>secwatch — Column Help</h1>
<p class="sub">How to read the threat monitor. Verdicts are produced by a 1st-pass deterministic prefilter and a 2nd-pass Jev (TypeSafe System One) judgment.</p>

<h2>How the monitor works (data window)</h2>
<p>The monitor shows a <strong>rolling window</strong> &mdash; it does <strong>not</strong> keep piling rows up in the page. On every poll it re-queries and <strong>replaces</strong> the whole list (newest first, by insertion id). Rows older than the window drop off the view; nothing accumulates in the browser.</p>
<table><tr><th>Setting</th><th>Default</th><th>Meaning</th></tr>
<tr><td><code>--minutes</code></td><td>1440</td><td>Time window shown &mdash; the last N minutes of verdicts (default 24h). Use a larger value to look further back.</td></tr>
<tr><td><code>--page-size</code></td><td>25</td><td>Rows per page in the table (client-side paging over the fetched window).</td></tr>
<tr><td><code>--poll</code></td><td>60</td><td>Refresh interval in seconds (re-fetch &amp; replace).</td></tr></table>
<p>The verdicts themselves are stored in the database table <code>tKVSSecurityCheck</code> and persist there; the monitor only reads a time window of that table via the stored procedure <code>pApiKVSSecurityCheckWindowbySk</code> (scoped to your csn by the agent key). <strong>Retention:</strong> the result table currently has <em>no</em> automatic cleanup &mdash; verdict rows remain in the DB indefinitely until a retention policy is added (for comparison, the raw tKVS input is pruned after 7 days).</p>

<h2>Agent liveness (header badge)</h2>
<p>The <strong>Agents N/M alive</strong> badge in the header is <strong>independent of verdicts</strong>. A quiet server that is not under attack produces no candidate events, so it writes <strong>zero</strong> rows to the verdict table &mdash; yet its agent is still healthy. The badge answers &ldquo;is the agent alive?&rdquo; even when the table is empty.</p>
<p>It reads <code>tLSvr.lsChkdt</code> (agent check-in time) for your csn via <code>pApiAgentHealthCheckbySk</code>. Colour: <strong style="color:var(--grn)">green</strong> = all agents checked in within the last hour; <strong style="color:var(--amber)">amber</strong> = some are slow (10&ndash;59 min) or inactive; <strong style="color:var(--red)">red</strong> = at least one is down (no check-in for 60+ min). Slow/down servers are listed by hostname just under the header.</p>

<h2>Route</h2>
<p>Where the verdict is routed (gate rules). <strong>alert</strong> and <strong>review</strong> rows show the exact reason inline under the route value &mdash; so you don't have to open each row.</p>
<table><tr><th>Value</th><th>Meaning</th></tr>
<tr><td class="a">alert</td><td>High-confidence attack, or data-exfiltration / write attempt suspected. Notify immediately.</td></tr>
<tr><td class="r">review</td><td>Borderline — a human should look. Also used when Jev was skipped/failed and a candidate remains.</td></tr>
<tr><td class="l">log</td><td>Judged benign. Recorded for counts only, no notification.</td></tr></table>

<h2>Type</h2>
<p>Event source type (shown without the <code>secevt_</code> prefix).</p>
<table><tr><th>Type</th><th>Source</th></tr>
<tr><td><code>batch_audit</code></td><td>Aurora / DB audit log (batch)</td></tr>
<tr><td><code>waf</code></td><td>WAF log</td></tr>
<tr><td><code>cf</code></td><td>CloudFront (CDN) access log</td></tr>
<tr><td><code>signal</code></td><td>Derived/aggregated signal or other app log</td></tr></table>

<h2>inj &mdash; is_injection</h2>
<p>Jev <code>noul</code> probability (0.00&ndash;1.00) that the request is a SQL-injection attack or attack preparation (recon). There is no separate confidence for a noul &mdash; the probability itself is the signal. Higher = more likely an attack.</p>

<h2>sev &mdash; severity</h2>
<table><tr><th>Score</th><th>Meaning</th></tr>
<tr><td>0</td><td>Noise</td></tr>
<tr><td>1</td><td>Recon / probing</td></tr>
<tr><td>2</td><td>Enumeration / read attempt</td></tr>
<tr><td>3</td><td>Reading credentials / personal data</td></tr>
<tr><td>4</td><td>Write / file / privilege manipulation attempt</td></tr></table>

<h2>Attack &mdash; attack_type</h2>
<table><tr><th>Value</th><th>Meaning</th></tr>
<tr><td><code>boolean_blind</code></td><td>Boolean blind (ASCII/SUBSTRING true/false probing)</td></tr>
<tr><td><code>time_blind</code></td><td>Time blind (SLEEP/BENCHMARK)</td></tr>
<tr><td><code>union_based</code></td><td>UNION-based extraction</td></tr>
<tr><td><code>error_based</code></td><td>Error-based (EXTRACTVALUE/UPDATEXML)</td></tr>
<tr><td><code>file_write</code></td><td>File write (INTO OUTFILE/DUMPFILE)</td></tr>
<tr><td><code>file_read</code></td><td>File read (LOAD_FILE)</td></tr>
<tr><td><code>schema_enum</code></td><td>Schema enumeration (information_schema, etc.)</td></tr>
<tr><td><code>stacked_or_ddl</code></td><td>Stacked queries / DDL (;drop/alter, etc.)</td></tr>
<tr><td><code>recon_probe</code></td><td>Reconnaissance / probing</td></tr>
<tr><td><code>benign</code></td><td>Not an attack</td></tr></table>

<h2>Engine</h2>
<table><tr><th>Value</th><th>Meaning</th></tr>
<tr><td><code>jev-1.13</code></td><td>2nd-pass Jev (TypeSafe System One) judged this event.</td></tr>
<tr><td><code>rule</code></td><td>Jev was skipped or unavailable; verdict is from the deterministic prefilter only (conservative).</td></tr></table>

<h2>Origin &rarr; AI prompt</h2>
<p>Where the raw (unmasked) record lives at the source. Because events are masked at the agent, the original evidence exists only at the source &mdash; this column is the pointer back to it.</p>
<p>Click <code>&#x29c9; copy AI prompt</code> to copy a ready-to-paste instruction (Korean) for an AI agent. Instead of running a shell command yourself, paste it into your AI assistant and let it drive the investigation. The prompt is self-contained &mdash; it embeds this row's verdict facts, the origin pointer, the fetch command (when one can be built), and the next-action steps per the spec:</p>
<table><tr><th>Part</th><th>Content</th></tr>
<tr><td>Verdict facts</td><td>time, route + reason, type, attack type, injection probability, severity, engine, lssn</td></tr>
<tr><td>Origin pointer</td><td><code>kscOriginRef</code>: source / system / location / ref &mdash; where to fetch the raw record</td></tr>
<tr><td>Fetch command</td><td>S3 (<code>aws s3 cp</code>) or Aurora/CloudWatch (<code>aws logs get-log-events</code>) when derivable; otherwise the AI uses the location</td></tr>
<tr><td>Next actions</td><td>confirm the attack, assess data-extraction / write, then notify &amp; open a linked giip issue per <code>SPEC_JEV_SQLI_DETECTION.md &sect;7</code></td></tr></table>
<p style="color:var(--mut);font-size:12px">Fetching the raw record may require the AWS CLI configured for the relevant account. The AI prompt tells the agent to adapt the command to the environment if needed.</p>
</div></body></html>"""

class Handler(BaseHTTPRequestHandler):
    sk = csn = None
    poll = 10
    minutes = 1440
    page_size = 25
    lang = "en"  # UI language (default English). Add languages to I18N in PAGE (select via --lang).
    heartbeat_path = None  # secevt_run 하트비트 파일(항목 5): "스윕이 돌았다 + 확인건수 + 후보 0" 생존신호.
    def log_message(self, *a): pass  # stay quiet (also avoids sk leakage)
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            self._send(200, PAGE.replace("%POLL%", str(self.poll)).replace("%MIN%", str(self.minutes))
                       .replace("%PAGESIZE%", str(self.page_size)).replace("%LANG%", self.lang),
                       "text/html; charset=utf-8"); return
        if self.path.startswith("/help"):
            self._send(200, HELP, "text/html; charset=utf-8"); return
        if self.path.startswith("/api/events"):
            q = urllib.parse.urlparse(self.path).query
            minutes = self.minutes
            try:
                minutes = int(urllib.parse.parse_qs(q).get("minutes", [self.minutes])[0])
            except (ValueError, TypeError):
                pass
            try:
                res = fetch_results(self.sk, minutes)
            except urllib.error.URLError as e:
                res = {"error": "query failed: %s" % str(getattr(e, "reason", e)).replace(self.sk or "", "[REDACTED]")}
            res["csn"] = self.csn
            self._send(200, json.dumps(res, ensure_ascii=False)); return
        if self.path.startswith("/api/health"):
            try:
                res = fetch_health(self.sk)
            except urllib.error.URLError as e:
                res = {"error": "query failed: %s" % str(getattr(e, "reason", e)).replace(self.sk or "", "[REDACTED]")}
            res["csn"] = self.csn
            self._send(200, json.dumps(res, ensure_ascii=False)); return
        if self.path.startswith("/api/heartbeat"):
            hb = {}
            try:
                if self.heartbeat_path and os.path.exists(self.heartbeat_path):
                    with open(self.heartbeat_path, "r", encoding="utf-8") as f:
                        hb = json.load(f)
            except (OSError, ValueError):
                hb = {}
            self._send(200, json.dumps(hb, ensure_ascii=False)); return
        self._send(404, "{}")

def main():
    ap = argparse.ArgumentParser(description="secwatch threat monitor (reads verdict results)")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--poll", type=int, default=60, help="poll interval in seconds (default 60 = 1 min)")
    ap.add_argument("--minutes", type=int, default=1440, help="query time window in minutes (default 1440 = 24h)")
    ap.add_argument("--page-size", type=int, default=25, help="rows per page (default 25)")
    ap.add_argument("--lang", default="en", help="UI language (default en; extend via I18N in PAGE)")
    ap.add_argument("--heartbeat", default=None,
                    help="secevt_run 하트비트 파일 경로(기본 env GIIP_SECEVT_HEARTBEAT 또는 ./secwatch.last_run.json). secevt_run 과 같은 경로를 가리켜야 한다")
    ap.add_argument("--self-test", action="store_true", help="run one query and exit (no server)")
    a = ap.parse_args()
    sk, csn = resolve()
    if not sk:
        sys.stderr.write("[monitor] no sk (set env GIIP_SK or giipAgent.cfg sk=).\n"); sys.exit(3)
    if a.self_test:
        r = fetch_results(sk, a.minutes)
        n = len(r.get("events", [])) if "events" in r else 0
        sys.stderr.write("[monitor] self-test: %s (csn=%s results=%d)\n"
                         % ("OK" if "error" not in r else ("ERR:" + r["error"]), csn, n))
        sys.exit(0 if "error" not in r else 4)
    Handler.sk, Handler.csn, Handler.poll, Handler.minutes, Handler.page_size, Handler.lang = \
        sk, csn, a.poll, a.minutes, a.page_size, a.lang
    Handler.heartbeat_path = a.heartbeat or os.environ.get("GIIP_SECEVT_HEARTBEAT") \
        or os.path.join(os.getcwd(), "secwatch.last_run.json")
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    sys.stderr.write("[monitor] http://127.0.0.1:%d  (csn=%s, last %d min, %d s poll, Ctrl+C to quit)\n"
                     % (a.port, csn, a.minutes, a.poll))
    try: srv.serve_forever()
    except KeyboardInterrupt: sys.stderr.write("\n[monitor] stopped\n")

if __name__ == "__main__":
    main()
