# gissue 스케줄러 실행 이력 — admin/catquest/schedulers 에 표시되는 방식 (giip #3563, 정정: giip #3575)

> 이 문서는 PR #107 의 분석을 **정정**한다. #107 은 "PowerShell 이 bash 의 `sar_run_start` 를 못 불러서 이력이 없다"고 보고 bash 래퍼를 추가했지만, 그것은 원인이 아니었다.

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
