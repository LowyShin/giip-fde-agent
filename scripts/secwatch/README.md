# secwatch — tKVS 보안점검 입력(secevt) producer

> giip-fde-agent 기능. **리눅스/윈도우 공용 Python(stdlib만, 의존성 없음).**
> 역할: 의심 SQL/요청 이벤트를 **마스킹·전단필터**해서 tKVS 에 `secevt` factor 로 던진다.
> 판정(1차 룰 + 2차 Jev → `tKVSSecurityCheck` 적재)은 **별도 consumer(다음 단계)** 가 한다.
> 정본 설계: `giipdb/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md` (§5 state, §6 게이트, §13 결과테이블, §16 키, §17 factor).
> 관련 이슈: **giip #3833**.

---

## 1. 이 기능이 하는 일 (한눈에)

```
[의심 이벤트 JSON]  →  secevt_put.py  →  tKVS (kType=lssn, kKey=<lssn>, kFactor=secevt)
                        ├ SQL 리터럴 '?' 마스킹 (at source — 원본/PII 를 tKVS 에 저장 안 함)
                        └ 1차 결정론 전단필터(candidate/rules/score) 부착
```

- **producer(이 기능)**: 이벤트를 tKVS 에 적재. 여기까지가 본 기능 범위.
- **consumer(다음 기능)**: tKVS `secevt` 를 읽어 Jev 로 판정 → `tKVSSecurityCheck`. (미구현)

---

## 2. 파일

| 파일 | 용도 |
|---|---|
| `secevt_put.py` | producer. 이벤트 JSON → 마스킹·전단필터 → giipApiSk4 `KVSPut` |
| `secevt_sample.py` | 데이터 만드는 법(라벨된 공격/정상 샘플 생성기) |
| `README.md` | 이 문서 |

---

## 3. 사전 요건

- `python3` (3.6+, stdlib만 — pip 설치 불필요).
- 이 PC 의 giip 에이전트 **sk** 와 **lssn**. 아래 우선순위로 자동 해석(사용자에게 묻지 않음):
  - `sk`: 환경변수 `GIIP_SK` → 현재/상위 폴더의 `giipAgent.cfg|.cnf` 의 `sk=`
  - `lssn`: `--lssn` 인자 → 환경변수 `GIIP_LSSN` → `giipAgent.cfg|.cnf` 의 `lssn=`
- 네트워크로 `https://giipfaw.azurewebsites.net/api/giipApiSk4` 접근 가능.
- **sk 값은 로그·출력·인자·URL 에 평문으로 남기지 않는다.**

---

## 4. 데이터 만드는 법

### 4-1. 빠른 샘플(테스트/학습용)
```bash
python3 secevt_sample.py              # 라벨 포함 배열
python3 secevt_sample.py --no-label   # 실전 입력 형태(평가용 label 제거)
python3 secevt_sample.py --only attack
```

### 4-2. 입력 이벤트 스키마 (객체 1개 또는 배열)
```json
{
  "src": "aurora_audit|waf|cloudfront|applog|giipapi|other",
  "ts": "2026-10-15T21:20:49Z",
  "db": "prd-cmsdb", "dbuser": "cur_app", "op": "QUERY", "retcode": 1064,
  "client_ip_class": "internal|external|cloud|nat|unknown",
  "ua_class": "browser|script|bot|unknown",
  "sql_shape": "원본 SQL 또는 이미 마스킹된 shape (producer 가 리터럴 '?' 치환)",
  "req_uri": "/path", "req_args_shape": "k=v&...",
  "resp_bytes": 2189, "resp_series": [428,2189,428],
  "baseline": "평시 대비 1~2줄 문맥(이 user 가 통상 뭘 하는지 등)"
}
```
- **IP 는 원본 대신 `client_ip_class` 로만** 싣는다(사양서 §5).
- 실제 소스(Aurora 감사로그/WAF/앱로그/giipApi)에서 뽑을 때, 이 스키마로 정규화해 producer 에 넘기면 된다. 마스킹·전단필터는 producer 가 수행한다.

---

## 5. 실행

```bash
# 1) 먼저 dry-run 으로 보낼 payload 확인(전송 안 함, token 가림)
python3 secevt_sample.py --no-label | python3 secevt_put.py --lssn <LSSN> --stdin --dry-run

# 2) 실제 전송
python3 secevt_put.py --lssn <LSSN> --event-file events.json
cat events.json | python3 secevt_put.py --lssn <LSSN> --stdin

# 3) 가성비: 전단필터 candidate=true 인 것만 전송
python3 secevt_put.py --lssn <LSSN> --event-file events.json --only-candidates
```
종료코드: `0` 성공 / `2` 입력·사용법 오류 / `3` sk 없음 / `4` 전송 실패.

---

## 6. 전송 결과 확인(적재 검증)

giipv3 KVS 조회 또는 API `KVSList kType kKey kFactor` (SP `pApiKVSListbySk`, kFactor 정확일치)로
`kType=lssn, kKey=<LSSN>, kFactor=secevt` 의 최근 행을 확인한다. 읽기 SP: `pApiKVSFactorLastbyAK`/`pApiKVSFactorListbyAK`.

---

## 7. 다른 PC 에 적용하는 절차 (AI 에게 그대로 지시 가능)

1. 이 레포(giip-fde-agent)를 그 PC 에 둔다(기존 설치면 `scripts/secwatch/` 만 있으면 됨).
2. 그 PC 의 giip 에이전트 `giipAgent.cfg`(또는 `.cnf`)에 `sk=`/`lssn=` 가 있는지 확인. 없으면 `GIIP_SK`/`GIIP_LSSN` 환경변수로 준다.
3. 연결 점검: `python3 scripts/secwatch/secevt_sample.py --no-label | python3 scripts/secwatch/secevt_put.py --stdin --dry-run` → payload 가 출력되면 OK.
4. 합성 전송: 위 명령에서 `--dry-run` 을 빼고 실행 → `pApiKVSListbySk` 로 `secevt` 행 적재 확인.
5. 실데이터 연동: 그 PC 의 실제 소스를 §4-2 스키마로 정규화하는 수집부를 붙여 producer 에 넘긴다.
   - **운영 실데이터 투입 전 반드시**: 사양서 §9 데이터취급 심사(외부 Jev 송신은 consumer 단계이지만, tKVS 적재 자체도 사내 로그 취급 정책을 따른다).
6. 정기 실행이 필요하면 그 PC 의 스케줄러(cron/작업스케줄러)로 producer 를 주기 호출한다.

---

## 8. 한계·주의

- 마스킹은 따옴표 문자열·숫자 리터럴을 `?` 로 치환한다(shape 보존). 16진 blob(`0x..`) 등 일부 상수는 남을 수 있어, 민감 상수를 쓰는 소스라면 수집부에서 추가 정규화한다.
- 전단필터는 **재현율 우선**(의심되면 candidate=true). 정상인데 걸리는 건(예: `biwa` 의 정상 `information_schema` 조회)은 2차 Jev + `baseline` 이 교정한다 — 전단에서 과탐을 두려워하지 않는다.
- producer 는 tKVS 에 넣기만 한다. 통지/차단은 하지 않는다(consumer 설계 §6·§7).
- giipApiSk4 는 HTTP 200 고정 — 본문으로 성공 판단. 실패 응답이면 종료코드 4.
