#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_judge.py — 보안점검 consumer(판정 워커). 리눅스/윈도우 공용, stdlib만.

csn 의 **최근 1시간 tKVS 전량(factor 불문)** 을 한 번에 읽어, 종류(kFactor)별로 분류하고
1차 전단필터 → (후보만) 2차 Jev 판정으로 **해킹 의심 여부를 체크해 보고**한다.
factor 별로 나눠 읽지 않으므로 factor 이름이 표준과 달라도 누락되지 않는다(사양서 §17.3).

읽기 경로: giipApiSk4 `text='KVSWindow kFactorLike minutes'`, token=<sk>,
  jsondata={"kFactorLike":"secevt%","minutes":60}  → SP `pApiKVSWindowbySk`(csn 은 sk 로 자동).
Jev 경로: POST https://api.typesafe.ai/v1/systemone, Authorization: Bearer <TYPESAFE_API_KEY>
  (사양서 §2·§6). 키는 env TYPESAFE_API_KEY → (옵션)파일. **키는 로그/출력 어디에도 싣지 않는다.**

사용:
  python3 secevt_judge.py                         # csn 1시간 전량 읽어 룰+Jev 판정, 표로 보고
  python3 secevt_judge.py --minutes 120 --json    # 2시간 창, 판정 JSON 출력
  python3 secevt_judge.py --no-jev                # 네트워크 없이 1차 전단필터만(Jev 생략)
  python3 secevt_judge.py --from-file rows.json   # API 대신 KVSWindow 응답(JSON)으로 오프라인 판정
  python3 secevt_sample.py | python3 secevt_judge.py --from-events -   # 샘플 이벤트 직접 판정(학습/점검)

인증(sk)·csn 해석(자동, 사용자에게 묻지 않음):
  sk  : env GIIP_SK → 상위 giipAgent.cfg|.cnf 'sk='   (csn 은 sk 가 서버에서 특정 — 지정 불필요)
  csn : env GIIP_CSN → cfg 'csn='  (표시용)
