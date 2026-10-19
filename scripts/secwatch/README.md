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
| `secevt_collect.py` | **수집부①→②**. 소스 로그(aurora_audit/waf/cloudfront/**sec_monitor**/generic) → 정규화 이벤트(+origin) |
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
  "client_ip": "203.0.113.9",
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

### 5.1 필드를 빼면 **무엇이 조용히 죽는가** (이 표가 이 문서의 핵심)

빠진 필드는 에러를 내지 않는다 — 판정이 조용히 약해질 뿐이다. 그래서 "왜 화면에 안 보이지?"로만 드러난다.
실제 사고(2026-10-19): 어떤 수집기가 `client_ip`·`resp_bytes` 없이 10분마다 보냈고, 화면의 공격자 IP 가 계속 `-` 였다.

| 필드 | 없으면 | 결과(화면에서 보이는 증상) |
|---|---|---|
| `client_ip` | **같은 공격자 추적 불가** | `공격자 IP` 칸이 `-`. IP 로 묶기·차단 판단을 못 한다 |
| `resp_bytes` | 유출 판정 근거 없음 | `데이터 유출` 플래그가 **영원히 안 뜬다**(Jev `data_extracted` 가 판정 불가) |
| `resp_series` | 응답크기 이봉 탐지 불가 | 전단필터 `resp_bimodal` 룰이 **발동 자체를 못 한다**(블라인드 인젝션이 값을 빼내는 신호를 놓침) |
| `retcode` | 성공/실패 구분 불가 | `1064`(구문오류=실패) 같은 판단 근거가 사라진다. `error_retcode` 룰도 안 걸린다 |
| `sql_shape` / `req_args_shape` / `req_uri` | **전단필터가 볼 게 없다** | 룰이 하나도 안 걸려 `candidate=false` → 전송조차 안 되거나 저강도(`recon_probe`)로만 판정된다 |
| `baseline` | 평시 대비 문맥 없음 | 정상 업무도구를 공격으로 오판할 확률이 올라간다(오탐) |
| `origin` | **원본 복귀 단서 없음** | 마스킹 때문에 비마스킹 원본은 ①소스에만 남는다 → 침해대응 때 되돌아갈 수 없다 |

### 5.2 IP 정책 (2026-10-19 개정 — 이전 문서와 다르다)

**실제 IP(`client_ip`)를 보낸다.** 종전 문서는 "IP 는 `client_ip_class` 라벨로만" 이었는데, **같은 공격자를 추적·차단하려면 실제 IP 가 필요**하다는 제품 결정으로 바뀌었다. 종전 규정의 취지(외부 SaaS 에 PII 미전송)는 **보내는 쪽이 아니라 게이트웨이가** 지킨다:

- 실제 IP → **giip DB(`kscActorIp`)에만** 저장(추적·차단·동일 공격자 판정)
- **Jev(외부 SaaS) 전송 state 에는 IP 를 넣지 않는다** — 게이트웨이가 state 조립에서 제외한다. Jev 는 요청/SQL 형태로 판정하므로 IP 없이도 판정력이 떨어지지 않는다
- `client_ip_class` 도 **같이** 보낸다(빠른 필터용). 둘 중 하나만 보내지 말 것

