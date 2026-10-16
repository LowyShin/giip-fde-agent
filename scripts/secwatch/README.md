# secwatch — 보안점검 에이전트(②) : 소스 수집 → 마스킹 → Jev 게이트웨이 전송

> giip-fde-agent 기능. **리눅스/윈도우 공용 Python(stdlib만, 의존성 없음).**
> 역할: 소스 로그에서 정규화한 의심 이벤트를 **마스킹·전단필터**해서, 후보만 giip **Jev 게이트웨이**로 보낸다.
> **이 PC 에는 Jev 키가 없다.** giip 에이전트 키(`sk`)로만 인증하고 마스킹된 이벤트만 전송한다.
> Jev 2차 판정·결과 적재(`tKVSSecurityCheck`)는 게이트웨이(giip 측 Azure)가 한다.
> 정본 설계: `giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md` (§4 아키텍처·§6 질문·§7 게이트·§13 결과테이블·§16 키·§17 전송).
> 관련 이슈: **giip #3833**.

---

## 1. 구조 (한눈에)

```
① 소스(Aurora 감사로그/WAF/CloudFront/신호)
     │  수집·정규화(+origin)
② secevt_agent.py  [이 PC — Jev 키 없음]
     │  마스킹(리터럴 '?' 치환, at source) · 1차 전단필터 · 후보만
     │  giipApi(sk 인증)로 마스킹 이벤트 POST
⑤ giip Jev 게이트웨이 (giipfaw giipJevGateway)  [Jev 키 = Azure 앱설정]
     │  sk→csn 검증 · Jev(/v1/systemone) 판정 · 게이트 라우팅(alert/review/log)
⑥ tKVSSecurityCheck  (판정 + kscOriginRef(①원본 위치))
⑦ 대시보드(결과 테이블 조회)
```

**왜 게이트웨이인가**: 고객 수집 PC 에는 Jev 키를 둘 수 없다. 그래서 Jev 호출은 giip 측 게이트웨이 1곳이 대행하고, 이 PC 는 sk 로만 인증한다.

---

## 2. 종류별 4개 이벤트 타입 (반드시 이 이름)

에이전트가 이벤트 `src` 로 자동 결정한다(→ 결과행 `kscFactor`). **임의 이름을 만들지 말 것.**

| 타입(kscFactor) | 소스 | 이벤트 `src` |
|---|---|---|
| `secevt_batch_audit` | Aurora/DB 감사로그(배치) | `aurora_audit` · `db_audit` · `batch_audit` |
| `secevt_waf` | WAF 로그 | `waf` |
| `secevt_cf` | CloudFront(CDN) 접근로그 | `cloudfront` · `cf` |
| `secevt_signal` | 파생/집계 신호·기타 앱로그 | `signal` · `applog` · 그 외(기본) |

---

## 3. 파일

| 파일 | 용도 |
|---|---|
| `secevt_collect.py` | **수집부①→②**. 소스 로그(aurora_audit/waf/cloudfront/generic) → 정규화 이벤트(+origin) |
| `secevt_agent.py` | **에이전트②**. 이벤트 → 마스킹·전단필터 → 게이트웨이 POST(키 없음) |
| `secevt_run.py` | **스윕 진입점**. 설정대로 수집→전송 1회(스케줄러가 호출) |
| `secevt_lib.py` | 공용 helper(마스킹·전단필터·이벤트 조립·설정 해석) |
| `secevt_sample.py` | 데이터 만드는 법(라벨된 공격/정상 샘플 생성기) |
| `register-secwatch-scheduler.ps1` | Windows 작업스케줄러 등록(리눅스는 cron — 아래 §8) |
| `secwatch.sources.example.json` | 소스 설정 템플릿(`secwatch.sources.json` 으로 복사) |
| `monitor.py` | 간이 감시 모니터(결과 테이블 조회로 전환 예정 — ⑦) |
| `README.md` | 이 문서 |

> **"secwatch 등록"(설치·설정·정기실행)의 표준 절차 정본은 [`docs/60-operations/secwatch-agent.md`](../../docs/60-operations/secwatch-agent.md)** 다. 아래 §6·§8 은 그 요약이다.

---

## 4. 사전 요건

- `python3` (3.6+, stdlib만 — pip 불필요).
- 이 PC 의 giip 에이전트 **sk** 와 **lssn**(자동 해석, 사용자에게 묻지 않음):
  - `sk`: 환경변수 `GIIP_SK` → 현재/상위 폴더의 `giipAgent.cfg|.cnf` 의 `sk=` **(이것은 giip 에이전트 키 — Jev 키가 아니다)**
  - `lssn`: `--lssn` → `GIIP_LSSN` → `giipAgent.cfg|.cnf` 의 `lssn=`
- 게이트웨이 접근: `https://giipfaw.azurewebsites.net/api/giipJevGateway` (환경변수 `GIIP_JEV_GATEWAY_URL` 로 변경 가능).

---

## 5. 입력 이벤트 스키마 (객체 1개 또는 배열)

