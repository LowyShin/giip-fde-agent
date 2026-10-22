# gissue 스케줄러 실행 이력 — admin/catquest/schedulers 에 표시되는 방식 (giip #3563, 정정: giip #3575)

> 이 문서는 PR #107 의 분석을 **정정**한다. #107 은 "PowerShell 이 bash 의 `sar_run_start` 를 못 불러서 이력이 없다"고 보고 bash 래퍼를 추가했지만, 그것은 원인이 아니었다.

> **PR #114(봇)** 는 래퍼의 `exec` 만 제거해 종료 trap 이 돌게 했다. 하지만 래퍼는 박스 에이전트(`hostname-machine-id`) 아래에 이력을 쌓고, 이 문서의 수정이 `gissue_csn<CSN>` 아래에 같은 실행을 기록하므로 둘을 같이 두면 **같은 실행이 두 에이전트에 중복 기록**된다. 그래서 우회(래퍼)가 아니라 근본 수정을 택해 래퍼를 제거했다.

## 증상
`admin/catquest/schedulers` 에서 gissue 스케줄러(`gissue_csn<CSN>`) 행이 없거나, History 에 실행 이력이 비어 있다.

## 근본 원인 (실측)
`run-gissue-claude.ps1` 은 이미 에이전트 등록, 실행 시작, heartbeat, 종료를 호출하고 있었다. 그런데 `giipApiSk2`(익명 디스패처)에 **폼 키 `sk`/`proc`** 로 보냈다.
디스패처는 SK 를 **`token`**, 실행할 SP 를 **`text`** 로만 읽으므로 `sk`/`proc` 는 무시되고 `help` 가 실행됐다. 응답도 검사하지 않아 경고 한 줄 없이 조용히 실패했고,
그래서 `tSchedulerAgent` 에 `gissue_csn47` 행이 없었다.

