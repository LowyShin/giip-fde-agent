#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_lib.py — secwatch 공용 helper (리눅스/윈도우 공용, stdlib만, 부작용 없음).

마스킹(at source)·1차 전단필터·이벤트 조립·설정 해석을 한 곳에 모은다.
secevt_agent.py(게이트웨이 전송)·secevt_sample.py 가 import 해서 쓴다.
정본 설계: giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md §5·§17. 관련 giip #3833.
"""
import os, re, sys, json, hashlib, time

def reconfigure_utf8():
    """stdin/stdout/stderr 를 UTF-8(errors=replace)로 고정한다(공용).
    cp932(일본어 Windows) 등 비 UTF-8 콘솔에서 이모지·한글 입출력이 UnicodeEncodeError/DecodeError 로 죽어,
    전송 성공인데 종료코드 1 이 되는 사고를 막는다(giip #3833). reconfigure 없는 오래된 파이썬은 무시(2차 방어는 호출측)."""
    for name in ("stdin", "stdout", "stderr"):
        st = getattr(sys, name, None)
        try:
            st.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

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
# 규칙을 추가/변경하면 docs/60-operations/secwatch-agent.md 의 "1차 전단필터 판정기준" 표도 같이 고친다
# (정본 문서와 코드 동기화 — giip #3833, DBRE 의뢰 항목 2). 대상 필드: sql_shape, req_args_shape, req_uri.
_PREFILTER = [
    # schema_enum: 스키마/메타 테이블 열람(정찰). performance_schema 포함(DBRE 의뢰 항목 2b).
    ("schema_enum",   re.compile(r"information_schema|performance_schema|sys\.(objects|columns|tables)|pg_catalog", re.I)),
    ("union_based",   re.compile(r"\bunion\b.+\bselect\b", re.I)),
    ("file_write",    re.compile(r"into\s+outfile|into\s+dumpfile", re.I)),
    ("file_read",     re.compile(r"load_file\s*\(", re.I)),
    ("boolean_blind", re.compile(r"ascii\s*\(\s*substring|ord\s*\(\s*mid|substr(?:ing)?\s*\(", re.I)),
    ("time_blind",    re.compile(r"\bsleep\s*\(|benchmark\s*\(|pg_sleep\s*\(|waitfor\s+delay", re.I)),
    ("error_based",   re.compile(r"extractvalue\s*\(|updatexml\s*\(|floor\s*\(\s*rand", re.I)),
    ("stacked_or_ddl",re.compile(r";\s*(drop|alter|create|insert|update|delete|grant)\b", re.I)),
    # 아래 4개는 DBRE 의뢰 항목 2b 로 추가(2026-10-17). 기존 탐지를 약화하지 않는 순수 추가(재현율 확대).
    # cred_table: 자격증명/권한 테이블 표적(mysql.user, mysql.db 등).
    ("cred_table",    re.compile(r"\bmysql\.user\b|\bmysql\.db\b", re.I)),
    # oob_interact: 블라인드/OOB 유출용 외부 상호작용 도메인(OAST/DNS 로그 수집기).
    ("oob_interact",  re.compile(r"\boast\.|\bdnslog\b|burpcollab|\bnip\.io\b", re.I)),
    # ssrf_metadata: 클라우드 메타데이터 엔드포인트 접근 시도(SSRF). req_uri 는 비마스킹이라 IP 가 보존됨.
    ("ssrf_metadata", re.compile(r"169\.254\.169\.254", re.I)),
    # sensitive_file: LFI/경로조작으로 시스템 파일 노출 시도.
    ("sensitive_file",re.compile(r"/etc/passwd", re.I)),
]
_ERR_RETCODES = {1064, 1054, 1146, 1241, 1242}  # 구문오류 연속(시행착오) 신호(MySQL 1064 등)

def prefilter(ev, novel_ctx=None):
    hay = " ".join(str(ev.get(k) or "") for k in ("sql_shape", "req_args_shape", "req_uri"))
    rules = [name for name, rx in _PREFILTER if rx.search(hay)]
    rc = ev.get("retcode")
    if isinstance(rc, int) and rc in _ERR_RETCODES:
        rules.append("error_retcode")
    series = ev.get("resp_series") or []
    if isinstance(series, list) and len(set(int(x) for x in series if isinstance(x, (int, float)))) >= 2 \
       and any(r in rules for r in ("boolean_blind", "union_based")):
        rules.append("resp_bimodal")
    # novel_shape(항목 7, giip #3833): send_novel 가 켜졌고, 이 형태(shape_id)가 "알려진 정상 형태"가
    # 아니면(초출) 후보로 올려 Jev 2차 판정을 받게 한다. 게이트웨이 run.ps1(성역)을 건드리지 않고
    # 에이전트 전단필터만으로 "초출 → Jev" 를 실현하는 경로다. 정상으로 판정되면 호출측이 학습(아래).
    if novel_ctx and novel_ctx.get("send_novel") and novel_ctx.get("shape_id") \
       and not is_known_shape(novel_ctx.get("known") or {}, novel_ctx["shape_id"], novel_ctx.get("now")):
        rules.append("novel_shape")
    candidate = len(rules) > 0
    score = min(1.0, round(0.3 + 0.2 * len(rules), 3)) if candidate else 0.0
    return {"candidate": candidate, "rules": sorted(set(rules)), "score": score}

# ── 초출(novel) 형태 탐지 + 자동학습 (항목 7, giip #3833) ───────────────────
# 핵심 안전장치(자동학습 악용 방지):
#   (1) 학습 단위가 "마스킹된 형태"(리터럴 '?' 치환)의 shape_id 다 → 공격 변형은 형태가 달라 shape_id 가
#       달라지므로, 정상 형태를 학습해도 다른 형태의 공격은 화이트리스트되지 않는다.
#   (2) Jev 가 'log'(정상)로 **실제 판정**(engine=jev)한 형태만 학습한다 → 공격 형태는 Jev 가 log 로
#       판정하지 않으므로 학습 경로에 들어오지 못한다.
#   (3) 학습 항목에 만료(TTL)를 둔다 → 장기 '길들이기'를 제한한다(만료되면 다시 초출로 Jev 재판정).
def compute_shape_id(kv):
    """마스킹된 형태(sql_shape/req_args_shape/req_uri)로 안정적 shape_id 를 만든다. 전부 비면 None."""
    parts = [str(kv.get(k) or "") for k in ("sql_shape", "req_args_shape", "req_uri")]
    basis = "\x1f".join(parts)
    if not basis.replace("\x1f", "").strip():
        return None
    return hashlib.sha256(basis.encode("utf-8", "replace")).hexdigest()[:20]

def load_known_shapes(path):
    """알려진-정상 형태 저장소를 로드한다. 형식 {"v":1,"shapes":{shape_id:{"first":epoch,"exp":epoch}}}."""
    if not path:
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d.get("shapes") or {}
    except (OSError, ValueError):
        return {}

def is_known_shape(known, shape_id, now=None):
    if not shape_id or not known:
        return False
    e = known.get(shape_id)
    if not e:
        return False
    exp = e.get("exp")
    if exp is None:
        return True
    now = now if now is not None else int(time.time())
    return exp > now

def learn_shape(path, shape_id, ttl_days=30, now=None, sample=None):
    """shape_id 를 알려진-정상으로 등록(만료 포함). read-modify-write + 원자적 교체.
    반드시 maybe_learn_shape 의 가드(Jev log 판정)만 통과한 형태에만 쓴다."""
    if not path or not shape_id:
        return False
    now = now if now is not None else int(time.time())
    try:
        shapes = load_known_shapes(path)
        e = shapes.get(shape_id) or {}
        e.setdefault("first", now)
        e["exp"] = now + int(ttl_days) * 86400
        if sample and "sample" not in e:
            e["sample"] = str(sample)[:120]
        shapes[shape_id] = e
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"v": 1, "shapes": shapes}, f, ensure_ascii=False)
        os.replace(tmp, path)
        return True
    except OSError:
        return False

