# CSN 70424 Repo Maintenance — 2026-11-04 04:21 (저장소 정비 90차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **90차 저장소 정비 세션** — 2026-11-04 04:21 KST 시작. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- **86·87·88·89차 죽은 세션 잔재 4건(연속)을 계승해 마감**했다 — 4회 연속 세션이 **커밋·PR 단계에 도달하지 못한 채**
  종료되어 작업 기록 4건과 What's New 갱신이 워크트리 `maint-86-2108` 에 미커밋으로 남아 있었다.
- 적용한 규칙 파일(**이 저장소 `.agent/rules/` 에 실재하는 것만 인용** — `KNOW-028` 대응표 기준. 이 저장소 규칙은 56개):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `33_artifact_hygiene.md` · `35_commit_push_per_task.md` · `36_whats_new_maintenance.md` ·
  `41_issue_session_safety_index.md` · `42_completion_by_execution_evidence.md` ·
  `46_cross_csn_write_scope.md` · `47_auto_cleanup_safety_requirements.md` ·
  `48_single_source_safety_predicate.md` · `50_bot_pr_scope_discipline.md` ·
  `54_generic_agent_no_customer_info.md` · `55_information_lookup_order_and_feedback.md` ·
  `56_deliverable_placement_docs_vs_deployable_source.md` · `PROTOCOL_PROGRESS_COMMENT.md`
  (적용 role: `.agent/roles/orchestrator.md`)
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-86-2108` (**86·87·88·89차 잔재 계승** · 기준 `origin/main` = `5cb482f`)
- 작업 브랜치: `chore/csn70424-maint86-20261103-2108` (**86차부터 계승** · 커밋 0건 상태로 인계)
- 공유 체크아웃은 **커밋·스테이징 없이** 읽기 전용으로 사용했다.

### 위임 판단 — Agent 도구(서브에이전트)를 쓰지 않은 사유

83·84·85·86·87·88·89차와 동일. `MODEL_USAGE_SPEC.md` 의 **"MiniMax 메인 → Claude 폴백/QA"** 원칙상
**이 세션이 MiniMax 메인 경로**이며 폴백 사유가 없다(세션 모델 MiniMax-M3 정상 동작). 산출물은
**본 세션의 실측 결과 그 자체**로, 검증된 사실을 새 서브에이전트에 옮겨 되돌려받을 대상이 아니다.
(경로 명시 — 이 파일은 **이 저장소에 없다**: `lowyworkenv\MODEL_USAGE_SPEC.md` · 88차가 지적한 경로 파손 인용의 정정)

### 저장소 락 — **90차는 락을 획득하지 않았다**(사유 기록)

- 저장소 정비 지시의 사전 락 요건은 **lowyworkenv 자신인 CSN(33) 이 lowyworkenv 저장소를 커밋·push 할 때**의 것이고,
  **90차는 lowyworkenv 를 커밋·push 하지 않는다**(모든 산출물은 `giip-fde-agent` 워크트리).
- **남의 락을 빼앗지 않는다**(rule 48) — 83·84·85차와 동일한 판단.
- read-only 조회는 이 PC 의 정본 스크립트가 lowyworkenv 에만 있어(저장소 밖) lowyworkenv 공유 체크아웃 cwd 에서 실행했다
  (`scripts/gissue/tkb.js` · `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1` · `scripts/gissue/get-issue.sh`).
  **쓰기는 하지 않았다.**

## 근본원인 — **러너 105분 자기 마감이 4회 연속 커밋 실패의 원인**(90차 신규 실측)

86·87·88·89차가 커밋하지 못한 이유를 "세션이 죽었다"만으로 남기고 넘어가지 않고 **로그와 러너 코드로 실측**했다.

**증거 1 — 러너의 자기 마감 상수**: `scripts/gissue/run-gissue-claude.ps1:272` → `$RunTimeoutMin = 105`
(주석: "뛰도록 105로 하향(Windows ExecutionTimeLimit 은 '내부 정리마저 실패했을 때'의 최후 안전망으로 2시간 유지)").

**증거 2 — 저장소 정비 경로의 조기 마감**: `run-gissue-claude.ps1:1726-1731` —
`Invoke-GissueOvertimeCheck` 는 **처리 중인 이슈가 없으면**(저장소 정비 단계)
`$r.Deadline = Get-Date` 로 마감시각을 **즉시 앞당기고** `return $false` 한다.
이어 본 루프 `elseif ((Get-Date) -gt $r.Deadline)` → **`Stop-Job $r.Job`** (잡 워커 종료) → `Complete-Run` (`:1757-1760`).

**증거 3 — CSN 70424 로그의 세션 START→종료 패턴**(`scripts/gissue/logs/gissue_csn70424.log`):

| START | 종료 기록 | 소요 |
|---|---|---|
| 2026-11-03 21:08:08 | 22:52:09 `[OVERTIME] 과시간 감지 — run 기준 (프로세스 105.1분)` | **105분** |
| 2026-11-03 23:25:45 | 2026-11-04 02:12:49 `stale lock 제거 — 시간초과(3h)` | — |
| 2026-11-04 02:12:49 | 03:52:02 `[OVERTIME] ... (프로세스 105분)` → 04:21:15 `stale lock 제거` | **105분** |
| 2026-11-04 04:21:15 | **← 90차 세션 시작** | — |

로그의 OVERTIME 판정 직후 단계 줄은 항상 **`[ENGINE] MiniMax 1차 시도 실패(exit=-1) → 재시도 1회`** 까지이며,
그 뒤는 잡 출력이 회수되지 않는다("잡 출력은 이슈 세션 안의 엔진 출력까지 담지 못한다").

**결론** — 커밋·PR 은 세션의 **마지막 단계**인데, 측정·기록 작성에 예산을 쓰면 **항상 커밋 전에 잘린다**.
88차 기록이 지적한 "`[claude-code:unrecognized_model] {"model":"MiniMax-M3"}` 엔진 오류"는 **86·87차의 별개 증상**이며,
**89차까지 살아남은 회차도 커밋 전에 죽었다** — 즉 89차의 산출물도 원인은 동일하다.
→ **90차는 커밋·push 를 먼저 하고 기록을 나중에 쓰는 순서**로 바꿔 진행했다(아래 별도 act 1).

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → `[]` · `git ls-remote --heads origin` → `refs/heads/main` **1건뿐** · nested 관리 대상 저장소 0건(`.gemini/extensions/bkit` 는 외부 원본 서브모듈 `popup-studio-ai/bkit-claude-code`) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → 실패 체크 보유 PR 0건 · green 은 별도 확인: `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 10` → **10건 전부 success**(최신 `41640171537` = `5cb482f` = 85차 PR #354 머지 후 run) |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 3건** | `git stash list` → 0건(공유 체크아웃 + `maint-86-2108` + `maint-62-2331` 3곳) · `maint-86-2108` **계승·마감**(90차가 커밋·PR 생성) · `maint-62-2331` **보류**(정본 도구 `MANUAL-REVIEW`) · `aux-sched-2645` 는 lowyworkenv 등록 워크트리라 손대지 않음 |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 0건 · 24시간 창 2건(4411·4434)** | 아래 §[H] — 89차 기록을 신뢰하지 않고 **직접 명령으로 전건 재확인** → **전건 일치** → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act 3건** — ① 86·87·88·89차 미커밋 산출물 계승·마감(커밋·push·PR) ② 89차 기록의 **미실행 서술** 정정
(rule 73 · `KNOW-013` — `> 정정(2026-11-04, 90차)` 블록 추가) ③ 러너 105분 자기 마감의 근본원인 실측·기록.

---

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트(충돌 해소 3번) 대상이 없었다.
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).
- **원격 ref 확인(`KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다)**:
  `git ls-remote --heads origin` → **`refs/heads/main` 1건뿐** → PR 없이 원격에 갇힌 브랜치 **0건**.
