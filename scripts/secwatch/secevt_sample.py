#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secevt_sample.py — secevt 이벤트 '데이터 만드는 법' 참조 생성기 (리눅스/윈도우 공용, stdlib만).

secevt_put.py 가 받는 입력 JSON 의 정본 예시를 만든다. 공격/정상 라벨을 섞어
배열로 출력하므로, 그대로 producer 에 흘려 마스킹·전단필터·전송을 점검할 수 있다.
(SQL 리터럴은 일부러 원본 그대로 둔다 — producer 가 at-source 로 '?' 치환함을 확인하려고.)

사용:
  python3 secevt_sample.py                         # 라벨 포함 배열 stdout
  python3 secevt_sample.py --no-label              # 'label' 필드 제거(실전 입력 형태)
  python3 secevt_sample.py | python3 secevt_put.py --lssn 71240 --stdin --dry-run
  python3 secevt_sample.py --only attack           # 공격 샘플만

각 이벤트 필드는 사양서 §5/§17 의 kValue 입력 스키마와 동일하다(단 'label' 은 평가용 메타).
"""
import sys, json, argparse

SAMPLES = [
    # ── 공격: UNION + INTO OUTFILE (파일쓰기 시도), 구문오류 retcode ──
    {"label": "attack", "src": "aurora_audit", "ts": "2026-10-15T21:20:49Z",
     "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 1064,
     "client_ip_class": "external", "ua_class": "script",
     "sql_shape": "SELECT per.id person_id, per.name FROM person per WHERE per.id = 10 UNION SELECT 1,2,3 INTO OUTFILE '/tmp/x.txt'",
     "baseline": "cur_app 평시 information_schema 미참조; 동일 접속원 최근 5분 동종 312건"},

    # ── 공격: boolean blind (ASCII(SUBSTRING)), 응답크기 이봉 ──
    {"label": "attack", "src": "waf", "ts": "2026-10-15T21:22:03Z",
     "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 0,
     "client_ip_class": "external", "ua_class": "script",
     "req_uri": "/personGateway.php",
     "req_args_shape": "method=id&searchKey=1 AND (ASCII(SUBSTRING((SELECT pass FROM admin LIMIT 1),1,1))>64)",
     "resp_bytes": 2189, "resp_series": [428, 2189, 428, 2189],
     "baseline": "admin 테이블·pass 컬럼 표적 의심"},

    # ── 공격: time blind (SLEEP) ──
    {"label": "attack", "src": "applog", "ts": "2026-10-15T21:25:11Z",
     "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 0,
     "client_ip_class": "cloud", "ua_class": "script",
     "sql_shape": "SELECT * FROM items WHERE id = 1 OR SLEEP(5)",
     "baseline": "응답 지연 5초 관측"},

    # ── 공격: error-based (EXTRACTVALUE) ──
    {"label": "attack", "src": "aurora_audit", "ts": "2026-10-15T21:26:40Z",
     "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 1105,
     "client_ip_class": "external", "ua_class": "script",
     "sql_shape": "SELECT EXTRACTVALUE(1, CONCAT(0x7e,(SELECT version())))"},

    # ── 정상: 통상 업무 쿼리 ──
    {"label": "benign", "src": "aurora_audit", "ts": "2026-10-15T21:27:00Z",
     "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 0,
     "client_ip_class": "internal", "ua_class": "browser",
     "sql_shape": "SELECT title, body FROM article_settings WHERE site_id = 12 AND article_id = 884"},

    # ── 정상: information_schema 를 쓰는 합법 업무도구(오탐 평가 최중요, biwa 류) ──
    {"label": "benign", "src": "applog", "ts": "2026-10-15T21:28:30Z",
     "db": "prd-cmsdb", "dbuser": "biwa", "op": "QUERY", "retcode": 0,
     "client_ip_class": "internal", "ua_class": "script",
     "sql_shape": "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'curation'",
     "baseline": "biwa 는 스키마 조회 상시 수행하는 정상 업무도구"},

    # ── 정상: 사내 WAF 테스트 1건 ──
    {"label": "benign", "src": "waf", "ts": "2026-10-15T07:26:00Z",
     "db": None, "dbuser": None, "op": None, "retcode": None,
     "client_ip_class": "internal", "ua_class": "script",
     "req_uri": "/healthz", "req_args_shape": "ping=1",
     "baseline": "150.195.219.160 사내 점검 테스트"},
]

def main():
    ap = argparse.ArgumentParser(description="secevt 샘플 이벤트 생성")
    ap.add_argument("--no-label", action="store_true", help="평가용 'label' 필드 제거")
    ap.add_argument("--only", choices=["attack", "benign"], help="한쪽 라벨만")
    a = ap.parse_args()
    rows = [dict(s) for s in SAMPLES]
    if a.only:
        rows = [r for r in rows if r.get("label") == a.only]
    if a.no_label:
        for r in rows:
            r.pop("label", None)
    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()
