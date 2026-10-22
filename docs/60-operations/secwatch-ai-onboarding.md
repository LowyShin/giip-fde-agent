# secwatch — 지시받은 보안 로그 항목을 상시감시에 편입하기 (AI 실행용 지시서)

> **독자: 수집 PC/서버에서 도는 AI 에이전트.** 사용자가 "이 항목을 secwatch 로 봐줘" 라고 지시하면,
> 이 문서의 절차를 **그대로 실행**해 그 항목을 secwatch 상시감시 파이프라인에 편입한다.
> 결과: 지정한 보안 로그가 주기적으로 수집·마스킹·전단필터돼 giip Jev 게이트웨이로 전송되고,
> SQL 인젝션/공격 판정이 `tKVSSecurityCheck` 에 적재돼 모니터에서 보인다.
>
> 설치·등록 일반 절차: [`secwatch-agent.md`](secwatch-agent.md). 스크립트 관점: [`../../scripts/secwatch/README.md`](../../scripts/secwatch/README.md).
> 정본 설계: giipdb `SPEC_JEV_SQLI_DETECTION.md`(§5 입력 스키마·§6 질문·§7 게이트·§17 전송). 이슈: **giip 3833**.

---

## 0. 적용 범위 (먼저 판정)

secwatch 는 **범용 분석기가 아니다.** 게이트웨이의 Jev 판정은 오직 "이것이 SQL 인젝션/공격 또는 공격 준비인가"
(`is_injection`·`attack_type`·`severity`·`data_extracted`·`write_attempt`)만 답한다. 그러므로 편입 대상은
**보안/공격 의심 로그**(DB 감사로그·WAF·CDN 접근로그·앱 보안 신호 등)로 한정한다.

- 지시받은 항목이 보안과 무관한 일반 데이터면 → **편입하지 말고** "secwatch 는 공격 판정 전용이라 이 항목은 맞지 않는다"
  고 사용자에게 보고한다. 억지로 넣으면 모든 행이 의미 없는 LOG 로 떨어진다.

---

## 1. 흐름 한눈에

```
사용자 지시(항목)
  → ① 소스 로그(이 PC 의 파일/스트림)
  → ② secevt_collect.py  : 원형식 → §5 정규화 이벤트(+origin)
  → ② secevt_agent.py    : 마스킹(리터럴 '?' 치환, at source) · 1차 전단필터 · 후보만 전송 [이 PC 에 Jev 키 없음, sk 인증]
  → ⑤ giip Jev 게이트웨이 : sk→csn 검증 · Jev 판정 · 게이트 라우팅(alert/review/log)
  → ⑥ tKVSSecurityCheck  : 판정 + kscOriginRef(①원본 위치) 적재
  → ⑦ monitor.py / 대시보드 : 결과 조회
secevt_run.py = ② 를 설정(secwatch.sources.json)대로 1회 스윕. 스케줄러가 주기 호출 → 상시감시.
```

**마스킹·전단필터는 에이전트가 자동으로 한다.** AI 가 할 일은 "지시받은 항목을 §5 스키마로 수집되게 만들고,
설정·스케줄러에 등록"하는 것뿐이다. 원본 SQL/PII 를 직접 보내지 않는다.

---

## 2. 입력 — 항목을 먼저 확정한다

사용자 지시에서 아래를 확정한다. 모르면 **묻지 말고 이 PC 에서 직접 확인**(파일 존재·형식 확인)한 뒤, 불명확한 것만 보고한다.

| 확정할 것 | 예 |
|---|---|
| 무엇을 보나(로그 종류) | Aurora/DB 감사로그, WAF 로그, CloudFront 접근로그, 앱의 공격 의심 로그 |
| 어디 있나(이 PC 의 경로) | `/var/log/audit/server_audit.log`, `C:\logs\waf\waf.jsonl` |
| 원형식 | CSV / JSON-lines / W3C 탭구분 / 기타 |
| 소스 시스템명 | `prd-cmsdb`, `cms-waf` (origin.system 에 들어감) |

### 이벤트 타입(kscFactor)은 4개 중 하나로만 — 임의 이름 금지
수집 이벤트의 `src` 필드가 타입을 자동 결정한다(사양서 §17.1). **반드시 아래 `src` 값 중 하나를 쓴다.**