## 올바른 호출 형식
| 항목 | 값 |
|---|---|
| SK | 폼 키 `token` |
| SP | 폼 키 `text` = `"<이름> <값...>"`. 서버가 `pApi<이름>bySk` 로 조립(예: `SchedulerAgentRunStart` → `pApiSchedulerAgentRunStartbySk`). 값은 SP 파라미터 선언 순서의 위치 인자 |
| `jsondata` | 빈 값(비어 있지 않으면 마지막 파라미터로 하나 더 붙는다, giip #2477) |
| 값 인용 | 작은따옴표 리터럴. 값 안의 작은따옴표는 제거, CR/LF 는 공백 |
| NULL | 디스패처가 문자열로 넘긴다. INT 파라미터(`@exitCode`)에는 숫자 문자열을 채운다(NULL 이면 `nvarchar to int` 오류) |

구현: `scripts/gissue/lib/scheduler-state.ps1`(`Invoke-SchedulerAgentSp`, 응답 `RstVal` 이 200 이 아니면 예외 → 로그에 이유가 남는다), 단위 테스트 `scripts/gissue/tests/test-scheduler-state.ps1`.

## 기록되는 흐름
1. 잡 시작: `SchedulerAgentUpsert`(에이전트 등록, `gissue_csn<CSN>`) → `SchedulerAgentRunStart`
2. 이슈마다: `SchedulerAgentHeartbeatPut`(처리 건수, 현재 단계, 현재 이슈)
3. 종료(`Complete-Run`): `SchedulerAgentRunEnd` — 상태는 `DONE`→`SUCCEEDED`, `TIMEOUT*`→`TIMED_OUT`, 그 외 `FAILED`. 처리 건수는 잡이 마지막에 출력하는 `[RUN-COUNTS] processed=N` 에서 읽는다

## 검증 방법
```sql
SELECT TOP 10 r.runIdKey, r.status, r.startTime, r.endTime, r.processedCount, r.summary
FROM tSchedulerAgentRun r JOIN tSchedulerAgent a ON a.agentId = r.agentId
WHERE a.agentKey = 'gissue_csn47' ORDER BY r.startTime DESC;
```
화면: `admin/catquest/schedulers` 에서 `gissue_csn47` 의 History. 호출이 실패하면 `gissue_csn<CSN>.log`/잡 출력에 `[WARN][SchedulerState-...]` 또는 `[SchedulerState-runEnd]` 줄이 남는다.

## 한계
- 건너뜀/실패 건수는 아직 집계하지 않아 0 으로 기록된다. 처리 건수는 "엔진 처리를 시작한 이슈 수"다.

## 틱 20분 vs 실행 길이 — 소프트 예산을 도입한 이유 (giip 3615)

### 실측(읽기 전용, 2026-10-07 기준 csn 47 docker 인스턴스)
- 틱은 20분(`7,27,47`)인데 실제 실행 시작은 **2시간 간격**이었다: 15:27, 17:27, 19:27, 21:27, 23:27, 01:27, 03:27, 05:27, 07:27 (그리고 09:07).
  2026-10-06 15:27 이후 약 18.5시간 동안 틱은 약 55번이었고 실제로 일한 실행은 10번이다. 나머지 틱은 `SKIP: 실행 중(lock N분 전, PID 생존 확인)` 이었다
  (`gissue_csn47.log` 에서 2026-10-06 30건, 2026-10-07 09:54 까지 23건).
- 실행 길이(`tSchedulerAgentRun`, `agentKey = 'gissue_csn47'`):

  | 시작 | 상태 | 길이(분) | 처리 건수 | 처리 1건당 평균(분) |
  |---|---|---|---|---|
  | 10-06 15:27 | TIMED_OUT | 105 | 기록 0(*) | - |
  | 10-06 17:27 | TIMED_OUT | 105 | 기록 0(*) | - |
  | 10-06 19:27 | SUCCEEDED | 103 | 기록 0(*) | - |
  | 10-06 21:30 | SUCCEEDED | 101 | 26 | 3.9 |
  | 10-06 23:31 | TIMED_OUT | 101 | 23 | 4.4 |
  | 10-07 01:27 | SUCCEEDED | 104 | 25 | 4.2 |
  | 10-07 03:27 | SUCCEEDED | 101 | 32 | 3.2 |
  | 10-07 05:27 | SUCCEEDED | 101 | 13 | 7.8 |
  | 10-07 07:27 | SUCCEEDED | 93 | 45 | 2.1 |
  | 10-07 09:07 | RUNNING | (47분 경과 시점) | 8 | 5.9 |

  (*) 위 세 건의 처리 건수 0 은 종료 기록의 집계 누락이다(giip #3563 수정 이전 실행). 실제로는 일했다.
- 이슈 큐: `gissue_csn47.out.log` 에 남은 25회의 `[QUEUE]` 줄에서 처리 대상은 **73~97건**이었다. 한 실행이 처리하는 7~45건으로는 큐가 비지 않는다.
  큐가 비지 않으니 러너는 하드 타임아웃(105분) 근처까지 계속 돈다 = 락을 90분 넘게 쥔다.
- 처리 상태 구성(같은 out.log 의 `[ISSUE]` 786건): PENDING 350(44.5%), READY 305(38.8%), REVIEW 130(16.5%), STALE_IN_PROGRESS 1. TESTED 0.
  REVIEW 재검증 쿨다운 스킵(`[REVIEW-SKIP]`)은 1025건이었다.

### 측정의 한계(정직하게)
- **이슈 1건당 소요 시간의 분포(중앙값, 최대)는 직접 측정하지 못했다.** 잡 출력(`gissue_csn47.out.log`)에는 시각이 없고, 이 파일은 2026-10-06 15:09 이후 갱신되지 않았다
  (잡이 105분 하드 타임아웃으로 중단되면 출력이 남지 않는다 — `run-gissue-claude.ps1` 의 `[RUN-COUNTS]` 주석 참고). `[QUEUE-SUMMARY]` 줄(상태별 건수·분)도 이 파일에는 한 줄도 없다.
- 위 표의 "처리 1건당 평균"은 `실행 길이 / 처리 건수` 라서 저장소 정비 세션과 사후 준비 시간이 섞인 **상한 쪽 근사**다. 7회(진행 중 1회 포함) 값의 중앙값 약 4.2분, 범위 2.1~7.8분.
  이슈 1건의 하드 캡은 40분(`IssueEngineDeadlineMin`)이고 REVIEW/TESTED 는 더 짧다.
- 소프트 예산을 켠 뒤에는 `[QUEUE-SUMMARY]` 가 실행마다 상태별 건수와 소요 분을 남기므로(코드는 이미 있음) 그 로그로 분포를 다시 측정해야 한다.

### 효과 예측(추정, 검증 전)
- 소프트 예산 15분이면 한 실행은 약 15분 + 마지막 이슈 1건(평균 4~8분, 최대 40분 캡)이다. 이슈 1건 평균을 4분으로 보면 실행당 3~4건이다.
  틱 20분마다 실행이 새로 시작되므로 처리량은 "2시간에 약 25건" 수준에서 "2시간에 18~24건" 수준이 될 수 있다 - 즉 **총처리량이 늘어난다는 보장은 없다**.
  얻는 것은 실행 간격의 균등화(2시간 → 20분)와, 새로 들어온 PENDING 이 최대 20분 안에 착수되는 지연 감소다. 총처리량은 엔진 처리 속도가 정한다.
- 반대 효과: 실행마다 고정 비용(저장소 정비 세션, presweep, 사후 점검 3종)이 반복되어 이슈당 오버헤드가 늘 수 있다. 이 고정 비용은 별도로 측정하지 못했다.

### 기아(starvation) 점검 — 제안만, 구현하지 않음
- 큐 정렬은 `STALE_IN_PROGRESS → PENDING → READY → REVIEW/TESTED`. 큐가 73~97건이고 한 실행이 7~45건만 처리하는 지금도 REVIEW 는 130건(16.5%) 처리됐다.
  이유는 REVIEW 가 (a) 큐 끝에 있지만 PENDING/READY 가 줄어드는 시점에 닿고 (b) 회차당 상한 5건(`ReviewRecheckMaxPerRun`) 을 갖기 때문이다.
- 소프트 예산 15분이면 실행당 3~4건만 시작하므로 **PENDING/READY 가 계속 들어오는 한 큐 끝의 REVIEW/TESTED 에는 닿지 못할 위험이 크다**(추정).
  REVIEW 는 `Actionflow` 판정과 DONE 전환의 마지막 문이라 장기간 밀리면 DONE 이 지연된다.
- 제안(미구현): 매 N번째 틱(예: 3번째)은 소프트 예산을 무시하거나, 실행당 최소 1건은 REVIEW/TESTED 에 할당한다. 어느 쪽이든 큐 정렬/이슈 처리 로직을 건드리므로 이 변경 범위 밖이다.

### 사후 점검 3종과 다음 틱의 동시 실행 — 코드 확인 결과
- `Complete-Run` 은 **락 파일을 지운 뒤** 사후 점검을 순서대로 실행한다: `Invoke-GissuePrGateSweep` → `Invoke-GissueReviewDoneAudit` → `Invoke-GissuePrAttributionSweep` →
  `Invoke-GissueWorktreeCleanup` → `Invoke-GissueWorktreeDailySweep` → `Send-GissueLogsToConsole` → `Repair-GissueRootOwnedFiles`.
  `pr-gate-sweep.ps1`, `review-done-audit.ps1`, `pr-attribution-sweep.ps1` 에는 락/뮤텍스가 없다(소스에서 `lock`, `Mutex` 검색 결과 없음).
  따라서 다음 틱은 사후 점검이 도는 중에도 락을 잡고 시작할 수 있다(러너 프로세스가 2개 동시에 살아 있게 된다).
- 겹쳐도 확인된 안전 장치: (1) 사후 점검은 상태 기반이고 중복 방지 마커(코멘트 마커와 되돌림 횟수 캡)로 멱등하게 설계되어 있다.
  (2) Phase 0 reaper 는 부모 프로세스가 살아 있는 `claude` 는 죽이지 않는다(`parentAlive` 면 SKIP) — 사후 점검이 띄우는 판정용 claude 는 부모(sweep pwsh)가 살아 있어 안전하다.
  (3) worktree 정리는 최근 활동 idle 가드(`MinIdleMinutes`, `ProtectRecentMinutes 60`)로 방금 만든 worktree 를 건드리지 않는다.
- 확인하지 못한 위험: 사후 점검이 REVIEW 이슈를 READY 로 되돌리는 순간 다음 틱이 같은 이슈의 REVIEW 재검증 세션을 시작하는 경쟁(둘 다 같은 이슈를 만진다)은 코드로 막혀 있지 않다.
  결과는 중복 작업이나 되돌림 코멘트가 엇갈리는 정도로 추정하지만 실제 발생 여부는 측정하지 못했다. 이 경쟁은 소프트 예산 도입 전에도 실행 말미/다음 틱 사이에서 가능했고, 틱 20분 + 짧은 실행에서 빈도가 늘 수 있다.
  사후 점검 3종을 락 안으로 옮기는 것은 효과가 없다고 이슈에서 정리됐으므로(락 점유 시간의 원인이 아님) 하지 않았다.

### 다른 인스턴스에 대한 효과 — 근거와 한계
- 근거(코드): 러너 `run-gissue-claude.ps1` 은 표준 정본이고, `docker/entrypoint.sh` 는 모든 docker 인스턴스에 같은 20분 cron(`7,27,47`)을 만들며, 하드 예산도 모두 105분이다.
  같은 코드·같은 예산·같은 틱이라 **백로그가 큰 인스턴스는 같은 증상(실행이 락을 오래 쥐어 틱이 버려짐)이 나올 가능성이 높다.**
- 한계: 다른 인스턴스의 로그/DB 실행 이력은 이 세션에서 볼 수 없었다. 따라서 "다른 인스턴스에서 실제로 같은 증상이 있었다"는 관측은 없다. 큐가 짧은 인스턴스는 애초에 실행이 짧아 영향이 없고(소프트 예산이 걸리기 전에 큐가 빈다),
  소프트 예산은 큐가 길 때만 동작이 달라진다.
- 기존 인스턴스 영향: Windows 배포(60분 틱)와 docker 이미지 재빌드 전 인스턴스는 `softBudgetMin` 을 쓰지 않는 한 동작이 이전과 같다. docker 는 **이미지 재빌드(또는 csn-projects.json 키 지정)** 후에만 기본값 15 가 적용된다.
