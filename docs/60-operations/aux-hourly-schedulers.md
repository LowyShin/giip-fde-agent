# 보조 시간별 스케줄러 — 표준 스펙과 제어법

> 정본입니다. 메인 스케줄러(`:07`, 이슈 처리 본체)는 `./hourly-issue-scheduler.md` 를 보고, 이 문서는
> **그 옆에서 같이 도는 보조 스케줄러 5종**과 **태스크 등록 게이트**를 다룹니다.
> 이식 출처는 `lowyworkenv/scripts/gissue/`(csn 47 운영 인스턴스)이며, 이식 이슈는 giip #2645 입니다.
> 이 문서는 **특정 PC·특정 CSN·특정 절대경로에 의존하지 않습니다** — clone 한 경로에서 그대로 읽습니다.

## 0) 전제 — 실행 엔진은 Windows PowerShell 5.1

이 문서의 모든 예시는 `powershell` (Windows PowerShell 5.1) 입니다. **PowerShell 7(`pwsh`)이 있다고
가정하지 않습니다.** 없는 PC 에서 `pwsh` 로 부르면 `command not found` 로 **아무 일도 하지 않고**
끝나는데, 스케줄러 문맥에서는 그게 "조용한 무동작"이라 실패로 보이지 않습니다(giip #2559 실사고:
그 이유로 14개 CSN 이 한 건도 실행되지 않았습니다).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<스크립트 경로>"
```

## 1) 보조 스케줄러 5종

메인 태스크 외에, 각각 **별도 러너 + 별도 Task Scheduler 항목**으로 분리 등록됩니다.
분리한 이유는 메인 러너(수천 줄 단일 파일)에 기능을 끼워넣지 않기 위해서입니다.

| 기본 태스크 이름 | 주기 | 러너 | 등록기 | 근거 |
|---|---|---|---|---|
| `GIIP_StalePending_Hourly` | 매시 :07 | `scripts/gissue/run-list-stale-pending.ps1` | `register-stale-pending-task.ps1` | giip #2410, 주기 수정 #2480 |
| `GIIP_StaleReview_Hourly` | 매시 :07 | `scripts/gissue/run-list-stale-review.ps1` | `register-stale-review-task.ps1` | giip #2420, 주기 수정 #2480 |
| `GIIP_AuditReviewPrs_Hourly` | 매시 :07 | `scripts/gissue/run-audit-review-prs.ps1` | `register-audit-review-prs-task.ps1` | giip #2395/#2431 |
| `GIIP_GateEscalation_Hourly` | 매시 :07 | `scripts/gissue/run-gate-escalation-recheck.ps1` | `register-gate-escalation-task.ps1` | giip #2428 |
| `GIIP_SlackbotRestart_Hourly` | 매시 :37 | `scripts/gissue/run-slackbot-restart-check.ps1` | `register-slackbot-restart-task.ps1` | giip #2148 |

태스크 이름은 **배포마다 고유해야 합니다**. 한 PC 가 여러 배포를 호스팅하면 등록기의 `-TaskName`
으로 덮어씁니다(예: `-TaskName GIIP_StalePending_Hourly_csn70424`).

### 각각 무엇을 하나

- **StalePending / StaleReview** — 각각 `PENDING` / `REVIEW` 상태로 오래 머문 이슈를 찾습니다.
  조회는 `scripts/gissue/list-issues.js --min-age-minutes` (giipfaw API) 를 씁니다.
  결과는 `scripts/gissue/audit-results/stale-{pending,review}-csn<N>-<stamp>.json` 과
  같은 폴더의 `.log` 에 남습니다(둘 다 gitignore 대상).
  `--min-age-minutes` 가 재는 것은 **그 상태에 들어간 뒤 경과 시간**(상태 전이 코멘트에서 역산)입니다.
  전이 코멘트를 못 찾은 이슈는 방치로 세지 않고 `undetermined`(판정불가)로 따로 셉니다 — 숫자를
  부풀리지도, 놓치지도 않기 위해서입니다. 자세한 근거는 `scripts/gissue/stale-issue-scan-lib.ps1`
  상단 주석에 있습니다.
- **AuditReviewPrs** — "REVIEW 인데 PR 이 0건"인 이슈를 감사합니다(`audit-review-prs.mjs` 호출).
  결과 JSON 을 `audit-results/` 에 보존합니다.
  ⚠ 종료코드 규약: 감사 본체는 **의심 건이 있으면 1** 을 돌려줍니다(정상 동작). 2 이상만 실제 실패입니다.
- **GateEscalation** — 게이트가 누적 3회 되돌려 `*-GATE-HUMAN-REVIEW` 로 종착한 뒤 아무도 읽지 않게 된
  이슈에 `[GATE-RECHECK]` 작업지시서 코멘트를 남기고 상태를 `READY` 로 되돌려, 다음 `:07` 세션이 실제
  판정을 하게 합니다. 대상은 `-TargetStatuses` 화이트리스트(`REVIEW,NEEDS_DECISION`)로만 제한되며,
  `IN_PROGRESS` / `READY` 는 **기본값에도 인자로도 넣을 수 없습니다**(넣으면 시작 즉시 중단) — 1차 구현이
  진행 중인 세션의 이슈를 가로챘던 실사고 때문입니다.
- **SlackbotRestart** — 감시 경로(`-WatchPath`, 기본 `slack-bot`)의 배포 커밋이 바뀌었는데 pm2 프로세스가
  옛 코드로 돌고 있으면, **유휴 판정 3신호를 모두 통과할 때만** `pm2 restart` 합니다.
  유휴가 아니면 보류하고 다음 시간에 재시도합니다(강제 재시작은 하지 않습니다). 상세는 §5.

## 2) 태스크 등록 3중 게이트 (giip #2431 / #2591)

`register-*-task.ps1` 계열은 `Register-ScheduledTask` **직전에**
`scripts/gissue/task-target-guard.ps1` 의 `Assert-ScheduledTaskTarget` 을 호출합니다.
아래 3가지 중 하나라도 실패하면 **등록하지 않고 종료코드 1 로 끝납니다.**

| # | 검사 | 막는 사고 |
|---|---|---|
| 1 | 대상 `.ps1` 의 `Test-Path` | 없는 파일을 가리키는 태스크가 Ready 로 등록됨(#2431 실제 사고 2건) |
| 2 | `check-ps1-parse.ps1` 통과 — 구문(`[PS1-PARSE]`) + BOM(`[PS1-BOM]`) | 파싱 불가 스크립트가 `LastTaskResult=0` 을 돌려주며 조용히 죽음(#2429) / BOM 없는 비ASCII `.ps1` 이 검사만 통과하고 실행에서 죽음(#2591) |
| 3 | 대상 경로가 임시 worktree(`\temp\worktrees\`, `\.claude\worktrees\`) 하위가 **아님** | 등록기를 worktree 안에서 실행해 임시 경로가 태스크에 박힘 → worktree 정리 시 태스크 사망 |

### 왜 게이트 3이 필요한가
등록기는 `$PSScriptRoot` 로 **자기 위치 기준**으로 대상을 잡습니다. 즉 worktree 안에서 등록기를
실행하면 worktree 경로가 그대로 태스크에 기록됩니다. 따라서 **코드 수정은 worktree 에서 하더라도,
태스크 등록/재등록은 반드시 정상 체크아웃에서** 해야 합니다. worktree 안에서 등록이 거부되는 것은
버그가 아니라 설계된 동작입니다.

### `check-ps1-parse.ps1` 호출 형태 (giip #2436 에서 고쳐진 형태 — 전부 실측 검증됨)
```
-File check-ps1-parse.ps1 <파일1> [파일2 ...]        # 위치 인자
-File check-ps1-parse.ps1 -Path <파일1> [파일2 ...]  # 이름 지정
-File check-ps1-parse.ps1 -Staged                    # pre-commit 훅이 쓰는 형태
-File check-ps1-parse.ps1 -All                       # 레포 전체
```
`-RepoRoot <경로>` 와 `-ExcludeDirPattern <정규식>` 은 **이름 지정 전용**입니다(위치 인자로는
바인딩되지 않습니다). 파이프라인 입력은 지원하지 않습니다. `-Staged` / `-All` 에 파일 인자를 섞으면
종료코드 2 로 막습니다. 명시한 파일이 없으면 종료코드 1 로 차단합니다.
`task-target-guard.ps1` 은 `-Path` 를 명시해 호출합니다.

### 판정이 2개인 이유 (`[PS1-PARSE]` / `[PS1-BOM]`, giip #2590/#2591)
`[PS1-PARSE]` 는 오탐을 피하려고 파일을 **항상 UTF-8 로** 읽습니다. 그런데 실행 엔진
(`powershell -File`)은 BOM 없는 파일을 **시스템 ANSI 코드페이지**(이 환경은 cp932)로 읽습니다.
검사기와 실행기의 디코딩이 어긋나므로, 그 차이에서만 나는 실패를 `[PS1-PARSE]` 는 구조적으로 볼 수
없습니다. 실측(2026-09-16): BOM 없는 `.ps1` 6개가 "6개 전부 통과"를 받았는데 `powershell -File` 실행은
파서 에러 7건으로 **한 줄도 실행되지 않았고**, 내용을 한 글자도 바꾸지 않고 BOM 3바이트(`EF BB BF`)만
추가하자 둘 다 정상이 됐습니다.

**그래서 이 레포의 모든 `.ps1` 은 UTF-8 with BOM 으로 저장합니다.** ASCII 전용 파일은 대상이 아닙니다
(cp932 로 읽으나 UTF-8 로 읽으나 같기 때문). UTF-16 LE/BE BOM 도 통과합니다.

## 3) 태스크 주기 게이트 (giip #2480)

`register-*-task.ps1` 계열은 트리거를 만든 뒤 `Register-ScheduledTask` **직전에**
`scripts/gissue/task-cadence-guard.ps1` 의 `Assert-ScheduledTaskCadence` 를 호출합니다.
**태스크 이름이 약속한 주기와 트리거의 실제 반복 설정이 어긋나면 등록하지 않고 종료코드 1** 입니다.

| 이름 패턴 | 요구 조건 |
|---|---|
| `...Hourly` | `Repetition.Interval` 이 정확히 **PT1H**, `Duration` 은 비었거나(무기한) **1일 이상** |
| `...Daily` | `Repetition.Interval` 이 없거나 **1일 이상**(1시간 반복인데 이름이 Daily 면 거짓) |
| 그 외 | 검사 생략(주기를 이름으로 약속하지 않은 태스크) |

### 왜 필요한가
`GIIP_StalePending_Hourly` / `GIIP_StaleReview_Hourly` 는 이름이 `_Hourly` 인데 트리거가
`-Weekly -DaysOfWeek <7일> -At 00:07` 이라 **반복이 아예 없어 하루 1회만** 돌고 있었습니다. 등록은
성공하고 태스크는 Ready, `LastTaskResult=0` 이라 실패로 보이지 않았습니다. 앞선 작업에서 같은 파일을
사람이 직접 읽으면서도 이름과의 불일치를 잡지 못했습니다 — "사람이 보면 안다"에 기대면 재발합니다.

### 정상 트리거 형태 2종 (둘 다 실제로 매시 :07 에 돕니다)
```powershell
# (A) 대부분의 태스크
New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 7 -Second 0) `
    -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)

# (B) GIIP_GateEscalation_Hourly — Daily 트리거로 매일 재무장 + 24시간 동안 매시 반복
$trigger = New-ScheduledTaskTrigger -Daily -At 00:07
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 00:07 `
    -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