def maybe_learn_shape(path, kv, verdict, ttl_days=30, now=None):
    """Jev 가 'log'(정상)로 실제 판정한 초출(novel_shape) 형태만 알려진-정상으로 자동학습한다.
    공격 형태는 Jev 가 log 로 판정하지 않으므로 학습되지 않는다(악용 방지). 학습하면 True."""
    try:
        rules = (kv.get("prefilter") or {}).get("rules") or []
        if "novel_shape" not in rules:
            return False
        shape_id = kv.get("shape_id")
        if not shape_id or not path or not isinstance(verdict, dict):
            return False
        if verdict.get("routedTo") != "log":
            return False
        if not str(verdict.get("engine") or "").lower().startswith("jev"):
            return False  # rule-only 폴백(prefilter 판정)으로 log 된 건 학습하지 않는다
        sample = kv.get("sql_shape") or kv.get("req_args_shape") or kv.get("req_uri")
        return learn_shape(path, shape_id, ttl_days=ttl_days, now=now, sample=sample)
    except Exception:
        return False

def resolve_known_shapes_path(explicit=None):
    """알려진-형태 저장소 경로: 인자 → env GIIP_SECEVT_KNOWN_SHAPES → cwd/secwatch.known_shapes.json."""
    return explicit or os.environ.get("GIIP_SECEVT_KNOWN_SHAPES") \
        or os.path.join(os.getcwd(), "secwatch.known_shapes.json")