```json
{
  "src": "aurora_audit|waf|cloudfront|signal|applog|other  (→ §2 표로 타입 결정)",
  "ts": "2026-10-15T21:20:49Z",
  "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 1064,
  "client_ip_class": "internal|external|cloud|nat|unknown",
  "ua_class": "browser|script|bot|unknown",
  "sql_shape": "원본 SQL 또는 이미 마스킹된 shape (에이전트가 리터럴 '?' 치환)",
  "req_uri": "/path", "req_args_shape": "k=v&...",
  "resp_bytes": 2189, "resp_series": [428,2189,428],
  "baseline": "평시 대비 1~2줄 문맥",
  "origin": { "source":"aurora_audit", "system":"prd-cmsdb",
              "location":"로그그룹·스트림 / S3 키 / 테이블",
              "ref":"원본 내 식별자(event id/seq/offset/requestId)",
              "ts":"2026-10-15T21:20:49Z" }
}
```
- **`origin` 를 반드시 채운다.** 마스킹 때문에 비마스킹 원본은 ①소스에만 남으므로, 결과행에서 원본으로 되돌아갈 유일한 단서다(침해대응).
- **IP 는 원본 대신 `client_ip_class` 로만** 싣는다. **원본 SQL/PII 를 그대로 보내지 않는다**(마스킹은 에이전트가 수행).

---

## 6. 실행

```bash
# 1) dry-run — 게이트웨이로 보낼 payload 확인(전송 안 함, sk 가림)
python3 secevt_sample.py --no-label | python3 secevt_agent.py --lssn <LSSN> --stdin --dry-run

# 2) 실제 전송(후보만 — 비용 절감)
python3 secevt_agent.py --lssn <LSSN> --event-file events.json
cat events.json | python3 secevt_agent.py --lssn <LSSN> --stdin

# 3) 비후보까지 전송(진단용)
python3 secevt_agent.py --lssn <LSSN> --event-file events.json --all
```
게이트웨이는 각 이벤트의 verdict(`routedTo` = alert/review/log, 판정값)를 돌려주고 `tKVSSecurityCheck` 에 적재한다.
종료코드: `0` 성공 / `2` 입력오류 / `3` sk 없음 / `4` 전송 실패.

---

## 7. 결과 확인

판정 결과는 `tKVSSecurityCheck`(giipdb)에 적재된다. 조회 컬럼: `kscFactor`(타입)·`kscRoutedTo`(alert/review/log)·
`kscIsInjection`·`kscSeverity`·`kscOriginRef`(①원본 위치)·`kscVerdictJson`. 대시보드(⑦)가 이 테이블을 본다.

---

## 8. 다른 PC 에 적용 (AI 에게 그대로 지시 가능)

1. 이 레포(giip-fde-agent)를 그 PC 에 두고 `scripts/secwatch/` 를 확인.
2. 그 PC 의 `giipAgent.cfg`(또는 `.cnf`)에 `sk=`/`lssn=` 가 있는지 확인. 없으면 `GIIP_SK`/`GIIP_LSSN` 환경변수로 준다. **Jev 키는 필요 없다(게이트웨이가 보유).**
3. 연결 점검: `python3 secevt_sample.py --no-label | python3 secevt_agent.py --lssn <LSSN> --stdin --dry-run` → payload 가 출력되면 OK.
4. 합성 전송: `--dry-run` 을 빼고 실행 → 게이트웨이 verdict 반환 + `tKVSSecurityCheck` 적재 확인.
5. 실데이터 연동: `secwatch.sources.example.json` 을 `secwatch.sources.json` 으로 복사해 소스별 `file`/`system`/`since_offset` 와 `lssn` 을 채운다. `secevt_collect.py` 가 aurora_audit/waf/cloudfront 를 파싱하며, 포맷이 다르면 `generic`(정규화된 JSON-lines) 경로를 쓴다.
   - **운영 실데이터 투입 전 반드시**: 사양서 §9 데이터취급 심사(외부 Jev 송신은 게이트웨이가 하지만, 마스킹 규약·송신 범위는 이 정책을 따른다).
6. **등록(정기 실행)**: Windows 는 `register-secwatch-scheduler.ps1 -Action Register -Config <경로> -IntervalMinutes 5`, 리눅스는 cron 으로 `secevt_run.py --config <경로>` 를 주기 호출. 상세는 [`docs/60-operations/secwatch-agent.md`](../../docs/60-operations/secwatch-agent.md) §6.

---

## 9. 반드시 지킬 것 / 하지 말 것

- ✅ 이벤트 타입은 **§2 의 4개 이름만** 쓴다 — `src` 로 자동 결정. 임의 factor 이름 금지.
- ✅ `origin` 을 반드시 채운다(원본 추적).
- ✅ 마스킹은 에이전트가 한다 — 원본 SQL 리터럴·IP·PII 를 그대로 넣지 않는다.
- 🚫 **이 PC 에 Jev 키(`TYPESAFE_API_KEY`)를 두지 않는다.** 게이트웨이(Azure 앱설정)에만 존재.
- 🚫 `sk` 값을 로그·인자·URL 에 평문으로 남기지 않는다(dry-run 도 가림).

---

## 10. 한계·주의

- 마스킹은 따옴표 문자열·숫자 리터럴을 `?` 로 치환한다(shape 보존). 16진 blob(`0x..`) 등 일부 상수는 남을 수 있어, 민감 상수를 쓰는 소스라면 수집부에서 추가 정규화한다.
- 전단필터는 **재현율 우선**(의심되면 candidate=true). 정상 과탐(예: `biwa` 의 정상 `information_schema` 조회)은 게이트웨이의 2차 Jev + `baseline` 이 교정한다.
- 에이전트는 전송만 한다. 통지/차단은 게이트웨이·대시보드 쪽(사양서 §7)이 담당.
