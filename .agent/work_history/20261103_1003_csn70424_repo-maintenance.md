# CSN 70424 Repo Maintenance — 2026-11-03 09:22 (저장소 정비 78차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **78차 저장소 정비 세션** — 2026-11-03 09:22 KST 시작. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- **이전 회차(77차) 계승 — 이번 회차의 핵심 act** — 77차는 2026-11-03 08:12 에 커밋 `bc2bef2` 를
  **원격에 push 하고 PR 을 만들지 못한 채** 세션을 끝냈다. 77차 기록 파일의 "남은 사항 2" 가 스스로 남긴 후속:
  > **PR 상태** — 77차 PR 은 생성 후 CI(Repo Gates)로 최종 확인한다. 머지 커밋·run id 는 후속 회차가 실측해 기록한다.

  즉 77차는 "PR 을 만들겠다"는 **계획만 문서로 남기고 실행하지 않은 상태**였다(`KNOW-013` — 회차 기록의
  "완료" 서술은 실행되지 않은 계획일 수 있다). 78차는 그 후속을 실제 명령으로 수행했다.
- 적용한 규칙 파일(이 저장소 `.agent/rules/` 에 실재하는 것만 인용):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `35_commit_push_per_task.md` · `36_no_md_in_nongit.md` · `41_branch_lifecycle_pr.md` ·
  `42_completion_by_execution_evidence.md` · `47_auto_cleanup_safety_requirements.md` ·
  `48_single_source_safety_predicate.md` · `50_bot_pr_scope_discipline.md` ·
  `53_pre_push_pure_source_guard.md` · `54_generic_agent_no_customer_info.md` ·
  `55_destructive_cleanup_incident_gate.md` · `PROTOCOL_PROGRESS_COMMENT.md`
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-78-1002` (**신규 생성** — 77차 워크트리는 본 PR 머지 후 정본 도구로 회수)
- 작업 브랜치: `chore/csn70424-maint78-20261103-1002` (기준 `origin/main` = `ec4dbcd`)
- 공유 체크아웃은 **읽기 전용**으로만 사용(커밋·스테이징 없음).

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list -R LowyShin/giip-fde-agent --state open` → `[]` (열린 PR 0건) · nested 관리 대상 저장소 0건(`.gemini/extensions/bkit` 는 외부 원본 서브모듈 — 관리 대상 아님) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 · `gh run list -R LowyShin/giip-fde-agent --branch main --limit 6` → **6건 전부 success** · 머지 후 main run `41556266463`(headSha `ec4dbcd`) **success** |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 2건 → 1건 회수 · 1건 보류** | `git stash list` → 0건(auto-unblock stash 없음, 공유 체크아웃·워크트리 2곳 모두) · `maint-77-0812` **회수** · `maint-62-2331` **보류**(정본 도구 MANUAL-REVIEW 재확인) → 아래 §[F] |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 0건 · 24시간 창 5건 · 전건 일치** | `-HoursBack 2` → **0건** · `-HoursBack 24` → **5건**(4411 DONE · 4429 DONE · 4334 PENDING · 4434 READY · 4431 PENDING) → 아래 §[H] 에서 직접 재확인 → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act — 77차 stranded 커밋 회수 (PR #349)**: 4단계 밖에서, 77차가 push 하고 남긴 커밋 `bc2bef2` 를
PR 로 마감했다. `KNOW-015`("열린 PR 0건"은 "할 일 없음"의 증거가 아니다 — 원격에 남은 브랜치로 PR 을 만들어 계승)
이 지시하는 절차 그대로다. 상세는 아래 §별도 act.

---

## 별도 act — 77차 stranded 커밋 회수 (PR #349)

### 실측 — PR 이 없다는 사실 자체가 확인 대상이었다

| 항목 | 명령 | 결과 |
|---|---|---|
| 원격에 남은 브랜치 | `git branch -r` | `origin/chore/csn70424-maint77-20261103-0812` **존재** (origin/main 외 잔여 1건) |
| 그 브랜치의 미반영 커밋 | `git log --oneline origin/main..chore/csn70424-maint77-20261103-0812` | `bc2bef2` **1건** |
| 그 커밋의 내용 | `git diff --stat origin/main..chore/csn70424-maint77-20261103-0812` | **파일 2건(+182)** — 77차 작업 기록 신규 181줄 · `docs/WHATS_NEW.md` 77차 항목 1건 |
| PR 존재 여부 | `gh pr list -R LowyShin/giip-fde-agent --state all --head chore/csn70424-maint77-20261103-0812` | `[]` — **PR 0건** = push 후 PR 미생성 상태 확정 |
| 워크트리 상태 | `git -C D:/temp/worktrees/giip-fde-agent/maint-77-0812 status --short` | **빈 출력**(미커밋 0건) — 워크트리는 깨끗하고 커밋만 원격에 갇혀 있었다 |

### 수행

1. **PR #349 생성** — base `main` · head `chore/csn70424-maint77-20261103-0812`.
   PR 본문에 위 실측표 · 78차 4단계 결과 · 게이트 3종 실측 · `maint-62-2331` MANUAL-REVIEW 재확인 사유를 기재했다.
2. **PR 파일 실측 대조** — `gh pr view 349 --json files` → **정확히 2건**(`.agent/work_history/20261103_0812_...md` ADDED 181 · `docs/WHATS_NEW.md` MODIFIED +1). 무관 파일 혼입 **0건**.
3. **PR CI 3건 pass 확인** — `gh pr checks 349` → GitGuardian **pass**(32s) · MJS gates **pass**(42s) · PS1 gates **pass**(1m54s).
   `mergeable` **MERGEABLE** · `mergeStateStatus` **CLEAN**.
4. **squash 머지** — `gh pr merge 349 --squash`.
   merge 커밋 `ec4dbcd3f889a11e97faf3ea64bf262829814217` · mergedAt `2026-11-03T00:55:26Z`(= 09:55:26 KST) · mergedBy `LowyShin`.
5. **머지 후 main CI** — run **`41556266463`** · headSha `ec4dbcd` · **success**.
6. **콘텐츠 보존 검증(머지 후 main 기준)** —
   - `git show origin/main:.agent/work_history/20261103_0812_csn70424_repo-maintenance.md` → **181줄 존재**(본문 첫 줄 = `# CSN 70424 Repo Maintenance — 2026-11-03 07:26 (저장소 정비 77차)`)
   - `git show origin/main:docs/WHATS_NEW.md | grep -c '저장소 위생 정비 77차'` → **1** (77차 항목 반영 확인)
7. **워크트리 회수** — §[F] 참조 (정본 도구).

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list -R LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트(충돌 해소 3번) 대상이 없었다.
- nested 관리 대상 저장소 **0건** — `find . -mindepth 2 -maxdepth 4 -name .git` 결과 `.gemini/extensions/bkit` 1건뿐이며,
  이는 **외부 원본 서브모듈**(popup-studio-ai/bkit-claude-code)이라 이 저장소의 PR 관리 대상이 아니다
  (76·77차와 동일한 판정).
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이 되므로):
  `gh run list -R LowyShin/giip-fde-agent --branch main --limit 6` →
  `41537394369`(2a67d29) · `41430489808`(db2ed82) · `41394112774`(f3ae1ed) · `41384332988`(d459b17) ·
  `41377808488`(6bf6d93) · `41357197608`(bcc5b46) — **6건 전부 success**.
