# CSN 70424 Repo Maintenance — 2026-11-04 06:30 (저장소 정비 92차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **92차 저장소 정비 세션** — 2026-11-04 06:30 KST. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- 직전 회차 = **91차**(2026-11-04 05:17 KST). 92차 시작 시점 실측 →
  **열린 PR 0건 · 원격 ref `main` 1건뿐 · stash 0건** — 직전 회차 산출물은 모두 머지 완료 상태였고,
  남은 잔재는 91차가 보류 처리한 워크트리 1건(`maint-62-2331`)뿐이었다.
- 적용한 규칙 파일(**이 저장소 `.agent/rules/` 에 실재하는 것만 인용** — `KNOW-028` 대응표 기준):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `33_artifact_hygiene.md` · `35_commit_push_per_task.md` · `36_whats_new_maintenance.md` ·
  `41_issue_session_safety_index.md` · `42_completion_by_execution_evidence.md` ·
  `46_cross_csn_write_scope.md` · `47_auto_cleanup_safety_requirements.md` ·
  `48_single_source_safety_predicate.md` · `50_bot_pr_scope_discipline.md` ·
  `54_generic_agent_no_customer_info.md` · `55_information_lookup_order_and_feedback.md` ·
  `56_deliverable_placement_docs_vs_deployable_source.md` · `PROTOCOL_PROGRESS_COMMENT.md`
  (적용 role: `.agent/roles/orchestrator.md`)
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-92-0630` (**신규 생성**) · 기준 `origin/main` = `6fe4a0b`
- 작업 브랜치: `chore/csn70424-maint92-20261104-0630`
- 공유 체크아웃은 **커밋·스테이징 없이** 읽기 전용으로 사용했다(ff-sync 만 수행).

### 위임 판단 — Agent 도구(서브에이전트)를 쓰지 않은 사유

83~91차와 동일. `MODEL_USAGE_SPEC.md` 의 **"MiniMax 메인 → Claude 폴백/QA"** 원칙상
**이 세션이 MiniMax 메인 경로**이며 폴백 사유가 없다(세션 모델 MiniMax-M3 정상 동작). 산출물은
**본 세션의 실측 결과 그 자체**로, 검증된 사실을 새 서브에이전트에 옮겨 되돌려받을 대상이 아니다.
(경로 명시 — 이 파일은 **이 저장소에 없다**: `lowyworkenv\MODEL_USAGE_SPEC.md`)

### 저장소 락 — **92차는 락을 획득하지 않았다**(사유 기록)

- 저장소 정비 지시의 사전 락 요건은 **lowyworkenv 자신인 CSN 이 lowyworkenv 저장소를 커밋·push 할 때**의 것이고,
  **92차는 lowyworkenv 를 커밋·push 하지 않는다**(모든 산출물은 `giip-fde-agent` 워크트리).
- **남의 락을 빼앗지 않는다**(rule 48) — 83~91차와 동일한 판단.
- read-only 조회는 이 PC 의 정본 스크립트가 lowyworkenv 에만 있어(저장소 밖) lowyworkenv 공유 체크아웃 cwd 에서 실행했다
  (`scripts/gissue/tkb.js` · `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1` · `scripts/gissue/get-issue.sh`).
  **쓰기는 하지 않았다.**

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → `[]` · `git ls-remote --heads origin` → `refs/heads/main` **1건뿐** · nested 관리 대상 저장소 0건(`.gemini/extensions/bkit` 는 외부 원본 서브모듈) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → 실패 체크 보유 PR 0건 · green 은 별도 확인: `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 8` → **8건 전부 success**(최신 `41718856336` = `6fe4a0b`) · 로컬 `run-repo-gates.ps1` **exit 0**(ps1 28 · mjs 5 · 링크스캔 실제 결함 0) |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 2건** | `git stash list` → 0건(공유 체크아웃 · `maint-92-0630` · `maint-62-2331` 3곳 모두) · `maint-62-2331` **보류**(정본 도구 `MANUAL-REVIEW` · `KNOW-023`) · `maint-92-0630` 는 본 세션 작업 워크트리 |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 2건(4219·2855) · 24시간 창 4건(4219·2855·4411·4434)** | 아래 §[H] — 91차 기록을 신뢰하지 않고 **직접 명령으로 전건 재확인** → **전건 일치** → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act 4건** — ① 공유 체크아웃 `main` ff-sync(`60d09f9` → `6fe4a0b`) ② **verify-runner 종료코드 4 vs 1 구분 교훈 신규 등록**
(`KNOW-033` · tKB **kbSn 6914**) ③ `maint-62-2331` 잔재의 **"고유 정보 0건"** 재확정(78·86차와 별개로 **줄 단위** 대조로 재실행)
④ 92차 기록 + `INDEX.md` 행 + What's New 항목.

---

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트 대상이 없었다.
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).
- **원격 ref 확인(`KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다)**:
  `git ls-remote --heads origin` → **`refs/heads/main` 1건뿐** → PR 없이 원격에 갇힌 브랜치 **0건**.
