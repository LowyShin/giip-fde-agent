# CSN 70424 Repo Maintenance — 2026-11-04 05:17 (저장소 정비 91차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **91차 저장소 정비 세션** — 2026-11-04 05:17 KST 시작. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- 직전 회차 = **90차**(2026-11-04 04:21 KST) + 90차 후속 3건(PR #356 `KNOW-032` 신규 등록 ·
  PR #357 90차 기록 정정 · PR #358 What's New 반영). 91차 시작 시점 실측 →
  **열린 PR 0건 · 원격 ref `main` 1건뿐 · stash 0건** — 직전 회차 산출물은 모두 머지 완료 상태였다
  (즉 **이번 회차에 계승할 죽은 세션 잔재는 0건**이고, 남은 잔재는 90차가 남긴 워크트리 1건뿐이었다).
- 적용한 규칙 파일(**이 저장소 `.agent/rules/` 에 실재하는 것만 인용** — `KNOW-028` 대응표 기준. 이 저장소 규칙은 56개):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `33_artifact_hygiene.md` · `35_commit_push_per_task.md` · `36_whats_new_maintenance.md` ·
  `41_issue_session_safety_index.md` · `42_completion_by_execution_evidence.md` ·
  `46_cross_csn_write_scope.md` · `47_auto_cleanup_safety_requirements.md` ·
  `48_single_source_safety_predicate.md` · `50_bot_pr_scope_discipline.md` ·
  `54_generic_agent_no_customer_info.md` · `55_information_lookup_order_and_feedback.md` ·
  `56_deliverable_placement_docs_vs_deployable_source.md` · `PROTOCOL_PROGRESS_COMMENT.md`
  (적용 role: `.agent/roles/orchestrator.md`)
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-91-0517` (**신규 생성**) · 기준 `origin/main` = `5f13781`
- 작업 브랜치: `chore/csn70424-maint91-20261104-0517`
- 공유 체크아웃은 **커밋·스테이징 없이** 읽기 전용으로 사용했다(ff-sync 만 수행).

### 위임 판단 — Agent 도구(서브에이전트)를 쓰지 않은 사유

83·84·85·86·87·88·89·90차와 동일. `MODEL_USAGE_SPEC.md` 의 **"MiniMax 메인 → Claude 폴백/QA"** 원칙상
**이 세션이 MiniMax 메인 경로**이며 폴백 사유가 없다(세션 모델 MiniMax-M3 정상 동작). 산출물은
**본 세션의 실측 결과 그 자체**로, 검증된 사실을 새 서브에이전트에 옮겨 되돌려받을 대상이 아니다.
(경로 명시 — 이 파일은 **이 저장소에 없다**: `lowyworkenv\MODEL_USAGE_SPEC.md`)

### 저장소 락 — **91차는 락을 획득하지 않았다**(사유 기록)

- 저장소 정비 지시의 사전 락 요건은 **lowyworkenv 자신인 CSN 이 lowyworkenv 저장소를 커밋·push 할 때**의 것이고,
  **91차는 lowyworkenv 를 커밋·push 하지 않는다**(모든 산출물은 `giip-fde-agent` 워크트리).
- **남의 락을 빼앗지 않는다**(rule 48) — 83·84·85·86·87·88·89·90차와 동일한 판단.
- read-only 조회는 이 PC 의 정본 스크립트가 lowyworkenv 에만 있어(저장소 밖) lowyworkenv 공유 체크아웃 cwd 에서 실행했다
  (`scripts/gissue/tkb.js` · `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1` · `scripts/gissue/get-issue.sh`).
  **쓰기는 하지 않았다.**

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → `[]` · `git ls-remote --heads origin` → `refs/heads/main` **1건뿐** · nested 관리 대상 저장소 0건(`.gemini/extensions/bkit` 는 외부 원본 서브모듈 `popup-studio-ai/bkit-claude-code`) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → 실패 체크 보유 PR 0건 · green 은 별도 확인: `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 10` → **10건 전부 success**(최신 `41709589799` = `5f13781` = PR #358 머지 후 run) |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 2건** | `git stash list` → 0건(공유 체크아웃 · `maint-91-0517` · `maint-62-2331` · `maint-90c-0515` 4곳 모두) · `maint-90c-0515` **정본 도구로 회수**(Removed 1건) · `maint-62-2331` **보류**(정본 도구 `MANUAL-REVIEW`) |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 0건 · 24시간 창 2건(4411·4434)** | 아래 §[H] — 90차 기록을 신뢰하지 않고 **직접 명령으로 전건 재확인** → **전건 일치** → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act 4건** — ① 공유 체크아웃 `main` ff-sync(`84e3f67` → `5f13781`) ② 90차 후속 회차가 남긴 워크트리
`maint-90c-0515` **정본 도구로 회수** ③ **rule 54 식별자 치환**(이 저장소 밖 프로젝트의 CSN 기재 7건 + 본 기록 1건)
④ 91차 기록 + What's New 항목 작성.

---

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트(충돌 해소 3번) 대상이 없었다.
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).
- **원격 ref 확인(`KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다)**:
  `git ls-remote --heads origin` → **`refs/heads/main` 1건뿐** → PR 없이 원격에 갇힌 브랜치 **0건**.