```
⚠ `RepetitionDuration` 에 `[TimeSpan]::MaxValue` 를 쓰면 Task Scheduler XML 상한을 넘겨 등록이
HRESULT `0x80041318` 로 거부됩니다(giip #1275). 약 10년(`-Days 3650`)을 씁니다.

회귀 테스트: `scripts/gissue/tests/test-task-cadence-guard.ps1`
(결함 재현 4 + 정상 5 = 9케이스, 실제 스케줄러를 건드리지 않습니다).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-task-cadence-guard.ps1
```

## 4) 설치 / 제어

### 4-1) 선행조건
메인 스케줄러(`./hourly-issue-scheduler.md` §4)와 같습니다 — `csn-projects.json`,
`slack-bot/.secrets/giip-accounts.json`, node, git(bash 포함). **DB 직접접속은 쓰지 않습니다**(§6).

### 4-2) 등록 (멱등 — 다시 실행하면 갱신, 중복 생성 없음)
**정상 체크아웃에서** 실행합니다(worktree 안이면 §2 게이트 3 이 막습니다).

```powershell
# 예: csn 47 을 대상으로 4종 등록
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-pending-task.ps1     -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-review-task.ps1      -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-audit-review-prs-task.ps1  -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gate-escalation-task.ps1   -Csn 47
# pm2 로 슬랙봇을 돌리는 배포만
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-slackbot-restart-task.ps1
```
`-Csn 0`(기본값)이면 러너가 `csn-projects.json` 의 `enabled` CSN 전체를 돕니다.

