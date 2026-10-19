#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_collect.py — 소스 로그(①) → 정규화 이벤트(②) 수집부. 리눅스/윈도우 공용, stdlib만.

소스 로그 파일(또는 stdin)을 읽어 사양서 §5 이벤트 스키마(+origin)로 바꿔 JSON 배열로 출력한다.
그대로 secevt_agent.py 에 파이프하면 마스킹·전단필터·게이트웨이 전송까지 이어진다.
정본 설계: giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md §5·§17. 관련 giip #3833.

사용:
  python3 secevt_collect.py --source aurora_audit --file /var/log/audit/server_audit.log
  python3 secevt_collect.py --source waf --file waf.jsonl
  python3 secevt_collect.py --source cloudfront --file cf-access.log
  python3 secevt_collect.py --source generic --file events.jsonl   # 이미 정규화된 JSON-lines/배열
  ... | python3 secevt_collect.py --source generic --stdin | python3 secevt_agent.py --lssn <LSSN> --stdin
  python3 secevt_collect.py --source aurora_audit --file a.log --since-offset .state  # 증분(처리위치 기록)

origin(원본 위치)은 소스/파일/라인번호/식별자/시각으로 자동 채운다 — 침해대응 시 ①로 복귀하는 단서.
IP·원본 SQL 등 민감값은 여기서 '분류/형태'로만 두거나 그대로 두고, 마스킹은 secevt_agent 가 수행한다.
"""
import sys, os, csv, io, json, argparse, re

def _origin(source, system, location, ref, ts):
    o = {"source": source, "system": system, "location": location, "ref": ref, "ts": ts}
    return {k: v for k, v in o.items() if v not in (None, "")}

# ── aurora_audit: MariaDB/MySQL server audit 플러그인 CSV 1행 ────────────────
# 형식: timestamp,serverhost,username,host,connectionid,queryid,operation,database,object,retcode
#   object(=QUERY 의 SQL)는 작은따옴표로 감싸고 내부 따옴표는 '' 로 이스케이프 → csv quotechar="'".
def parse_aurora_audit(line, system, location, lineno):
    line = line.rstrip("\r\n")
    if not line:
        return None
    try:
        row = next(csv.reader(io.StringIO(line), quotechar="'", doublequote=True, skipinitialspace=False))
    except Exception:
        return None
    if len(row) < 7:
        return None
    ts = row[0].strip('"').strip()
    username = row[2] if len(row) > 2 else None
    queryid = row[5] if len(row) > 5 else None
    operation = (row[6] if len(row) > 6 else "").upper()
    database = row[7] if len(row) > 7 else None
    sql = row[8] if len(row) > 8 else None
    retcode = None
    if len(row) > 9:
        try: retcode = int(row[9])
        except (ValueError, TypeError): retcode = None
    if operation not in ("QUERY", "EXECUTE", "PREPARE"):
        return None  # CONNECT/DISCONNECT 등은 대상 아님
    return {
        "src": "aurora_audit", "ts": ts, "db": database, "dbuser": username,
        # 감사로그의 host 필드 = 접속원. 추적용으로 실제 값을 보낸다(giip #3833, 2026-10-19 결정).
        "client_ip": (row[3].strip() if len(row) > 3 and row[3].strip() not in ("", "-") else None),
        "op": "QUERY", "retcode": retcode, "sql_shape": sql,
        "origin": _origin("aurora_audit", system, location, "queryid#%s" % queryid if queryid else "line#%d" % lineno, ts),
    }

# ── waf: AWS WAF 로그(JSON lines) ──────────────────────────────────────────
def parse_waf(line, system, location, lineno):
    line = line.strip()
    if not line:
        return None
    try:
        j = json.loads(line)
    except json.JSONDecodeError:
        return None
    hr = j.get("httpRequest", {}) or {}
    ua = None
    for h in (hr.get("headers") or []):
        if str(h.get("name", "")).lower() == "user-agent":
            ua = h.get("value")
    ts = j.get("timestamp")
    if isinstance(ts, (int, float)):  # epoch ms
        ts = str(ts)
    return {
        "src": "waf", "ts": ts,
        "req_uri": hr.get("uri"), "req_args_shape": hr.get("args"),
        # client_ip: 공격자 추적·차단에 실제 IP 가 필요하다는 제품 결정(2026-10-19, giip #3833).
        # 이 값은 giip DB(kscActorIp)에만 저장되고 Jev(외부 SaaS) 전송 state 에는 들어가지 않는다 —
        # 게이트웨이가 state 조립 시 제외한다. class 라벨은 종전처럼 함께 보낸다(빠른 필터용).
        "client_ip": hr.get("clientIp"),
        "client_ip_class": "external" if hr.get("clientIp") else "unknown",
        "ua_class": "script" if (ua and not re.search(r"Mozilla|Chrome|Safari|Firefox", ua or "")) else "browser",
        "origin": _origin("waf", system, location,
                          "requestId#%s" % j.get("requestId") if j.get("requestId") else "line#%d" % lineno, ts),
    }

# ── cloudfront: W3C 탭구분 접근로그 ────────────────────────────────────────
# 표준 필드: date time x-edge-location sc-bytes c-ip cs-method cs(Host) cs-uri-stem sc-status
#            cs(Referer) cs(User-Agent) cs-uri-query ...
def parse_cloudfront(line, system, location, lineno):
    line = line.rstrip("\r\n")
    if not line or line.startswith("#"):
        return None
    f = line.split("\t")
    if len(f) < 9:
        return None
    ts = "%sT%sZ" % (f[0], f[1]) if len(f) > 1 else None
    uri = f[7] if len(f) > 7 else None
    status = None
    if len(f) > 8:
        try: status = int(f[8])
        except (ValueError, TypeError): status = None
    ua = f[10] if len(f) > 10 else None
    query = f[11] if len(f) > 11 else None
    # sc-bytes(응답 바이트) = W3C 4번째 필드. 사양서 §6.2 가 data_extracted("실제로 값을 읽어냈나")
    # 판정 근거로 요구하는 "응답크기" 가 바로 이 값인데, 지금까지 읽지 않아 resp_bytes 가 늘 비어 있었다
    # → Jev 에 유출 판정 근거가 없어 모니터의 '데이터 유출' 플래그가 뜰 수 없었다.
    resp_bytes = None
    if len(f) > 3:
        try: resp_bytes = int(f[3])
        except (ValueError, TypeError): resp_bytes = None
    return {
        "src": "cloudfront", "ts": ts, "req_uri": uri, "req_args_shape": query,
        "retcode": status, "resp_bytes": resp_bytes,
        # c-ip(W3C 5번째 필드) = 공격자 IP. 추적·차단용으로 실제 값을 보낸다(giip #3833, 2026-10-19 결정).
        "client_ip": (f[4] if len(f) > 4 and f[4] not in ("", "-") else None),
        "client_ip_class": "external", "ua_class": "script",
        "origin": _origin("cloudfront", system, location, "line#%d" % lineno, ts),
    }

# ── generic: 이미 정규화된 JSON-lines 또는 JSON 배열(모든 소스의 안전 범용 경로) ──
def parse_generic(line, system, location, lineno):
    line = line.strip()
    if not line:
        return None
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(ev, dict):
        return None
    ev.setdefault("origin", _origin(ev.get("src", "generic"), system, location, "line#%d" % lineno, ev.get("ts")))
    return ev


# ── sec_monitor: dbre_tools/sec_monitor 의 리포트 JSON(out/report_*.json) ──────────
# 왜 전용 파서인가: 이 포맷을 `generic` 으로 흘리면 받은 JSON 을 그대로 통과시키므로
#   client_ip·resp_bytes 가 비어 모니터의 공격자 IP 가 `-` 가 된다(2026-10-19 실사고).
#   그래서 "원본에서 뽑는" 코드를 여기 둔다 — 수집기는 `--source sec_monitor` 만 쓰면 된다.
#
# 입력 사양(관용적으로 받는다 — 리포트 스키마가 조금 달라도 동작하게):
#   · 파일 전체가 JSON 1개(배열 또는 객체). 객체면 아래 컨테이너 키 중 하나에서 건 목록을 찾는다:
#     findings / alerts / events / items / results / records / rows / data / detections
#     (컨테이너가 없으면 그 객체 자체를 1건으로 본다)
#   · 각 건에서 아래 **동의어 중 먼저 발견된 것**을 §5 필드로 매핑한다(대소문자·하이픈 무시):
#     IP        ← client_ip, clientIp, ip, src_ip, source_ip, remote_addr, remote_ip, attacker_ip, c-ip, peer_ip
#      응답크기  ← resp_bytes, response_bytes, bytes, sc_bytes, sc-bytes, size, length
#      상태코드  ← retcode, status, status_code, http_status, errno, sql_errno, code
#     페이로드  ← sql, query, sql_shape, payload, req_args, args, query_string, statement, request, message, detail
#     요청경로  ← uri, path, req_uri, url, endpoint
#     UA        ← ua, user_agent, userAgent, agent
#     시각      ← ts, timestamp, time, datetime, detected_at, occurred_at, created_at
#     DB/계정   ← db, database, schema / dbuser, user, username, account
#     문맥      ← baseline, summary, note, description, title, rule, reason
# 비고: 마스킹(리터럴 '?' 치환)은 secevt_agent 가 수행한다 — 여기서는 원본을 그대로 담아도 된다.
_SM_CONTAINERS = ("findings", "alerts", "events", "items", "results", "records", "rows", "data", "detections")
_SM_MAP = {
    "client_ip":  ("client_ip", "clientip", "ip", "src_ip", "source_ip", "remote_addr", "remote_ip", "attacker_ip", "cip", "peer_ip"),
    "resp_bytes": ("resp_bytes", "response_bytes", "bytes", "sc_bytes", "size", "length"),
    "retcode":    ("retcode", "status", "status_code", "http_status", "errno", "sql_errno", "code"),
    "sql_shape":  ("sql", "query", "sql_shape", "payload", "statement", "detail"),
    "req_args_shape": ("req_args", "req_args_shape", "args", "query_string", "params"),
    "req_uri":    ("uri", "path", "req_uri", "url", "endpoint"),
    "ua":         ("ua", "user_agent", "agent"),
    "ts":         ("ts", "timestamp", "time", "datetime", "detected_at", "occurred_at", "created_at"),
    "db":         ("db", "database", "schema"),
    "dbuser":     ("dbuser", "user", "username", "account"),
    "baseline":   ("baseline", "summary", "note", "description", "title", "rule", "reason"),
}

def _sm_norm(k):
    return str(k).lower().replace("-", "_").replace(" ", "_")

def _sm_pick(d, names):
    flat = {_sm_norm(k): v for k, v in d.items()}
    for n in names:
        v = flat.get(n)
        if v not in (None, "", [], {}):
            return v
    return None

def _sm_ipclass(ip):
    if not ip:
        return "unknown"
    s = str(ip)
    if s.startswith(("10.", "192.168.", "127.")) or s.startswith("172."):
        return "internal"
    return "external"

def parse_sec_monitor_obj(rec, system, location, lineno):
    """리포트의 건 1개 → §5 이벤트. 공격 단서가 하나도 없으면 None."""
    if not isinstance(rec, dict):
        return None
    ip = _sm_pick(rec, _SM_MAP["client_ip"])
    payload = _sm_pick(rec, _SM_MAP["sql_shape"])
    args = _sm_pick(rec, _SM_MAP["req_args_shape"])
    uri = _sm_pick(rec, _SM_MAP["req_uri"])
    if not any((payload, args, uri)):
        return None  # 전단필터가 볼 게 없는 건은 보내지 않는다(비용·소음)
    rb = _sm_pick(rec, _SM_MAP["resp_bytes"])
    try: rb = int(rb) if rb is not None else None
    except (TypeError, ValueError): rb = None
    rc = _sm_pick(rec, _SM_MAP["retcode"])
    try: rc = int(rc) if rc is not None else None
    except (TypeError, ValueError): rc = None
    ts = _sm_pick(rec, _SM_MAP["ts"])
    ua = _sm_pick(rec, _SM_MAP["ua"])
    ev = {
        "src": "signal",  # §2 표의 인식값(→ secevt_signal). 임의 이름 금지.
        "ts": str(ts) if ts else None,
        "db": _sm_pick(rec, _SM_MAP["db"]),
        "dbuser": _sm_pick(rec, _SM_MAP["dbuser"]),
        "op": "QUERY" if payload else "ALERT",
        "retcode": rc,
        "client_ip": str(ip) if ip else None,
        "client_ip_class": _sm_ipclass(ip),
        "ua_class": ("script" if (ua and not re.search(r"Mozilla|Chrome|Safari|Firefox", str(ua))) else ("browser" if ua else "unknown")),
        "sql_shape": str(payload) if payload else None,
        "req_uri": str(uri) if uri else None,
        "req_args_shape": str(args) if args else None,
        "resp_bytes": rb,
        "baseline": _sm_pick(rec, _SM_MAP["baseline"]),
        "origin": _origin("sec_monitor", system, location,
                          str(_sm_pick(rec, ("id", "ref", "finding_id", "event_id", "seq")) or ("line#%d" % lineno)), ts),
    }
    return {k: v for k, v in ev.items() if v is not None}

def parse_sec_monitor_file(text, system, location):
    """파일 전체(JSON 1개) → 이벤트 리스트. 컨테이너 키에서 건 목록을 찾는다."""
    try:
        doc = json.loads(text)
    except json.JSONDecodeError:
        return []
    recs = None
    if isinstance(doc, list):
        recs = doc
    elif isinstance(doc, dict):
        for c in _SM_CONTAINERS:
            v = doc.get(c)
            if isinstance(v, list):
                recs = v
                break
        if recs is None:
            recs = [doc]
    if not recs:
        return []
    out = []
    for i, rec in enumerate(recs, 1):
        ev = parse_sec_monitor_obj(rec, system, location, i)
        if ev:
            out.append(ev)
    return out

PARSERS = {"aurora_audit": parse_aurora_audit, "waf": parse_waf,
           "cloudfront": parse_cloudfront, "generic": parse_generic,
           "sec_monitor": None}  # sec_monitor 는 파일 전체 JSON — collect_events 가 전용 분기로 처리

# 한 요청 형상에 대해 같은 스윕 안에서 관측된 응답크기 목록을 최대 몇 개까지 실어 보낼지.
# 길게 보낼 이유가 없다(이봉 판정에는 서로 다른 값 2개면 충분하고, state 크기는 비용이다 — 사양서 §9-3).
_SERIES_MAX = 12

def attach_resp_series(events):
    """같은 요청 형상끼리 묶어 resp_series(응답크기 목록)를 채운다 — 유출 가능성 지표의 근거.

    왜 필요한가: 전단필터(secevt_lib.prefilter)에는 이미 `resp_bimodal` 규칙이 있다
    (응답크기가 서로 다른 값 2개 이상 + boolean_blind/union_based 동반 → 블라인드 인젝션이
    참/거짓에 따라 다른 크기를 돌려주고 있다는 신호). 그런데 `resp_series` 를 **아무도 채우지 않아
    그 규칙이 한 번도 발동할 수 없었다.** 사양서 §6.2·§6.3 이 data_extracted("실제로 값을 읽어냈나")
    판정 근거로 드는 "응답 2189B/428B 이봉" 이 바로 이 series 다.

    수집기(에이전트)만 원본 로그의 응답크기를 볼 수 있으므로 여기서 조립해 보낸다
    (게이트웨이는 마스킹된 이벤트만 받기 때문에 스스로 만들 수 없다).

    묶는 키: (src, req_uri) — 쿼리스트링(req_args_shape)은 공격자가 값만 바꿔가며 넣는 쪽이라
    제외해야 같은 엔드포인트에 대한 크기 변화가 한 묶음으로 모인다.
    순수 함수에 가깝게 유지하려고 입력 리스트를 제자리에서 갱신하고 그대로 돌려준다.
    """
    groups = {}
    for ev in events:
        if not isinstance(ev, dict):
            continue
        rb = ev.get("resp_bytes")
        if not isinstance(rb, int):
            continue
        key = (ev.get("src"), ev.get("req_uri"))
        groups.setdefault(key, []).append(rb)
    for ev in events:
        if not isinstance(ev, dict) or ev.get("resp_series"):
            continue  # 파서/소스가 이미 series 를 줬으면 건드리지 않는다
        series = groups.get((ev.get("src"), ev.get("req_uri")))
        if series and len(series) >= 2:
            ev["resp_series"] = series[:_SERIES_MAX]
    return events

def collect_events(source, file=None, use_stdin=False, system=None, since_offset=None):
    """소스 로그를 읽어 정규화 이벤트 리스트를 반환한다(secevt_run.py 도 이 함수를 쓴다)."""
    parser = PARSERS[source]
    location = file or "stdin"
    if file and system is None:
        system = os.path.basename(file)
    events = []
    if use_stdin and source == "sec_monitor":
        return attach_resp_series(parse_sec_monitor_file(sys.stdin.read(), system, location))
    if use_stdin:
        for i, line in enumerate(sys.stdin, 1):
            ev = parser(line, system, location, i)
            if ev:
                events.append(ev)
        return attach_resp_series(events)
    start = 0
    if since_offset and os.path.exists(since_offset):
        try:
            start = int(open(since_offset, "r", encoding="utf-8").read().strip() or "0")
        except (ValueError, OSError):
            start = 0
    # sec_monitor 는 한 줄당 1건이 아니라 **파일 전체가 JSON 1개**다 → 전용 분기.
    if source == "sec_monitor":
        with open(file, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        evs = parse_sec_monitor_file(text, system, location)
        if since_offset:
            try: open(since_offset, "w", encoding="utf-8").write(str(os.path.getsize(file)))
            except OSError: pass
        return attach_resp_series(evs)
    with open(file, "r", encoding="utf-8", errors="replace") as fh:
        if start and start <= os.path.getsize(file):
            fh.seek(start)
        lineno = 0
        for line in fh:
            lineno += 1
            ev = parser(line, system, location, lineno)
            if ev:
                events.append(ev)
        if since_offset:
            try:
                open(since_offset, "w", encoding="utf-8").write(str(fh.tell()))
            except OSError:
                pass
    return attach_resp_series(events)

def main():
    ap = argparse.ArgumentParser(description="소스 로그 → 정규화 이벤트(+origin) 수집부")
    ap.add_argument("--source", required=True, choices=sorted(PARSERS.keys()))
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--file", help="소스 로그 파일 경로")
    g.add_argument("--stdin", action="store_true", help="stdin 에서 로그 읽기")
    ap.add_argument("--system", help="origin.system 에 넣을 소스 시스템명(DB/호스트/계정)")
    ap.add_argument("--since-offset", help="증분 처리위치 파일(마지막으로 읽은 바이트 오프셋 기록/재개)")
    a = ap.parse_args()

    events = collect_events(a.source, file=a.file, use_stdin=a.stdin,
                            system=a.system, since_offset=a.since_offset)
    json.dump(events, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    sys.stderr.write("[secevt_collect] source=%s 파싱 이벤트 %d건 (location=%s)\n"
                     % (a.source, len(events), a.file or "stdin"))

if __name__ == "__main__":
    main()