| 이벤트 `src` | 결과 타입(kscFactor) | 쓰는 경우 |
|---|---|---|
| `aurora_audit` · `db_audit` · `batch_audit` | `secevt_batch_audit` | DB 감사로그 |
| `waf` | `secevt_waf` | WAF 로그 |
| `cloudfront` · `cf` | `secevt_cf` | CDN 접근로그 |
| `signal` · `applog` · (그 외 기본) | `secevt_signal` | 파생 신호·기타 앱 보안 로그 |

> **주의(혼동 포인트):** 설정의 `source`(= 어느 파서를 쓸지, 아래 §3)와 이벤트의 `src` 필드(= kscFactor 결정)는 **다른 값**이다.
> 커스텀 파서를 만들 때도 이벤트의 `src` 는 위 표의 인식값으로 채워야 타입이 올바르게 붙는다.

---

## 3. 수집·정규화 경로 결정 (결정 트리)

지시받은 항목의 원형식에 따라 **셋 중 하나**를 고른다.

### A. 이미 지원하는 형식 — 그대로 쓴다
`aurora_audit`(MariaDB/MySQL 감사 플러그인 CSV) · `waf`(AWS WAF JSON-lines) · `cloudfront`(W3C 탭구분)
· **`sec_monitor`**(`dbre_tools/sec_monitor` 의 `out/report_*.json`).
→ 추가 코드 없이 설정의 `source` 에 해당 값만 넣으면 끝. **§4 로 간다.**

> **`sec_monitor` 를 쓸 때**: 파일 전체가 JSON 1개(배열 또는 `findings`/`alerts`/`events`/… 컨테이너)인
> 형식을 받아 `client_ip`·`resp_bytes`·`retcode`·페이로드를 **원본에서 자동으로 뽑는다**.
> 필드명은 동의어를 폭넓게 인식한다(`src_ip`/`remote_addr`/`clientIp`/`c-ip`,
> `bytes`/`response_bytes`/`sc-bytes`, `status`/`http_status`/`code` 등) — 리포트 스키마가 조금 달라도 동작한다.
> **받는 키의 전체 목록은 `scripts/secwatch/secevt_collect.py` 의 `parse_sec_monitor_*` 주석에 있고, 그 주석이 입력 사양이다.**
> 리포트에 IP 가 들어 있는데도 화면에 `-` 로 뜨면, 그 리포트의 IP 키 이름을 그 주석의 동의어 목록에 추가하면 된다.

### B. 이미 §5 스키마의 JSON-lines — `generic` (조건부)
항목이 이미 한 줄당 1 이벤트 JSON 이고 §5 필드에 맞으면 `source: "generic"`.

> **주의 — `generic` 은 받은 JSON 을 그대로 통과시킨다(변조하지 않는 설계).**
> 즉 `client_ip`·`resp_bytes` 가 그 JSON 에 **없으면 아무도 채워주지 않는다.**
> 최신 giip-fde-agent 를 쓰는 것만으로는 채워지지 않는다 — 그 필드를 뽑는 코드는 **파서 안에** 있다.
> 그래서 원본에 IP·응답크기가 있는데 JSON 에 빠져 있다면 **B 가 아니라 C(파서 추가)를 택한다.**
> §2.1 표를 보고 빠진 필드가 있으면 C 로 간다.

→ §2.1 의 필수 필드가 **모두 들어 있을 때만** 추가 코드 없이 **§4 로 간다.**

§5 이벤트 스키마(한 줄당 1건):
```json
{ "src": "waf|applog|...(위 §2 표)", "ts": "ISO8601",
  "db": "...", "dbuser": "...", "op": "QUERY", "retcode": 1064,
  "client_ip": "203.0.113.9",
  "client_ip_class": "internal|external|cloud|nat|unknown",
  "ua_class": "browser|script|bot|unknown",
  "sql_shape": "공격 의심 SQL/페이로드 (마스킹은 에이전트가 함)",
  "req_uri": "/path", "req_args_shape": "k=v&...",
  "resp_bytes": 2189, "resp_series": [428,2189,428],
  "baseline": "평시 대비 1~2줄 문맥",
  "origin": { "source":"...", "system":"...", "location":"파일/로그그룹/키", "ref":"원본 내 식별자", "ts":"..." } }
```