- 78차가 만든 PR #349 는 머지 전후로 3건 전부 pass 를 확인했다(위 별도 act 3·5번).

## [F] 죽은 세션 워크트리 잔재 처리

- `git stash list` → **0건**. `auto-unblock ` 접두 stash 없음 → stash 구조 대상 0건.
  (공유 체크아웃 + 워크트리 2곳 모두 확인)
- 워크트리 잔재 2건 실측 후 처리:

| 워크트리 | 브랜치 / HEAD | 미커밋 | 78차 처리 |
|---|---|---|---|
| `maint-77-0812` | `chore/csn70424-maint77-20261103-0812` / `bc2bef2` | 0건 | **회수(삭제)** — PR #349 MERGED 확인 후 정본 도구 경로 |
| `maint-62-2331` | `chore/csn70424-maint64-20261102-0250` / `b10cf06` | 2건(`docs/HISTORY.md` · `docs/WHATS_NEW.md`) | **보류(삭제하지 않음)** |

### 1) maint-77-0812 — 정본 도구로 회수

- 정본 도구(`scripts/gissue/cleanup-worktrees.ps1`)를 **공유 체크아웃 cwd** 에서 실행했다
  (회수 대상 워크트리 안에서 실행하면 보호 경로로 SKIP 되어 조용히 성공처럼 끝난다 — 실측된 함정).