정본: giipdb `docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md` §17.3
(https://github.com/LowyShin/giipdb/blob/main/docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md)

### 5.3 `generic` 경로의 함정 — **직접 만든 JSON 은 아무도 보완해주지 않는다**

`--source generic` 은 받은 JSON 을 **그대로 통과**시킨다(남이 정규화한 이벤트를 변조하지 않는다는 설계). 즉:

> **`generic` 으로 보내면 `client_ip`·`resp_bytes`·`resp_series` 를 당신이 직접 넣어야 한다.**
> 최신 giip-fde-agent 를 쓰는 것만으로는 채워지지 않는다 — 그 필드를 채우는 코드는
> `aurora_audit`/`waf`/`cloudfront` **파서 안에** 있다.

**`dbre_tools/sec_monitor` 리포트는 전용 파서가 이미 있다** — `--source sec_monitor` 를 쓰면 끝이다:
```bash
python3 secevt_collect.py --source sec_monitor --file out/report_20261019_0348.json \
  | python3 secevt_agent.py --lssn <LSSN> --stdin
```
파일 전체가 JSON 1개(배열 또는 `findings`/`alerts`/`events`/… 컨테이너)인 형식을 받아,
`client_ip`·`resp_bytes`·`retcode`·페이로드를 **원본에서 뽑아** §5 로 매핑한다(필드명 동의어를 폭넓게 인식 —
`src_ip`/`remote_addr`/`clientIp`/`c-ip`, `bytes`/`response_bytes`/`sc-bytes` 등). `resp_series` 는 자동 조립된다.
받는 키 전체 목록은 `secevt_collect.py` 의 `parse_sec_monitor_*` 주석에 있다(그 주석이 입력 사양이다).

그 밖의 자체 포맷이면 선택지는 둘이다:
1. **파서를 추가한다(권장)** — `secevt_collect.py` 에 `parse_<name>` 을 붙이고 `PARSERS` 에 한 줄 등록.
   기존 `parse_cloudfront`(응답크기 `sc-bytes` 추출) / `parse_waf`(`httpRequest.clientIp` 추출)를 본뜨면 된다.
   파일 하나만 고치면 되고, `attach_resp_series()` 가 같은 스윕의 응답크기를 자동으로 묶어준다.
2. **생산자 쪽에서 §5 를 완전히 채워 `generic` 으로 보낸다** — 위 5.1 표의 필드를 직접 채운다.

### 5.4 도입 직후 자기점검 (보내기 전에 1분)

```bash
# 내 소스가 §5 를 채우는지 payload 로 눈으로 확인(전송 안 함, sk 는 가려짐)
python3 secevt_collect.py --source <내소스> --file <경로> \
  | python3 secevt_agent.py --lssn <LSSN> --stdin --dry-run
```
출력 payload 에서 **아래가 보이는지** 확인한다 — 안 보이면 위 5.1 표의 "결과" 열이 그대로 현실이 된다.

- `"client_ip": "..."` (실제 IP) + `"client_ip_class": "..."`
- `"resp_bytes": <숫자>` / 같은 경로 요청이 2건 이상이면 `"resp_series": [...]`
- `"sql_shape"` 또는 `"req_args_shape"` 에 **리터럴이 `?` 로 치환된** 공격 페이로드
- `"origin": {...}` 가 비어 있지 않음
- `"prefilter": {"candidate": true, "rules": [...]}` — rules 가 비면 전송 대상이 아니다

적재 후 화면/DB 확인:
```sql
-- 공격자 IP·패턴번호·응답정보가 실제로 들어왔는지
SELECT TOP 5 kscsn, kscActorIp, kscPatternNo, kscRespBytes, kscAttackType, kscRoutedTo, kscRegdt
FROM tKVSSecurityCheck WHERE kscKey = '<내 lssn>' ORDER BY kscsn DESC;
```
`kscActorIp` 가 `NULL` 이면 **보내는 쪽이 `client_ip` 를 안 넣은 것이다**(게이트웨이·DB·화면은 이미 받을 준비가 되어 있다).

---

## 5.5 AI 지시서 언어 — 조직 cLang 을 따른다 (새로 만들지 말 것)

모니터의 `copy AI prompt` 는 **조직(csn)의 `tCorp.cLang`** 언어로 만들어진다. 설정이 없으면 영어다.

해석 순서(정본 규칙 `.agent/rules/52_project_language_from_csn.md` 의 우선순위를 그대로 따른다):

1. `GIIP_CLANG` 환경변수(명시 override)
2. **`slack-bot/.csn-lang-cache.env`** 의 `CSN_<csn>_LANG` — csn→cLang 영속 캐시(정본 메커니즘).
   이 캐시는 `slack-bot/csn-lang-cache.js` 의 `prefetch()` 가 `pApiCorpLangGetbySk` 로 채운다.
3. `giipAgent.cfg`/`.cnf` 의 `cLang`
4. 없으면 `en`

지원 언어키: `en`(기본) · `ko` · `ja` · `zh-CN` · `zh-TW`. `cLang` 값이 `ko-kr`/`en-US` 처럼
지역 접미사를 가지면 정규화된다(중국어만 간체/번체 구분을 위해 지역 유지).

> **중요**: 언어 해석기를 **새로 만들지 말 것.** 이미 정본 메커니즘이 있고, rule 52 가 "중복 메커니즘을
> 새로 만들 위험"을 명시 경고한다. 2026-10-19 에 실제로 그 중복이 발생했다(경위는 rule 52 말미 참조).
> 웹 콘솔(giipv3 `admin/secwatch-monitor`)은 **페이지 로케일**을 쓴다 — 언어 전환 UI 가 있기 때문이다.

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

> **"사용자가 항목을 지시하면 AI 가 수집→정규화→상시감시 편입" 전용 지시서**:
> [`docs/60-operations/secwatch-ai-onboarding.md`](../../docs/60-operations/secwatch-ai-onboarding.md). 아래는 그 요약이다.

1. 이 레포(giip-fde-agent)를 그 PC 에 두고 `scripts/secwatch/` 를 확인.
2. 그 PC 의 `giipAgent.cfg`(또는 `.cnf`)에 `sk=`/`lssn=` 가 있는지 확인. 없으면 `GIIP_SK`/`GIIP_LSSN` 환경변수로 준다. **Jev 키는 필요 없다(게이트웨이가 보유).**
3. 연결 점검: `python3 secevt_sample.py --no-label | python3 secevt_agent.py --lssn <LSSN> --stdin --dry-run` → payload 가 출력되면 OK.
4. 합성 전송: `--dry-run` 을 빼고 실행 → 게이트웨이 verdict 반환 + `tKVSSecurityCheck` 적재 확인.
5. 실데이터 연동: `secwatch.sources.example.json` 을 `secwatch.sources.json` 으로 복사해 최상위 `lssn`(한 번) 과 소스별 `file`/`system`/`since_offset` 를 채운다. `secevt_collect.py` 가 aurora_audit/waf/cloudfront 를 파싱하며, 포맷이 다르면 `generic`(정규화된 JSON-lines) 경로를 쓴다.
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
- **전단필터 판정기준(규칙 목록·대상 필드·점수식·비후보·방침) 정본**: [`docs/60-operations/secwatch-agent.md` §10](../../docs/60-operations/secwatch-agent.md#10-1차-전단필터-판정기준-정본). 규칙을 바꾸면 그 §10 표도 함께 고친다.
- 에이전트는 전송만 한다. 통지/차단은 게이트웨이·대시보드 쪽(사양서 §7)이 담당.