### 2.1 **반드시 채워야 하는 필드** — 빼면 에러 없이 기능이 죽는다

빠진 필드는 예외를 내지 않는다. 판정이 조용히 약해지고, 화면에서 "왜 안 보이지?"로만 드러난다.
**실제 사고(2026-10-19)**: 어떤 수집기가 `client_ip`·`resp_bytes` 없이 10분마다 보내서, 모니터의
`공격자 IP` 가 계속 `-` 였고 판정도 `recon_probe 25%` 에 머물렀다. AI 는 아래를 **채우는 것이 임무다.**

| 필드 | 어디서 얻나 | 안 채우면 |
|---|---|---|
| **`client_ip`** (실제 IP) | WAF `httpRequest.clientIp` / CloudFront `c-ip`(W3C 5번째) / DB감사로그 host / 앱로그의 접속원 | **공격자 IP 가 `-` 로 뜨고 같은 공격자 추적·차단이 불가능** |
| `client_ip_class` | 위 IP 를 internal/external/cloud/nat 으로 분류 | 빠른 필터 불가(IP 와 **둘 다** 보낸다) |
| **`resp_bytes`** | 접근로그의 응답 바이트(CloudFront `sc-bytes` 등) | **`데이터 유출` 플래그가 영원히 안 뜬다**(유출 판정 근거 없음) |
| **`resp_series`** | 같은 경로 요청들의 응답크기 목록 | 응답크기 이봉 룰(`resp_bimodal`)이 **발동 자체를 못 한다** |
| `retcode` | SQL 오류코드(1064 등)·HTTP 상태 | 성공/실패 구분 불가, `error_retcode` 룰 미발동 |
| `sql_shape` / `req_args_shape` / `req_uri` | 공격 페이로드가 담긴 필드 | **전단필터가 볼 게 없어** 후보로 잡히지 않거나 저강도로만 판정 |
| `origin` | 소스·파일·식별자 | 침해대응 때 **원본으로 되돌아갈 단서 소멸** |

> `resp_series` 는 직접 만들지 않아도 된다 — `secevt_collect.py` 의 `attach_resp_series()` 가
> 같은 스윕에서 `(src, req_uri)` 로 묶어 자동으로 채운다. **단 `resp_bytes` 를 채웠을 때만 작동한다.**

### 2.2 IP 정책 (2026-10-19 개정 — 옛 문서와 반대다)

**실제 IP 를 보낸다.** 종전 규정은 "IP 는 `client_ip_class` 라벨만" 이었으나, 같은 공격자 추적·차단에
실제 IP 가 필요하다는 제품 결정으로 바뀌었다. 외부 유출 방지는 **보내는 쪽이 아니라 게이트웨이가** 한다:
giip DB(`kscActorIp`)에만 저장하고 **Jev(외부 SaaS) 전송 state 에서는 제외**한다.
정본: giipdb `docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md` §17.3.

### C. 그 외 원형식 — 파서를 추가한다 (권장) 또는 전처리
원형식이 A·B 어디에도 안 맞으면, `scripts/secwatch/secevt_collect.py` 에 **기존 패턴 그대로** 파서를 하나 더 붙인다.

1. `parse_<name>(line, system, location, lineno)` 함수를 추가한다. 기존 `parse_waf`/`parse_cloudfront` 를 본뜬다.
   - 반환은 §5 스키마 dict(위 B). **`origin` 은 `_origin(...)` 로 반드시 채운다** — 마스킹 후 원본 추적 유일 단서.
   - **공격 페이로드는 `sql_shape` 또는 `req_args_shape` 또는 `req_uri` 에 담는다.** 전단필터·마스킹이 이 세 필드만 본다.
   - **`client_ip` 에 실제 IP 를 담는다**(§2.2). 원본 로그에 IP 가 있으면 반드시 뽑는다 — 이걸 빼면
     화면의 공격자 IP 가 `-` 가 된다. 분류 라벨 `client_ip_class` 도 함께 채운다.
   - **응답 바이트가 원본에 있으면 `resp_bytes` 에 담는다**(예: CloudFront W3C 4번째 필드 `sc-bytes`).
     이걸 채우면 `resp_series` 는 `attach_resp_series()` 가 자동으로 묶어준다 → 유출 판정이 가능해진다.
   - 파싱 실패 줄은 `return None`.
   - 참고 구현: `parse_waf`(clientIp 추출) · `parse_cloudfront`(c-ip + sc-bytes 추출).