종료코드: 0 정상(의심 유무와 무관), 2 입력오류, 3 sk 없음, 4 읽기 실패.
"""
import sys, os, re, json, argparse, urllib.request, urllib.parse, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import secevt_put as sp  # prefilter / mask_sql / resolve_sk / _read_cfg_value 재사용(import 시 부작용 없음)

API_SK4_URL = os.environ.get("GIIP_API_SK4_URL", "https://giipfaw.azurewebsites.net/api/giipApiSk4")
JEV_URL = os.environ.get("JEV_URL", "https://api.typesafe.ai/v1/systemone")
JEV_MODEL = os.environ.get("JEV_MODEL", "jev-latest")

# ── Jev API 키 (절대 출력 금지) ───────────────────────────────────────────
def load_jev_key(env_path=None):
    k = os.environ.get("TYPESAFE_API_KEY")
    if k and k.strip():
        return k.strip()
    cands = [env_path, os.environ.get("TYPESAFE_ENV"), "/work/.secrets/typesafe.env",
             os.path.expanduser("~/.secrets/typesafe.env")]
    for p in cands:
        if p and os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        m = re.match(r"\s*TYPESAFE_API_KEY\s*=\s*(.+)", line)
                        if m:
                            return m.group(1).strip().strip('"').strip("'")
            except (OSError, IOError):
                pass
    return None

# ── csn 1시간 전량 읽기 ───────────────────────────────────────────────────
def kvs_window(sk, factor_like="secevt%", minutes=60):
    """giipApiSk4 KVSWindow → pApiKVSWindowbySk. sk 로 csn 자동 특정. 행 리스트 반환."""
    jsondata = json.dumps({"kFactorLike": factor_like, "minutes": int(minutes)},
                          ensure_ascii=False, separators=(",", ":"))
    form = urllib.parse.urlencode({"token": sk, "text": "KVSWindow kFactorLike minutes",
                                   "jsondata": jsondata}).encode("utf-8")
    req = urllib.request.Request(API_SK4_URL, data=form,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8", "replace")
    parsed = json.loads(body)
    rows = parsed.get("data", parsed) if isinstance(parsed, dict) else parsed
    if not isinstance(rows, list):
        rows = [rows]
    if rows and isinstance(rows[0], dict) and "kValue" not in rows[0] and "RstVal" in rows[0]:
        raise RuntimeError("조회 실패(RstVal=%s) — sk/권한 확인" % rows[0].get("RstVal"))
    return rows

def parse_kvalue(row):
    kv = row.get("kValue")
    if isinstance(kv, str):
        try:
            kv = json.loads(kv)
        except json.JSONDecodeError:
            kv = {"_raw": kv}
    return kv if isinstance(kv, dict) else {"_raw": kv}

# ── Jev 판정(형 지정 질문, 사양서 §6) ─────────────────────────────────────
# 질문 순서 고정 — 응답 answers[i] 를 이 이름에 매핑한다.
JEV_QUESTIONS = [
    {"name": "is_injection", "type": "noul",
     "instructions": "이 SQL/요청은 SQL 인젝션 공격 또는 공격 준비(정찰·탐사)다"},
    {"name": "attack_type", "type": "choice",
     "instructions": "이 요청의 공격 유형을 하나 고르라",
     "criteria": {
         "boolean_blind": "참/거짓 블라인드(ASCII/SUBSTRING 등)",
         "time_blind": "시간 블라인드(SLEEP/BENCHMARK 등)",
         "union_based": "UNION 기반 추출",
         "error_based": "오류 기반(EXTRACTVALUE/UPDATEXML 등)",
         "file_write": "파일 쓰기(INTO OUTFILE/DUMPFILE)",
         "file_read": "파일 읽기(LOAD_FILE)",
         "schema_enum": "스키마 열거(information_schema 등)",
         "stacked_or_ddl": "스택 쿼리·DDL(;drop/alter 등)",
         "recon_probe": "정찰·탐사 수준",
         "benign": "공격이 아님(정상)"}},
    {"name": "severity", "type": "score",
     "instructions": "이 사건의 중대도를 고르라",
     "criteria": ["0 노이즈", "1 정찰·탐사", "2 열거·읽기 시도",
                  "3 인증정보·개인정보 읽기", "4 쓰기·파일·권한 조작 시도"]},
    {"name": "data_extracted", "type": "noul",
     "instructions": "이 요청 계열로 공격자가 DB 값을 실제로 읽어냈다(응답크기 이봉·200·retcode=0 근거)"},
    {"name": "targets_credentials", "type": "noul",
     "instructions": "대상이 인증정보(pass·admin·mysql.user 등)다"},
    {"name": "write_attempt", "type": "noul",
     "instructions": "데이터·파일·권한 쓰기를 시도한다"},
]

def build_state(kv):
    """마스킹된 kValue 로 Jev state 문자열(1 이벤트=1 상태)을 만든다. 공격자 제어 문자열은 shape 로만."""
    fields = [
        ("src", kv.get("src")), ("db", kv.get("db")), ("dbuser", kv.get("dbuser")),
        ("op", kv.get("op")), ("retcode", kv.get("retcode")),
        ("client_ip_class", kv.get("client_ip_class")), ("ua_class", kv.get("ua_class")),
        ("sql_shape", kv.get("sql_shape")), ("req_uri", kv.get("req_uri")),
        ("req_args_shape", kv.get("req_args_shape")),
        ("resp_bytes", kv.get("resp_bytes")), ("resp_series", kv.get("resp_series")),
        ("baseline", kv.get("baseline")),
    ]
    return " ".join("%s=%s" % (k, v) for k, v in fields if v not in (None, "", []))

def jev_judge(state_text, api_key, debug=False):
    """Jev System One 호출. answers 를 질문 이름으로 매핑해 반환. 실패 시 예외."""
    questions = [{k: q[k] for k in q if k != "name"} for q in JEV_QUESTIONS]
    body = json.dumps({"model": JEV_MODEL, "state": state_text, "questions": questions},
                      ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(JEV_URL, data=body, headers={
        "Content-Type": "application/json", "Authorization": "Bearer " + api_key})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8", "replace")
    parsed = json.loads(raw)
    if debug:
        # 키는 절대 찍지 않는다. 응답 본문만.
        sys.stderr.write("[secevt_judge][jev-debug] %s\n" % raw[:1000])
    answers = parsed.get("answers", parsed) if isinstance(parsed, dict) else parsed
    out = {"usage": parsed.get("usage") if isinstance(parsed, dict) else None}
    if isinstance(answers, list):
        for q, a in zip(JEV_QUESTIONS, answers):
            out[q["name"]] = a
    elif isinstance(answers, dict):
        # 이름 키 응답도 수용
        for q in JEV_QUESTIONS:
            if q["name"] in answers:
                out[q["name"]] = answers[q["name"]]
    return out

def _noul(a):
    if isinstance(a, dict):
        return a.get("noul")
    return a if isinstance(a, (int, float)) else None

def _score(a):
    if isinstance(a, dict):
        return a.get("score")
    return a if isinstance(a, (int, float)) else None

def _choice(a):
    if isinstance(a, dict):
        return a.get("choice")
    return a

# ── 라우팅(사양서 §7 게이트) ───────────────────────────────────────────────
def route(pf, jev):
    """alert / review / log 로 라우팅. jev 없으면(None) 룰만으로 보수적 판정."""
    if jev:
        inj = _noul(jev.get("is_injection")) or 0.0
        sev = _score(jev.get("severity")) or 0
        at = _choice(jev.get("attack_type"))
        de = _noul(jev.get("data_extracted")) or 0.0
        wa = _noul(jev.get("write_attempt")) or 0.0
        if de >= 0.7 or wa >= 0.7:
            return "alert", "데이터유출/쓰기 시도 의심"
        if inj >= 0.9 and sev >= 2:
            return "alert", "고확실 공격(inj≥0.9, sev≥2)"
        if inj <= 0.1 and at == "benign":
            return "log", "정상 판정"
        return "review", "경계 확률 — 사람 검토"
    # Jev 미수행: 전단필터만
    if not pf.get("candidate"):
        return "log", "전단필터 비후보"
    strong = {"file_write", "file_read", "stacked_or_ddl", "union_based", "error_based"}
    if strong & set(pf.get("rules", [])):
        return "alert", "강한 룰 적중(Jev 미수행 — 보수적 경보)"
    return "review", "전단 후보(Jev 미수행)"

def judge_rows(rows, api_key, use_jev, jev_debug=False):
    verdicts = []
    for r in rows:
        kv = parse_kvalue(r)
        pf = kv.get("prefilter") if isinstance(kv.get("prefilter"), dict) else sp.prefilter(kv)
        jev = None
        jev_err = None
        if use_jev and pf.get("candidate") and api_key:
            try:
                jev = jev_judge(build_state(kv), api_key, debug=jev_debug)
            except Exception as e:  # 네트워크/벤더 오류: 룰만으로 폴백(스케줄러 안 막음)
                jev_err = str(e)[:160]
        routed, why = route(pf, jev)
        verdicts.append({
            "ksn": r.get("ksn"), "lssn": r.get("kKey"), "factor": r.get("kFactor"),
            "ts": kv.get("ts") or r.get("kRegdt"), "regdt": r.get("kRegdt"),
            "src": kv.get("src"), "candidate": pf.get("candidate"),
            "rules": pf.get("rules", []), "score": pf.get("score", 0.0),
            "route": routed, "why": why, "engine": "jev-1.13" if jev else "rule",
            "jev": {
                "is_injection": _noul(jev.get("is_injection")) if jev else None,
                "attack_type": _choice(jev.get("attack_type")) if jev else None,
                "severity": _score(jev.get("severity")) if jev else None,
                "data_extracted": _noul(jev.get("data_extracted")) if jev else None,
                "targets_credentials": _noul(jev.get("targets_credentials")) if jev else None,
                "write_attempt": _noul(jev.get("write_attempt")) if jev else None,
            } if jev else None,
            "jev_error": jev_err,
            "shape": kv.get("sql_shape") or kv.get("req_args_shape") or kv.get("req_uri"),
        })
    return verdicts

def report(verdicts, csn, minutes, use_jev):
    order = {"alert": 0, "review": 1, "log": 2}
    vs = sorted(verdicts, key=lambda v: (order.get(v["route"], 3), str(v.get("regdt") or ""), ))
    n_alert = sum(1 for v in vs if v["route"] == "alert")
    n_review = sum(1 for v in vs if v["route"] == "review")
    n_log = sum(1 for v in vs if v["route"] == "log")
    facs = sorted(set(v["factor"] for v in vs if v["factor"]))
    sys.stderr.write("[secevt_judge] csn=%s 창=%d분 행=%d factor=%s Jev=%s\n"
                     % (csn or "(sk자동)", minutes, len(vs), ",".join(facs) or "(없음)",
                        "on" if use_jev else "off"))
    sys.stderr.write("[secevt_judge] 🔴 ALERT %d · 🟠 REVIEW %d · ⚪ LOG %d\n" % (n_alert, n_review, n_log))
    if not vs:
        return
    hdr = "%-6s %-22s %-9s %-7s %-6s %s" % ("route", "factor", "lssn", "inj", "score", "shape")
    sys.stderr.write(hdr + "\n" + "-" * len(hdr) + "\n")
    for v in vs:
        inj = v["jev"]["is_injection"] if v["jev"] else None
        sys.stderr.write("%-6s %-22s %-9s %-7s %-6s %s\n" % (
            v["route"], (v["factor"] or "")[:22], str(v["lssn"] or ""),
            ("%.2f" % inj) if isinstance(inj, (int, float)) else "-",
            ("%.2f" % v["score"]) if v["score"] else "-",
            (v["shape"] or "")[:60]))

def main():
    ap = argparse.ArgumentParser(description="보안점검 consumer — csn 1시간 전량 tKVS → 룰+Jev → 해킹 의심 보고")
    ap.add_argument("--minutes", type=int, default=60, help="조회 창(분, 기본 60)")
    ap.add_argument("--factor-like", default="secevt%", help="kFactor LIKE 필터(기본 secevt%%, '' 면 전량)")
    ap.add_argument("--no-jev", action="store_true", help="Jev 생략(네트워크 없이 1차 전단필터만)")
    ap.add_argument("--jev-env", help="TYPESAFE_API_KEY 가 든 env 파일 경로")
    ap.add_argument("--jev-debug", action="store_true", help="Jev 응답 본문 일부를 stderr 로(키는 안 찍음)")
    ap.add_argument("--from-file", help="API 대신 KVSWindow 응답 JSON 파일로 판정(오프라인)")
    ap.add_argument("--from-events", help="secevt_sample.py 형식 이벤트 배열(파일/'-'=stdin)을 직접 판정")
    ap.add_argument("--json", action="store_true", help="판정 결과를 JSON 으로 stdout 출력")
    a = ap.parse_args()

    use_jev = not a.no_jev
    api_key = load_jev_key(a.jev_env) if use_jev else None
    if use_jev and not api_key:
        sys.stderr.write("[secevt_judge] TYPESAFE_API_KEY 없음 → Jev 생략(룰만). "
                         "키를 주려면 env TYPESAFE_API_KEY 또는 --jev-env.\n")
        use_jev = False

    csn = os.environ.get("GIIP_CSN") or sp._read_cfg_value("csn")

    if a.from_events is not None:
        raw = sys.stdin.read() if a.from_events == "-" else open(a.from_events, "r", encoding="utf-8").read()
        events = json.loads(raw)
        events = events if isinstance(events, list) else [events]
        # 이벤트 → KVSWindow 행 형태로 감싸(kValue=build_kvalue) 동일 경로로 판정
        rows = [{"ksn": None, "kKey": None, "kFactor": None, "kRegdt": ev.get("ts"),
                 "kValue": json.dumps(sp.build_kvalue(ev), ensure_ascii=False)} for ev in events]
    elif a.from_file:
        parsed = json.loads(open(a.from_file, "r", encoding="utf-8").read())
        rows = parsed.get("data", parsed) if isinstance(parsed, dict) else parsed
        if not isinstance(rows, list):
            rows = [rows]
    else:
        sk = sp.resolve_sk()
        try:
            rows = kvs_window(sk, a.factor_like, a.minutes)
        except urllib.error.URLError as e:
            sys.stderr.write("[secevt_judge] 읽기 실패: %s\n"
                             % str(getattr(e, "reason", e)).replace(sk, "[REDACTED]"))
            sys.exit(4)
        except RuntimeError as e:
            sys.stderr.write("[secevt_judge] %s\n" % e); sys.exit(4)

    verdicts = judge_rows(rows, api_key, use_jev, jev_debug=a.jev_debug)
    report(verdicts, csn, a.minutes, use_jev)
    if a.json:
        json.dump({"csn": csn, "minutes": a.minutes, "verdicts": verdicts},
                  sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")

if __name__ == "__main__":
    main()
