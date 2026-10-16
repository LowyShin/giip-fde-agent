#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_lib.py — secwatch 공용 helper (리눅스/윈도우 공용, stdlib만, 부작용 없음).

마스킹(at source)·1차 전단필터·이벤트 조립·설정 해석을 한 곳에 모은다.
secevt_agent.py(게이트웨이 전송)·secevt_sample.py 가 import 해서 쓴다.
정본 설계: giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md §5·§17. 관련 giip #3833.
"""
import os, re

# ── 이벤트 타입(kscFactor) 매핑 (사양서 §17.1) ─────────────────────────────
FACTORS = ("secevt_batch_audit", "secevt_waf", "secevt_cf", "secevt_signal")
SRC_FACTOR = {
    "aurora_audit": "secevt_batch_audit", "db_audit": "secevt_batch_audit", "batch_audit": "secevt_batch_audit",
    "waf": "secevt_waf",
    "cloudfront": "secevt_cf", "cf": "secevt_cf",
    "signal": "secevt_signal", "applog": "secevt_signal",
}
DEFAULT_FACTOR = "secevt_signal"  # src 매핑 불가 시 catch-all

def resolve_factor(ev, forced=None):
    """--factor 강제값이 있으면 그 값, 아니면 이벤트 src 로 4개 타입 중 하나로 매핑."""
    if forced:
        return forced
    return SRC_FACTOR.get(str(ev.get("src") or "").lower(), DEFAULT_FACTOR)

# ── 설정/식별값 해석 (비밀값은 출력하지 않음) ───────────────────────────────
def read_cfg_value(key):
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

def resolve_sk(exit_fn=None):
    sk = os.environ.get("GIIP_SK") or read_cfg_value("sk")
    if not sk and exit_fn:
        exit_fn("sk 를 찾지 못했습니다 (env GIIP_SK 또는 상위 giipAgent.cfg/.cnf 의 sk=).", 3)
    return sk

def resolve_lssn(arg_lssn):
    lssn = arg_lssn or os.environ.get("GIIP_LSSN") or read_cfg_value("lssn")
    return str(lssn).strip() if lssn else None

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

# ── 1차 결정론 전단 필터 (후보만 게이트웨이로 보내기 위한 값싼 게이트) ───────
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
_ERR_RETCODES = {1064, 1054, 1146, 1241, 1242}  # 구문오류 연속(시행착오) 신호(MySQL 1064 등)

def prefilter(ev):
    hay = " ".join(str(ev.get(k) or "") for k in ("sql_shape", "req_args_shape", "req_uri"))
    rules = [name for name, rx in _PREFILTER if rx.search(hay)]
    rc = ev.get("retcode")
    if isinstance(rc, int) and rc in _ERR_RETCODES:
        rules.append("error_retcode")
    series = ev.get("resp_series") or []
    if isinstance(series, list) and len(set(int(x) for x in series if isinstance(x, (int, float)))) >= 2 \
       and any(r in rules for r in ("boolean_blind", "union_based")):
        rules.append("resp_bimodal")
    candidate = len(rules) > 0
    score = min(1.0, round(0.3 + 0.2 * len(rules), 3)) if candidate else 0.0
    return {"candidate": candidate, "rules": sorted(set(rules)), "score": score}

# ── 이벤트 조립 (마스킹 적용 + 전단필터 + origin 통과, v1) ──────────────────
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
        # origin(①소스 원본 위치)은 마스킹 대상 아님 — 침해대응 추적용으로 그대로 통과.
        "origin": ev.get("origin"),
    }
    out["prefilter"] = prefilter(out)
    return {k: v for k, v in out.items() if v is not None}