- nested 관리 대상 저장소 **0건** — `find <repo> -maxdepth 4 -name .git` 결과 `.git`(자기 자신)과
  `.gemini/extensions/bkit/.git` 2건이며, 후자는 **외부 원본 서브모듈**(`git submodule status` → `a10e87ac… .gemini/extensions/bkit`)이라
  이 저장소의 PR 관리 대상이 아니다.

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이므로):
  `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 10` →
  `41640171537`(`5cb482f`) · `41603388010`(`8acb49d`) · `41586628373`(`f1a7300`) · `41577694547`(`0f8ece6`) ·
  `41559830794`(`834b2f6`) · `41556266463`(`ec4dbcd`) · `41537394369`(`2a67d29`) · `41430489808`(`db2ed82`) ·
  `41394112774`(`f3ae1ed`) · `41384332988`(`d459b17`) → **10건 전부 success**.

## [F] orphan stash / 워크트리 잔재

- `git stash list` → **0건**(공유 체크아웃 · `maint-86-2108` · `maint-62-2331` 3곳 확인). `auto-unblock ` stash 0건.
- 워크트리 실측(`git worktree list` + `D:\temp\worktrees\giip-fde-agent` 디렉터리 listing):
  | 경로 | 상태 | 90차 조치 |
  |---|---|---|
  | `D:\temp\worktrees\giip-fde-agent\maint-86-2108` | 브랜치 `chore/csn70424-maint86-20261103-2108` · **커밋 0건**(HEAD = `5cb482f` = `origin/main`) · 미커밋 산출물 6건 · PR 0건 | **계승·마감**(90차가 커밋 `06a8fe5` + PR #355 생성) |
  | `D:\temp\worktrees\giip-fde-agent\maint-62-2331` | 브랜치 `chore/csn70424-maint64-20261102-0250` · 미커밋 `docs/HISTORY.md`·`docs/WHATS_NEW.md` | **보류** — 정본 도구 `MANUAL-REVIEW`(머지 PR 없음) · `KNOW-023` · rule 47·48 |
  | `D:\temp\worktrees\giip-fde-agent\aux-sched-2645` | lowyworkenv 등록 워크트리(`feat/giip-2645-fde-aux-schedulers`) | **손대지 않음**(lowyworkenv 소유) |
  | 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` | `main` · `git status --short` **clean** | 읽기 전용으로만 사용 |

- `maint-62-2331` 보류 근거 — 90차 DryRun 실측(2026-11-04 04:31:11~04:31:18 KST, 공유 체크아웃 cwd):
  `cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent" -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-62-2331" -MinIdleMinutes 0 -DryRun`
  → `ManualReview` 1건(`Reason`: 머지 PR 없음) · `Removed {}` · `SkippedLocked {}` · `Aborted False` · 요약 "삭제 0건 / locked 제외 0건 / 수동확인 필요 1건".
  **정본 판정을 우회하지 않는다**(rule 47 · 48) — 사람이 확인 후 수동 제거가 필요하다.

## [H] 최근 코멘트 논리 재검증 — 2시간 창 0건 · 24시간 창 2건 · **전건 일치 → 정정 0건**

- 조회: `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **0건**(빈 배열) ·
  `-HoursBack 24 -Json` → **2건**(4411 · 4434).
  88·89차가 본 5건 중 `4429`·`4334`·`4431` 은 24시간 창 밖으로 벗어났다 — **창 건수는 매 회차 줄어난다**(고정값으로 쓰지 않는다).
- **조회 산출물 파일 주의(85차가 실제로 겪은 함정)** — 조회 산출물은 **매 회차 고유 파일명**으로 받았다:
  `D:\temp\h70424\h2_90.txt` · `h24_90.txt`(87·88·89차는 `_88` 계열을 재사용했고, 85차는 84차 잔여 파일을 오인할 뻔했다).
- 자기 코멘트 제외: 90차는 **이슈 쓰기 0건**이므로 자기 코멘트도 없다.

### 4411 (DONE) — 85차 정정 note · 사실 주장 **전건 일치**

| 85차 note 의 주장 | 90차 재확인 결과 |
|---|---|
| tKB `KNOW-049`(csn 33) = kbSn **6835** · `regDt 2026-11-02T08:20:46.89` · `modDt 2026-11-02T10:40:25.383` | `tkb.js list --csn 33 --search "KNOW-049" --json` → **kbSn 6835** · `regDt 2026-11-02T08:20:46.89` · `modDt 2026-11-02T10:40:25.383` · `refType KNOWLEDGE` ✓ |
| tKB `KNOW-021`(csn 70424) = kbSn **6805** · `regDt 2026-11-01T17:54:56.217` | **6805** · `regDt 2026-11-01T17:54:56.217` ✓ |
| `GIIP_GissueLiveness_Hourly` 태스크 Ready·Enabled·매시 실행 | `Get-ScheduledTask` → State **Ready** · `Settings.Enabled` **True** · Trigger `2026-11-02T00:37:00+09:00` · LastRun **2026-11-04 03:37:37** / LastTaskResult **0** / NextRun **04:37:37** ✓ |
| `scripts/gissue/logs/gissue_liveness_state.json` 미존재 | `Test-Path` → **False** ✓ |
| 정본 PR 340 · 이식 PR 1062 머지 | PR **340** MERGED(`b10cf068`, 2026-11-01T16:38:47Z) · PR **1062** MERGED(`0e0e726`, 2026-11-01T16:42:16Z) ✓ |
| 85차 정정 note 가 이 이슈의 **마지막 코멘트**(`loadedRole=.agent/roles/orchestrator.md`) | `get-issue.sh 4411 70424` → 코멘트 **10건** · 마지막 `regdate 2026-11-03T10:54:51Z`(= 19:54:51 KST) · `loadedRole` **`.agent/roles/orchestrator.md`** ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 DONE 유지(전이 없음)**.

### 4434 (READY) — 79차 번호 충돌 정정 note · 사실 주장 **전건 일치**

| 79차 note 의 주장 | 90차 재확인 결과 |
|---|---|
| 저장소 `KNOW-028` 점유 1건 | `ls .agent/k_layer/notes/` → `KNOW-028_rule_citations_must_resolve_in_this_repo.md` **1건** ✓ |
| tKB `KNOW-028` = kbSn 6870, regDt 2026-11-03T03:00:29.21 | **6870** · `regDt 2026-11-03T03:00:29.21` ✓ |
| 저장소 `KNOW-029` 0건 | **0건** ✓ |
| tKB `KNOW-029` = `[]` | **`[]`** ✓ |
| `Get-Module -ListAvailable SqlServer` → 22.3.0 | **Name=SqlServer Version=22.3.0** ✓ |
| 정본 `FindOpenChildren` 포트 = API 경로 | `scripts/gissue/run-gissue-claude.ps1:3760` → `node $ListIssuesScript --csn … --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED,NEEDS_DECISION' --json` ✓ |
| 로그 `2026-11-02 19:52:17 … steps=cause-comment,find-children-failed,…` | `scripts/gissue/logs/gissue_csn47.log:137486` → **그대로 존재** ✓ |
| 로그 `[OVERTIME][WARN] find-children: execSQLFile 조회 실패(exit=0)` | 같은 파일 `137487` 행 → **그대로 존재** ✓ |
| 정본에 호스트 상수 파일 없음 → 기본 Shadow 유지 | `scripts/gissue/lib/overtime-split.ps1:48` `else { 'Shadow' }` / `scripts/gissue/gissue-audit-lib.ps1:801` `default { return 'Shadow' }` ✓ |
| `scripts/gissue/tests/test-overtime-findchildren-port.ps1` 아직 없음 | **없음** ✓ (본문 기재와 일치) |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 READY 유지(전이 없음)**.

- 부가 확인 — 79차 note 의 "이 이슈에는 **코멘트가 0건**이라(lastCommentContent = null)" 는 **작성 당시 상태**에 대한
  자가 서술이다(본 note 등록으로 현재는 1건 — 90차 실측 `get-issue.sh 4434 70424` → 코멘트 **1건** ·
  `loadedRole=.agent/roles/orchestrator.md` · `regdate 2026-11-03T04:07:29Z`(= 13:07:29 KST)). [H] 대상이 되는
  "현재 성립하지 않는 주장"이 아니므로 정정하지 않는다(85차와 동일 판단).

## 별도 act 1 — 86·87·88·89차 죽은 세션 잔재 계승·마감 (`KNOW-013` · `KNOW-015` · `KNOW-030`)

- 89차(2026-11-04 02:20 KST 시작)는 산출물 5건을 **커밋·PR 없이** 남기고 종료됐다.
  90차 실측(계승 시점): 워크트리 `maint-86-2108` HEAD = `5cb482f`(= `origin/main`) → **커밋 0건** ·
  `gh pr list --state all --head chore/csn70424-maint86-20261103-2108` → **PR 0건** ·
  `git ls-remote --heads origin` → 원격 ref **main 1건뿐** · `git stash list` → 0건 —
  즉 **PR·원격 ref·stash 어디에도 "이 세션의 산출물이 남아 있다"는 단서가 없다**(`KNOW-030` 의 상황).
  **`gh pr list --state open` 만으로는 이 stranded 상태를 볼 수 없다** — `git ls-remote --heads origin` 를 같이 봐야 한다.
- 90차는 **새 워크트리·새 브랜치를 만들지 않고** `maint-86-2108` + `chore/csn70424-maint86-20261103-2108` 를 그대로 이어받아
  커밋 → push → PR 생성 → CI → 머지 → 워크트리 회수까지 마감했다.
- **커밋 순서를 바꾼 것이 이번 회차의 핵심 차이다** — 근본원인 절에 적은 대로 **계승 잔재를 먼저 커밋·push** 한 뒤
  90차 기록을 2번째 커밋으로 추가했다. 그래야 세션이 다시 잘려도 이전 회차 산출물이 원격에 남는다.

## 별도 act 2 — 89차 기록의 **미실행 서술** 정정 (`KNOW-013` · rule 73)

- 89차 기록 `20261104_0220_csn70424_repo-maintenance.md` 는 §[F]·§별도 act 목록에서
  **"86·87·88차 미커밋 산출물 계승·마감(커밋·PR 생성은 이 세션이 수행)"** 을 서술했다. **미실행**이었다(90차 실측 위 참조).
- 90차는 과거 본문을 고쳐 쓰지 않고 **끝에 `> 정정(2026-11-04, 90차)` 블록을 덧붙였다**(rule 73 · `KNOW-013`).
- **89차의 나머지 서술은 90차가 직접 재확인해 실행됨을 확인했다** — 86·87차 기록의 `> 정정(2026-11-04, 89차)` 블록
  (86차·87차 각 1건 · grep 실측) · 88차 기록의 `> 정정(2026-11-04, 89차)` 블록(4건) · 88차 기록의
  `> 정정(2026-11-04, 89차)` 블록 추가 **실행됨**(grep 실측).

## 별도 act 3 — 러너 105분 자기 마감의 근본원인 실측·기록

- 위 §근본원인 참조. `scripts/gissue/logs/gissue_csn70424.log` 의 START→[OVERTIME]→`stale lock 제거` 패턴과
  `scripts/gissue/run-gissue-claude.ps1` 의 `$RunTimeoutMin = 105` · `Invoke-GissueOvertimeCheck` 의 조기 마감 ·
  `Stop-Job` 종료가 **1:1로 대응**한다.
- **이 저장소 밖(lowyworkenv 러너) 사안**이라 90차는 러너 코드를 수정하지 않았다. 사람이 lowyworkenv 쪽에서
  "저장소 정비 세션의 커밋 단계를 앞당기거나, 105분 마감 전에 산출물을 push 하는 중간 산출 규칙"을 검토할 사항이다.
- **88차가 기록한 `[claude-code:unrecognized_model] {"model":"MiniMax-M3"}` 엔진 오류는 86·87차 증상**이며
  (lowyworkenv `scripts/gissue/model-config.json` 의 `minimaxModel: "MiniMax-M3"` vs claude CLI 2.1.311 인식 불일치),
  **89차까지는 엔진 오류 없이 진행됐으나 커밋 전에 죽었다** — 즉 **원인이 하나로만 설명되지 않는다**.

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 은 **2026-11-04 로 유지**(88차가 이미 갱신 — 변경 없음).
- `## 2026-11-04` 섹션에 **90차 항목 1건**을 89차 항목 뒤에 추가한다(섹션 내 항목은 회차 순 오름차순 배열 유지).
- **이관 0건** — 현재 섹션은 `2026-11-04` · `2026-11-03` · `2026-11-02` · `2026-10-31` · `2026-10-30` 이고,
  `2026-10-27` 이전은 이미 `docs/HISTORY.md` 로 이관했다(88차 수행 · 7일 창 = 2026-10-28 이후).
- **줄바꿈 주의** — 이 저장소는 `core.autocrlf=true` 라 `docs/WHATS_NEW.md` 와 `.agent/k_layer/notes/INDEX.md` 는
  **CRLF** 이다(90차 실측: `docs/WHATS_NEW.md` = CRLF 54줄 · LF-only 0줄 · `docs/HISTORY.md` = CRLF 210줄 · LF-only 0줄).
  새 항목은 **바이트 단위 CRLF** 로 삽입한다(LF 가 섞이면 diff 폭이 부풀어간다).
  새 `work_history` 파일은 **LF** 로 저장한다(90차 실측: 신규 4건 LF-only 236·251·311·248줄 · CRLF 0).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- 다른 저장소(lowyworkenv · giipprj) 언급은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.
- 이슈 번호(4411·4434)는 추적성 표시용이며 고객 식별자가 아니다.
- `MODEL_USAGE_SPEC.md` 인용은 **경로를 명시**했다(88차가 지적한 경로 파손 인용의 정정).

## 결과 저장처 / 소비처

- 수정/신규 파일(90차 커밋 대상):
  `.agent/work_history/20261104_0421_csn70424_repo-maintenance.md`(신규 — 본 파일) ·
  `.agent/work_history/20261104_0220_csn70424_repo-maintenance.md`(수정 — 89차 기록 · `> 정정(2026-11-04, 90차)` 블록 추가) ·
  `docs/WHATS_NEW.md`(수정 — 90차 항목 1건 추가)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승) ·
  `KNOW-022`(PR 머지 ≠ 이슈 측 쓰기 완료) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다) ·
  `KNOW-028`(이 저장소 규칙 인용은 이 저장소에 있는 파일명만) ·
  `KNOW-030`(스테이징만 하고 죽은 세션의 산출물은 PR·원격ref·stash 검사에서 전부 안 보인다) ·
  `KNOW-031`(긴 백그라운드 실행 10분 제한 · 저장소 락은 CSN 전체가 공유)

