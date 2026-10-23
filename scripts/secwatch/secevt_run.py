#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_run.py — secwatch 1회 스윕 진입점(스케줄러가 부른다). 리눅스/윈도우 공용, stdlib만.

설정 파일(secwatch.sources.json)에 적힌 소스들을 순회하며, 각 소스에 대해
  수집(secevt_collect) → 마스킹·전단필터(secevt_lib) → 후보만 게이트웨이 전송(secevt_agent)
을 한 번 수행한다. cron(리눅스) / 작업스케줄러(윈도우)가 이 스크립트를 주기 호출하면 상시 감시가 된다.
등록 방법·운영 절차: docs/60-operations/secwatch-agent.md. 관련 giip #3833.

사용:
  python3 secevt_run.py                         # 설정 자동탐색(아래) 후 1회 스윕
  python3 secevt_run.py --config /etc/giip/secwatch.sources.json
  python3 secevt_run.py --dry-run               # 전송 없이 각 소스 파싱·후보 수만 보고

설정 자동탐색 순서: --config → env SECWATCH_CONFIG → giipAgent.cfg|.cnf 와 같은 폴더의
  secwatch.sources.json → 이 스크립트 폴더의 secwatch.sources.json.
설정 스키마(secwatch.sources.example.json 참고):
  { "lssn": <lssn>,
    "sources": [ { "source":"aurora_audit", "file":"/var/log/audit/server_audit.log",
                   "system":"prd-cmsdb", "since_offset":"/var/lib/giip/secwatch/aurora.offset" } ] }
  lssn 생략 시 env GIIP_LSSN / giipAgent.cfg 의 lssn 사용. sk 는 secevt_agent 와 동일 규칙(키 없음).