- 명령: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent" -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-77-0812" -MinIdleMinutes 0`
- **DryRun 먼저**: `[DRY-RUN] 삭제 예정(머지 확인, idle 가드 비활성(MinIdleMinutes=0), 링크 없음 확인됨)` · 요약 "삭제 1건 / locked 제외 0건 / 수동확인 필요 0건" · `Aborted=False`
- **실행 결과**: `삭제됨(머지 확인, idle 가드 비활성(MinIdleMinutes=0), 인접 레포 무결성 재검증 통과)` ·
  `원격 브랜치 삭제: chore/csn70424-maint77-20261103-0812` · `Removed 1건` · `SkippedLocked 0` · `ManualReview 0` · `Aborted=False`
- 재검증: `git worktree list` → 공유 체크아웃 + `maint-62-2331` **2건만**(78차 워크트리는 미생성 상태).
  `git branch -r` → `origin/main` · `origin/HEAD` **2개만**.

### 2) maint-62-2331 — 보류(삭제하지 않음)

- **정본 도구 판정 재확인(78차)**: DryRun 결과
  `MANUAL-REVIEW(미머지 — 자동삭제 대상 아님): D:\temp\worktrees\giip-fde-agent\maint-62-2331 (branch=chore/csn70424-maint64-20261102-0250)`
  · 요약 "삭제 0건 / locked 제외 0건 / 수동확인 필요 1건" — 사유는 **"머지 PR 없음(사람 확인 필요 — 미완료 작업일 수 있음)"**.
  `gh pr list --state all --head chore/csn70424-maint64-20261102-0250` → `[]` 로 확인된다.
- **78차가 추가한 실측 — 잔재가 "회귀"가 아니라 "중복"임을 바이트 단위로 확인**:
  - `docs/HISTORY.md` 미커밋 추가 **99줄**을 추출해 `origin/main:docs/HISTORY.md` 와 `comm -23` 대조 → **main 에 미존재 0줄**(전건 동일).
    즉 이 99줄은 main 에 **이미 반영돼 있다**(76차가 롤링 창 이관으로 넣은 항목).
  - `docs/WHATS_NEW.md` 미커밋 변경(기준일 `2026-11-02` · `## 2026-11-02` 섹션 추가 / `## 2026-10-25`…`## 2026-10-20` 섹션 제거)
    → 현재 main 은 이미 `## 2026-11-02` 섹션을 갖고 있고, `2026-10-25`…`2026-10-20` 섹션은 **이미 없다**.
    main 의 `## 2026-11-02` 섹션에는 63차 항목이 1건 존재(`grep -c '저장소 위생 정비 63차'` → **1**).
  - 결론: 워크트리 내용은 `origin/main` 보다 **오래된 스냅샷**이며, 미커밋 diff 는 **이미 반영된 항목의 되돌림**이다
    (`KNOW-023` — 오래된 스냅샷을 커밋하면 회귀 PR 이 된다).
- **그래도 삭제하지 않았다** — 정본 도구 판정(`MANUAL-REVIEW`)을 우회하지 않는다(rule 47 · rule 48).
  커밋하면 회귀 PR 이 되고, 강제 삭제는 정본 판정을 우회하는 것이므로 **보류 유지**가 정본 답이다.
  → 사람 확인 후 제거하려면 `git worktree remove --force "D:\temp\worktrees\giip-fde-agent\maint-62-2331"` + `git branch -D chore/csn70424-maint64-20261102-0250` 로 수동 처리해야 한다(78차는 수행하지 않음).

## [H] 최근 코멘트 논리 재검증 — 5건 전건 일치

- 조회: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\listRecentCommentIssues.ps1" -Csn 70424 -HoursBack 2 -Json` → **0건**
- 조회: 같은 스크립트 `-HoursBack 24` → **5건**: 4411(DONE) · 4429(DONE) · 4334(PENDING) · 4434(READY) · 4431(PENDING)
- **자기 자신 제외 대상 0건** — 78차는 이슈 코멘트를 아직 남기지 않았다.
- 시간축 주의(`KNOW-026`): JSON 의 `/Date(ms)/` 는 **DB 저장 UTC − 9h** 다. 창 판정(SQL `DATEDIFF`)은 정확하고 **읽을 때만 +9h** 보정한다.
- tKB 조회는 이 저장소가 아니라 **정본 lowyworkenv 체크아웃 cwd** 에서 실행했다(`scripts/gissue/tkb.js` 는 lowyworkenv 에 있다).