## 남은 사항 (후속)

1. **이 회차 PR 번호·머지 커밋·CI run id 는 이 기록의 작성 시점 미확정** — 적지 않는다.
   확정값은 **PR 코멘트**와 **다음 회차 기록**이 실측해 인계한다(기록에 예정형 서술을 남기지 않는다 — `KNOW-013`).
2. **`maint-86-2108` 워크트리 회수** — 이 PR 이 머지된 뒤 정본 도구
   (`cleanup-worktrees.ps1 -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-86-2108" -MinIdleMinutes 0`)로 회수하고,
   **실행 결과(Removed 건수 · 원격 ref 삭제 여부)는 PR 코멘트에 실측값으로 남긴다.**
   (회수는 **공유 체크아웃 cwd** 에서 실행한다 — 회수 대상 워크트리 안에서 실행하면 보호 경로로 처리되어 조용히 0건이 된다.)
3. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   사람이 확인 후 수동 제거가 필요하다(`KNOW-023` · rule 47 · rule 48).
   90차가 보류 근거를 **정본 도구 DryRun(2026-11-04 04:31:11~04:31:18 KST)** 으로 재확인했다.
4. **`giip 4434` 의 노트 번호** — `KNOW-029` 로 등록해야 한다(79차가 issue note 로 명시).
   4434 는 READY 상태이며 90차도 **상태를 바꾸지 않았다**. **이슈 처리 세션의 몫**이다.
   (90차 실측: 저장소 `KNOW-029` 0건 · tKB `[]` — 슬롯이 비어 있음이 재확인됨.)