def resolve_send_novel(explicit=None):
    """send_novel 기본 OFF. 인자(True) 또는 env GIIP_SECEVT_SEND_NOVEL(1/true/on) 일 때만 ON."""
    if explicit:
        return True
    return str(os.environ.get("GIIP_SECEVT_SEND_NOVEL") or "").strip().lower() in ("1", "true", "on", "yes")

# ── 이벤트 조립 (마스킹 적용 + 전단필터 + origin 통과, v1) ──────────────────
def build_kvalue(ev, novel_ctx=None):
    out = {
        "v": 1,
        "src": ev.get("src", "other"),
        "ts": ev.get("ts"),
        "db": ev.get("db"),
        "dbuser": ev.get("dbuser"),
        "op": ev.get("op"),
        "retcode": ev.get("retcode"),
        # client_ip: 공격자 추적·차단에 실제 IP 가 필요하다는 제품 결정(2026-10-19, giip #3833).
        # 게이트웨이가 이 값을 giip DB(kscActorIp)에만 저장하고 **Jev 전송 state 에서는 제외**한다
        # (외부 SaaS 에 PII 를 보내지 않는다는 §17.3 의 취지는 유지 — Jev 는 요청 형태로 판정하므로
        #  IP 가 없어도 판정력이 떨어지지 않는다). 반복 공격 문맥이 필요하면 baseline 으로 넘긴다.
        "client_ip": ev.get("client_ip"),
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
    # 초출 형태 판정·학습을 위해 마스킹된 형태 기준 shape_id 를 계산해 novel_ctx 에 싣는다(있을 때만).
    if novel_ctx is not None:
        novel_ctx["shape_id"] = compute_shape_id(out)
    out["prefilter"] = prefilter(out, novel_ctx)
    # send_novel 일 때만 결과/게이트웨이에 shape_id 를 포함한다(요청: 판정결과에 형태 식별자).
    if novel_ctx and novel_ctx.get("send_novel") and novel_ctx.get("shape_id"):
        out["shape_id"] = novel_ctx["shape_id"]
    return {k: v for k, v in out.items() if v is not None}
