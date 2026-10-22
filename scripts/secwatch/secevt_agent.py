#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_agent.py — 보안점검 에이전트 ②(고객 수집 PC/서버). 리눅스/윈도우 공용, stdlib만.

소스에서 정규화한 이벤트를 **마스킹(at source)·1차 전단필터**해서, 후보만 giip **Jev 게이트웨이**(⑤)로
보낸다. 게이트웨이가 Jev 로 판정해 결과를 tKVSSecurityCheck 에 적재하고 verdict 를 돌려준다.

**이 PC 에는 Jev 키가 없다.** sk(giip 에이전트 키)로만 인증하고, 마스킹된 이벤트만 전송한다.
정본 설계: giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md §4·§17. 관련 giip #3833.

사용:
  echo '<event json>' | python3 secevt_agent.py --lssn <lssn> --stdin
  python3 secevt_agent.py --lssn <lssn> --event-file ev.json
  python3 secevt_sample.py --no-label | python3 secevt_agent.py --lssn <lssn> --stdin --dry-run
  python3 secevt_agent.py --lssn <lssn> --event-file ev.json --all   # 비후보까지 전송(기본은 후보만)

인증(sk)·lssn 해석(자동, 사용자에게 묻지 않음):
  sk   : env GIIP_SK → 상위 giipAgent.cfg|.cnf 'sk='   (Jev 키 아님 — giip 에이전트 키)
  lssn : --lssn → env GIIP_LSSN → cfg 'lssn='
  sk 값은 로그/출력/예외에 평문으로 남기지 않는다.