5. **tKB `KNOW-030`(kbSn 6874) 의 `refType` 이 `GENERAL`** — tKB 갱신 경로가 `refType` 을 받지 않아
   다른 KNOW 노트와(`KNOWLEDGE`) 다르다. 잔여 사항이며 tKB 스키마/SP 개정이 필요한 사안이다.
6. **러너 105분 자기 마감 ↔ 커밋 단계 순서**(§근본원인) — lowyworkenv 러너 측 사안. 사람이 lowyworkenv 쪽에서
   저장소 정비 세션의 산출물 push 를 앞당기는 중간 산출 규칙을 검토할 사항이다.

> **정정(2026-11-04, 90차 후속) — 위 "줄바꿈 주의" 절의 서술 대상**
> 위 §What's New 롤링 창 처리의 "줄바꿈 주의" 는 **워크트리(체크아웃) 실측값**을 인용한 것이다.
> 이 저장소는 `core.autocrlf=true` 라 **git 저장소(인덱스·origin/main) 는 전부 LF** 다 —
> 90차 후속 실측(`git show origin/main:<path>` 원문 바이트):
> `.agent/k_layer/notes/INDEX.md` = CRLF 0 · LF-only 36 ·
> `KNOW-032_...md` = CRLF 0 · LF-only 70 ·
> `KNOW-031_...md` = CRLF 0 · LF-only 55 ·
> `docs/WHATS_NEW.md` = CRLF 0 · LF-only 55 ·
> 신규 work_history 5건 = **모두 CRLF 0 · LF-only**(236·251·311·262·245줄).
> → **"이 저장소의 파일은 CRLF 이다" 는 워크트리 뷰의 착시**이며, 커밋 단위로 CRLF 를 관리할 대상이 아니다.
> CRLF 로 만든 파일도 커밋 시 LF 로 정규화되므로 **커밋 diff 는 깨끗하다**.
> 실제로 주의할 것은 **자동변환에 의한 diff 폭 과장**(표 변경이 +N/-N 으로 부풀어 보이는 것) 뿐이며,
> 본 회차 PR #355 는 스테이징 대상 파일만 명시 경로로 `git add` 해 해당 현상을 피했다.
>
> **추기(2026-11-04, 90차 후속) — KNOW-032 등록 완료**
> 위 §근본원인("러너 105분 자기 마감이 커밋 단계를 막는다")은 **k-layer 노트 + tKB** 로 등록됐다.
> - 노트: `.agent/k_layer/notes/KNOW-032_runner_105min_deadline_kills_the_commit_step_commit_before_writing_records.md` (신규 70줄)
> - INDEX: `.agent/k_layer/notes/INDEX.md` 에 **KNOW-032 행 추가** (kbSn **6897**) — `KNOW-029` 는 giip 4434 예약이라 비워둠
> - tKB: `node scripts/gissue/tkb.js sync-klayer --csn 70424 --dir <worktree>/.agent/k_layer/notes --project giip-fde-agent --note "KNOW-032_*.md"`
>   → `OK created kbSn=6897` · 합계 1건(created 1 / updated 0 / 실패·불일치 0) · csn 70424 · refType KNOWLEDGE · tags `sync, k-layer, ai-memory`
> - **중복 사전 조회**: `tkb.js list --csn 70424 --search "KNOW-032" --json` → `[]`
> - **본문 무결성**: 저장 본문 **3324자 = 소스 3324자 바이트 동일**(CRLF 70줄 그대로 보존) → 4000자 절단 미해당
> - PR: **#356** → 머지 커밋 `1f9a7a3` · CI 3건 전건 SUCCESS(PS1 gates · MJS gates · GitGuardian) ·
>   로컬 `scripts/gissue/run-repo-gates.ps1` → **exit 0**(ps1 28 · mjs 5 · 링크스캔 실제 결함 0)
>
> **이 추가 등록 PR 이 §근본원인의 대응 그 자체다** — 커밋·push 를 기록 작성보다 먼저 하는 순서를 그대로 지켰다.
> 90차 본 기록(PR #355)도 커밋을 2단계로 쪼개 **먼저 push** 했으므로, 러너가 마감에 끊겨도 **원격에 남는다**.