2. `PARSERS` dict 에 `"<name>": parse_<name>` 한 줄 등록.
3. 이벤트의 `src` 는 §2 표의 인식값으로 설정(예 앱 보안 로그면 `"applog"`).

> 원본 파일을 건드리면 안 되는 소스라면, 대신 가벼운 전처리로 §5 JSON-lines 파일을 따로 만들고 `source: "generic"` 으로 그 파일을 tail 한다(B 로 귀결).
> 파서 추가가 거의 항상 더 깔끔하다 — 새 설정 파일·크론 항목이 안 늘기 때문.

---

## 4. 설정 등록 — `secwatch.sources.json`

템플릿 복사 후 항목을 추가한다. `secevt_run.py` 가 읽는다.
```bash
cp scripts/secwatch/secwatch.sources.example.json <설치경로>/secwatch.sources.json
```
```json
{
  "lssn": 72784,
  "sources": [
    { "source": "aurora_audit", "file": "/var/log/audit/server_audit.log",
      "system": "prd-cmsdb", "since_offset": "/var/lib/giip/secwatch/aurora.offset" },
    { "source": "<A의 값 | generic | C에서 추가한 이름>", "file": "<이 PC의 경로>",
      "system": "<소스 시스템명>", "since_offset": "<증분 위치파일 경로>" }
  ]
}
```
- **`lssn` 은 최상위에 한 번만** 둔다(소스별이 아님). 미지정 시 env `GIIP_LSSN` 또는 `giipAgent.cfg` 의 `lssn=`.
- `since_offset`: 지정하면 매 스윕마다 **새로 늘어난 줄만** 처리(상시감시 필수). 생략하면 매번 파일 전체 재처리.
- `source` 값은 반드시 파서 키(§3 의 A 값, `generic`, 또는 C 에서 추가한 이름)와 일치해야 한다.

---

## 5. 연결 점검 (실데이터 전, dry-run)

전송 없이 수집→마스킹 payload 만 확인한다(token 은 가려짐).
```bash
# 합성 샘플로 경로·분류 확인
python3 scripts/secwatch/secevt_sample.py --no-label \
  | python3 scripts/secwatch/secevt_agent.py --lssn <LSSN> --stdin --dry-run

# 실제 항목을 dry-run 으로(파서가 §5 로 뽑는지 + 마스킹되는지 확인)
python3 scripts/secwatch/secevt_collect.py --source <source> --file <경로> \
  | python3 scripts/secwatch/secevt_agent.py --lssn <LSSN> --stdin --dry-run
```
payload 가 출력되고 `sql_shape`/`req_args_shape` 의 리터럴이 `?` 로 치환돼 있으면 OK.

---

## 6. 상시 감시 등록 (주기 실행)

`secevt_run.py` 를 스케줄러가 N분(기본 5분)마다 부르게 한다.

**Windows (작업스케줄러):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\secwatch\register-secwatch-scheduler.ps1 `
  -Action Register -Config "C:\giip\secwatch.sources.json" -IntervalMinutes 5
# 확인 / 해제
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\secwatch\register-secwatch-scheduler.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\secwatch\register-secwatch-scheduler.ps1 -Action Unregister
```

**Linux (cron):**
```cron
*/5 * * * * /usr/bin/python3 /path/giip-fde-agent/scripts/secwatch/secevt_run.py --config /etc/giip/secwatch.sources.json >> /var/log/giip/secwatch.log 2>&1
```

---

## 7. 검증 — 실제로 분석되는지 확인

1. 수동 스윕 1회:
   ```bash
   python3 scripts/secwatch/secevt_run.py --config <설치경로>/secwatch.sources.json --dry-run   # 파싱·후보 수만
   python3 scripts/secwatch/secevt_run.py --config <설치경로>/secwatch.sources.json              # 실제 전송
   ```
   종료요약의 `전송 N · 🔴ALERT · 🟠REVIEW · ⚪LOG` 분포를 본다.