- nested 관리 대상 저장소 **0건** — `.gemini/extensions/bkit` 는 외부 원본 서브모듈(`popup-studio-ai/bkit-claude-code`)이라
  이 저장소의 PR 관리 대상이 아니다. 서브모듈 쪽 `git stash list` 도 **0건**.

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이므로):
  `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 8` →
  `41718856336`(`6fe4a0b`) · `41713971723`(`60d09f9`) · `41709589799`(`5f13781`) · `41708701788`(`84e3f67`) ·
  `41706492385`(`1f9a7a3`) · `41705243320`(`0352d4b`) · `41640171537`(`5cb482f`) · `41603388010`(`8acb49d`)
  → **8건 전부 success**.
- **로컬 게이트도 실행했다**(CI green 외에 "워크트리 green ≠ main green" 배제):
  `scripts/gissue/run-repo-gates.ps1` (92차 워크트리, 기준 `6fe4a0b`) → **exit 0** ·
  `ps1 28건 / mjs 5건 / 링크스캔 1 / 실패 0건** · 마크다운 574개 · 전체 링크 1,167건 · 상대링크 785건 ·
  스캐폴딩(예외) 21건 · **실제 결함 0건**.
- **산출물 추가 후 링크스캔 재실행** — 게이트 실행 시점에는 92차 작업 기록 파일이 아직 생성 전이라
  마크다운 수가 574개였다. 기록·`INDEX.md`·What's New 갱신을 마친 뒤
  `node scripts/gissue/lib/relative-links.mjs` 를 단독 재실행 → **exit 0** ·
  **마크다운 576개 · 전체 링크 1,168건 · 상대링크 786건 · 스캐폴딩(예외) 21건 · 실제 결함 0건**
  (새로 추가한 2개 상대링크 — What's New 의 작업 기록·노트 링크 — 모두 정상 해결).

## [F] orphan stash / 워크트리 잔재

- `git stash list` → **0건**(공유 체크아웃 · `maint-92-0630` · `maint-62-2331` 3곳 확인).
  `auto-unblock ` stash 0건 → **매칭·회수 대상 stash 없음**.
- 워크트리 실측(`git worktree list`):
  | 경로 | 상태 | 92차 조치 |
  |---|---|---|
  | `D:\temp\worktrees\giip-fde-agent\maint-92-0630` | 브랜치 `chore/csn70424-maint92-20261104-0630` · HEAD `6fe4a0b` | 92차 작업 워크트리(신규) — 본 세션이 커밋·PR·머지 후 회수 |
  | `D:\temp\worktrees\giip-fde-agent\maint-62-2331` | 브랜치 `chore/csn70424-maint64-20261102-0250` · HEAD `b10cf06` · 미커밋 `docs/HISTORY.md`·`docs/WHATS_NEW.md` | **보류** — 정본 도구 `MANUAL-REVIEW`(머지 PR 없음) · `KNOW-023` · rule 47·48 |
  | 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` | `main`(`6fe4a0b` 로 ff-sync) · `git status --short` **clean** | 읽기 전용으로만 사용 |