- nested 관리 대상 저장소 **0건** — `find <repo> -maxdepth 5 -name .git` 결과 `.git`(자기 자신)과
  `.gemini/extensions/bkit/.git` 2건이며, 후자는 **외부 원본 서브모듈**(`git submodule status` → `a10e87ac… .gemini/extensions/bkit`)이라
  이 저장소의 PR 관리 대상이 아니다. 서브모듈 쪽 `git stash list` 도 **0건**임을 확인했다.

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이므로):
  `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 10` →
  `41709589799`(`5f13781`) · `41708701788`(`84e3f67`) · `41706492385`(`1f9a7a3`) · `41705243320`(`0352d4b`) ·
  `41640171537`(`5cb482f`) · `41603388010`(`8acb49d`) · `41586628373`(`f1a7300`) · `41577694547`(`0f8ece6`) ·
  `41559830794`(`834b2f6`) · `41556266463`(`ec4dbcd`) → **10건 전부 success**.
- **로컬 게이트도 실행했다**(CI green 외에 "워크트리 green ≠ main green" 배제):
  `scripts/gissue/run-repo-gates.ps1` (91차 워크트리, 기준 `5f13781`) → **exit 0** ·
  `ps1 28건 / mjs 5건 / 링크스캔 1 / 실패 0건` · 마크다운 572개 · 전체 링크 1,164건 · 상대링크 782건 ·
  스캐폴딩(예외) 21건 · **실제 결함 0건**.

## [F] orphan stash / 워크트리 잔재

- `git stash list` → **0건**(공유 체크아웃 · `maint-91-0517` · `maint-62-2331` · `maint-90c-0515` 4곳 확인).
  `auto-unblock ` stash 0건 → **매칭·회수 대상 stash 없음**.