"""
import sys, os, json, time, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import secevt_lib as L
import secevt_collect as C
import secevt_agent as A

def find_config(explicit):
    cands = [explicit, os.environ.get("SECWATCH_CONFIG")]
    # giipAgent.cfg 가 있는 폴더(에이전트 설치 위치) + 이 스크립트 폴더
    here = os.path.dirname(os.path.abspath(__file__))
    cands += [os.path.join(os.getcwd(), "secwatch.sources.json"),
              os.path.join(here, "secwatch.sources.json")]
    for p in cands:
        if p and os.path.exists(p):
            return p
    return None

def main():
    ap = argparse.ArgumentParser(description="secwatch 1회 스윕(수집→마스킹→게이트웨이 전송)")
    ap.add_argument("--config", help="secwatch.sources.json 경로(미지정 시 자동탐색)")
    ap.add_argument("--dry-run", action="store_true", help="전송 없이 소스별 파싱·후보 수만 보고")
    a = ap.parse_args()
    L.reconfigure_utf8()

    cfg_path = find_config(a.config)
    if not cfg_path:
        sys.stderr.write("[secevt_run] 설정 없음 — secwatch.sources.json (또는 --config/env SECWATCH_CONFIG). "
                         "secwatch.sources.example.json 참고.\n"); sys.exit(2)
    try:
        cfg = json.loads(open(cfg_path, "r", encoding="utf-8").read())
    except (OSError, json.JSONDecodeError) as e:
        sys.stderr.write("[secevt_run] 설정 읽기 실패(%s): %s\n" % (cfg_path, e)); sys.exit(2)

    lssn = L.resolve_lssn(str(cfg.get("lssn")) if cfg.get("lssn") else None)
    if not lssn:
        sys.stderr.write("[secevt_run] lssn 없음(config.lssn / env GIIP_LSSN / cfg lssn=).\n"); sys.exit(2)
    sk = None if a.dry_run else L.resolve_sk(lambda m, c: (sys.stderr.write("[secevt_run] %s\n" % m), sys.exit(c)))

    sources = cfg.get("sources") or []
    if not sources:
        sys.stderr.write("[secevt_run] config.sources 비어있음.\n"); sys.exit(2)

    # 초출(novel) 형태(항목 7, giip #3833). config.send_novel 또는 env GIIP_SECEVT_SEND_NOVEL 로 켠다(기본 OFF).
    send_novel = L.resolve_send_novel(bool(cfg.get("send_novel"))) and not a.dry_run
    known_path = L.resolve_known_shapes_path(cfg.get("known_shapes_file")) if send_novel else None
    known = L.load_known_shapes(known_path) if send_novel else {}
    now = int(time.time())
    learned = 0

    total_parsed = total_sent = total_skipped = 0
    totals = {"alert": 0, "review": 0, "log": 0}
    for s in sources:
        src = s.get("source"); fpath = s.get("file")
        if src not in C.PARSERS or not fpath:
            sys.stderr.write("[secevt_run] 소스 항목 무시(source/file 확인): %s\n" % json.dumps(s, ensure_ascii=False)); continue
        try:
            events = C.collect_events(src, file=fpath, system=s.get("system"), since_offset=s.get("since_offset"))
        except OSError as e:
            sys.stderr.write("[secevt_run] %s 읽기 실패: %s\n" % (fpath, e)); continue
        total_parsed += len(events)
        for ev in events:
            novel_ctx = {"send_novel": send_novel, "known": known, "now": now} if send_novel else None
            kv = L.build_kvalue(ev, novel_ctx)
            if not kv["prefilter"]["candidate"]:
                total_skipped += 1
                continue
            kv["lssn"] = lssn
            kv["kscFactor"] = L.resolve_factor(ev)
            if a.dry_run:
                total_sent += 1
                continue
            try:
                v = A.send_to_gateway(sk or "", kv)
            except Exception as e:
                msg = str(e)
                if sk: msg = msg.replace(sk, "[REDACTED]")
                sys.stderr.write("[secevt_run] %s 전송 실패: %s\n" % (src, msg)); continue
            total_sent += 1
            if v.get("success") is False:
                sys.stderr.write("[secevt_run] %s 게이트웨이 오류: %s\n" % (src, v.get("error")))
                continue
            rt = v.get("routedTo")
            if rt in totals:
                totals[rt] += 1
            # 초출 형태가 Jev 에서 정상(log)으로 판정되면 학습(만료 전까지 다음 회차부터 조용히 통과).
            if send_novel and L.maybe_learn_shape(known_path, kv, v, now=now):
                learned += 1
                sid = kv.get("shape_id")
                if sid:
                    known[sid] = {"first": now, "exp": now + 30 * 86400}
    novel_note = (" · novel학습 %d" % learned) if send_novel else ""
    sys.stderr.write("[secevt_run] 스윕 완료(config=%s): 파싱 %d · 전송 %d · 건너뜀(비후보) %d%s%s\n"
                     % (os.path.basename(cfg_path), total_parsed, total_sent, total_skipped,
                        "" if a.dry_run else " · 🔴%d 🟠%d ⚪%d" % (totals["alert"], totals["review"], totals["log"]),
                        novel_note))

    # 생존신호(항목 5, giip #3833): 보낼 이벤트가 없는 회차도 "돌았다 + 확인건수 + 후보 0"을 남겨,
    # 대시보드가 "멈춘 건지 이상이 없는 건지"를 구분할 수 있게 한다. 새 이벤트 타입을 만들지 않고(의뢰자
    # "독자 명칭 금지" 준수) 로컬 상태 파일에 쓴다 — monitor.py 가 /api/heartbeat 로 읽어 표시한다.
    if not a.dry_run:
        try:
            hb_path = cfg.get("heartbeat_file") or os.environ.get("GIIP_SECEVT_HEARTBEAT") \
                or os.path.join(os.path.dirname(os.path.abspath(cfg_path)), "secwatch.last_run.json")
            hb = {"v": 1, "ts": int(time.time()), "lssn": str(lssn),
                  "parsed": total_parsed, "candidates": total_sent, "skipped": total_skipped,
                  "routed": totals, "novel_learned": learned if send_novel else None}
            tmp = hb_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(hb, f, ensure_ascii=False)
            os.replace(tmp, hb_path)
        except OSError as e:
            sys.stderr.write("[secevt_run] heartbeat 기록 실패(무시): %s\n" % e)

if __name__ == "__main__":
    main()