### `maint-62-2331` 보류 근거 — 92차 재확정(78·86차와 별개의 **줄 단위** 대조)

- 정본 도구(`cleanup-worktrees.ps1`) 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태를 그대로 둔다 —
  **정본 판정을 우회하지 않는다**(rule 47 · 48 · `KNOW-023`).
- 92차는 **78차(`git diff --stat`)**·**86차(`git diff origin/main`)**와 **다른 방법**으로 재확인했다.
  **미커밋 추가분 중 `origin/main` 에 바이트 동일하게 존재하는 줄이 몇 개인지** 를 **줄 단위**로 세었다:
  - `docs/HISTORY.md` 추가분 **99줄 전건** → `origin/main` 에 **전건 존재(동일)** → **누락 0건**.
  - `docs/WHATS_NEW.md` 는 워크트리 기준일이 **2026-11-02**(구버전)이고 `origin/main` 은 **2026-11-04** —
    **오래된 스냅샷**이라 커밋하면 최신 기록을 되돌리는 **회귀 PR** 이 된다.
- **결론 — "고유 recoverable 정보 0건"**. 계승·커밋 대상이 아니므로 **보류 유지**(내용은 한 글자도 건드리지 않았다).

## [H] 최근 코멘트 논리 재검증 — 2시간 창 2건 · 24시간 창 4건 · **전건 일치 → 정정 0건**

