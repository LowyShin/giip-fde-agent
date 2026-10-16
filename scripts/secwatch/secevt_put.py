#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_put.py — giip-fde-agent 보안점검 입력 producer (리눅스/윈도우 공용, stdlib만).

tKVS 에 종류별로 분리된 4개 보안점검 입력 factor 를 던진다. 판정(1차 룰 + 2차 Jev)은
별도 consumer(판정 워커)가 이 factor 들을 읽어 tKVSSecurityCheck 에 적재한다.

4개 factor(사양서 §17.1) — 이벤트 src 로 자동 매핑:
  secevt_batch_audit  Aurora/DB 감사로그(배치)   ← src=aurora_audit|db_audit|batch_audit
  secevt_waf          WAF 로그                   ← src=waf
  secevt_cf           CloudFront(CDN) 접근로그    ← src=cloudfront|cf
  secevt_signal       파생/집계 신호·기타 로그    ← src=signal|applog|그 외(기본)

핵심 규약 (사양서 SPEC_JEV_SQLI_DETECTION.md §17):
  - factor 주소: kType='lssn', kKey=<lssn>, kFactor=<위 4개 중 하나>
  - kValue: RAW JSON 객체(문자열 래핑 금지, KVS_STORAGE_STANDARD)
  - **마스킹 at source**: SQL 리터럴(따옴표 문자열/숫자)은 tKVS 에 쓰기 전에 '?' 로 치환한다.
    giipdb 에 원본 SQL/PII 를 저장하지 않기 위함. IP 는 원본 대신 종별 라벨만 싣는다.
  - 1차 결정론 전단 필터 결과(candidate/rules/score)를 kValue.prefilter 에 함께 싣는다.

쓰기 경로: giipApiSk4 (text='KVSPut kType kKey kFactor kValue', token=<sk>).
  run-gissue-claude.ps1 의 KVSPut 패턴 및 giipAgentWin lib/Kvs.ps1 과 동일한 계약.

사용:
  echo '<event json>' | python3 secevt_put.py --lssn 71240 --stdin
  python3 secevt_put.py --lssn 71240 --event-file ev.json
  python3 secevt_put.py --lssn 71240 --event-file ev.json --dry-run   # 전송 안 함, 보낼 payload 출력

인증(sk)·lssn 해석 우선순위(자동, 사용자에게 묻지 않음):
  sk   : env GIIP_SK  ->  현재/상위 폴더의 giipAgent.cfg|.cnf 의 'sk='  ->  실패 시 에러
  lssn : --lssn 인자  ->  env GIIP_LSSN  ->  giipAgent.cfg|.cnf 의 'lssn='
  sk 값은 로그/출력/예외에 평문으로 남기지 않는다.
