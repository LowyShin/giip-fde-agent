# 매시 이슈 처리 스케줄러 표준 스펙 — 정비 상세

> 본문(정본): [hourly-issue-scheduler.md](./hourly-issue-scheduler.md) 에서 분리된 절
> 모음이다 (giip #6329 — 500라인 초과 분리). 절 번호는 본문과 동일하게 유지한다.
> 담는 절: §5-1-1 저장소 정비 세션 · §10 orphan `.worktrees` 자가정리 · §13-2 원본과의 파일 격차

### 5-1-1) 저장소 정비 세션 — 사전 체크 게이트 + gair 경유 (giip #5671)

> **⛔ 정비 전면 중지 (2026-11-21 운영 지시)** — REPO-MAINT는 현재 **중지 상태**다. 판정 정본
> `scripts/gissue/lib/repomaint-gate.ps1`의 마스터 스위치 `Test-RepoMaintEnabled`가 `$false`인
> 동안은 대상 수·게이트 환경변수와 무관하게 어떤 CSN에서도 정비 세션을 기동하지 않으며, 기록
> 파일·PR도 만들지 않는다. 계기는 수정 0건 회차의 기록 PR이 반복 생성돼 토큰만 소모된 것이다.
> **재개는 그 함수의 반환값을 `$true`로 바꾸는 PR로만 한다** — 환경변수나 호스트 로컬 설정으로는
> 켤 수 없다. 아래 게이트·gair 규칙은 재개 시점에 다시 적용되는 규칙으로 보존한다.

CSN 마다 매시간 기동하는 **저장소 정비(REPO-MAINT) 세션**은 아래 두 가지 규칙을 추가로 따른다.

#### (1) 스크립트 사전 체크 게이트 — 정비 대상 0건이면 세션 미기동 (토큰 0)

정비 세션은 [0]/[E]/[F]/[H] 네 단계를 한 세션에서 처리한다. 대상이 **0건**인 회차에도 세션이
기동되면 토큰을 쓰고 work_history 기록(PR 포함)까지 열린다. 그래서 **세션을 띄우기 전에** 스크립트가
대상 수를 세고, 합계 0이면 세션 자체를 띄우지 않는다.

| 단계 | 대상 판정 | 실제 조회 |
|---|---|---|
| [0] | 열린 PR 중 `mergeable == 'CONFLICTING'` | `gh pr list --repo <owner/repo> --state open --json number,mergeable,statusCheckRollup` |
| [E] | 열린 PR 중 `statusCheckRollup` 에 `FAILURE` 체크가 있음 | 위와 동일(`conclusion`·`state` 두 필드를 모두 본다) |
| [F] | `git stash list` 중 메시지가 `auto-unblock ` 로 시작하는 항목 | 대상 저장소마다 `git stash list` |
| [H] | 최근 2시간 내 코멘트가 있는 이슈 | `list-issues.js --csn <csn> --status ... --hours-back 2 --json` |

- 판정 정본은 `scripts/gissue/lib/repomaint-gate.ps1` — `Get-RepoMaintTargetCounts`(단계별 수 + 합계)와
  `Test-RepoMaintNeeded`(합계 1건 이상인지) 두 **순수 함수**이며, 실제 조회는 **포트(스크립트블록) 주입**
  으로 받는다(`lib/capped-wait.ps1` 와 같은 컨벤션). 회귀 테스트는 `tests/test-repomaint-gate.ps1`.
- 합계 0이면 `Start-Job` 블록 전체를 건너뛰고
  `[REPO-MAINT] CSN <csn> 정비 대상 0건 — 세션 기동 생략(스크립트 사전 체크)` 한 줄만 남긴다.
  **기록 파일·PR 은 만들지 않는다.**
- 게이트 실행이 예외로 실패하면(gh 실행 불가 등) 그 사실을 출력하고 **종전대로 세션을 기동한다(fail-open)** —
  조회 실패를 "대상 0건"으로 오인해 정비를 놓치는 쪽이 위험하므로, 판정을 못 하면 세션을 띄운다.
- 프롬프트에도 같은 규칙이 들어 있다: 실제로 수정한 파일이 0건이면 work_history 기록 파일을 만들지
  말고 PR도 열지 말고 조용히 종료하라.
- **워크트리 회수는 정비 대상도, 기록의 근거도 아니다**: 머지된 PR 의 워크트리 회수·머지된 브랜치
  삭제 같은 호스트 로컬 정리는 레포 파일을 바꾸지 않으므로 "수정한 파일"에 세지 않는다. 회수는 잡
  종료 후처리 스크립트 단계(`Invoke-GissueWorktreeCleanup`)가 AI 없이 수행하므로, 게이트가 세션을
  생략한 회차에도 회수는 누락되지 않는다. 정비 세션이 직접 회수했더라도 그 사실만으로 기록 파일·PR
  을 만들지 않으며, 회수 과정에서 발견한 미커밋 변경을 레포 파일로 실제로 반영한 경우에만 그
  변경분으로 PR 을 연다. (회수를 근거로 기록 PR 을 만들면 그 PR 의 워크트리를 다음 회차가 회수하며
  같은 기록 PR 이 자기증식하는 루프가 된다.)

#### (2) gair 경유 — 정비 세션 + 일반 이슈 세션(허용 CSN) (giip AI API 라우터, giip #5671)

정비 세션과, 허용 목록에 든 CSN의 **일반 이슈 처리 세션**의 엔진 호출은 **gair**(giip AI API
라우터)를 경유한다. 방식은 slack-bot 채팅 경로(`slack-bot/gair-accounts.js`)와 같다.

- 베이스 URL: `https://giipfaw.azurewebsites.net/api/gair` (`ANTHROPIC_BASE_URL` 교체)
- 인증: **CSN 의 SK 에서 파생한 AK** — `scripts/gissue/get-ak.sh <csn> --json` (AdminGetAK)
- **모델은 고정하지 않는다** — `--model` 을 아예 붙이지 않고 gair 의 JEV 판정·프로파일 매핑에 맡긴다.
- gair 호출 실패·AK 파생 실패 시 **폴백하지 않고 오류로 종료한다** (giip #6229, gair 단일 경로) —
  `[ENGINE] gair 시도 실패…` 로그를 남기고 예외를 표면화하며, 실행 기록(§17-7)에는 `path-gair-failed`
  로 집계된다. gair 경유를 끄는 스위치(`GISSUE_GAIR=0` / `GISSUE_REPO_MAINT_GAIR=0`)를 명시한 경우에만
  종전 **MiniMax → Claude** 경로를 쓴다. AK/SK 는 어떤 로그에도 남기지 않는다.
- **일반 이슈 세션은 허용 CSN만 대상이다**: gair는 호출자 CSN의 `tSystemParameter`(category='gair')를
  읽어 업스트림을 정하므로, gair 설정이 등록되지 않은 CSN이 시도하면 이슈마다 실패 호출만 쌓인다.
  그래서 허용 목록으로 게이트한다(환경변수 표 참조). AK는 CSN 실행당 1회만 파생해 이슈 루프
  전체에서 재사용한다. ForceClaude 이슈(REVIEW/TESTED 재검증)는 종전대로 gair를 건너뛰고
  claude로 직행한다.

#### 환경변수

| 환경변수 | 기본값 | 효과 |
|---|---|---|
| `GISSUE_REPO_MAINT_GATE` | 켜짐(`0` 이 아니면) | `0` 이면 사전 체크 게이트를 끈다(종전 동작 — 매 회차 세션 기동) |
| `GISSUE_REPO_MAINT_GAIR` | 켜짐(`0` 이 아니면) | `0` 이면 정비 세션의 gair 경유를 끄고 기존 MiniMax → Claude 경로를 쓴다 |
| `GISSUE_GAIR_CSNS` | gair 설정이 등록된 플랫폼 CSN | 일반 이슈 세션의 gair 경유 허용 CSN 목록(쉼표 구분). gair 설정을 등록한 CSN만 넣는다. 목록에 `*` 가 포함되면 **전 CSN 허용**이다(플랫폼 측 gair 허용 등록이 전 CSN으로 확장된 호스트에서 사용). 목록 해석의 정본은 `scripts/gissue/lib/gair-gate.ps1` 이고, 게이트 판정(`gissue-audit-lib.ps1` 의 `Invoke-GissueJudge`)도 같은 목록으로 gair 경유를 정한다 — 허용 CSN의 판정은 gair 경유(모델 미고정), AK 파생 실패 시 직접 폴백 없이 판정 실패로 표면화한다. 같은 원칙이 러너 안의 판정 2곳(CJK-QA 2차 판정, 엔진 무처리(NO_ACTION) 판정 — 둘 다 세션 계획을 넘겨받아 따른다)과 페이지 피드백 판정(`page-feedback-analyze.ps1`, CSN 고정이라 같은 판정 계획을 재사용)에도 적용된다 |
| `GISSUE_GAIR` | 켜짐(`0` 이 아니면) | `0` 이면 일반 이슈 세션의 gair 경유를 전부 끈다 |

## 10) orphan `.worktrees` 자가정리 — 왜 존재하는가 (giip #1540/#1544/#1547)

`run-gissue-claude.ps1`은 각 CSN 처리마다(Phase 1 busy-wait 대기보다 먼저) `Remove-GissueOrphanWorktrees`
함수로 담당 프로젝트(+nested repo) 안의 `.worktrees/` 디렉터리를 스캔해, **git worktree로 정식
등록되지 않은(orphan) + 이슈 상태가 DONE이거나 이슈 자체가 없는 + 24시간 이상 방치된** 디렉터리만
안전하게 삭제한다. 존재 이유:

- **giip #1540** (2026-08-26): lowyworkenv의 동일 러너에서, 이미 DONE 처리된 이슈의 `.worktrees/`
  잔해 안에 orphan `node_modules`(pnpm 구조, 매우 깊은 경로)가 남아 있어 Windows git이
  "Filename too long"을 반복 발생시켰다. 이 러너의 `[F]` orphan-stash 자동언블록(`stash -u`) 로직이
  이 잔해를 건드릴 때마다 실패해, 그 실패가 **20,236회** 반복되며 CSN47 이슈 큐 전체가 완전히
  마비됐다(어떤 이슈도 처리되지 못함).
- **giip #1544**: 위 인시던트의 재발 방지로, lowyworkenv 쪽 러너 자신에게 이 결정적(비-LLM)
  PowerShell 정리 로직을 추가했다(`Get-GissueIsnStatusMap`/`Remove-GissueOrphanWorktrees`, DB
  직접 조회 경로 사용).
- **giip #1547** (이 변경): 이 레포(`giip-fde-agent`)의 `run-gissue-claude.ps1`도 동일한
  `[F]`/`stash -u`/AUTO-UNBLOCK 구조를 그대로 갖고 있어 같은 취약점에 노출될 수 있으므로, 원본
  레포 자신에도 동일 취지의 방어 로직을 이식했다. 이 레포는 DB 직접 접근이 없어(§4 참고), isn 상태
  조회를 giipfaw API(`scripts/gissue/lib/get-isn-status.js`, 신규)로 대체한 것이 lowyworkenv 판과의
  유일한 구조적 차이다.
- **giip 4518** (2026-11-04, 원본 giip #2406): 같은 `stash -u` 자동언블록 경로에서 **Windows
  예약장치명**(`nul`·`CON`·`COM1` 등) untracked 파일이 있으면 위 "Filename too long"과 **원인이 다른
  또 하나의 실패 모드**가 나온다. `git stash push -u`가 stash는 정상 생성하면서(= tracked 변경 보존
  성공) untracked 정리만 `warning: failed to remove nul: Permission denied` / `Ignoring path nul`로
  실패해 **exit=1**로 끝나는 **부분 성공**이다(경로길이 초과 계열은 stash 자체가 실패하지만, 예약장치명은
  보존은 성공하고 워킹트리만 리셋되지 않는다). exit 코드만 보고 실패로 판정하면 base 복귀를 포기해 매
  `:07` 무한 반복한다(원본 로그 302건). 처리 책임: **구현=lowyworkenv**(스케줄러 정본 코드가 사는
  저장소 — `scripts/gissue/stash-unblock.ps1` 의 예약장치명 부분성공 판정 + 연속 실패 **이슈 코멘트**
  에스컬레이션), **이식=giip-fde-agent**(이 저장소 — `scripts/gissue/lib/gissue-stash-unblock-lib.ps1`
  한 벌로 두 자동언블록 호출부(`[AUTO-UNBLOCK]`/`[AUTO-UNBLOCK-FORCED]`)가 판정·tracked 전용 폴백을
  **공유**해 복붙 격차를 막는다). 이식판은 DB 직접 접근이 없어(§4) 연속 실패 에스컬레이션이 이슈
  코멘트가 아니라 `gissue_ALERT.log` + `Step-GissueFailCount` 카운터 기반인 점이 lowyworkenv 판과의
  차이다. 예약장치명 파일은 **지우거나 옮기지 않고** 워킹트리에 그대로 둔 채(일반 삭제도 실패하는
  장치명이라 파괴적 작업 금지) 수동 제거 명령(`cmd /c del \\.\<이름>`)을 로그로 안내한다. 회귀 테스트:
  `scripts/gissue/tests/test-stash-unblock-lib.ps1`.

READY/PENDING/IN_PROGRESS/REVIEW/TESTED 상태의 이슈에 연결된 워크트리, 그리고 `git worktree list`에
정식 등록된 워크트리는 이 로직이 **절대** 건드리지 않는다 — 사람이 지금 그 워크트리에서 작업 중일 수
있기 때문이다. 삭제 자체도 Windows `MAX_PATH`(260자) 제한을 우회하기 위해 robocopy 빈 폴더 `/MIR`
미러 트릭을 쓴다(`Remove-Item` 단독으로는 깊은 pnpm 경로 등에서 실패할 수 있다 — 이번 인시던트 수동
조치에서 실제로 쓴 방법). 실행 로그에서 `[ORPHAN-CLEANUP]` 접두어로 필터링하면 무엇을 왜 지웠는지(또는
왜 보류했는지) 바로 확인할 수 있다.

- **시간 예산 (giip #6331)**: 이 정리는 Phase 1에서 CSN 잡 기동 전에 동기로 수행되므로 전체에 120초 상한을 둔다. 레포 루트 직계 스캔은 남은 예산만큼만 기다리고(초과 시 중단), 삭제 루프도 예산 초과 시 멈춘다. 남은 후보는 다음 회차로 이월되며, 정리가 이슈 처리를 막지 않는다.

## 13-2) 원본(`lowyworkenv`)과의 파일 격차 — 무엇이 이식되지 않았는가 (giip #2645 작업 D)

**이 문서는 다른 PC 가 clone 해 쓰는 계약서입니다. 알려진 결손을 숨기지 않습니다.**

2026-09-17 신규 clone(`origin/main` `2df478a`) 실측: `scripts/gissue` 최상위 파일이 원본 54개 대
이 레포 43개입니다. 차이 14건 + gitignore 대상 `csn-projects.json` 1건 = 15건이며, 전부 아래 표에
있습니다. 반대로 이 레포에만 있는 파일도 3건 있습니다(`csn-projects.json.example` /
`list-issues.js` / `stale-issue-scan-lib.ps1` — 이식 과정에서 신설).

### 13-2-1) 이식하지 않는 것이 맞는 것 (후속 불요)

| 파일 | 판단 근거(파일을 열어 확인한 내용) |
| :-- | :-- |
| `README.md` / `SPEC.md` | 이 스케줄러 표준의 **정본은 이 문서**입니다(§7). 원본의 두 문서를 복제하면 정본이 둘이 됩니다. |
| `SCHEDULER_CONTROL.md` | "이 PC(Lowy-DP01) 운영 인스턴스"의 제어법이라 배포 대상마다 무의미합니다. §14 가 원본 경로를 링크로만 가리킵니다. |
| `SLACKBOT_AUTO_RESTART.md` | 같은 내용이 이 레포의 `./aux-hourly-schedulers.md`(slackbot 재시작 스케줄러 절)로 재작성돼 있습니다. |
| `csn-projects.json` | 시크릿성 로컬 설정(CSN·절대경로). `csn-projects.json.example` 로 대체되며 배포마다 직접 채웁니다(§13 2단계). |
| `_scan_tp.cjs` (17줄) | 하드코딩된 isn 5개(`1966,1968,1971,1972,2040`)를 `/tmp/g70424/c_*.json` 에서 읽는 1회용 조사 스크립트. 재사용 경로 없음. |
| `extract_sk<csn>.ps1` (2줄) | 특정 csn 의 SK 1건을 콘솔에 덤프하는 2줄짜리 일회성 스크립트. 시크릿을 표준출력으로 내보내므로 이식 대상이 아닙니다(`.agent/rules/49_no_plaintext_credential_persist.md`). |
| `verify-1665-oneshot.ps1` (186줄) | 헤더에 "giip #1671 단발성(1회) 검증"이라 명시돼 있고, 실행 끝에 자기 태스크를 `Unregister-ScheduledTask` 로 지웁니다. 2026-08-29 14:07 실행 1회로 역할이 끝났습니다. |
| `review-done-audit.ps1.bak_1570_20260828094004` | 파일명 그대로 2026-08-28 편집 백업본. |
| `test-cd-worktree-hook.ps1` (190줄) | `.claude/hooks/check-ps1-parse.sh`(원본 PC 의 훅 배치)를 대상으로 하는 회귀 테스트라, 그 훅이 없는 배포에서는 대상 자체가 없습니다. |
| `register-interactive-session.ps1` (330줄) | Claude Code **대화형 세션**을 `tSchedulerAgent` 에 등록하는 훅 연동 스크립트(giip #1645). `:07` 스케줄러 동작과 무관하고, 원본 PC 의 훅·`CLAUDE_CODE_BRIDGE_SESSION_ID` 환경에 의존합니다. |
| `register-issue.ps1` (37줄) | 같은 디렉터리 `register-issue.js` 를 부르는 **PowerShell 래퍼**일 뿐입니다. `register-issue.js` 는 이식돼 있고, 이 레포의 러너·감사 스크립트는 전부 `.js` 를 직접 호출합니다(`run-gissue-claude.ps1` 109행, `review-done-audit.ps1` 101행). 기능 결손 없음. |

### 13-2-2) DB 직접접속 전용 — 이식 대상 아님 (이 레포는 API 경로만 쓴다)

이 레포의 배포 대상에는 `giipdb/mgmt/dbconfig.json`(DB 자격증명)이 없습니다. §13-1-3 의 "쓰기 경로가
API 하나뿐" 이라는 설계와 같은 이유로, 아래 3건은 의도적으로 제외했습니다.

| 파일 | 하는 일 | 이식하지 않은 결과 |
| :-- | :-- | :-- |
| `giipdb-locate.ps1` | nested `giipdb/mgmt`(= `execSQLFile.ps1` + `dbconfig.json`) 위치 탐색 헬퍼 | DB 적재를 안 하므로 호출부가 없습니다. **이 레포의 어떤 스크립트도 이 파일을 참조하지 않습니다**(전수 grep 확인). |
| `sync-csn-mapping-from-db.ps1` | `dbo.tGissueCsnMapping` 을 정본으로 보고 `csn-projects.json` 을 DB 에서 덮어씀(giip #2363) | 이 레포는 `csn-projects.json` **파일 자체가 정본**입니다(§13 2단계). 원본과 정본 방향이 다르다는 점만 알고 있으면 됩니다. 참조부 없음. |
| `sync-ai-actor-credentials.ps1` | AI 행위자 계정의 AK 를 giipdb → `slack-bot/.secrets/giip-accounts.json` 으로 직접 이동(giip #2613) | AK 를 **수동으로** 채워야 합니다. 절차서 `scripts/gissue/AI_ACTOR_ACCOUNTS.md` §3-3 이 이미 이 항목을 `미이식` 로 표기하고 있습니다. |

⚠️ **`scripts/gissue/ai-actors.json` 의 `_comment` 가 이 미이식 파일을 가리킵니다** —
"`sync-ai-actor-credentials.ps1` 이 DB 에서 그리로 직접 옮긴다"고 쓰여 있으나 **그 파일은 이 레포에
없습니다.** 신규 PC 에서는 그 문장을 따라갈 수 없으므로, AK 는 `AI_ACTOR_ACCOUNTS.md` 의 절차대로
직접 기입하십시오. (문구 교정은 이 문서 작업의 범위 밖이라 후속 이슈 소관입니다 — 로직·설정 파일을
건드리지 않고 사실만 여기 남깁니다.)

### 13-2-3) ⚠️ 알려진 결손 — 고쳐야 하지만 아직 안 고쳐진 것

**아래 2건은 "이식됐지만 원본과 동등하지 않은" 상태입니다. 후속 이슈 소관입니다.**

| 항목 | 실측 내용 | 신규 PC 에 미치는 영향 |
| :-- | :-- | :-- |
| `scripts/gissue/pr-gate-sweep.ps1` 이 **구버전** | 이 레포 19,753 바이트 vs 원본 43,108 바이트. 원본에만 있는 함수: `Format-PrEvidence` / `Invoke-GateEscalate` / `Set-IssueNeedsDecision` | **게이트 에스컬레이션 / NEEDS_DECISION 전이 경로가 없습니다.** 게이트 실패가 사람에게 올라가지 않고 그대로 머무를 수 있습니다. |
| `scripts/gissue/get-issue.sh` 에 **`--role` 플래그 없음** | 원본은 `--role` 로 구조화 필드 `loadedRole` 을 채웁니다(giip #1324/#1452). 이 레포의 `get-issue.sh` / `post-comment.js` / `comment-api.js` 에는 그 경로 자체가 없습니다(`role` 문자열 출현 0회 vs 원본 8회). | 이 레포가 남기는 코멘트는 **`loadedRole=null`** 이 됩니다. 어느 역할로 처리했는지가 이슈에 기록되지 않습니다. |

### 13-2-4) 해소된 결손 (giip #2645 — 이력)

PR #86 시점에 이 절이 "알려진 결손"으로 적어 둔 것 중 아래 2건은 **고쳐졌습니다.** 같은 증상을
다시 만났을 때 "원래 그런 것"으로 오인하지 않도록 이력을 남깁니다.

| 항목 | 그때 상태 | 지금 |
| :-- | :-- | :-- |
| `bash` 를 PATH 에서 못 찾음 | 문서가 "시스템 PATH 에 `Git\bin` 을 추가하라"고 안내했고, 러너의 두 상태전이 호출부는 맨 `bash` 를 불러 **이 PC 에서도 항상 실패**하면서 `Out-Null` + 빈 `catch {}` 로 흔적조차 남기지 않았습니다(실패 시 이슈가 IN_PROGRESS 에 박힘) | `Resolve-GissueBashExe` 공용 함수가 PATH → `git.exe` 역산 → 알려진 설치 위치 순으로 해석합니다. PATH 조치 불필요. 상태 전이는 종료코드를 확인해 `[STATUS-OK]` / `[STATUS-FAIL]` 로 **반드시** 기록합니다. `verify-runner.mjs` 의 `spawnSync('bash')` 도 같은 해석을 씁니다 |
| `test-verify-gate-exit-contract.ps1` 가 clone 직후 FAIL | `-LiveCsn` 기본값이 원본 PC 의 **33** 이라 `PASS=23 FAIL=1` | 기본값 `0` → `csn-projects.json` 의 첫 enabled CSN 자동 선택, 정할 수 없으면 사유를 밝히고 SKIP. 인자 없이 exit 0 |
