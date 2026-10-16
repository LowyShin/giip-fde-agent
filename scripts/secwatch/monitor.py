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
            "origin": "%s %s" % (origin.get("source") or "", origin.get("ref") or origin.get("location") or ""),
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
</style></head><body>
<header>
 <h1><span id="dot" class="dot"></span><span id="title"></span></h1>
 <span class="meta" id="who"></span>
 <span class="meta" id="upd">—</span>
 <div class="stats">
   <span class="stat"><span id="l_total"></span> <b id="n">0</b></span>
   <span class="stat">🔴 <b id="na">0</b></span>
   <span class="stat">🟠 <b id="nr">0</b></span>
   <span class="stat">⚪ <b id="nl">0</b></span>
 </div>
</header>
<table><thead><tr id="hdr"></tr></thead>
<tbody id="rows"></tbody></table>
<script>
const POLL=%POLL%, MIN=%MIN%, LANG="%LANG%";
// i18n: add languages here; UI picks I18N[LANG] (falls back to en). (multilingual: later)
const I18N={
  en:{title:"secwatch Threat Monitor (verdicts)",total:"Total",last:"last",min:"min",
      updated:"Updated",loading:"Loading…",empty:"No recent verdicts",
      cols:["Time","Route","Type","inj","sev","Attack","Engine","Origin"]}
};
const T=I18N[LANG]||I18N.en;
document.getElementById('title').textContent=T.title;
document.getElementById('l_total').textContent=T.total;
document.getElementById('hdr').innerHTML=T.cols.map(c=>'<th>'+c+'</th>').join('');
document.getElementById('rows').innerHTML='<tr><td colspan=8 class=empty>'+T.loading+'</td></tr>';
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
  document.getElementById('rows').innerHTML=ev.map(e=>{
   const inj=(e.inj!=null)?Number(e.inj).toFixed(2):'-';
   return '<tr class="'+(e.route||'')+'"><td>'+(e.ts||'')+'</td><td class=rt>'+(e.route||'')+
    '</td><td class=factor><span>'+fshort(e.factor)+'</span></td><td class=sc>'+inj+
    '</td><td class=sc>'+(e.sev??'')+'</td><td>'+(e.attack||'')+'</td><td>'+(e.engine||'')+
    '</td><td class=origin>'+(e.origin||'').replace(/</g,'&lt;')+'</td></tr>';
  }).join('');
 }catch(err){document.getElementById('dot').className='dot err';}
}
tick(); setInterval(tick, POLL*1000);
</script></body></html>"""

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
