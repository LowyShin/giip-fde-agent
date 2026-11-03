# CSN 70424 Repo Maintenance — 2026-11-03 16:23 (저장소 정비 82차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **82차 저장소 정비 세션** — 2026-11-03 16:23 KST 시작. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- 적용한 규칙 파일(**이 저장소 `.agent/rules/` 에 실재하는 것만 인용** — `KNOW-028` 대응표 기준):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `33_artifact_hygiene.md` · `35_commit_push_per_task.md` · `36_whats_new_maintenance.md` ·
  `41_issue_session_safety_index.md` · `42_completion_by_execution_evidence.md` ·
  `46_cross_csn_write_scope.md` · `47_auto_cleanup_safety_requirements.md` ·
  `48_single_source_safety_predicate.md` · `50_bot_pr_scope_discipline.md` ·
  `54_generic_agent_no_customer_info.md` · `55_information_lookup_order_and_feedback.md` ·
  `PROTOCOL_PROGRESS_COMMENT.md`
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-81-1428` · 기준 `origin/main` = `f1a7300`
- 작업 브랜치: `chore/csn70424-maint81-20261103-1428` — **81차 세션의 워크트리·브랜치를 계승**했다
  (`KNOW-030` 교훈 2 — 이미 배선된 브랜치를 그대로 쓴다. 새 브랜치를 새로 만들지 않는다).
- 공유 체크아웃은 **커밋·스테이징 없이** 사용했다(읽기 전용 + `git merge --ff-only` 로 main 만 최신화).

### 위임 판단 — AGENT 도구(서브에이전트)를 쓰지 않은 사유

`.agent/roles/orchestrator.md` 의 "구현은 서브에이전트에 위임" 원칙을 적용하지 않았다. 사유:
(1) `MODEL_USAGE_SPEC.md` 의 **"MiniMax 메인 → Claude 폴백/QA"** 원칙상 **이 세션이 MiniMax 메인 경로**이며
폴백 사유가 없었다(세션 모델 MiniMax-M3 정상 동작).
(2) 산출물은 **본 세션의 실측 결과 그 자체**로, "이해를 위임하지 않는다"(role 문서) 원칙상
검증된 사실 120여 건을 새 서브에이전트에 옮긴 뒤 되돌려받아야 하는 산출물은 그렇지 않다.
(3) `KNOW-030` 이 freshly 만든 사고 유형이 **"죽은 세션이 스테이징만 남긴다"** 인데, 위임은 그 유형의
실패 표면을 늘린다. 82차는 계승·계승·실행 결과로 마감했다.

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list -R LowyShin/giip-fde-agent --state open` → `[]` · `git ls-remote --heads origin` → `refs/heads/main` **1건뿐**(원격에 PR 없는 잔여 ref 0건) · nested 관리 대상 저장소 0건(`.gemini/extensions/bkit` 는 외부 원본 서브모듈) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → 실패 체크 보유 PR 0건 · `gh run list -R LowyShin/giip-fde-agent --branch main --limit 6` → **6건 전부 success**(최신 `41586628373` = `f1a7300` 80차 PR #352 머지 후 run) |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 2건(1건 계승·마감 · 1건 보류)** | `git stash list` → 0건(공유 체크아웃 + 워크트리 3곳 확인) · `maint-81-1428` **계승**(81차 잔재 `KNOW-030` untracked 1건) · `maint-62-2331` **보류**(정본 도구 `MANUAL-REVIEW`) |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 0건 · 24시간 창 4건 · 전건 일치** | `-HoursBack 2` → **0건** · `-HoursBack 24` → **4건**(4434 · 4411 · 4429 · 4334) → 아래 §[H] 에서 직접 재확인 → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act 4건**(4단계 밖) — ① **81차 죽은 세션 잔재 회수**(`KNOW-030` 노트 커밋·PR)
② **tKB `KNOW-030`(kbSn 6874) 본문 소실 정정**(81차 등록 행의 `content = null`)
③ **80차 기록의 dangling `§PR` 참조 정정** ④ **`INDEX.md` 에 `KNOW-030` 행 추가**.
→ 아래 §별도 act.

---

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list -R LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트 대상이 없었다.
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).
- nested 관리 대상 저장소 **0건** — `find . -maxdepth 3 -name .git` 결과 `.gemini/extensions/bkit` 1건뿐이며,
  이는 **외부 원본 서브모듈**(popup-studio-ai/bkit-claude-code)이라 이 저장소의 PR 관리 대상이 아니다
  (76·77·78·79·80·81차와 동일한 판정).
