#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monitor.py — secwatch 간이 해킹 감시 모니터 (리눅스/윈도우 공용, stdlib만).

giipAgentWin/giipAgentLinux 의 설정 파일(giipAgent.cfg|.cnf)에서 **sk** 를 읽어 **csn** 을
특정하고, 보안점검 이벤트를 AJAX 로 폴링해 로컬 웹페이지로 보여준다.

※ 마이그레이션 중(⑦, giip #3833 rev.3): 게이트웨이 구조로 전환되어 판정 결과는 이제
  **tKVSSecurityCheck**(결과 테이블)에 쌓인다. 이 모니터는 그 결과 테이블 조회로 전환 예정이며,
  아래 tKVS factor 폴링 코드는 구(舊) 경로(tKVS 스테이징)용이다. 결과-조회 SP 신설 후 교체한다.

보안 설계: **sk 는 이 Python 프로세스(서버)에만 있고 브라우저로 내려가지 않는다.** 페이지는
로컬 백엔드(`/api/events`)만 호출하고, 백엔드가 sk 로 giipApiSk4 를 대신 호출한다.
서버는 127.0.0.1 에만 바인딩한다(외부 노출 금지).

사용:
  python3 monitor.py                 # 127.0.0.1:8787, 설정에서 sk/lssn/csn 자동
  python3 monitor.py --port 9000 --lssn 71240
  python3 monitor.py --self-test     # KVSList 읽기 1회만 수행하고 종료(연결 점검, 서버 안 띄움)

sk/lssn/csn 해석(자동): sk = env GIIP_SK → 상위 giipAgent.cfg|.cnf 'sk='.
  lssn = --lssn → env GIIP_LSSN → cfg 'lssn='.  csn = env GIIP_CSN → cfg 'csn='(표시용).
sk 값은 응답·로그·HTML 어디에도 싣지 않는다.
"""
import sys, os, re, json, argparse, urllib.request, urllib.parse, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API_SK4_URL = os.environ.get("GIIP_API_SK4_URL", "https://giipfaw.azurewebsites.net/api/giipApiSk4")

# 종류별로 분리된 4개 보안점검 입력 factor(사양서 §17.1). 모니터는 넷을 모두 폴링해 합쳐 보여준다.
FACTORS = ("secevt_batch_audit", "secevt_waf", "secevt_cf", "secevt_signal")

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
    lssn = os.environ.get("GIIP_LSSN") or _cfg("lssn")
    csn = os.environ.get("GIIP_CSN") or _cfg("csn")  # 표시용(sk 로 특정; 없으면 서버가 sk 로 스코프)
    return sk, lssn, csn

def kvs_list(sk, lssn, factor):
    """giipApiSk4 KVSList — 그 sk(=csn) 스코프의 factor 행을 읽는다. sk 로 csn 이 특정된다."""
    jsondata = json.dumps({"kType": "lssn", "kKey": str(lssn), "kFactor": factor},
                          ensure_ascii=False, separators=(",", ":"))
    form = urllib.parse.urlencode({"token": sk, "text": "KVSList kType kKey kFactor",
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
    # 401 등은 첫 행에 RstVal 만 있음
    if rows and isinstance(rows[0], dict) and "kValue" not in rows[0] and "RstVal" in rows[0]:
        return {"error": "조회 실패(RstVal=%s) — sk/권한 확인" % rows[0].get("RstVal")}
    events = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        kv = r.get("kValue")
        if isinstance(kv, str):
            try: kv = json.loads(kv)
            except json.JSONDecodeError: kv = {"_raw": kv}
        if not isinstance(kv, dict):
            continue
        pf = kv.get("prefilter") or {}
        events.append({
            "ts": kv.get("ts") or r.get("kRegdt"),
            "regdt": r.get("kRegdt"),
            "factor": factor,
            "src": kv.get("src"), "dbuser": kv.get("dbuser"),
            "ip_class": kv.get("client_ip_class"), "retcode": kv.get("retcode"),
            "score": pf.get("score", 0), "candidate": pf.get("candidate", False),
            "rules": pf.get("rules", []),
            "shape": kv.get("sql_shape") or kv.get("req_args_shape") or kv.get("req_uri"),
        })
    events.sort(key=lambda e: str(e.get("regdt") or e.get("ts") or ""), reverse=True)
    return {"events": events}

def kvs_list_all(sk, lssn):
    """4개 factor 를 모두 폴링해 한 목록으로 합친다. 일부 factor 만 실패하면 그 사유를 함께 싣는다."""
    merged, errors = [], []
    for f in FACTORS:
        r = kvs_list(sk, lssn, f)
        if "error" in r:
            errors.append("%s: %s" % (f, r["error"]))
        else:
            merged.extend(r.get("events", []))
    merged.sort(key=lambda e: str(e.get("regdt") or e.get("ts") or ""), reverse=True)
    # 4개 factor 가 전부 실패했을 때만 전체 오류로 본다(일부 성공은 그 결과를 보여준다).
    if errors and not merged and len(errors) == len(FACTORS):
        return {"error": " / ".join(errors)}
    out = {"events": merged}
    if errors:
        out["warn"] = " / ".join(errors)
    return out

PAGE = """<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>secwatch — 해킹 감시</title>
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
 tr.hi td.sc{color:var(--red)} tr.md td.sc{color:var(--amber)} tr.lo td.sc{color:var(--grn)}
 .shape{font-family:ui-monospace,monospace;color:#aeb6c0;max-width:52ch;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .rules span{display:inline-block;background:#1b222c;border:1px solid var(--bd);border-radius:5px;padding:1px 6px;margin:1px;font-size:11px;font-family:ui-monospace,monospace}
 .empty{color:var(--mut);padding:30px;text-align:center}
</style></head><body>
<header>
 <h1><span id="dot" class="dot"></span>secwatch 해킹 감시</h1>
 <span class="meta" id="who">csn ? · lssn ?</span>
 <span class="meta" id="upd">—</span>
 <div class="stats">
   <span class="stat">총 <b id="n">0</b></span>
   <span class="stat">후보 <b id="nc">0</b></span>
   <span class="stat">고위험 <b id="nh">0</b></span>
 </div>
</header>
<table><thead><tr><th>시각</th><th>factor</th><th>점수</th><th>src</th><th>user</th><th>IP</th><th>retcode</th><th>룰</th><th>SQL 형태(마스킹)</th></tr></thead>
<tbody id="rows"><tr><td colspan="9" class="empty">불러오는 중…</td></tr></tbody></table>
<script>
const POLL=%POLL%;
function cls(s){return s>=0.7?'hi':s>=0.4?'md':'lo'}
async function tick(){
 try{
  const r=await fetch('/api/events?minutes=60'); const d=await r.json();
  document.getElementById('who').textContent='csn '+(d.csn||'?')+' · lssn '+(d.lssn||'?');
  document.getElementById('upd').textContent='갱신 '+new Date().toLocaleTimeString();
  const dot=document.getElementById('dot');
  if(d.error){dot.className='dot err';document.getElementById('rows').innerHTML='<tr><td colspan=9 class=empty>'+d.error+'</td></tr>';return}
  dot.className=d.warn?'dot stale':'dot';
  const ev=d.events||[];
  document.getElementById('n').textContent=ev.length;
  document.getElementById('nc').textContent=ev.filter(e=>e.candidate).length;
  document.getElementById('nh').textContent=ev.filter(e=>e.score>=0.7).length;
  if(!ev.length){document.getElementById('rows').innerHTML='<tr><td colspan=9 class=empty>최근 보안점검 이벤트 없음</td></tr>';return}
  const fshort=f=>(f||'').replace(/^secevt_/,'');
  document.getElementById('rows').innerHTML=ev.map(e=>{
   const rs=(e.rules||[]).map(x=>'<span>'+x+'</span>').join('');
   return '<tr class="'+cls(e.score||0)+'"><td>'+(e.ts||e.regdt||'')+'</td><td class=rules><span>'+fshort(e.factor)+'</span></td><td class=sc>'+(e.score||0).toFixed(2)+
    '</td><td>'+(e.src||'')+'</td><td>'+(e.dbuser||'')+'</td><td>'+(e.ip_class||'')+'</td><td>'+(e.retcode??'')+
    '</td><td class=rules>'+rs+'</td><td class=shape title="'+(e.shape||'').replace(/"/g,'&quot;')+'">'+(e.shape||'')+'</td></tr>';
  }).join('');
 }catch(err){document.getElementById('dot').className='dot err';}
}
tick(); setInterval(tick, POLL*1000);
</script></body></html>"""

class Handler(BaseHTTPRequestHandler):
    sk = lssn = csn = None
    poll = 10
    def log_message(self, *a): pass  # 조용히(sk 유출 방지 겸)
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            self._send(200, PAGE.replace("%POLL%", str(self.poll)), "text/html; charset=utf-8"); return
        if self.path.startswith("/api/events"):
            try:
                res = kvs_list_all(self.sk, self.lssn)
            except urllib.error.URLError as e:
                res = {"error": "조회 실패: %s" % str(getattr(e, "reason", e)).replace(self.sk or "", "[REDACTED]")}
            res["csn"] = self.csn; res["lssn"] = self.lssn
            self._send(200, json.dumps(res, ensure_ascii=False)); return
        self._send(404, "{}")

def main():
    ap = argparse.ArgumentParser(description="secwatch 간이 해킹 감시 모니터")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--lssn"); ap.add_argument("--poll", type=int, default=10, help="폴링 주기(초)")
    ap.add_argument("--self-test", action="store_true", help="KVSList 1회 읽고 종료(서버 안 띄움)")
    a = ap.parse_args()
    sk, lssn, csn = resolve()
    lssn = a.lssn or lssn
    if not sk:
        sys.stderr.write("[monitor] sk 없음(env GIIP_SK 또는 giipAgent.cfg sk=).\n"); sys.exit(3)
    if not lssn:
        sys.stderr.write("[monitor] lssn 없음(--lssn / env GIIP_LSSN / cfg lssn=).\n"); sys.exit(2)
    if a.self_test:
        r = kvs_list_all(sk, lssn)
        n = len(r.get("events", [])) if "events" in r else 0
        sys.stderr.write("[monitor] self-test: %s (csn=%s lssn=%s events=%d)\n"
                         % ("OK" if "error" not in r else ("ERR:" + r["error"]), csn, lssn, n));
        sys.exit(0 if "error" not in r else 4)
    Handler.sk, Handler.lssn, Handler.csn, Handler.poll = sk, str(lssn), csn, a.poll
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    sys.stderr.write("[monitor] http://127.0.0.1:%d  (csn=%s lssn=%s, %d초 폴링, Ctrl+C 종료)\n"
                     % (a.port, csn, lssn, a.poll))
    try: srv.serve_forever()
    except KeyboardInterrupt: sys.stderr.write("\n[monitor] 종료\n")

if __name__ == "__main__":
    main()
