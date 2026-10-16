#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monitor.py — secwatch 간이 해킹 감시 모니터 (리눅스/윈도우 공용, stdlib만).

giipAgentWin/giipAgentLinux 의 설정 파일(giipAgent.cfg|.cnf)에서 **sk** 를 읽어 **csn** 을 특정하고,
보안점검 **판정 결과**(`tKVSSecurityCheck`)를 AJAX 로 폴링해 로컬 웹페이지로 보여준다.
읽기 SP: `pApiKVSSecurityCheckWindowbySk` (giipApiSk4 text='KVSSecurityCheckWindow minutes').
rev.3(게이트웨이 구조): tKVS 가 아니라 결과 테이블을 본다(giip #3833, SPEC_JEV_SQLI_DETECTION.md §13·§17).

보안 설계: **sk 는 이 Python 프로세스(서버)에만 있고 브라우저로 내려가지 않는다.** 페이지는 로컬
백엔드(`/api/events`)만 호출하고, 백엔드가 sk 로 giipApiSk4 를 대신 호출한다. 127.0.0.1 전용 바인딩.

사용:
  python3 monitor.py                 # 127.0.0.1:8787, 설정에서 sk/csn 자동, 최근 60분 결과
  python3 monitor.py --port 9000 --minutes 180
  python3 monitor.py --self-test     # 조회 1회만 수행하고 종료(연결 점검)

sk/csn 해석(자동): sk = env GIIP_SK → 상위 giipAgent.cfg|.cnf 'sk='.  csn = env GIIP_CSN → cfg 'csn='(표시용; sk 로 특정).
sk 값은 응답·로그·HTML 어디에도 싣지 않는다.
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
    csn = os.environ.get("GIIP_CSN") or _cfg("csn")  # 표시용(sk 로 특정)
    return sk, csn

def fetch_results(sk, minutes=60):
    """giipApiSk4 KVSSecurityCheckWindow — 그 sk(=csn) 스코프 결과행을 시간범위로 읽는다."""
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
        return {"error": "비JSON 응답", "raw": body[:200]}
    rows = parsed.get("data", parsed) if isinstance(parsed, dict) else parsed
    if not isinstance(rows, list):
        rows = [rows]
    if rows and isinstance(rows[0], dict) and "kscFactor" not in rows[0] and "RstVal" in rows[0]:
        return {"error": "조회 실패(RstVal=%s) — sk/권한 확인" % rows[0].get("RstVal")}
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
            "ts": r.get("kscRegdt"),
            "route": r.get("kscRoutedTo"), "factor": r.get("kscFactor"),
            "inj": r.get("kscIsInjection"), "sev": r.get("kscSeverity"),
            "attack": r.get("kscAttackType"), "engine": r.get("kscEngine"),
            "status": r.get("kscStatus"), "lssn": r.get("kscKey"),
            "origin": origin,  # {source,system,location,ref,ts} — 클라이언트가 표시+다운로드 명령 생성
        })
    return {"events": events}

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
 a.help{color:var(--mut);font-size:12px;text-decoration:none;border:1px solid var(--bd);border-radius:6px;padding:4px 9px}
 a.help:hover{color:var(--tx);border-color:var(--mut)}
</style></head><body>
<header>
 <h1><span id="dot" class="dot"></span><span id="title"></span></h1>
 <span class="meta" id="who"></span>
 <span class="meta" id="upd">—</span>
 <a class="help" href="/help" target="_blank" rel="noopener">? Help</a>
 <div class="stats">
   <span class="stat"><span id="l_total"></span> <b id="n">0</b></span>
   <span class="stat">🔴 <b id="na">0</b></span>
   <span class="stat">🟠 <b id="nr">0</b></span>
   <span class="stat">⚪ <b id="nl">0</b></span>
 </div>
