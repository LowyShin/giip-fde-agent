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

로컬 대시보드: `python3 scripts/secwatch/monitor.py` → http://127.0.0.1:8787 (기본 1분 폴링, `--poll` 조정).
- UI 는 **영어 기본**이며 다국어 준비됨 — `monitor.py` 의 `I18N` 에 언어를 추가하고 `--lang <code>` 로 선택.
- 컬럼 설명은 화면 우상단 **? Help**(`/help`).
- **Origin 열**: `⧉ copy cmd` 를 눌러 복사한 명령을 분석가 자신의 터미널(cmd)에 붙여넣으면 원본 레코드를 파일로 받는다(S3=`aws s3 cp`, Aurora 감사로그=`aws logs get-log-events > 파일`; AWS CLI 필요). 그 외 소스는 명령 없이 origin 라벨만 표시.
- **데이터 윈도우(누적 아님)**: 화면은 **롤링 윈도우**다 — 매 폴링마다 목록을 통째로 교체(최신순)하며 브라우저에 쌓이지 않는다. 기본 **최근 60분**(`--minutes`), 폴링 **60초**(`--poll`). 판정 결과 자체는 `tKVSSecurityCheck`(DB)에 **영구 보존**되고(조회 SP `pApiKVSSecurityCheckWindowbySk`), 모니터는 그 시간범위만 읽는다.
- **giip 웹 콘솔(giipv3)**: 로컬 `monitor.py` 외에, giip 웹 콘솔에도 같은 결과를 보는 페이지가 있다(admin → secwatch 모니터). 웹 콘솔은 sk 를 브라우저에 두지 않으려고 **AK 인증 조회 SP `pApiKVSSecurityCheckWindowbyAK`** 를 쓴다(로그인 유저의 csn 범위만, giip #3833). 화면 호출: `fetchAzureCommand("KVSSecurityCheckWindow minutes routedTo csn", ...)`.
- **보존주기·표시·예상량(giip 측 사양)**:
  - **보존**: 결과 테이블 `tKVSSecurityCheck` 는 현재 **자동 정리가 없어 계속 누적**된다(원본 tKVS 는 7일 정리와 대비). 필요 시 giipfaw `CleanTable` 에 보존주기를 추가한다. `kscRoutedTo='log'`(정상 판정) 행도 동일하게 보존된다 — 롤링 윈도우라 화면에는 시간범위 밖이면 안 보일 뿐, 삭제되지 않는다.
  - **표시 상한·페이지 송출**: 조회 SP 는 시간범위(`minutes`, 최대 10080=7일) 안의 행을 최신순 전량 반환한다. 별도 건수 상한·페이지 송출은 **없다**(윈도우를 좁혀서 양을 조절한다). 대량 누적 환경이면 `minutes` 를 줄인다.
  - **1일 예상 행수**: 전송량 상한 기준 1 수집기당 10분마다 최대 80건 → 상한 ~11,520행/일, 통상은 0~수십건/일(동형 이벤트는 수집기가 1건으로 집약). csn·수집기 수에 비례.

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

## 10. 1차 전단필터 판정기준 (정본)

에이전트②는 **값싼 결정론 규칙**으로 "후보"만 Jev 게이트웨이로 보낸다(비후보는 안 보냄, `--all` 로만 강제 전송).
판정 로직은 `scripts/secwatch/secevt_lib.py` 의 `prefilter()`·`_PREFILTER`·`_ERR_RETCODES` 다.
**규칙을 추가/변경하면 이 표를 같이 고친다**(코드 주석에도 명시). 근거: SPEC_JEV_SQLI_DETECTION.md §5·§17, giip #3833.

### 10.1 판정 대상 필드
`sql_shape`, `req_args_shape`, `req_uri` 세 필드를 이어 붙여 검사한다.
- `sql_shape`·`req_args_shape` 는 **마스킹 후**(리터럴 `'…'`·숫자 → `?`) 검사한다 → 숫자가 포함된 패턴은 마스킹돼 안 걸릴 수 있다.
- `req_uri` 는 **마스킹하지 않는다** → URL 안의 IP·경로·도메인이 그대로 보존된다(아래 ssrf_metadata 등이 req_uri 에서 매칭).

### 10.2 규칙 목록

| 규칙 이름 | 탐지 패턴(요지) | 의도 |
|---|---|---|
| `schema_enum` | `information_schema`, `performance_schema`, `sys.objects/columns/tables`, `pg_catalog` | 스키마·메타 정찰 |
| `union_based` | `UNION … SELECT` | UNION 기반 추출 |
| `file_write` | `INTO OUTFILE`, `INTO DUMPFILE` | 파일 쓰기(유출) |
| `file_read` | `LOAD_FILE(` | 파일 읽기 |
| `boolean_blind` | `ASCII(SUBSTRING`, `ORD(MID`, `SUBSTR(ING)(` | 불리언 블라인드 |
| `time_blind` | `SLEEP(`, `BENCHMARK(`, `PG_SLEEP(`, `WAITFOR DELAY` | 시간 기반 블라인드 |
| `error_based` | `EXTRACTVALUE(`, `UPDATEXML(`, `FLOOR(RAND` | 오류 기반 추출 |
| `stacked_or_ddl` | `; DROP/ALTER/CREATE/INSERT/UPDATE/DELETE/GRANT` | 스택 쿼리·DDL |
| `cred_table` | `mysql.user`, `mysql.db` | 자격증명/권한 테이블 표적 |
| `oob_interact` | `oast.`, `dnslog`, `burpcollab`, `nip.io` | OOB/DNS 외부 상호작용(블라인드 유출) |
| `ssrf_metadata` | `169.254.169.254` | 클라우드 메타데이터 SSRF |
| `sensitive_file` | `/etc/passwd` | LFI/경로조작 시스템파일 노출 |
| `error_retcode` | retcode ∈ {1064,1054,1146,1241,1242} | 구문오류 연속(시행착오 신호) |
| `resp_bimodal` | `resp_series` 값이 2종 이상 **이고** boolean_blind/union_based 동반 | 응답 2봉 분포(블라인드 집계 신호) |

### 10.3 점수
`score = min(1.0, 0.3 + 0.2 × 적중규칙수)`, 후보가 아니면(적중 0) `score = 0`. 후보 여부는 "적중규칙 ≥ 1".

### 10.4 후보가 되지 않는 것 — 그리고 그 보완 경로
전단필터는 **패턴 기반**이라 다음은 후보로 잡지 못한다.
- 패턴이 없는 이상(정규식을 피한 변형, 신종 기법).
- 응답 크기/빈도만의 이상(단일 규칙으로는 안 걸림 — `resp_bimodal` 은 블라인드 규칙 동반 시에만).
- **평상시에 없던 "초출(novel) 형태"** 자체(지금까지 본 적 없는 SQL/URL 형태).

이들은 전단필터 밖의 경로로 다룬다: 집계 신호(`secevt_signal`), 그리고 **초출 형태 → Jev 후보화**(novel_shape, 아래).

### 10.5 방침 — 재현율 우선
전단필터는 **재현율(빠뜨리지 않기) 우선**이다. 오탐은 게이트웨이의 **2차 Jev 판정**과 `baseline`(평상시 설명)이 바로잡는다.
그래서 전단필터는 "의심스러우면 보낸다"로 느슨하게 두고, 정밀 판정은 Jev 에 맡긴다.

## 11. 초출(novel) 형태 → Jev 후보화 + 자동학습 (항목 7, giip #3833)

패턴 규칙에 안 걸리는 **"평상시에 없던 형태"(초출)** 를 Jev 에 판정시키고, 정상으로 판정된 형태는 학습해 다음부터 조용히 통과시키는 기능. 기본 **OFF**(opt-in).

### 11.1 켜는 법
- 설정: `secwatch.sources.json` 에 `"send_novel": true` (또는 환경변수 `GIIP_SECEVT_SEND_NOVEL=1`, `secevt_agent.py --send-novel`).
- 저장소 경로: `"known_shapes_file"`(설정) 또는 env `GIIP_SECEVT_KNOWN_SHAPES`, 기본 `./secwatch.known_shapes.json`.

### 11.2 동작
1. 이벤트의 **마스킹된 형태**(sql_shape/req_args_shape/req_uri)로 `shape_id` 를 만든다.
2. send_novel 가 켜졌고 그 `shape_id` 가 "알려진 정상 형태" 저장소에 없으면 → 전단필터 규칙에 `novel_shape` 를 붙여 **후보**로 만든다 → 게이트웨이가 기존 로직대로 **Jev 로 2차 판정**한다(게이트웨이 `run.ps1` 성역을 건드리지 않는다).
3. Jev 가 그 형태를 **정상(`routedTo=log`)으로 판정**하면, 에이전트가 그 `shape_id` 를 알려진-정상 저장소에 **학습**(만료 포함)한다 → 다음 회차부터는 초출이 아니라 조용히 통과.

### 11.3 자동학습 악용 방지 (설계 핵심)
"정상 형태를 학습한다"는 것이 공격 우회로가 되지 않도록 세 가지로 막는다.
1. **학습 단위가 마스킹된 "형태"의 `shape_id`** 다. 공격 변형은 형태(마스킹 후 구조)가 달라 `shape_id` 가 달라지므로, 정상 형태를 학습해도 **다른 형태의 공격은 화이트리스트되지 않는다**(검증: `UNION … mysql.user` 가 붙은 공격은 정상 형태와 shape_id 가 다름).
2. **Jev 가 `log`(정상)로 실제 판정**(engine=jev)한 형태만 학습한다. 공격 형태는 Jev 가 log 로 판정하지 않으므로 학습 경로에 들어오지 못한다(rule-only 폴백 log 는 학습 제외).
3. **만료(TTL 30일)**. 학습된 형태도 만료되면 다시 초출로 Jev 재판정 → 장기 "길들이기"를 제한.

### 11.4 비용·운영
초출만 보내므로 초기엔 수백 건(평상시 SQL 형태 약 170종), 정상 학습이 쌓이면 정상 시 수 건/일로 수렴. 저장소 파일은 `{"v":1,"shapes":{shape_id:{"first":epoch,"exp":epoch}}}`.
구현: `secevt_lib.py`(`compute_shape_id`/`load_known_shapes`/`is_known_shape`/`learn_shape`/`maybe_learn_shape`), `secevt_agent.py`·`secevt_run.py`(연동).

## 12. 생존신호(heartbeat) — "멈춘 건지, 이상이 없는 건지" (항목 5, giip #3833)

보낼 이벤트가 없는 회차는 아무것도 전송하지 않아 대시보드가 멈춘 것처럼 보일 수 있다. 이를 구분하도록 **스윕이 돌 때마다 로컬 하트비트**를 남긴다(새 이벤트 타입을 만들지 않는다 — DB/게이트웨이 불변).

- **기록**: `secevt_run.py` 가 매 스윕 끝에 `secwatch.last_run.json` 을 쓴다(경로: config `heartbeat_file` / env `GIIP_SECEVT_HEARTBEAT` / 기본 config 폴더). 내용 `{ts, lssn, parsed, candidates, skipped, routed, novel_learned}`.
- **표시**: `monitor.py` 헤더에 "swept N min ago · checked M · cand K" 로 보인다(`/api/heartbeat`). 후보 0건이어도 "방금 돌았고 확인 M건, 이상 없음"이 보인다.
- **에이전트 자체의 생존**(프로세스가 체크인 중인지)은 기존 giipAgent 체크인(`tLSvr`)으로 `monitor.py` 의 agent DOWN/STALE 표시(§7)가 이미 담당한다. 이 하트비트는 "secwatch 스윕이 실제로 돌았는가"를 추가로 보여준다.