### 4-3) 해제
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-<...>-task.ps1 -Unregister
```

### 4-4) 상태 확인
```powershell
# 메인 + 보조 5종의 State / Repetition / LastRunTime / NextRunTime 한눈에
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\manage-gissue-scheduler.ps1 -Action Status
```
`manage-gissue-scheduler.ps1` 의 다른 액션(`Request` / `DryRun` / `RunOnce`)은 **메인 태스크 전용**입니다.
보조 태스크는 이 헬퍼가 등록하거나 시작하지 않습니다 — 즉시 1회 실행은 각 러너를 직접 부르거나
`Start-ScheduledTask -TaskName <이름>` 을 씁니다.

### 4-5) 즉시 1회 실행(검증)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-list-stale-pending.ps1    -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-list-stale-review.ps1     -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-audit-review-prs.ps1      -Csn 47
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-gate-escalation-recheck.ps1 -Csn 47 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-slackbot-restart-check.ps1 -DryRun
```

### 4-6) ⚠ 완료 판정 주의 — `LastTaskResult=0` 은 근거가 아니다
`GIIP_StalePending_Hourly` 는 **대상 파일이 아예 없는 상태에서도** 0 을 돌려주고 있었고(#2431),
**반복이 빠져 하루 1회만 도는 상태에서도** 0 이었습니다(#2480). 반드시 아래 셋으로 확인합니다.

```powershell
# 1) 러너 직접 실행 출력
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-list-stale-pending.ps1 -Csn 47
# 2) 실행 로그 tail
Get-Content scripts\gissue\audit-results\stale-pending-csn47.log -Tail 20 -Encoding UTF8
# 3) 실제 반복 주기 원문 (NextRunTime 이 내일로 잡혀 있으면 반복이 빠진 것)
Get-ScheduledTask GIIP_StalePending_Hourly | ForEach-Object { $_.Triggers.Repetition }
schtasks /query /tn GIIP_StalePending_Hourly /xml ONE
```

## 5) `GIIP_SlackbotRestart_Hourly` 상세 (giip #2148)

### 왜 있나
pm2 로 돌고 있는 프로세스는 코드가 main 에 머지·반영돼도 옛 코드를 그대로 유지합니다. 실측으로
"3일 미재시작" 때문에 **이미 고친 버그가 여전히 재현되는 것처럼** 보인 사례가 있었습니다(#2147/#2044/#2117).

### 무엇을 하나 (매시 :37)
1. **배포 커밋 변경 감지** — `git log -1 --format=%H -- <WatchPath>`(로컬 워킹트리) 값과 마커 파일
   `scripts/gissue/logs/slackbot_deployed_head.txt`(= 지금 돌고 있는 프로세스가 올라간 커밋)를
   비교합니다. 같으면 아무것도 하지 않습니다. 마커가 없으면(최초 도입) 현재 커밋을 **기록만** 합니다.
   - 이 스크립트는 `fetch`/`pull`/`checkout` 등 **워킹트리를 바꾸는 git 명령을 절대 실행하지 않습니다**
     (매시 :07 스케줄러와의 공유 체크아웃 경합 방지). origin/main 과의 차이는 정보성 로그로만 남깁니다.
2. **유휴 판정 3신호** — 하나라도 걸리면 재시작하지 않고 로그만 남기고 종료, 다음 시간에 재시도합니다
   (최대 1시간 지연은 설계상 수용값):
   1. **레포 점유**: 워크디렉터리 자신과 바로 아래 nested git 레포 중 하나라도 base 브랜치(main/master)가
      아니면 보류 — "base 가 아님" = "지금 태스크 실행 중" 신호.
   2. **repo-lock**: `.agent/locks/*.lock` 중 살아 있는 것(보유 프로세스 생존 + 120분 미만)이 있으면 보류.
   3. **pm2 로그 staleness**: `~/.pm2/logs/<ProcessName>-out.log` / `-error.log` 가 최근
      `-QuietMinutes`(기본 5분) 이내에 쓰였으면 활동 중으로 보고 보류.
   - pm2 에 그 프로세스가 없거나 status 가 online 이 아니면 손대지 않고 보류합니다
     (신규 기동/비정상 복구는 메인 `:07` 러너의 워치독 소관).
3. **재시작** — 3신호 전부 통과하면 `pm2 restart <ProcessName>` 후 status 를 재확인하고, online 이면
   마커 파일을 현재 커밋으로 갱신합니다. online 이 아니면 마커를 갱신하지 않아 다음 시간에 재시도합니다.
4. **연속 보류 경고** — 보류가 연속 `-HoldWarnThreshold`(기본 6회 ≈ 6시간)를 넘으면 로그에 `[ALERT]` 를
   남깁니다. **강제 재시작은 하지 않습니다**(진행 중 태스크 손실 방지가 우선).

### 파일
| 용도 | 경로 |
|---|---|
| 실행기 | `scripts/gissue/run-slackbot-restart-check.ps1` |
| 등록기 | `scripts/gissue/register-slackbot-restart-task.ps1` |
| 로그 | `scripts/gissue/logs/gissue_slackbot_restart.log` |
| 배포 커밋 마커 | `scripts/gissue/logs/slackbot_deployed_head.txt` |
| 연속 보류 상태 | `scripts/gissue/logs/slackbot_restart_state.json` |

(`scripts/gissue/logs/` 는 gitignore 대상이라 마커·상태 파일은 커밋되지 않습니다.)

### 왜 :37 인가
메인 스케줄러가 :07 에 돌면서 pm2 워치독과 CSN 처리로 레포를 만집니다. 그 실행과 겹치면 유휴 판정이
거의 항상 "점유 중"으로 나오므로 30분 오프셋을 뒀습니다.

### 채택되지 않은 방식 (재논의 방지)
- **git post-merge 훅 즉시 재시작** — 불채택. 진행 중 라이브 태스크/서브에이전트가 강제 종료될 위험.
- **수동 체크리스트** — 불채택. 실제로 일어난 미재시작 오인을 구조적으로 못 막습니다.

## 6) 이 레포판과 원본(lowyworkenv)판의 차이 — 의도된 것

원본은 csn 47 운영 인스턴스이고 곁에 `giipdb/mgmt/*.ps1`(DB 직접접속)이 있습니다. 이 레포에는 없습니다.
`./hourly-issue-scheduler.md` §4 는 **혼용 이식을 금지**합니다 — 존재하지 않는 경로를 참조하면 매 실행이
그 단계에서 조용히 실패하기 때문입니다. 그래서 이식하며 다음을 교체했습니다.

| 원본이 쓰던 것 | 이 레포에서 | 영향 |
|---|---|---|
| `giipdb/mgmt/execSQLFile.ps1` + `dbconfig.json` 로 `tAuditStalePendingResult` INSERT | `list-issues.js`(API) 조회 + `audit-results/*.json` 보존 | 대시보드 배지용 DB 적재는 이 배포에서 하지 않음 |
| `giipdb/mgmt/list-stale-review.ps1` (이 PC 전용 절대경로 폴백 포함) | 형제 러너와 동일 구조 + `stale-issue-scan-lib.ps1` | 두 러너가 갈라져 한쪽만 고쳐지던 문제 해소 |
| `giipdb/mgmt/addIssueComment.ps1` / `updateIssueStatus.ps1` | `get-issue.sh --comment-file` / `--status` | CSN 교차오염 방지 게이트가 그대로 적용됨 |
| `tAuditReviewPrsResult` INSERT | JSON 보존까지 | 위와 동일 |
| `$env:GIIP_ACTOR` (AI 행위자 고정) | 설정하지 않음 | 이 레포에 그 값을 읽는 주체 테이블이 없음 |
| `slack-bot` / `lowyworkenv-repo.lock` 하드코딩 | `-ProcessName` / `-WatchPath` / `.agent/locks/*.lock` | 다른 배포에서도 동작 |

각 파일 상단 주석에 **무엇을 왜 바꿨는지, 원본이 무엇을 어디에 저장했고 누가 소비했는지**를 남겨
두었습니다(코드를 지우는 대신 근거를 남기는 규칙).

> 한글/이모지가 든 코멘트 본문은 반드시 UTF-8 파일로 저장한 뒤 `--comment-file` 로 넘깁니다 —
> 커맨드라인 리터럴로 넘기면 headless 실행 체인에서 시스템 기본 코드페이지로 mojibake 가 납니다(giip #1030).

## 7) 연결 문서

- 메인 스케줄러 표준 스펙: `./hourly-issue-scheduler.md`
- 이슈 처리 세션 안전 규칙 색인: `../../.agent/rules/41_issue_session_safety_index.md`
- 진행/상태전이 코멘트 프로토콜: `../../.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`
- 완료 판정은 실행 결과로만: `../../.agent/rules/42_completion_by_execution_evidence.md`