- 조회: `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **2건**(4219 · 2855) ·
  `-HoursBack 24 -Json` → **4건**(4219 · 2855 · 4411 · 4434).
  91차가 본 2건(4411·4434)과 **다른 조합**이 나왔다 — **창 건수는 매 회차 실측할 것**(고정값으로 쓰지 않는다).
- 조회 산출물 파일은 회차마다 고유 파일명: `D:\temp\h70424\h2_92.txt` · `h24_92.txt`.
- **자기 코멘트 제외**: 92차는 **이슈 쓰기 0건**이므로 자기 코멘트도 없다.
- 코멘트 목록은 `scripts/gissue/lib/comment-api.js` 의 `listComments()` 로 직접 조회했다.

### 4219 (READY) — fact claims **전건 일치**

| 기존 코멘트의 주장 | 92차 재확인 결과 |
|---|---|
| `slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` 가 존재한다 | `git cat-file -e origin/main:slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` → **exit 0** ✓ |
| PR **#324** 는 머지됨 | `gh pr view 324` → **MERGED** · mergedAt `2026-10-27T06:07:11Z` ✓ |
| `git show origin/main:MODEL_USAGE_SPEC.md \| grep -qi 'jev'` → **exit 1** | 실제 실행 → **exit 1**(매치 0건) ✓ |
| PR **#1054** 는 머지됨 · base 는 `docs/dashboard-spec-and-directive-005-20261027` | **MERGED** · mergedAt `2026-10-27T08:07:14Z` · `baseRefName` 동일 ✓ |
| `f35baba5` 는 `origin/main` 의 조상이 아니다 | `git merge-base --is-ancestor f35baba5 origin/main` → **false** ✓ |
| `verify-runner.mjs 4219 70424` 결과는 **FAIL(exit 1)** | **ff-sync 후 exit 1** ✓ — 단, **ff-sync 전에는 exit 4** 로 나왔고 그 사실이 `KNOW-033` 의 근거다(아래 별도 act 2) |
| tPrivateKB kbSn **6913** 이 존재하고 제목이 같다 | `tkb.js get --csn 70424 --kb-sn 6913` → **존재** · 제목 일치 ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 READY 유지(전이 없음)**.

### 2855 (READY) — fact claims **전건 일치**

| 기존 코멘트의 주장 | 92차 재확인 결과 |
|---|---|
| `.agent/tasks/giip-2855.md` 가 존재한다 | `git cat-file -e origin/main:.agent/tasks/giip-2855.md` → **exit 0** ✓ |
| PR **#360** 는 머지됨 | `gh pr view 360` → **MERGED** · mergedAt `2026-11-03T21:07:10Z` ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 READY 유지(전이 없음)**.

### 4411 (DONE) — fact claims **전건 일치**

| 기존 코멘트의 주장 | 92차 재확인 결과 |
|---|---|
| tKB `KNOW-049`(다른 저장소 측) = kbSn **6835** · `regDt 2026-11-02T08:20:46.89` · `modDt 2026-11-02T10:40:25.383` | `tkb.js list --search "KNOW-049"` → **6835** · 두 시각 **일치** ✓ |
| tKB `KNOW-021`(이 저장소) = kbSn **6805** · `regDt 2026-11-01T17:54:56.217` | **6805** · `regDt` **일치** ✓ |
| `GIIP_GissueLiveness_Hourly` 태스크 Ready·Enabled·`LastTaskResult=0` | `Get-ScheduledTask`/`Get-ScheduledTaskInfo` → State **Ready** · `Settings.Enabled` **True** · `LastTaskResult` **0** ✓ (이후에도 정상 재실행 중) |
| `scripts/gissue/logs/gissue_liveness_state.json` 미존재 | **없음** ✓ |
| 정본 PR 340 · 이식 PR 1062 머지 | PR **340** MERGED(`b10cf068`, `2026-11-01T16:38:47Z`) · PR **1062** MERGED(`0e0e726`, `2026-11-01T16:42:16Z`) ✓ |
| 직전 정정 note 가 이 이슈의 **마지막 코멘트** | 코멘트 **10건** · 마지막 `gicSn 37610` ✓ · 직전 `gicSn 37241`(`2026-11-02T12:18:49Z`) ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 DONE 유지(전이 없음)**.

### 4434 (READY) — fact claims **전건 일치**

| 기존 코멘트의 주장 | 92차 재확인 결과 |
|---|---|
| 저장소 `KNOW-028` 1건 · `KNOW-029` 0건 | `KNOW-028_rule_citations_must_resolve_in_this_repo.md` **1건** · `KNOW-029` **0건** ✓ |
| tKB `KNOW-028` = kbSn **6870** · `regDt 2026-11-03T03:00:29.21` | **6870** · `regDt` **일치** ✓ |
| tKB `KNOW-029` = `[]` | **`[]`** ✓ |
| `Get-Module -ListAvailable SqlServer` → 22.3.0 | **SqlServer 22.3.0** ✓ |
| 정본 `FindOpenChildren` 이 API 경로 | `scripts/gissue/run-gissue-claude.ps1:3760` → `node $ListIssuesScript --csn … --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED,NEEDS_DECISION' --json` ✓ |
| 로그 2행(`137486`·`137487`) | `scripts/gissue/logs/gissue_csn47.log` → **그대로 존재** ✓ |
| 정본 기본값 Shadow | `scripts/gissue/lib/overtime-split.ps1:48` `else { 'Shadow' }` · `:52` `default { return 'Shadow' }` ✓ |
| `scripts/gissue/tests/test-overtime-findchildren-port.ps1` 아직 없음 | **없음** ✓ |

→ **주장 전건 일치** → 아무 것도 하지 않는다. **상태 READY 유지(전이 없음)**.

## 별도 act 1 — 공유 체크아웃 `main` ff-sync

- 92차 시작 시점 공유 체크아웃 `main` = `60d09f9` · `origin/main` = `6fe4a0b` 로 **1커밋 뒤처져 있었다**.
  `git fetch origin --prune` 후 `git merge --ff-only origin/main` → **fast-forward 완료**(`60d09f9..6fe4a0b`,
  `.agent/tasks/giip-2855.md` 1파일 추가). 92차 작업 워크트리는 이 갱신된 `origin/main`(`6fe4a0b`)에서 새로 만들었다.