| isn | 상태 | 마지막 코멘트의 검증 가능한 사실 주장 | 78차의 재확인 방법·결과 | 판정 |
|---|---|---|---|---|
| 4411 | DONE | 72차 정정 코멘트의 서술: ① lowyworkenv k-layer `KNOW-049` 등록됨 ② `GIIP_GissueLiveness_Hourly` 태스크가 **존재·실행 중** ③ `scripts/gissue/logs/gissue_liveness_state.json` **불존재** ④ `KNOW-021` 등록됨(kbSn 6805) | `node scripts/gissue/tkb.js list --csn 33 --search "KNOW-049" --json` → **kbSn 6835**(regDt 2026-11-02T08:20:46.89 · modDt 2026-11-02T10:40:25.383) / `node scripts/gissue/tkb.js list --csn 70424 --search "KNOW-021" --json` → **kbSn 6805** / `Get-ScheduledTask -TaskName 'GIIP_GissueLiveness_Hourly'` → State **Ready** · Enabled **True** · **LastRun 2026-11-03 08:37:37** · **LastTaskResult 0** / `Test-Path scripts/gissue/logs/gissue_liveness_state.json` → **False** | **일치** |
| 4429 | DONE | Live 유지 결정 기록: lowyworkenv `scripts/gissue/lib/overtime-host-default.ps1` = `'Live'` · `GISSUE_OVERTIME_SPLIT_MODE` 3단계 미설정 · **정본(giip-fde-agent) 기본값은 Shadow** | `Select-String` → `$script:GissueOvertimeHostDefaultMode = 'Live'` / 환경변수 Process·User·Machine **모두 미설정** / 정본 `scripts/gissue/lib/overtime-split.ps1` → `else { 'Shadow' }` (**정본은 Shadow 유지**) / 정본의 수정은 `db2ed82`("2시간 초과 처리 결과에 Log 포트 출력이 섞여 errors=1 + 빈 WARN 이 찍히던 결함", PR #347)로 **main 에 반영** | **일치** |
| 4334 | PENDING | 체크리스트 판정 Live 전환 기록: lowyworkenv PR **1069** 머지(merge `35154499`) · `checklist-host-default.ps1` = `'Live'` · `GISSUE_CHECKLIST_MODE` 3단계 미설정 · 로그 증거 `체크리스트 판정 모드: Live (source=default-constant)` · **정본은 Shadow 유지** | `gh pr view 1069 --repo LowyShin/Lowyworkenv` → **MERGED** · mergeCommit `351544992916a20d38459b3caf054ab405a1ae41` · mergedAt 2026-11-02T08:50:04Z(= 17:50:04 KST) / `Select-String` → `$script:GissueChecklistHostDefaultMode = 'Live'` / 환경변수 3단계 **모두 미설정** / `Select-String gissue_csn47.log '2026-11-02 18:13:18'` → `[2026-11-02 18:13:18] … 체크리스트 판정 모드: Live (source=default-constant)` **행 그대로 존재** / 정본 `scripts/gissue/gissue-audit-lib.ps1` → `else { 'Shadow' }` (**정본은 Shadow 유지**) | **일치** |
| 4434 | READY | **코멘트 0건** → 검증 대상 주장 0건 | 24시간 창 조회 결과 `lastCommentContent` = **null** | **대상 없음** |
| 4431 | PENDING | **코멘트 0건** → 검증 대상 주장 0건 | 24시간 창 조회 결과 `lastCommentContent` = **null** | **대상 없음** |

### 이슈 상태 — 전부 유지 (전이 0건)

- 4411 DONE · 4429 DONE · 4334 PENDING · 4434 READY · 4431 PENDING — **5건 전부 변경하지 않았다.**
- [H] 는 READY 복귀까지만 허용하며 **TESTED/DONE 전이는 하지 않았다**. 이번 회차는 정정 대상이 없어 **전이 자체가 0건**이다.
- **giip 이슈 쓰기 0건** — 모든 주장이 일치했으므로 정정 코멘트도 남기지 않았다(불필요한 코멘트 생성 금지).

## 로컬 검증 (게이트) — 78차가 실제로 실행

### 1) 77차 브랜치 워크트리(`maint-77-0812`)에서 실행 — PR #349 머지 직전

```
[MD-LINK] 마크다운 555개 · 전체 링크 1144건 · 상대링크 762건
[MD-LINK] 스캐폴딩(예외) 21건 · 실제 결함 0건           ← node scripts/gissue/lib/relative-links.mjs   exit 0
[PS1-PARSE] 결과: 검사 80개 전부 통과 (구문 + BOM)      ← powershell -File scripts/gissue/check-ps1-parse.ps1 -All   exit 0
[pre-push-guard] 가드 모듈 없음(비대상 레포) — 스킵        ← sh .agent/scripts/pre-push-pure-source-guard.sh .          exit 0
```

- **3종 모두 exit 0** — 실패를 성공으로 덮지 않았다.

### 2) 78차 작업 워크트리(`maint-78-1002`)에서 실행 — 본 커밋 push 직전

```
[MD-LINK] 마크다운 555개 · 전체 링크 1144건 · 상대링크 762건
[MD-LINK] 스캐폴딩(예외) 21건 · 실제 결함 0건           ← node scripts/gissue/lib/relative-links.mjs   exit 0
[PS1-PARSE] 결과: 검사 80개 전부 통과 (구문 + BOM)      ← powershell -File scripts/gissue/check-ps1-parse.ps1 -All   exit 0
[pre-push-guard] 가드 모듈 없음(비대상 레포) — 스킵        ← sh .agent/scripts/pre-push-pure-source-guard.sh .          exit 0
```

- **3종 모두 exit 0** — 실패를 성공으로 덮지 않았다.
- 78차 커밋은 `.md` 2건뿐이라 ps1·mjs 회귀 대상 파일은 변경되지 않는다.
  (`run-repo-gates.ps1` 전체 1회 실행은 20분 이상 소요라 미실행 — `Not-tested` 로 명시)

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 은 **2026-11-03 으로 유지**(이미 오늘 날짜 — 변경 없음).
- `## 2026-11-03` 섹션에 **78차 항목 1건** 추가(섹션 내 항목은 회차 순 오름차순 배열 유지).
- **이관 0건** — 현재 섹션은 `2026-11-03` · `2026-11-02` · `2026-10-31` · `2026-10-30` · `2026-10-27` 이고,
  `2026-10-26` 이전은 76차가 이미 `docs/HISTORY.md` 로 이관했다(7일 창 = 2026-10-27 이후).
- **줄바꿈 주의** — 이 저장소는 `core.autocrlf=true` 라 `docs/WHATS_NEW.md` 는 **CRLF** 로 체크아웃된다.
  새 항목은 **바이트 단위 CRLF** 로 삽입했다(LF 가 섞이면 diff 폭이 부풀어 보인다).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- 다른 저장소(lowyworkenv) 언급은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.
- 이슈 번호(4411·4429·4334·4434·4431)는 추적성 표시용이며 고객 식별자가 아니다.

## 결과 저장처 / 소비처

- 수정/신규 파일 2건:
  `.agent/work_history/20261103_1003_csn70424_repo-maintenance.md`(신규 — 본 파일, 78차 기록) ·
  `docs/WHATS_NEW.md`(수정 — `## 2026-11-03` 섹션에 78차 항목 1건 추가)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승) · `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다)

## 남은 사항 (후속)

1. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   78차는 미커밋 2건이 main 에 **이미 바이트 동일하게 존재**함(99줄 전건 일치 · WHATS_NEW 섹션도 이미 정리 완료)을 실측했으므로
   **회귀가 아니라 중복 스냅샷**임이 확인되었으나, 정본 판정을 우회하지 않고 보류한다(`KNOW-023` · rule 47 · rule 48).
   사람이 확인 후 수동 제거가 필요하다.
2. **78차 PR** — 78차 세션이 **직접 생성하고 머지**한다(커밋 직후 PR 생성이 필수 — 77차가 이 지점에서 갇혔다).
   머지 커밋·run id 는 PR 본문·코멘트와 **79차 기록**에 실측 남긴다.
3. **`KNOW` 노트 신규 등록 0건** — 이번 회차의 교훈(원격에 남은 죽은 세션 브랜치 회수)은 `KNOW-015` 가 이미 담고 있고,
   "기록의 후속 서술도 실행되지 않을 수 있다" 는 `KNOW-013` 의 범주다. **중복 노트를 만들지 않았다.**
   tKB 등록·갱신도 **0건**(신규 노트 없음).

> **정정(2026-11-03, 79차 저장소 정비):** 위 규칙 인용 중 `36_no_md_in_nongit.md` · `41_branch_lifecycle_pr.md` · `55_destructive_cleanup_incident_gate.md` 는 **이 저장소 `.agent/rules/` 에 존재하지 않는 파일명**이다 — 실측: `ls .agent/rules/`(53개) 목록에 없음, `git log --all --diff-filter=A -- .agent/rules/<파일명>` 로 저장소 이력 전체에도 추가된 적 없음. 이 저장소에서의 실제 대응은 `36_no_md_in_nongit.md` → 동등 규칙 없음 — `33_artifact_hygiene.md`(정본 분리)가 가장 가까움 · `41_branch_lifecycle_pr.md` → `41_issue_session_safety_index.md` + `35_commit_push_per_task.md` · `55_destructive_cleanup_incident_gate.md` → `47_auto_cleanup_safety_requirements.md` 이다. 본 기록은 **lowyworkenv 측 규칙 목록**을 그대로 옮긴 것으로, 근거·전체 대응표는 `.agent/k_layer/notes/KNOW-028_rule_citations_must_resolve_in_this_repo.md` 를 본다.
