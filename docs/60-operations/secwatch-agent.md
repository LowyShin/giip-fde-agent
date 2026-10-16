# secwatch 보안점검 에이전트 — 설치·등록·운영

> **역할**: 고객 수집 PC/서버에서 소스 로그(Aurora 감사로그·WAF·CloudFront·신호)를 수집·마스킹·전단필터해,
> 후보만 giip **Jev 게이트웨이**로 보내 SQL 인젝션 등 해킹 의심을 2차 판정·적재한다.
> **이 PC 에는 Jev 키가 없다**(sk 인증만). 구현 본체: `scripts/secwatch/`. 정본 설계: giipdb `SPEC_JEV_SQLI_DETECTION.md`. 이슈: **giip #3833**.
>
> 이 문서는 "새로 받아서 secwatch 등록" 을 **한 흐름으로** 수행하기 위한 표준 절차다.

---

## 0. 구조 요약

```
① 소스 로그 → ② secevt_collect.py(정규화+origin) → secevt_agent.py(마스킹·전단필터·전송, 키 없음)
   → ⑤ giip Jev 게이트웨이(giipfaw giipJevGateway, Jev 키 보유) → ⑥ tKVSSecurityCheck → ⑦ 대시보드
secevt_run.py = 위 ②를 설정(secwatch.sources.json)대로 1회 스윕. 스케줄러가 이걸 주기 호출.
```

## 1. 선행 조건 (반드시 먼저)

1. **게이트웨이 가동**: giipfaw `giipJevGateway` 가 Azure 에 배포되고 앱설정 `TYPESAFE_API_KEY` 가 설정돼 있어야 한다. (이게 없으면 전송이 실패한다.)
2. **데이터취급 심사(§9)**: 외부(Jev) 송신은 게이트웨이가 하지만, 실데이터 투입 전 보존·학습이용·소재지 심사를 완료한다.
3. **에이전트 키**: 이 PC 의 `giipAgent.cfg|.cnf` 에 `sk=` / `lssn=` (또는 env `GIIP_SK`/`GIIP_LSSN`). **Jev 키는 이 PC 에 두지 않는다.**
4. `python3` (3.6+, stdlib만).

## 2. 설치

```bash
# 레포는 이미 있다는 전제(giip-fde-agent). secwatch 는 scripts/secwatch/ 에 있다.
cp scripts/secwatch/secwatch.sources.example.json  <설치경로>/secwatch.sources.json
# 편집: lssn, 각 소스의 file 경로·system·since_offset
```

## 3. 연결 점검(실데이터 전)

```bash
# 합성 샘플로 수집→마스킹→(dry-run)전송 payload 확인
python3 scripts/secwatch/secevt_sample.py --no-label \
  | python3 scripts/secwatch/secevt_agent.py --lssn <LSSN> --stdin --dry-run
```
payload 가 출력되고 4개 타입(`secevt_batch_audit/waf/cf/signal`)으로 분류되면 OK.

## 4. 설정 (secwatch.sources.json)

```json
{ "lssn": 72784,
  "sources": [
    { "source":"aurora_audit", "file":"/var/log/audit/server_audit.log",
      "system":"prd-cmsdb", "since_offset":"/var/lib/giip/secwatch/aurora.offset" },
    { "source":"waf", "file":"/var/log/waf/waf.jsonl", "system":"cms-waf" } ] }
```
- `source`: `aurora_audit` | `waf` | `cloudfront` | `generic`(이미 정규화된 JSON-lines — 포맷이 다른 소스의 안전 경로).
- `since_offset`: 증분 처리위치 파일(지정 시 매 스윕마다 새 라인만 처리). 생략 시 매번 파일 전체.
- 포맷이 특이하면 `generic` 으로 두고, 소스를 §5 이벤트 스키마(+origin)로 바꾸는 가벼운 전처리를 앞에 붙인다.

## 5. 수동 스윕

```bash
python3 scripts/secwatch/secevt_run.py --config <설치경로>/secwatch.sources.json --dry-run  # 파싱·후보 수만
python3 scripts/secwatch/secevt_run.py --config <설치경로>/secwatch.sources.json             # 실제 전송
```

## 6. 등록(정기 실행)

**Windows (작업스케줄러):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\secwatch\register-secwatch-scheduler.ps1 `
  -Action Register -Config "C:\giip\secwatch.sources.json" -IntervalMinutes 5
# 확인/해제
... register-secwatch-scheduler.ps1 -Action Status
... register-secwatch-scheduler.ps1 -Action Unregister
```

**Linux (cron):**
```cron
*/5 * * * * /usr/bin/python3 /path/giip-fde-agent/scripts/secwatch/secevt_run.py --config /etc/giip/secwatch.sources.json >> /var/log/giip/secwatch.log 2>&1
```

## 7. 결과 확인

판정 결과는 giipdb `tKVSSecurityCheck` 에 적재된다. `kscRoutedTo`(alert/review/log)·`kscIsInjection`·`kscSeverity`·
`kscFactor`(타입)·`kscOriginRef`(①원본 위치)·`kscVerdictJson`. 대시보드(⑦)가 이 테이블을 조회한다.

로컬 대시보드: `python3 scripts/secwatch/monitor.py` → http://127.0.0.1:8787.
UI 는 **영어 기본**이며 다국어 준비됨 — `monitor.py` 의 `I18N` 에 언어를 추가하고 `--lang <code>` 로 선택한다.

## 8. 문제 해결

- 전송 실패(종료 4): 게이트웨이 URL/가동 확인(`GIIP_JEV_GATEWAY_URL`), sk 유효성. (§1-1 선행조건)
- sk 없음(종료 3): `giipAgent.cfg` 의 `sk=` 또는 env `GIIP_SK`.
- 결과가 전부 LOG: 전단필터 비후보(정상). 공격 샘플(`secevt_sample.py --only attack`)로 라우팅 확인.
- **금지**: 이 PC 에 `TYPESAFE_API_KEY` 를 두지 말 것. 임의 factor 이름 만들지 말 것(§표준 4개만).

## 9. 파일 맵

| 파일 | 역할 |
|---|---|
| `scripts/secwatch/secevt_collect.py` | 소스 로그 → 정규화 이벤트(+origin) |
| `scripts/secwatch/secevt_agent.py` | 마스킹·전단필터 → 게이트웨이 전송(키 없음) |
| `scripts/secwatch/secevt_run.py` | 설정대로 1회 스윕(스케줄러 진입점) |
| `scripts/secwatch/secevt_lib.py` | 공용 helper(마스킹·전단필터·이벤트조립) |
| `scripts/secwatch/secevt_sample.py` | 점검용 샘플 생성 |
| `scripts/secwatch/register-secwatch-scheduler.ps1` | Windows 등록(cron 은 §6) |
| `scripts/secwatch/secwatch.sources.example.json` | 설정 템플릿 |
| `scripts/secwatch/README.md` | scripts 관점 설명 |