- `git fetch --prune` 결과 **원격에서 사라진 추적 브랜치 ref 1건**이 정리되었다
  (`origin/task/giip-2855-entrypoint-phantom-dir`) — PR 없이 원격에 갇혀 있던 잔여 추적 ref 였다.
  **실제 원격 ref 은 `main` 1건뿐**(`git ls-remote --heads origin` 실측).

## 별도 act 2 — `KNOW-033` 신규: verify-runner 종료코드 4 ≠ 1

- **발견 경위** — [H] 4219 의 기존 코멘트가 "verify-runner 결과는 **FAIL(exit 1)**" 이라고 주장하고 있었다.
  92차가 그 주장을 **직접 재현**하려 실행한 결과는 **exit 4** 였다:
  ```
  [CHECKOUT-GATE] 검증 환경 부적격 — verify 블록을 실행하지 않습니다.
  HEAD(60d09f9) !== origin/main(6fe4a0b) — 기본 브랜치와 동기화되지 않음
  ```
  즉 **명령이 잘못된 게 아니라 환경(공유 체크아웃 1커밋 뒤처짐)이 어긋나 있었다.**
  공유 체크아웃을 ff-sync 한 뒤 재실행하니 **exit 1** 이 나와 **주장이 옳음이 확인**됐다 → [H] 정정 0건.
- **교훈의 핵심** — 종료코드 **4 = 검증 미실행(환경 부적격)** · 종료코드 **1 = 검증 실행 후 실패** 는
  **전혀 다른 사실**이다. exit 4 만 보고 "주장이 틀렸다" 로 정정하면 **틀린 정정**을 남긴다.
- 정본 코드 확인(`lowyworkenv\scripts\gissue\verify-runner.mjs`): `getWorkdirFromCsn`(csn-projects.json 의
  `csn.<csn>.workdir`) · `checkCheckoutState` ①브랜치 ②`HEAD == origin/<기본>` ③`status --porcelain` 빈 상태.
  하나라도 어긋나면 exit 4 로 **verify 블록을 실행하지 않고** 종료.
- **신규 등록** — `.agent/k_layer/notes/KNOW-033_verify_runner_exit4_is_untested_environment_not_verify_fail.md`
  (3006자) → `tkb.js sync-klayer --csn 70424 --dir .agent/k_layer/notes --project giip-fde-agent --note "KNOW-033*" --dry-run`
  → 1건 → 본 등록 → **`OK created kbSn=6914`**(`refType KNOWLEDGE` · csn 70424).
  등록 후 `tkb.js get --csn 70424 --kb-sn 6914 --json` → **본문 3006자 = 소스와 문자 단위 동일**(절단 없음).
  중복 사전 조회(`tkb.js list --search "KNOW-033"`) → `[]` 로 사전 중복 없음 확인.

## 별도 act 3 — `maint-62-2331` "고유 정보 0건" 재확정(줄 단위 대조)

- §[F] 참조. 78차(`git diff --stat`)·86차(`git diff origin/main`)와 **다른 방법**(추가분 줄을 `origin/main` 과
  **줄 단위 대조**)으로 세어 **`docs/HISTORY.md` 99줄 전건 존재 · 누락 0건**을 실측했다.
- 정본 도구 판정 `MANUAL-REVIEW` 는 **우회하지 않고** 보류 유지(rule 47 · 48 · `KNOW-023`).

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 은 **2026-11-04 로 유지**(91차가 이미 갱신 — 변경 없음).
- `## 2026-11-04` 섹션에 **92차 항목 1건**을 91차 항목 뒤에 추가한다(섹션 내 항목은 회차 순 오름차순 배열 유지).
- **이관 0건** — 현재 섹션은 `2026-11-04` · `2026-11-03` · `2026-11-02` · `2026-10-31` · `2026-10-30` 이고,
  7일 창(2026-10-28 이후) 밖 섹션은 이미 `docs/HISTORY.md` 로 이관되어 있다(88차 수행).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- 다른 저장소 측 tKB 를 조회한 부분은 `<csn>` 플레이스홀더로 적었고, 91차와 동일하게 **다른 저장소의 CSN 숫자는 기재하지 않았다**.