2. 적재 확인: 판정은 giipdb `tKVSSecurityCheck` 에 쌓인다(`kscFactor`·`kscRoutedTo`·`kscIsInjection`·`kscSeverity`·`kscOriginRef`).
3. 모니터: `python3 scripts/secwatch/monitor.py` → http://127.0.0.1:8787 (sk 자동, 기본 최근 24시간).
4. 전부 LOG 만 나오면: 전단필터가 비후보로 본 것(정상). 공격 샘플로 라우팅이 뜨는지 확인:
   `python3 scripts/secwatch/secevt_sample.py --only attack | python3 scripts/secwatch/secevt_agent.py --lssn <LSSN> --stdin`

---

## 8. AI 가 반드시 지킬 것 / 금지

- ✅ 편입 대상은 **보안/공격 의심 로그만**(§0). 비보안 데이터는 편입하지 말고 보고.
- ✅ 이벤트 타입은 **§2 의 4개 `src` 값만** 쓴다 — 임의 factor 이름 금지.
- ✅ `origin` 을 반드시 채운다(마스킹 후 원본 복귀 단서).
- ✅ 공격 페이로드는 `sql_shape`/`req_args_shape`/`req_uri` 에 담는다(그래야 전단필터·마스킹이 작동).
- ✅ **`client_ip`(실제 IP)와 `resp_bytes` 를 채운다** — 원본 로그에 있는데 안 담으면 공격자 추적과
  유출 판정이 통째로 불가능해진다(§2.1 표). `generic` 으로 흘리면 아무도 보완해주지 않는다.
- ✅ 편입 후 **`kscActorIp` 가 실제로 채워졌는지 DB/화면으로 확인**한다(§7). `NULL` 이면 내가 안 담은 것이다.
- ✅ 상시감시는 `since_offset` 을 반드시 설정(안 하면 매번 전량 재전송).
- 🚫 **이 PC 에 Jev 키(`TYPESAFE_API_KEY`)를 두지 않는다.** 게이트웨이(Azure 앱설정)에만 존재. 이 PC 는 sk 인증만.
- 🚫 원본 SQL 리터럴·IP 원본·PII 를 그대로 전송하지 않는다(마스킹은 에이전트가 at source 로 수행).
- 🚫 `sk` 값을 로그·인자·URL·커밋에 평문으로 남기지 않는다.

---

## 9. 사용자에게 돌려줄 보고 형식

편입을 마치면 아래를 보고한다.
- 편입한 항목: 소스종류 / 파일경로 / 매핑된 타입(kscFactor) / 수집 경로(A·B·C 중 무엇, C 면 추가한 파서명)
- 상시감시 등록: 스케줄러 종류·주기(예 5분), 설정파일 경로
- 첫 스윕 결과: 파싱 건수 / 전송(후보) 건수 / ALERT·REVIEW·LOG 분포
- 확인 방법: `monitor.py` 주소 또는 `tKVSSecurityCheck` 조회

---

## 9.5 AI 지시서 언어 (언어 해석기를 새로 만들지 말 것)

모니터의 AI 지시서는 조직(csn)의 `tCorp.cLang` 언어로 생성된다. 해석 순서는 정본 규칙
`.agent/rules/52_project_language_from_csn.md` 를 따르고, 1차 소스는 **`slack-bot/.csn-lang-cache.env`**
(csn→cLang 영속 캐시)다. 설정이 없으면 영어.
**이미 있는 메커니즘이므로 새 해석기를 만들지 않는다**(rule 52 가 중복 생성 위험을 명시 경고).
상세·소비자 목록: `scripts/secwatch/README.md` §5.5.

## 10. 관련 문서

- 설치·등록 일반 절차: [`secwatch-agent.md`](secwatch-agent.md)
- 스크립트 상세·파일맵: [`../../scripts/secwatch/README.md`](../../scripts/secwatch/README.md)
- 정본 설계(입력·질문·게이트·전송): giipdb `docs/30_Specs/SPEC_JEV_SQLI_DETECTION.md`