- 워크트리 실측(`git worktree list`):
  | 경로 | 상태 | 91차 조치 |
  |---|---|---|
  | `D:\temp\worktrees\giip-fde-agent\maint-90c-0515` | 브랜치 `chore/csn70424-maint90c-20261104-0515` · working tree clean · 커밋 `b2f149a` | **회수** — PR #358 MERGED(`5f13781`) 확인 후 정본 도구로 회수 |
  | `D:\temp\worktrees\giip-fde-agent\maint-62-2331` | 브랜치 `chore/csn70424-maint64-20261102-0250` · 미커밋 `docs/HISTORY.md`·`docs/WHATS_NEW.md` | **보류** — 정본 도구 `MANUAL-REVIEW`(머지 PR 없음) · `KNOW-023` · rule 47·48 |
  | `D:\temp\worktrees\giip-fde-agent\maint-91-0517` | 91차 작업 워크트리(신규) | 본 세션이 커밋·PR·머지 후 회수 |
  | 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` | `main`(`5f13781`로 ff-sync) · `git status --short` **clean** | 읽기 전용으로만 사용 |

### `maint-90c-0515` 회수 — 실행 결과(예정형 아님)

- 선행 확인: `gh pr view 358 --repo LowyShin/giip-fde-agent --json state,mergedAt,mergeCommit` →
  **MERGED** · merge 커밋 `5f13781` · mergedAt `2026-11-03T20:07:11Z` · head 브랜치
  `chore/csn70424-maint90c-20261104-0515` → **머지 PR 존재 확인 후에만 회수**(정본 도구 자동 회수 조건).
- DryRun(2026-11-04 05:16:00~05:16:18 KST, **공유 체크아웃 cwd**):
  `cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent" -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-90c-0515" -MinIdleMinutes 0 -DryRun`
  → `Removed` 1건 · `SkippedLocked` 0건 · `ManualReview` 0건 · `Aborted False`.
  (**백슬래시 경로로 줬다** — 슬래시 경로는 조용히 0건이 되는 함정이 있다.)
- 본 실행(2026-11-04 05:16:29~05:16:57 KST, 공유 체크아웃 cwd) → **`Removed` 1건** ·
  `SkippedLocked` 0건 · `ManualReview` 0건 · `Aborted False`.
- 회수 후 실측: `git worktree list` → 공유 체크아웃 + `maint-62-2331` **2건** ·
  `git branch -a` → `main` · `origin/main` · `chore/csn70424-maint64-20261102-0250` **뿐**
  (회수된 워크트리의 로컬 브랜치도 도구가 함께 정리했다) ·
  `git ls-remote --heads origin` → **`refs/heads/main` 1건뿐** · `git stash list` → 0건.

### `maint-62-2331` 보류 근거

- 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태를 그대로 둔다 — **정본 판정을 우회하지 않는다**
  (rule 47 · 48 · `KNOW-023`). 사람이 확인 후 수동 제거가 필요하다.
- 91차 실측(읽기 전용): working tree 에 미커밋 ` M docs/HISTORY.md` · ` M docs/WHATS_NEW.md` 가 남아 있고
  `git stash list` 는 0건 · HEAD = `b10cf06`(PR #340 머지 커밋). **내용은 한 글자도 건드리지 않았다.**

## [H] 최근 코멘트 논리 재검증 — 2시간 창 0건 · 24시간 창 2건 · **전건 일치 → 정정 0건**

- 조회: `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **0건**(빈 배열) ·
  `-HoursBack 24 -Json` → **2건**(4411 · 4434).
  90차가 본 2건과 동일 — **창 건수는 매 회차 실측할 것**(고정값으로 쓰지 않는다).
- **조회 산출물 파일은 회차마다 고유 파일명**으로 받았다: `D:\temp\h70424\h2_91.txt` · `h24_91.txt`
  (85차가 84차 잔여 파일을 오인한 함정 재발 방지).
- **자기 코멘트 제외**: 91차는 **이슈 쓰기 0건**이므로 자기 코멘트도 없다.
- 코멘트 목록은 `scripts/gissue/lib/comment-api.js` 의 `listComments()` 로 직접 조회했다
  (`get-issue.sh` 조회 모드는 코멘트 목록을 반환하지 않는다 — 실측으로 확인).

### 4411 (DONE) — 85차 정정 note · 사실 주장 **전건 일치**

| 85차 note 의 주장 | 91차 재확인 결과 |
|---|---|
| tKB `KNOW-049`(lowyworkenv 측) = kbSn **6835** · `regDt 2026-11-02T08:20:46.89` · `modDt 2026-11-02T10:40:25.383` | `tkb.js list --csn <csn> --search "KNOW-049" --json` → **kbSn 6835** · `regDt 2026-11-02T08:20:46.89` · `modDt 2026-11-02T10:40:25.383` · `refType KNOWLEDGE` ✓ |
| tKB `KNOW-021`(이 저장소) = kbSn **6805** · `regDt 2026-11-01T17:54:56.217` | `tkb.js list --csn 70424 --search "KNOW-021" --json` → **6805** · `regDt 2026-11-01T17:54:56.217` ✓ |
| `GIIP_GissueLiveness_Hourly` 태스크 Ready·Enabled·매시 실행 | `Get-ScheduledTask` + `Get-ScheduledTaskInfo` → State **Ready** · `Settings.Enabled` **True** · LastRun **2026-11-04 04:37:37** / LastTaskResult **0** / NextRun **05:37:37** ✓ (85차 기록 시점 이후 정상 재실행 중) |
| `scripts/gissue/logs/gissue_liveness_state.json` 미존재 | `Test-Path` → **False** ✓ |
| 정본 PR 340 · 이식 PR 1062 머지 | PR **340** MERGED(`b10cf068`, 2026-11-01T16:38:47Z) · PR **1062** MERGED(`0e0e726`, 2026-11-01T16:42:16Z) ✓ |
| 85차 note 가 이 이슈의 **마지막 코멘트**(`loadedRole=.agent/roles/orchestrator.md`) | 코멘트 **10건** · 마지막 `gicSn 37610` / `regdate 2026-11-03T10:54:51Z`(= 19:54:51 KST) / `author ai.dp01.gissue-scheduler` / `loadedRole .agent/roles/orchestrator.md` ✓ |
| 84차는 정정 note 를 **0건** 등록(직전 코멘트는 `gicSn 37241` · 2026-11-02T12:18:49Z) | 코멘트 시각열 → 84차 세션(2026-11-03 18:32 KST) 시점 등록분 **0건** ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 DONE 유지(전이 없음)**.