종료코드: 0 성공, 2 사용법/입력 오류, 3 인증(sk) 없음, 4 전송 실패.
"""
import sys, os, re, json, argparse, urllib.request, urllib.parse, urllib.error

API_SK4_URL = os.environ.get("GIIP_API_SK4_URL", "https://giipfaw.azurewebsites.net/api/giipApiSk4")

# 보안점검 입력은 '종류별로 분리된 4개 factor' 로 적재한다(사양서 §17.1). 이벤트의 src 로
# 자동 매핑하며, --factor 로 전부 한 factor 에 강제할 수도 있다.
FACTORS = ("secevt_batch_audit", "secevt_waf", "secevt_cf", "secevt_signal")
SRC_FACTOR = {
    # Aurora/DB 감사로그(배치 적재)
    "aurora_audit": "secevt_batch_audit", "db_audit": "secevt_batch_audit", "batch_audit": "secevt_batch_audit",
    # WAF 로그
    "waf": "secevt_waf",
    # CloudFront(CDN) 접근로그
    "cloudfront": "secevt_cf", "cf": "secevt_cf",
    # 파생/집계 신호(응답크기 이봉·빈도 급증 등)와 그 외 애플리케이션 로그
    "signal": "secevt_signal", "applog": "secevt_signal",
}
DEFAULT_FACTOR = "secevt_signal"  # src 매핑 불가 시 catch-all

def resolve_factor(ev, forced):
    """--factor 가 주어지면 그 값으로 강제, 아니면 이벤트 src 로 4개 factor 중 하나로 매핑."""
    if forced:
        return forced
    return SRC_FACTOR.get(str(ev.get("src") or "").lower(), DEFAULT_FACTOR)

# ── 인증/식별값 해석 (비밀값은 출력하지 않음) ──────────────────────────────
def _read_cfg_value(key):
    """현재 디렉터리와 이 스크립트 위치에서 루트까지 giipAgent.cfg|.cnf 의 '<key>=' 를 찾는다."""
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

def resolve_sk():
    sk = os.environ.get("GIIP_SK") or _read_cfg_value("sk")
    if not sk:
        sys.stderr.write("[secevt_put] sk 를 찾지 못했습니다 (env GIIP_SK 또는 상위 giipAgent.cfg/.cnf 의 sk=). "
                         "비밀값을 인자/URL 에 넣지 마십시오.\n")
        sys.exit(3)
    return sk

def resolve_lssn(arg_lssn):
    lssn = arg_lssn or os.environ.get("GIIP_LSSN") or _read_cfg_value("lssn")
    if not lssn:
        sys.stderr.write("[secevt_put] lssn 을 찾지 못했습니다 (--lssn / env GIIP_LSSN / giipAgent.cfg lssn=).\n")
        sys.exit(2)
    return str(lssn).strip()

# ── SQL 리터럴 마스킹 (shape 보존, at source) ─────────────────────────────
_SQL_STR = re.compile(r"'(?:[^']|'')*'")          # 작은따옴표 문자열(이스케이프 '' 포함)
_SQL_DQ  = re.compile(r'"(?:[^"]|"")*"')           # 큰따옴표 문자열
_SQL_NUM = re.compile(r"\b\d+(?:\.\d+)?\b")        # 숫자 리터럴

def mask_sql(sql):
    if not sql:
        return sql
    s = _SQL_STR.sub("?", sql)
    s = _SQL_DQ.sub("?", s)
    s = _SQL_NUM.sub("?", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

# ── 1차 결정론 전단 필터 (후보만 Jev 로 보내기 위한 값싼 게이트) ───────────
_PREFILTER = [
    ("schema_enum",   re.compile(r"information_schema|sys\.(objects|columns|tables)|pg_catalog", re.I)),
    ("union_based",   re.compile(r"\bunion\b.+\bselect\b", re.I)),
    ("file_write",    re.compile(r"into\s+outfile|into\s+dumpfile", re.I)),
    ("file_read",     re.compile(r"load_file\s*\(", re.I)),
    ("boolean_blind", re.compile(r"ascii\s*\(\s*substring|ord\s*\(\s*mid|substr(?:ing)?\s*\(", re.I)),
    ("time_blind",    re.compile(r"\bsleep\s*\(|benchmark\s*\(|pg_sleep\s*\(|waitfor\s+delay", re.I)),
    ("error_based",   re.compile(r"extractvalue\s*\(|updatexml\s*\(|floor\s*\(\s*rand", re.I)),
    ("stacked_or_ddl",re.compile(r";\s*(drop|alter|create|insert|update|delete|grant)\b", re.I)),
]
# 구문오류 연속(시행착오) 신호로 쓰는 retcode 집합(MySQL 1064 등)
_ERR_RETCODES = {1064, 1054, 1146, 1241, 1242}

def prefilter(ev):
    hay = " ".join(str(ev.get(k) or "") for k in ("sql_shape", "req_args_shape", "req_uri"))
    rules = [name for name, rx in _PREFILTER if rx.search(hay)]
    rc = ev.get("retcode")
    if isinstance(rc, int) and rc in _ERR_RETCODES:
        rules.append("error_retcode")
    # 응답크기 이봉(블라인드 참/거짓 분리) 신호
    series = ev.get("resp_series") or []
    if isinstance(series, list) and len(set(int(x) for x in series if isinstance(x, (int, float)))) >= 2 \
       and any(r in rules for r in ("boolean_blind", "union_based")):
        rules.append("resp_bimodal")
    candidate = len(rules) > 0
    score = min(1.0, round(0.3 + 0.2 * len(rules), 3)) if candidate else 0.0
    return {"candidate": candidate, "rules": sorted(set(rules)), "score": score}

# ── kValue 조립 (마스킹 적용 + 전단필터 부착, v1) ─────────────────────────
def build_kvalue(ev):
    out = {
        "v": 1,
        "src": ev.get("src", "other"),
        "ts": ev.get("ts"),
        "db": ev.get("db"),
        "dbuser": ev.get("dbuser"),
        "op": ev.get("op"),
        "retcode": ev.get("retcode"),
        "client_ip_class": ev.get("client_ip_class", "unknown"),
        "ua_class": ev.get("ua_class", "unknown"),
        "sql_shape": mask_sql(ev.get("sql_shape") or ev.get("sql")),
        "req_uri": ev.get("req_uri"),
        "req_args_shape": mask_sql(ev.get("req_args_shape") or ev.get("req_args")),
        "resp_bytes": ev.get("resp_bytes"),
        "resp_series": ev.get("resp_series"),
        "baseline": ev.get("baseline"),
    }
    # 원본 IP/SQL 등 민감 필드가 실수로 들어왔으면 싣지 않는다(at-source 보호).
    out["prefilter"] = prefilter(out)
    return {k: v for k, v in out.items() if v is not None}

# ── giipApiSk4 로 KVSPut ──────────────────────────────────────────────────
def kvs_put(sk, k_type, k_key, k_factor, k_value_obj, dry_run=False):
    jsondata = json.dumps(
        {"kType": k_type, "kKey": k_key, "kFactor": k_factor, "kValue": k_value_obj},
        ensure_ascii=False, separators=(",", ":"),
    )
    form = {"token": sk, "text": "KVSPut kType kKey kFactor kValue", "jsondata": jsondata}
    if dry_run:
        safe = dict(form); safe["token"] = "[REDACTED]"
        print(json.dumps(safe, ensure_ascii=False, indent=2))
        return True
    data = urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(API_SK4_URL, data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8", "replace")
    except urllib.error.URLError as e:
        msg = str(getattr(e, "reason", e)).replace(sk, "[REDACTED]")
        sys.stderr.write("[secevt_put] 전송 실패: %s\n" % msg)
        sys.exit(4)
    # HTTP 는 항상 200 이므로 본문 RstVal 로 성공 판단(사양 15.x giipApi 규약)
    if '"RstVal":200' in body.replace(" ", "") or '"rstval":200' in body.replace(" ", "").lower():
        return True
    # KVSPut 는 성공 시 결과행만 돌려주기도 한다 — error 문자열이 없으면 성공으로 본다.
    low = body.lower()
    if "error" in low or "invalid" in low or "could not" in low:
        sys.stderr.write("[secevt_put] KVSPut 실패 응답: %s\n" % body[:300].replace(sk, "[REDACTED]"))
        sys.exit(4)
    return True

def main():
    ap = argparse.ArgumentParser(description="tKVS 에 보안점검 입력(4개 분리 factor)을 던진다.")
    ap.add_argument("--lssn", help="producing agent lssn (미지정 시 env/cfg)")
    ap.add_argument("--factor", default=None, choices=FACTORS,
                    help="모든 이벤트를 이 factor 로 강제. 미지정 시 이벤트 src 로 4개 factor 자동 매핑")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--event-file", help="이벤트 JSON 파일(객체 1개 또는 배열)")
    g.add_argument("--stdin", action="store_true", help="stdin 에서 이벤트 JSON 읽기")
    ap.add_argument("--only-candidates", action="store_true",
                    help="전단필터 candidate=true 인 이벤트만 전송(가성비)")
    ap.add_argument("--dry-run", action="store_true", help="전송 없이 보낼 payload 만 출력(token 가림)")
    a = ap.parse_args()

    raw = sys.stdin.read() if a.stdin else open(a.event_file, "r", encoding="utf-8").read()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write("[secevt_put] 입력 JSON 파싱 실패: %s\n" % e); sys.exit(2)
    events = parsed if isinstance(parsed, list) else [parsed]

    sk = None if a.dry_run else resolve_sk()
    if a.dry_run and os.environ.get("GIIP_SK"):
        sk = os.environ["GIIP_SK"]
    lssn = resolve_lssn(a.lssn)

    sent = skipped = 0
    by_factor = {}
    for ev in events:
        kv = build_kvalue(ev)
        if a.only_candidates and not kv["prefilter"]["candidate"]:
            skipped += 1
            continue
        factor = resolve_factor(ev, a.factor)
        kvs_put(sk or "DRYRUN", "lssn", lssn, factor, kv, dry_run=a.dry_run)
        by_factor[factor] = by_factor.get(factor, 0) + 1
        sent += 1
    breakdown = ", ".join("%s=%d" % (f, by_factor[f]) for f in FACTORS if f in by_factor) or "(없음)"
    sys.stderr.write("[secevt_put] 완료: 전송 %d, 건너뜀(비후보) %d, lssn=%s factor[%s]%s\n"
                     % (sent, skipped, lssn, breakdown, " (DRY-RUN)" if a.dry_run else ""))

if __name__ == "__main__":
    main()