종료코드: 0 성공, 2 입력오류, 3 sk 없음, 4 전송 실패.
  주의: 게이트웨이 전송이 성공하면, 그 뒤 요약/JSON 표시 단계가 실패하더라도 종료코드는 0 이다.
  (cp932 등 비 UTF-8 콘솔에서 표시가 죽어도 "전송 성공"을 "실패"로 오인하지 않게 하기 위함 — giip #3833.)
"""
import sys, os, json, time, argparse, urllib.request, urllib.parse, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import secevt_lib as L

GATEWAY_URL = os.environ.get("GIIP_JEV_GATEWAY_URL", "https://giipfaw.azurewebsites.net/api/giipJevGateway")

def send_to_gateway(sk, event_payload, dry_run=False):
    """게이트웨이로 마스킹 이벤트 1건 POST(form token+jsondata). verdict dict 반환."""
    jsondata = json.dumps(event_payload, ensure_ascii=False, separators=(",", ":"))
    form = {"token": sk, "jsondata": jsondata}
    if dry_run:
        safe = dict(form); safe["token"] = "[REDACTED]"
        sys.stderr.write("[secevt_agent] DRY-RUN payload: %s\n" % json.dumps(safe, ensure_ascii=False))
        return {"success": None, "dryrun": True}
    data = urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(GATEWAY_URL, data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            body = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        # 4xx/5xx 는 본문에 원인이 담긴다(예: 500 'TYPESAFE_API_KEY app setting not configured').
        # 묻지 말고 드러낸다 — 설정/배포 문제를 바로 진단하기 위함.
        detail = ""
        try:
            detail = e.read().decode("utf-8", "replace")[:300]
        except Exception:
            pass
        return {"success": False, "error": "gateway HTTP %s: %s" % (e.code, detail)}
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"success": False, "error": "비JSON 응답", "raw": body[:200]}

def main():
    ap = argparse.ArgumentParser(description="보안점검 에이전트 — 마스킹 후보를 Jev 게이트웨이로 전송(키 없음)")
    ap.add_argument("--lssn", help="이 수집 에이전트 lssn (미지정 시 env/cfg)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--event-file", help="이벤트 JSON 파일(객체 1개 또는 배열)")
    g.add_argument("--stdin", action="store_true", help="stdin 에서 이벤트 JSON 읽기")
    ap.add_argument("--all", action="store_true", help="비후보 이벤트까지 전송(기본은 전단필터 후보만)")
    ap.add_argument("--dry-run", action="store_true", help="전송 없이 보낼 payload 만 출력(token 가림)")
    ap.add_argument("--json", action="store_true", help="게이트웨이 verdict 를 JSON 으로 stdout 출력")
    ap.add_argument("--send-novel", action="store_true",
                    help="평상시에 없던 초출(novel) 형태도 후보로 올려 Jev 판정을 받는다(기본 OFF, env GIIP_SECEVT_SEND_NOVEL 로도 가능)")
    a = ap.parse_args()
    L.reconfigure_utf8()

    def die(msg, code):
        sys.stderr.write("[secevt_agent] %s\n" % msg); sys.exit(code)

    raw = sys.stdin.read() if a.stdin else open(a.event_file, "r", encoding="utf-8").read()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as e:
        die("입력 JSON 파싱 실패: %s" % e, 2)
    events = parsed if isinstance(parsed, list) else [parsed]

    sk = None if a.dry_run else L.resolve_sk(die)
    if a.dry_run:
        sk = os.environ.get("GIIP_SK")  # dry-run 은 sk 없어도 됨
    lssn = L.resolve_lssn(a.lssn)
    if not lssn:
        die("lssn 을 찾지 못했습니다 (--lssn / env GIIP_LSSN / cfg lssn=).", 2)

    # 초출(novel) 형태 설정(항목 7, giip #3833). 기본 OFF. 켜지면 "알려진 정상 형태"가 아닌 형태를
    # 후보로 올려 Jev 판정을 받고, Jev 가 정상(log)으로 판정하면 그 형태를 알려진-정상으로 학습(만료 포함).
    send_novel = L.resolve_send_novel(a.send_novel) and not a.dry_run
    known_path = L.resolve_known_shapes_path() if send_novel else None
    known = L.load_known_shapes(known_path) if send_novel else {}
    now = int(time.time())
    learned = 0

    sent = skipped = 0
    results = []
    counts = {"alert": 0, "review": 0, "log": 0}
    for ev in events:
        novel_ctx = {"send_novel": send_novel, "known": known, "now": now} if send_novel else None
        kv = L.build_kvalue(ev, novel_ctx)
        if not a.all and not kv["prefilter"]["candidate"]:
            skipped += 1
            continue
        kv["lssn"] = lssn                      # 게이트웨이가 kscKey 로 사용
        kv["kscFactor"] = L.resolve_factor(ev)  # 이벤트 타입(종류)
        try:
            v = send_to_gateway(sk or "", kv, dry_run=a.dry_run)
        except urllib.error.URLError as e:
            msg = str(getattr(e, "reason", e))
            if sk:
                msg = msg.replace(sk, "[REDACTED]")
            die("게이트웨이 전송 실패: %s" % msg, 4)
        sent += 1
        if not a.dry_run:
            rt = v.get("routedTo")
            if rt in counts:
                counts[rt] += 1
            results.append({"factor": kv["kscFactor"], "verdict": v})
            if v.get("success") is False:
                sys.stderr.write("[secevt_agent] 게이트웨이 오류: %s\n" % v.get("error"))
            # 초출 형태가 Jev 에서 정상(log)으로 판정되면 학습 → 다음 회차부터 조용히 통과(만료 전까지).
            elif send_novel and L.maybe_learn_shape(known_path, kv, v, now=now):
                learned += 1
                sid = kv.get("shape_id")
                if sid:
                    known[sid] = {"first": now, "exp": now + 30 * 86400}
    # 전송은 위 루프에서 끝났다. 아래 요약/JSON 표시가 (비 UTF-8 콘솔 등으로) 실패하더라도
    # 종료코드를 바꾸지 않는다 — "전송 성공"을 "표시 실패"로 오인시키지 않기 위함(giip #3833).
    try:
        if a.dry_run:
            sys.stderr.write("[secevt_agent] DRY-RUN 완료: 대상 %d, 건너뜀(비후보) %d, lssn=%s\n" % (sent, skipped, lssn))
        else:
            novel_note = (" · novel학습 %d" % learned) if send_novel else ""
            sys.stderr.write("[secevt_agent] 완료: 전송 %d, 건너뜀(비후보) %d, lssn=%s · 🔴ALERT %d 🟠REVIEW %d ⚪LOG %d%s\n"
                             % (sent, skipped, lssn, counts["alert"], counts["review"], counts["log"], novel_note))
        if a.json and not a.dry_run:
            json.dump({"lssn": lssn, "results": results}, sys.stdout, ensure_ascii=False, indent=2)
            sys.stdout.write("\n")
    except Exception as disp_err:
        try:
            sys.stderr.write("[secevt_agent] 표시 단계 경고(전송은 완료): %s\n"
                             % str(disp_err).encode("ascii", "replace").decode("ascii"))
        except Exception:
            pass
    # 입력오류·sk 없음·전송실패(URLError)는 위에서 die()로 이미 비0 종료했다. 여기 도달 = 전송 성공.
    sys.exit(0)

if __name__ == "__main__":
    main()