### 4434 (READY) — 79차 번호 충돌 정정 note · 사실 주장 **전건 일치**

| 79차 note 의 주장 | 91차 재확인 결과 |
|---|---|
| 저장소 `KNOW-028` 점유 1건 | `ls .agent/k_layer/notes/` → `KNOW-028_rule_citations_must_resolve_in_this_repo.md` **1건** ✓ |
| tKB `KNOW-028` = kbSn **6870**, `regDt 2026-11-03T03:00:29.21` | **6870** · `regDt 2026-11-03T03:00:29.21` ✓ |
| 저장소 `KNOW-029` 0건 | **0건** ✓ |
| tKB `KNOW-029` = `[]` | **`[]`** ✓ |
| `Get-Module -ListAvailable SqlServer` → 22.3.0 | `SqlServer 22.3.0` ✓ |
| 정본 `FindOpenChildren` 포트 = API 경로 | **정본(giip-fde-agent)** `scripts/gissue/run-gissue-claude.ps1:3758-3762` → `node $ListIssuesScript --csn … --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED,NEEDS_DECISION' --json` ✓ |
| 로그 `2026-11-02 19:52:17 … steps=cause-comment,find-children-failed,…` | `scripts/gissue/logs/gissue_csn47.log:137486` → **그대로 존재** ✓ |
| 로그 `[OVERTIME][WARN] find-children: execSQLFile 조회 실패(exit=0)` | 같은 파일 `137487` 행 → **그대로 존재** ✓ |
| 정본에 호스트 상수 파일 없음 → 기본 Shadow 유지 | `scripts/gissue/lib/overtime-split.ps1:48` `else { 'Shadow' }` / `:52` `default { return 'Shadow' }` / `scripts/gissue/gissue-audit-lib.ps1:655`·`:664` `default { return 'Shadow' }` ✓ |
| `scripts/gissue/tests/test-overtime-findchildren-port.ps1` 아직 없음 | **없음** ✓ (본문 기재와 일치) |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 READY 유지(전이 없음)**.

- 부가 확인 — 79차 note 의 "이 이슈에는 **코멘트가 0건**이라(lastCommentContent = null)" 는 **작성 당시 상태**에 대한
  자가 서술이다(본 note 등록으로 현재는 1건 — 91차 실측 `listComments()` → 코멘트 **1건** ·
  `gicSn 37467` · `regdate 2026-11-03T04:07:29Z`(= 13:07:29 KST) · `loadedRole .agent/roles/orchestrator.md`).
  [H] 대상이 되는 "현재 성립하지 않는 주장"이 아니므로 정정하지 않는다(85·90차와 동일 판단).

## 별도 act 1 — 공유 체크아웃 `main` ff-sync

- 91차 시작 시점 공유 체크아웃 `main` = `84e3f67` · `origin/main` = `5f13781` 로 **1커밋 뒤처져 있었다**.
  `git fetch origin --prune` 후 `git merge --ff-only origin/main` → **fast-forward 완료**(`84e3f67..5f13781`,
  `docs/WHATS_NEW.md` 1 insertion). 91차 작업 워크트리는 이 갱신된 `origin/main`(`5f13781`)에서 새로 만들었다.
- `git fetch --prune` 결과 **원격에서 사라진 추적 브랜치 ref 4건**이 정리되었다
  (`origin/chore/csn70424-maint86…`·`maint90…`·`maint90b…`·`maint90c…`) — 모두 머지 완료된 브랜치의 잔여
  로컬 원격추적 ref 였다. **실제 원격 ref 은 `main` 1건뿐**(`git ls-remote --heads origin` 실측).

## 별도 act 2 — 90차 후속 회차가 남긴 워크트리 `maint-90c-0515` 회수