</header>
<table><thead><tr id="hdr"></tr></thead>
<tbody id="rows"></tbody></table>
<div id="toast"></div>
<script>
const POLL=%POLL%, MIN=%MIN%, LANG="%LANG%";
// i18n: add languages here; UI picks I18N[LANG] (falls back to en). (multilingual: later)
const I18N={
  en:{title:"secwatch Threat Monitor (verdicts)",total:"Total",last:"last",min:"min",
      updated:"Updated",loading:"Loading…",empty:"No recent verdicts",
      copy:"copy cmd",copied:"copied!",nocmd:"no download command for this source",
      cols:["Time","Route","Type","inj","sev","Attack","Engine","Origin → download command"]}
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
function fallback(text,done){const ta=document.createElement('textarea');ta.value=text;document.body.appendChild(ta);ta.select();try{document.execCommand('copy');done();}catch(e){}document.body.removeChild(ta);}
function toast(msg){const t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),1400);}
function cp(i,btn){
 const cmd=(window.__cmds||[])[i]; if(!cmd) return;
 const orig=btn.textContent, done=()=>{btn.textContent='\\u2713 '+T.copied;btn.classList.add('done');toast(T.copied);setTimeout(()=>{btn.textContent=orig;btn.classList.remove('done');},1500);};
 if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(cmd).then(done,()=>fallback(cmd,done));}
 else fallback(cmd,done);
}
async function tick(){
 try{
  const r=await fetch('/api/events?minutes='+MIN); const d=await r.json();
  document.getElementById('who').textContent='csn '+(d.csn||'?')+' · '+T.last+' '+MIN+' '+T.min;
  document.getElementById('upd').textContent=T.updated+' '+new Date().toLocaleTimeString();
  const dot=document.getElementById('dot');
  if(d.error){dot.className='dot err';document.getElementById('rows').innerHTML='<tr><td colspan=8 class=empty>'+d.error+'</td></tr>';return}
  dot.className='dot';
  const ev=d.events||[];
  document.getElementById('n').textContent=ev.length;
  document.getElementById('na').textContent=ev.filter(e=>e.route=='alert').length;
  document.getElementById('nr').textContent=ev.filter(e=>e.route=='review').length;
  document.getElementById('nl').textContent=ev.filter(e=>e.route=='log').length;
  if(!ev.length){document.getElementById('rows').innerHTML='<tr><td colspan=8 class=empty>'+T.empty+'</td></tr>';return}
  const fshort=f=>(f||'').replace(/^secevt_/,'');
  window.__cmds=ev.map(e=>originCmd(e.origin));
  document.getElementById('rows').innerHTML=ev.map((e,i)=>{
   const inj=(e.inj!=null)?Number(e.inj).toFixed(2):'-';
   const o=e.origin||{}, label=esc((o.source||'')+' '+(o.ref||o.location||'')), cmd=window.__cmds[i];
   const oc=cmd
     ? '<span class=osrc>'+label+'</span><button class=cp onclick="cp('+i+',this)">\\u29c9 '+T.copy+'</button><div class=cmd title="'+esc(cmd)+'">'+esc(cmd)+'</div>'
     : '<span class=osrc>'+label+'</span><button class="cp nocmd" title="'+esc(T.nocmd)+'">\\u2014</button>';
   return '<tr class="'+(e.route||'')+'"><td>'+esc(e.ts||'')+'</td><td class=rt>'+esc(e.route||'')+
    '</td><td class=factor><span>'+esc(fshort(e.factor))+'</span></td><td class=sc>'+inj+
    '</td><td class=sc>'+(e.sev??'')+'</td><td>'+esc(e.attack||'')+'</td><td>'+esc(e.engine||'')+
    '</td><td class=origin>'+oc+'</td></tr>';
  }).join('');
 }catch(err){document.getElementById('dot').className='dot err';}
}
tick(); setInterval(tick, POLL*1000);
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

<h2>Route</h2>
<p>Where the verdict is routed (gate rules).</p>
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

<h2>Origin &rarr; download command</h2>
<p>Where the raw (unmasked) record lives at the source. Because events are masked at the agent, the original evidence exists only at the source &mdash; this is the pointer back to it.</p>
<p>Click <code>&#x29c9; copy cmd</code> and paste it into your own terminal (cmd) to download that record to a file:</p>
<table><tr><th>Source</th><th>Generated command</th></tr>
<tr><td>S3 (WAF / CloudFront)</td><td><code>aws s3 cp "s3://&hellip;" "./&hellip;"</code></td></tr>
<tr><td>Aurora audit (CloudWatch)</td><td><code>aws logs get-log-events --log-group-name &hellip; --log-stream-name &hellip; &gt; audit_&hellip;.txt</code></td></tr>
<tr><td>other</td><td>no command generated &mdash; the origin label is shown as-is</td></tr></table>
<p style="color:var(--mut);font-size:12px">Requires the AWS CLI configured with access to the relevant account. Adjust the command to your environment if needed.</p>
</div></body></html>"""

class Handler(BaseHTTPRequestHandler):
    sk = csn = None
    poll = 10
    minutes = 60
    lang = "en"  # UI 언어(기본 영어). 다국어는 PAGE 의 I18N 에 추가(--lang 으로 선택).
    def log_message(self, *a): pass  # 조용히(sk 유출 방지 겸)
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            self._send(200, PAGE.replace("%POLL%", str(self.poll)).replace("%MIN%", str(self.minutes))
                       .replace("%LANG%", self.lang), "text/html; charset=utf-8"); return
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
                res = {"error": "조회 실패: %s" % str(getattr(e, "reason", e)).replace(self.sk or "", "[REDACTED]")}
            res["csn"] = self.csn
            self._send(200, json.dumps(res, ensure_ascii=False)); return
        self._send(404, "{}")

def main():
    ap = argparse.ArgumentParser(description="secwatch 간이 해킹 감시 모니터(판정 결과 조회)")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--poll", type=int, default=60, help="폴링 주기(초, 기본 60=1분)")
    ap.add_argument("--minutes", type=int, default=60, help="조회 시간범위(분)")
    ap.add_argument("--lang", default="en", help="UI 언어(기본 en; PAGE 의 I18N 에 추가해 확장)")
    ap.add_argument("--self-test", action="store_true", help="조회 1회 하고 종료(서버 안 띄움)")
    a = ap.parse_args()
    sk, csn = resolve()
    if not sk:
        sys.stderr.write("[monitor] sk 없음(env GIIP_SK 또는 giipAgent.cfg sk=).\n"); sys.exit(3)
    if a.self_test:
        r = fetch_results(sk, a.minutes)
        n = len(r.get("events", [])) if "events" in r else 0
        sys.stderr.write("[monitor] self-test: %s (csn=%s results=%d)\n"
                         % ("OK" if "error" not in r else ("ERR:" + r["error"]), csn, n))
        sys.exit(0 if "error" not in r else 4)
    Handler.sk, Handler.csn, Handler.poll, Handler.minutes, Handler.lang = sk, csn, a.poll, a.minutes, a.lang
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    sys.stderr.write("[monitor] http://127.0.0.1:%d  (csn=%s, 최근 %d분, %d초 폴링, Ctrl+C 종료)\n"
                     % (a.port, csn, a.minutes, a.poll))
    try: srv.serve_forever()
    except KeyboardInterrupt: sys.stderr.write("\n[monitor] 종료\n")

if __name__ == "__main__":
    main()