- 이슈 번호(4219·2855·4411·4434)와 PR 번호(324·1054·360·340·1062)는 추적성 표시용이며 고객 식별자가 아니다.
- `MODEL_USAGE_SPEC.md` 인용은 **경로를 명시**했다(88차가 지적한 경로 파손 인용의 정정).

## 결과 저장처 / 소비처

- 수정/신규 파일(92차 커밋 대상):
  `.agent/k_layer/notes/KNOW-033_verify_runner_exit4_is_untested_environment_not_verify_fail.md`(신규) ·
  `.agent/k_layer/notes/INDEX.md`(수정 — `KNOW-033` 행 추가) ·
  `.agent/work_history/20261104_0630_csn70424_repo-maintenance.md`(신규 — 본 파일) ·
  `docs/WHATS_NEW.md`(수정 — 92차 항목 1건 추가)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승) ·
  `KNOW-022`(PR 머지는 이슈 측 쓰기의 증거가 아니다) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다) ·
  `KNOW-026`(JSON `/Date(ms)/` 는 DB UTC −9h) · `KNOW-028`(이 저장소 규칙 인용은 이 저장소에 있는 파일명만) ·
  `KNOW-030`(스테이징만 하고 죽은 세션의 산출물은 PR·원격ref·stash 검사에서 전부 안 보인다) ·
  `KNOW-032`(러너 105분 자기 마감이 커밋 단계를 자른다) ·
  `KNOW-033`(verify-runner exit 4 = 검증 미실행 · exit 1 = 검증 실패)

## 남은 사항 (후속)

1. **이 회차 PR 번호·머지 커밋·CI run id 는 이 기록의 작성 시점 미확정** — 적지 않는다.
   확정값은 **PR 코멘트**와 **다음 회차 기록**이 실측해 인계한다(기록에 예정형 서술을 남기지 않는다 — `KNOW-013`).
2. **`maint-92-0630` 워크트리 회수** — 이 PR 이 머지된 뒤 정본 도구
   (`cleanup-worktrees.ps1 -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-92-0630" -MinIdleMinutes 0`)로 회수하고,
   **실행 결과(Removed 건수 · 원격 ref 삭제 여부)는 PR 코멘트에 실측값으로 남긴다.**
   (회수는 **공유 체크아웃 cwd** 에서 실행한다 — 회수 대상 워크트리 안에서 실행하면 보호 경로로 처리되어 조용히 0건이 된다.)
3. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   사람이 확인 후 수동 제거가 필요하다(`KNOW-023` · rule 47 · rule 48).
4. **`giip 4434` 의 노트 번호** — `KNOW-029` 로 등록해야 한다(79차가 issue note 로 명시).
   4434 는 READY 상태이며 92차도 **상태를 바꾸지 않았다**. **이슈 처리 세션의 몫**이다.
   (92차 실측: 저장소 `KNOW-029` 0건 · tKB `[]` — 슬롯이 비어 있음이 재확인됨.)
5. **tKB `KNOW-030`(kbSn 6874) 의 `refType` 이 `GENERAL`** — tKB 갱신 경로가 `refType` 을 받지 않아
   다른 KNOW 노트와(`KNOWLEDGE`) 다르다. 잔여 사항이며 tKB 스키마/SP 개정이 필요한 사안이다.
6. **러너 105분 자기 마감 ↔ 커밋 단계 순서** — 90차가 실측한 근본원인(러너가 저장소 정비 단계에서
   처리 중인 이슈가 없으면 마감시각을 즉시 앞당겨 커밋 전에 자른다)은 lowyworkenv 러너 측 사안이다.