- **원격 ref 확인(`KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다)**:
  `git ls-remote --heads origin` → **`refs/heads/main` 1건뿐**. PR 없이 원격에 갇힌 브랜치 0건.

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이 되므로):
  `gh run list -R LowyShin/giip-fde-agent --branch main --limit 6` →
  `41586628373`(`f1a7300`) · `41577694547`(`0f8ece6`) · `41559830794`(`834b2f6`) · `41556266463`(`ec4dbcd`) ·
  `41537394369`(`2a67d29`) · `41430489808`(`db2ed82`) — **6건 전부 success**.
  최신 run `41586628373` 은 **80차 PR #352 머지 후 main push run** 이므로 직전 회차 산출물이 green 으로 반영됐음을 확인했다.
- 참고: PR #352 의 CI 도 `Repo Gates` run `41586380134` **success** 였다.

## [F] 죽은 세션 워크트리 잔재 처리

- `git stash list` → **0건**. `auto-unblock ` 접두 stash 없음 → stash 구조 대상 0건.
  (공유 체크아웃 + 워크트리 2곳에서 각각 확인)
- 워크트리 잔재 3건 실측 후 처리:

| 워크트리 | 브랜치 / HEAD | 미커밋 | 82차 처리 |
|---|---|---|---|
| 공유 체크아웃 | `main` / `f1a7300` | 0건(clean) | 읽기 전용 사용 · ff-sync 불필요(이미 `origin/main` 과 동일) |
| `maint-81-1428` | `chore/csn70424-maint81-20261103-1428` / `f1a7300` | **1건(untracked `KNOW-030`)** | **계승 · 마감** — 81차 잔재를 이 워크트리·이 브랜치 그대로 커밋·PR |
| `maint-62-2331` | `chore/csn70424-maint64-20261102-0250` / `b10cf06` | 2건(`docs/HISTORY.md` · `docs/WHATS_NEW.md`) | **보류(삭제하지 않음)** |

### 1) maint-81-1428 — 81차 죽은 세션 잔재 계승

- **발견 경로(중요)** — `KNOW-030` 이 지적한 그대로, **열린 PR 0건 · 원격 ref 1건 · stash 0건 ·
  공유 체크아웃 clean 이 모두 성립한 상태**였다. 남은 검사 한 줄은 `git worktree list` 로 등록된
  워크트리마다 `git status --short` 를 보는 것이었다.
- **81차 잔재 실측** — `git -C D:/temp/worktrees/giip-fde-agent/maint-81-1428 status --short --untracked-files=all` →
  `?? .agent/k_layer/notes/KNOW-030_staged_only_dead_session_output_is_invisible_to_pr_remote_ref_and_stash_checks.md` ·
  `git log main..HEAD` → **0건** · `git diff --cached --name-only` → **빈 출력**(스테이징 아님, untracked) ·
  `gh pr list --state all --head chore/csn70424-maint81-20261103-1428` → `[]` ·
  `git ls-remote --heads origin` → `refs/heads/main` 1건뿐.
- **계승 처리** — 새 브랜치를 만들지 않고 **이미 배선된 브랜치**(`chore/csn70424-maint81-20261103-1428`)를 그대로 썼다.

### 2) maint-62-2331 — 보류(삭제하지 않음)

- **정본 도구 판정 재확인(82차)**: 공유 체크아웃 cwd 에서 DryRun 실행(2026-11-03 16:44:17) →
  `MANUAL-REVIEW(미머지 — 자동삭제 대상 아님): D:\temp\worktrees\giip-fde-agent\maint-62-2331 (branch=chore/csn70424-maint64-20261102-0250)` ·
  요약 "삭제 0건 / locked 제외 0건 / 수동확인 필요 1건" — 사유는 **"머지 PR 없음(사람 확인 필요 — 미완료 작업일 수 있음)"**.
  `Aborted=False`.
- **정본 판정을 우회하지 않는다**(rule 47 · rule 48 · `KNOW-023`) — 78·79·80·81차가 확인해 보류한 상태를 그대로 유지한다.

## [H] 최근 코멘트 논리 재검증 — 4건 전건 일치

- 조회: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\listRecentCommentIssues.ps1" -Csn 70424 -HoursBack 2 -Json` → **0건**(출력에 행 없음)
- 조회: 같은 스크립트 `-HoursBack 24` → **4건**: 4434(READY) · 4411(DONE) · 4429(DONE) · 4334(PENDING)
  - **80차 시점의 5건 중 4431 이 24시간 창 밖으로 벗어났다**(창이 미끄러지는 것 — `KNOW-026` 및 과거 회차 실측).
    4431 은 80차 기록에서 "코멘트 0건 → 검증 대상 주장 0건"으로 처리된 건이라 **검증 대상이 새로 생기지 않았다.**
- **자기 자신 제외 대상 0건** — 82차는 세션 시작 시 이슈 코멘트를 아직 남기지 않았다.
- 시간축 주의(`KNOW-026`): JSON 의 `/Date(ms)/` 는 **DB 저장 UTC − 9h** 다. 창 판정(SQL `DATEDIFF`)은 정확하고 **읽을 때만 +9h** 보정한다.
- tKB 조회는 이 저장소가 아니라 **정본 lowyworkenv 공유 체크아웃 cwd** 에서 실행했다(`scripts/gissue/tkb.js` 는 lowyworkenv 에 있다).

| isn | 상태 | 마지막 코멘트의 검증 가능한 사실 주장 | 82차의 재확인 방법·결과 | 판정 |
|---|---|---|---|---|
| 4434 | READY | 79차 note 의 서술: ① 저장소 내 `KNOW-028` 점유 1건 ② tKB `KNOW-028` = **kbSn 6870** ③ 저장소·tKB 양쪽 모두 `KNOW-029` 미점유 ④ 본문 사실 주장 5건(SqlServer 22.3.0 / `FindOpenChildren` API 포트 / 로그 2행 / 테스트 파일 부재 / 정본 기본값 Shadow) | `ls .agent/k_layer/notes/ \| grep -E "KNOW-0(28\|29)"` → **`KNOW-028` 1건, `KNOW-029` 0건** / `tkb.js list --csn 70424 --search "KNOW-028" --json` → **kbSn 6870** / `tkb.js list --csn 70424 --search "KNOW-029" --json` → **`[]`** / `Get-Module -ListAvailable SqlServer` → **22.3.0** / `grep -rn FindOpenChildren scripts/gissue/` → `run-gissue-claude.ps1:3758`(포트 정의) · `lib/overtime-split.ps1:367`(호출) **2건 존재** / `grep -c "2026-11-02 19:52:17" scripts/gissue/logs/gissue_csn47.log` → **2행** / `ls scripts/gissue/tests/ \| grep -i "children\|findchild"` → **0건(파일 부재)** / 정본 `scripts/gissue/lib/overtime-split.ps1:48·52` → `'Shadow'` | **일치** |
| 4411 | DONE | 72차 정정 코멘트의 서술: ① lowyworkenv k-layer `KNOW-049` 등록됨 ② `GIIP_GissueLiveness_Hourly` 태스크가 **존재·실행 중** ③ `scripts/gissue/logs/gissue_liveness_state.json` **불존재** ④ `KNOW-021` 등록됨(kbSn 6805) | `Get-ScheduledTask -TaskName 'GIIP_GissueLiveness_Hourly'` → State **Ready** · **LastRun 2026-11-03 15:37:37** · LastTaskResult **0** · NextRun **16:37:37** / `Test-Path scripts/gissue/logs/gissue_liveness_state.json` → **False** / `tkb.js list --csn 33 --search "KNOW-049" --json` → **kbSn 6835** / `tkb.js list --csn 70424 --search "KNOW-021" --json` → **kbSn 6805** | **일치** |
| 4429 | DONE | Live 유지 결정 기록: lowyworkenv `scripts/gissue/lib/overtime-host-default.ps1` = `'Live'` · `GISSUE_OVERTIME_SPLIT_MODE` 3단계 미설정 · **정본(giip-fde-agent) 기본값은 Shadow** | `Select-String` → `$script:GissueOvertimeHostDefaultMode = 'Live'`(`:19`) / 환경변수 Process·User·Machine **모두 미설정** / 정본 `scripts/gissue/lib/overtime-split.ps1:48` → `else { 'Shadow' }` · `:52` → `default { return 'Shadow' }` | **일치** |
| 4334 | PENDING | 체크리스트 판정 Live 전환 기록: lowyworkenv PR **1069** 머지(merge `35154499`) · `checklist-host-default.ps1` = `'Live'` · `GISSUE_CHECKLIST_MODE` 3단계 미설정 · 로그 증거 `체크리스트 판정 모드: Live (source=default-constant)` · **정본은 Shadow 유지** | `gh pr view 1069 --repo LowyShin/Lowyworkenv` → **MERGED**(merge `35154499` · mergedAt 2026-11-02T08:50:04Z) / `Select-String` → `$script:GissueChecklistHostDefaultMode = 'Live'`(`:20`) / 환경변수 3단계 **모두 미설정** / `grep "체크리스트 판정 모드" scripts/gissue/logs/gissue_csn47.log` → **5행** · 그중 **비-Live 0행**(전부 `Live (source=default-constant)`) / 정본 `scripts/gissue/gissue-audit-lib.ps1:801·805` → `'Shadow'` | **일치** |

### 이슈 상태 — 전부 유지 (전이 0건)

- 4434 READY · 4411 DONE · 4429 DONE · 4334 PENDING — **4건 전부 상태 변경하지 않았다.**
- [H] 는 READY 복귀까지만 허용하며 **TESTED/DONE 전이는 하지 않았다**. 이번 회차는 정정 대상이 없어 **전이 자체가 0건**이다.
- **giip 이슈 쓰기 0건** — 정정 대상이 없으므로 코멘트도 남기지 않았다(불필요한 코멘트 생성 금지).

---

## 별도 act 1 — 81차 죽은 세션 잔재 회수(`KNOW-030` 노트 커밋·PR)

- 81차가 15:16 에 쓴 `KNOW-030` 노트는 **untracked** 상태로 방치되어 있었다(커밋 0 · PR 0 · 원격 ref 0).
  82차가 81차 워크트리·브랜치를 계승해 **커밋·PR 로 마감**했다.
- **노트 내용 정정 3건**(82차 실측 + rule 73):
  1. **중국어 한자 2자 혼입 1건** — "모든〔중국어 한자〕 검사기가" → "모든**표준** 검사기가"
     (원문은 중국어 한자 2자로 쓰여 있었고, 한국어 표기로 교체했다. 수정 후 파일 전체 스캔 결과 **CJK 한자 0건**).
  2. **미실행 서술 정정** — 교훈 5 의 "80차 기록에 정정 블록을 덧붙여 …" 는 **81차에 실행되지 않았다**(PR #352 의 변경 파일은 2건뿐이고
     80차 기록에 정정 블록이 없다). "81차는 이 블록을 넣지 못한 채 종료됐고 82차가 실제로 추가했다" 로 정정.
  3. **tKB 4000자 한계 대응** — 원문 4065자(4080자 경계 초과)로 tKB 등록 시 절단될 수 있어
     **중복 문장만 축약해 3884자**로 만들었다(내용 변경 없음). → 전문이 tKB 에 그대로 들어간다.
- **81차의 작업 기록은 존재하지 않았다** — `KNOW-030` 의 "관련" 절이 가리키는
  `.agent/work_history/20261103_1428_csn70424_repo-maintenance.md` 가 없었고, 깨진 링크 상태였다.
  → **82차가 복원 작성**했다(81차 원문 서술이 아니라 **82차가 확인 가능한 사실만** 담은 복원본임을 파일 상단에 명시).

## 별도 act 2 — tKB `KNOW-030`(kbSn 6874) 본문 소실 정정

- 81차는 15:18:43 KST 에 `KNOW-030` 을 tKB 에 **등록**했다. 82차 실측 `tkb.js get --csn 70424 --kb-sn 6874 --json` →
  `kbSn=6874` · `title=giip-fde-agent/KNOW-030_...md` · `tags=k-layer,ai-memory` · `refType=GENERAL` ·
  **`content = null`** — **등록은 성공했으나 본문이 저장되지 않았다.**
- 82차는 **새 행을 만들지 않고** 같은 `kbSn` 으로 본문을 다시 등록했다(rule 61 — 번호 미재배정 · 중복 등록 금지).
  저장소 노트가 커밋된 뒤에 등록하여 **본문 = 커밋된 노트 전문**이 되도록 맞췄다.
- `refType` 은 `GENERAL`(81차 등록 시값)이며, tKB 갱신 SP 가 `refType` 을 받지 않아 **변경되지 않았다**(잔여 사항).

## 별도 act 3 — 80차 기록의 dangling `§PR` 참조 정정

- 80차 기록(`.agent/work_history/20261103_1331_csn70424_repo-maintenance.md`)은
  "정본 게이트 전체(`scripts/gissue/run-repo-gates.ps1`)는 … 별도 백그라운드 실행했고, 그 결과는 **PR 생성 전 확인했다(아래 §PR)**" 라고
  적었으나 **해당 파일에 `§PR` 절이 존재하지 않는다**(80차는 PR 생성 전에 종료).
  → **82차가 `> 정정(2026-11-03, 82차)` 블록을 덧붙여** 어느 시점에·어떻게 마감되었는지를 남겼다.
  (과거 본문은 고쳐 쓰지 않는다 — rule 73)

## 별도 act 4 — `INDEX.md` 에 `KNOW-030` 행 추가

- `.agent/k_layer/notes/INDEX.md` 에 `KNOW-030` 행이 없어 색인에서 새 노트가 보이지 않았다 →
  **82차가 행을 추가**(kbSn 6874)하고, tKB 색인(kbSn 1303)도 같은 내용으로 갱신했다.

---

## 로컬 검증 (게이트) — 82차가 실제로 실행

### 1) 로컬 게이트 3종 (커밋 직전 · 스테이징 **후** 실행)

```
[MD-LINK] 마크다운 562개 · 전체 링크 1153건 · 상대링크 771건
[MD-LINK] 스캐폴딩(예외) 21건 · 실제 결함 0건           ← node scripts/gissue/lib/relative-links.mjs        exit 0
[PS1-PARSE] 결과: 검사 80개 전부 통과 (구문 + BOM)      ← powershell -File scripts/gissue/check-ps1-parse.ps1 -All   exit 0
[pre-push-guard] 가드 모듈 없음(비대상 레포) — 스킵        ← sh .agent/scripts/pre-push-pure-source-guard.sh .          exit 0
```

- **3종 모두 exit 0** — 실패를 성공으로 덮지 않았다.
- **스테이징 후 재실행한 값이다** — `relative-links.mjs` 는 `git ls-files` 기준이라 **새 파일은 스테이징 후에야**
  스캔 대상이 된다(스테이징 전 559개 → 스테이징 후 562개, 실제 결함 0건). 즉 이번에 추가한
  `KNOW-030` · 81차 기록 · 82차 기록 **3건이 스캔에 포함된 상태**다.
- 82차 커밋은 **`.md` 6건뿐**이라 ps1·mjs 회귀 대상 파일은 변경되지 않는다.

### 2) 정본 게이트 전체 (`scripts/gissue/run-repo-gates.ps1`)

- 실행 시간이 길어 **2026-11-03 16:46 에 별도 백그라운드로 실행**했다.
- **1차 실행은 백그라운드 실행 시간 제한(10분)에 걸려 중단됐다 — 완주하지 못했다.**
  즉 **로컬 전체 게이트 실행 결과는 "성공도 실패도 아닌 미완주"이며, 결과로 쓸 수 없다.**
- 검증은 **PR CI(Repo Gates)** 가 담당한다 — CI 는 동일 게이트를 PR 에서 실행한다.
  78차 기록과 동일한 처리("변경이 `.md` 뿐이라 ps1·mjs 회귀 대상 파일은 변경되지 않는다")이며,
  CI 결과는 **PR 본문에 기재**한다.
- **2차 실행을 같은 명령으로 다시 띄웠다(제한 시간 상향)** — 완주하면 그 결과를 PR 본문에 함께 기재한다.

> **정정(2026-11-03, 82차)** — 위 절의 최초 서술은 "로컬 백그라운드 실행의 종료 코드·요약을 PR 본문에 기재했다"
> 였으나, **1차 실행이 10분 제한에 걸려 중단**된 뒤에는 기재할 결과가 없었다. 실패를 성공으로 덮지 않고
> **미완주를 그대로 남긴다**(rule 42).

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 은 **2026-11-03 으로 유지**(이미 오늘 날짜 — 변경 없음).
- `## 2026-11-03` 섹션에 **81차 항목 1건 · 82차 항목 1건**을 80차 항목 뒤에 추가했다
  (섹션 내 항목은 회차 순 오름차순 배열 유지).
- **이관 0건** — 현재 섹션은 `2026-11-03` · `2026-11-02` · `2026-10-31` · `2026-10-30` · `2026-10-27` 이고,
  `2026-10-26` 이전은 이미 `docs/HISTORY.md` 로 이관했다(7일 창 = 2026-10-27 이후).
- **줄바꿈 주의** — 이 저장소는 `core.autocrlf=true` 라 `docs/WHATS_NEW.md` 는 **CRLF** 이다.
  새 항목은 **바이트 단위 CRLF** 로 삽입했다(LF 가 섞이면 diff 폭이 부풀어 보인다).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- 다른 저장소(lowyworkenv) 언급은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.
- 이슈 번호(4434·4411·4429·4334)는 추적성 표시용이며 고객 식별자가 아니다.

## 결과 저장처 / 소비처

- 수정/신규 파일:
  `.agent/work_history/20261103_1428_csn70424_repo-maintenance.md`(신규 — 81차 기록 **복원본**) ·
  `.agent/work_history/20261103_1623_csn70424_repo-maintenance.md`(신규 — 본 파일, 82차 기록) ·
  `.agent/work_history/20261103_1331_csn70424_repo-maintenance.md`(`> 정정` 블록 추가) ·
  `.agent/k_layer/notes/KNOW-030_staged_only_dead_session_output_is_invisible_to_pr_remote_ref_and_stash_checks.md`(신규) ·
  `.agent/k_layer/notes/INDEX.md`(`KNOW-030` 행 추가) ·
  `docs/WHATS_NEW.md`(81차·82차 항목 2건 추가)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-030`(스테이징만 하고 죽은 세션의 산출물이 4대 검사에서 모두 안 보이는 문제) ·
  `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다) ·
  `KNOW-028`(이 저장소 규칙 인용은 이 저장소에 있는 파일명만)

## 남은 사항 (후속)

1. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   78~81차가 미커밋 2건이 main 에 이미 존재함(중복 스냅샷)을 실측했으나 보류 판단은 유지한다
   (`KNOW-023` · rule 47 · rule 48). 사람이 확인 후 수동 제거가 필요하다.
2. **`giip 4434` 의 노트 번호** — `KNOW-029` 로 등록해야 한다(79차가 issue note 로 명시).
   4434 는 READY 상태이며 82차는 **상태를 바꾸지 않았다**. **이슈 처리 세션의 몫**이다.
   (82차 실측: 저장소 `KNOW-029` 0건 · tKB `[]` — 슬롯이 비어 있음이 확인됨)
3. **tKB `KNOW-030`(kbSn 6874) 의 `refType` 이 `GENERAL`** — tKB 갱신 경로가 `refType` 을 받지 않아
   다른 KNOW 노트와(`KNOWLEDGE`) 다르다. 잔여 사항이며 tKB 스키마/SP 개정이 필요한 사안이다.
4. **이 회차 PR 번호·머지 커밋·CI run id 는 이 기록의 작성 시점 미확정** — 다음 회차가 실측해 인계한다.