- 90차 본체(PR #355·#356·#357·#358)는 모두 머지되었으나 **그 마지막 회차의 워크트리가 회수되지 않은 채
  방치**돼 있었다(PR #358 머지 후 세션이 종료). 91차가 회수했다 — 상세는 위 §[F] 의 실행 결과 참조.
- **원인 구조**: 커밋·push·PR·머지까지 갔어도 **회수(정리) 단계가 별도 세션에 밀리는** 패턴.
  90차 기록의 "남은 사항 2"(회수는 예정형 서술)는 실제로 **이 세션에서 실행되지 않았다** —
  91차가 실행 완료로 마감했다. (`KNOW-013` — 기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다)

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 은 **2026-11-04 로 유지**(90차가 이미 갱신 — 변경 없음).
- `## 2026-11-04` 섹션에 **91차 항목 1건**을 90차 항목 뒤에 추가한다(섹션 내 항목은 회차 순 오름차순 배열 유지).
- **이관 0건** — 현재 섹션은 `2026-11-04` · `2026-11-03` · `2026-11-02` · `2026-10-31` · `2026-10-30` 이고,
  7일 창(2026-10-28 이후) 밖 섹션은 이미 `docs/HISTORY.md` 로 이관되어 있다(88차 수행).
- **줄바꿈 주의** — 이 저장소는 `core.autocrlf=true` 라 **인덱스·origin/main 은 전부 LF** 이다
  (90차 후속 정정 블록 참조: "이 저장소의 파일은 CRLF 이다" 는 워크트리 뷰의 착시이며 커밋 단위 관리 대상이 아니다).
  새 항목은 **바이트 단위 CRLF** 로 삽입했다(워크트리 파일과 같은 형식 유지).
  새 `work_history` 파일은 **LF** 로 저장한다(레포에 저장되는 형태가 LF).

## 별도 act 4 — rule 54 식별자 치환 (이 저장소 밖 프로젝트의 CSN 기재 7건)

- **발견 경위** — 91차가 rule 54 자가 점검을 **커밋 직전**에 실행하면서 발견했다:
  `git diff --cached -U0 | grep -E '^\+' | grep -nE '\b[0-9]{2,5}\b' | grep -iE 'csn'` 가
  "저장소 정비 지시의 사전 락 요건은 **lowyworkenv 자신인 CSN(숫자)**" 문장을 계속 잡아냈다.
  이 저장소는 **PUBLIC 범용 에이전트**(rule 54)이고, 규칙의 예외는 **"이 저장소 자신의 전용 CSN"** 뿐이다.
  다른 저장소(lowyworkenv) 의 CSN 숫자는 **금지 항목**("CSN 번호(고객/프로젝트 식별 번호)")에 해당한다.
- **기계 게이트가 못 잡는 이유** — rule 54 의 제시된 검사식(`git grep -nE '\b7[0-9]{4}\b'`)은
  **5자리 CSN 형태만** 잡으므로 2자리 CSN 는 통과한다. 즉 **문서 검수(사람/AI 가독 단계)에서만 걸리는 건**이다.
- **확장 실측** — `git grep -lE 'CSN\([0-9]{1,4}\)' -- '*.md'` →
  **과거 정비 기록 7건**(2026-11-03 18:32 · 19:30 · 22:30 · 23:30 · 2026-11-04 00:34 · 02:20 · 04:21)
  + 91차 본 기록 1건 = **8건**. 84차부터 반복 도입된 동일 문구였다.
- **조치** — rule 54 §"위반을 발견하면"의 명시적 허용("과거 기록을 고쳐 쓰는 것이 부담되면 **식별 부분만
  `<csn>` 등으로 치환한다**")에 따라, **8건 전부에서 숫자만 제거**했다:
  `CSN(숫자)` → `CSN`. 문장의 사실 서술("lowyworkenv 자신인 CSN 이 lowyworkenv 저장소를 커밋·push 할 때")은
  **그대로 유지**되므로 어떤 기술적 주장도 바뀌지 않는다. **과거 기록의 다른 본문은 한 글자도 건드리지 않았다.**
  - 바이트 단위 치환(파이썬 `open(f,'rb')` + `replace`)으로 수행해 **줄바꿈·인코딩이 바뀌지 않았음을 확인**했다
    (각 파일 CRLF/LF 비율 불변: 218/218 · 228/228 · 236/236 · 251/251 · 311/311 · 262/262 · 273/273 · 0/227).
  - `> 정정(...)` 블록을 붙이지 않은 이유 — 이번 건은 **기술적 주장의 오류가 아니라 rule 54 가 허용한 식별자 치환**이고,
    과거 기록의 본문 서술 자체는 여전히 참이기 때문이다(rule 73 의 "정정 블록" 대상이 아님).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
  (다른 저장소 측 tKB 를 조회한 부분은 `<csn>` 플레이스홀더로 적었고, 다른 저장소 CSN 기재는 위 act 4 에서 제거했다.)
- **재실측(치환 후)** — `git grep -nE 'CSN\([0-9]{1,4}\)' -- '*.md'` → **0건** ·
  `git grep -nE '\b7[0-9]{4}\b' -- <변경 파일>` → **이 저장소 자신의 CSN(70424) 외 0건**.
- 다른 저장소(lowyworkenv · giipprj) 언급은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.
- 이슈 번호(4411·4434)와 PR 번호(340·1062·358)는 추적성 표시용이며 고객 식별자가 아니다.
- `MODEL_USAGE_SPEC.md` 인용은 **경로를 명시**했다(88차가 지적한 경로 파손 인용의 정정).

## 결과 저장처 / 소비처

- 수정/신규 파일(91차 커밋 대상):
  `.agent/work_history/20261104_0517_csn70424_repo-maintenance.md`(신규 — 본 파일) ·
  `docs/WHATS_NEW.md`(수정 — 91차 항목 1건 추가) ·
  `.agent/work_history/20261104_0421_csn70424_repo-maintenance.md` · `20261104_0220_…` · `20261104_0034_…` ·
  `20261103_2330_…` · `20261103_2230_…` · `20261103_1930_…` · `20261103_1832_…`
  (모두 수정 — **rule 54 식별자 치환 1줄씩만**, 다른 본문 무변경 · 아래 act 4 참조)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다) ·
  `KNOW-028`(이 저장소 규칙 인용은 이 저장소에 있는 파일명만) ·
  `KNOW-030`(스테이징만 하고 죽은 세션의 산출물은 PR·원격ref·stash 검사에서 전부 안 보인다) ·
  `KNOW-032`(러너 105분 자기 마감이 커밋 단계를 자른다)

## 남은 사항 (후속)

1. **이 회차 PR 번호·머지 커밋·CI run id 는 이 기록의 작성 시점 미확정** — 적지 않는다.
   확정값은 **PR 코멘트**와 **다음 회차 기록**이 실측해 인계한다(기록에 예정형 서술을 남기지 않는다 — `KNOW-013`).
2. **`maint-91-0517` 워크트리 회수** — 이 PR 이 머지된 뒤 정본 도구
   (`cleanup-worktrees.ps1 -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-91-0517" -MinIdleMinutes 0`)로 회수하고,
   **실행 결과(Removed 건수 · 원격 ref 삭제 여부)는 PR 코멘트에 실측값으로 남긴다.**
   (회수는 **공유 체크아웃 cwd** 에서 실행한다 — 회수 대상 워크트리 안에서 실행하면 보호 경로로 처리되어 조용히 0건이 된다.)
3. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   사람이 확인 후 수동 제거가 필요하다(`KNOW-023` · rule 47 · rule 48).
4. **`giip 4434` 의 노트 번호** — `KNOW-029` 로 등록해야 한다(79차가 issue note 로 명시).
   4434 는 READY 상태이며 91차도 **상태를 바꾸지 않았다**. **이슈 처리 세션의 몫**이다.
   (91차 실측: 저장소 `KNOW-029` 0건 · tKB `[]` — 슬롯이 비어 있음이 재확인됨.)
5. **tKB `KNOW-030`(kbSn 6874) 의 `refType` 이 `GENERAL`** — tKB 갱신 경로가 `refType` 을 받지 않아
   다른 KNOW 노트와(`KNOWLEDGE`) 다르다. 잔여 사항이며 tKB 스키마/SP 개정이 필요한 사안이다.
6. **러너 105분 자기 마감 ↔ 커밋 단계 순서** — 90차가 실측한 근본원인(러너가 저장소 정비 단계에서
   처리 중인 이슈가 없으면 마감시각을 즉시 앞당겨 커밋 전에 자른다)은 lowyworkenv 러너 측 사안이다.
   사람이 lowyworkenv 쪽에서 산출물 push 를 앞당기는 중간 산출 규칙을 검토할 사항이다.
