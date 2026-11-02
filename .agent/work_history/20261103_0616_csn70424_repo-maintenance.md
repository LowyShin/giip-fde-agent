# CSN 70424 Repo Maintenance — 2026-11-03 06:16 (저장소 정비 76차)

## 세션 정체

- 작업 CSN: 70424 · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **76차 저장소 정비 세션** — 2026-11-03 06:08:05 KST 시작(스케줄러 `gissue_csn70424.log` 의 START).
  이슈별 세션이 아니라 CSN 저장소 전체 스코프의 [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- **이전 회차(75차) 계승**: 75차는 2026-11-03 03:18:51 에 시작해 **커밋·PR 없이 죽었다**
  (스케줄러 로그 `[2026-11-03 06:08:05] [CSN 70424] stale lock 제거 - PID 72788 죽음 + 시간초과(3h)`).
  75차 기록이 서술한 "커밋·PR 로 마감했다" 는 **실행되지 않았다** — 76차가 실측해 확인하고 마감했다.
- 적용한 규칙 파일(이 저장소 `.agent/rules/` 에 실재하는 것만 인용):
  `11_structured_commit.md` · `22_documentation_standards.md` · `29_tool_usage_and_verification.md` ·
  `33_artifact_hygiene.md` · `35_commit_push_per_task.md` · `36_whats_new_maintenance.md` ·
  `37_repo_url_in_report.md` · `41_issue_session_safety_index.md` ·
  `42_completion_by_execution_evidence.md` · `43_delegation_safety_block.md` ·
  `47_auto_cleanup_safety_requirements.md` · `48_single_source_safety_predicate.md` ·
  `50_bot_pr_scope_discipline.md` · `53_pre_push_pure_source_guard.md` ·
  `54_generic_agent_no_customer_info.md` · `55_information_lookup_order_and_feedback.md` ·
  `PROTOCOL_PROGRESS_COMMENT.md`
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-69-1308` (75차 워크트리 계승 · 신규 생성 안 함)
- 작업 브랜치: `chore/csn70424-maint76-20261103-0616` (`origin/main` `db2ed82` 기준)
- 공유 체크아웃 기준선: `git rev-parse HEAD` = `git rev-parse origin/main` = `db2ed82`, `git status --short` 비어 있음

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list --state open --json number,headRefName,url` → `[]`(열린 PR 0건). nested 관리 대상 저장소는 **0건** — `find . -maxdepth 4 -name .git` → 이 워크트리 기준 `./.git` **1건**뿐(공유 체크아웃 기준으로는 `./.gemini/extensions/bkit/.git` 까지 2건). bkit 는 외부 원본 서브모듈(`git submodule status` → `-a10e87ac0a27f9c11b8716e60f0b38af216d64bc` — 앞의 `-` 는 이 워크트리에서 미초기화)이라 PR 대상이 아니다 |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → CI 실패 검사 대상 0건. `gh run list --repo LowyShin/giip-fde-agent --limit 8` 실측 — **최근 8건 전부 `success`** (아래 표) |
| [F] orphan stash / 워크트리 잔재 | **stash 0건 · 워크트리 잔재 2건 실측 → 1건 계승·마감 · 1건 보류** | `git stash list` → **0건**(auto-unblock stash 없음). 워크트리 잔재 2건(`maint-69-1308` · `maint-62-2331`) 실측 후 아래 §[F] 에서 처리 |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 0건 · 24시간 창 5건 · 전건 일치** | `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **0건**. `-HoursBack 24` → **5건**(4411 DONE · 4429 DONE · 4334 PENDING · 4434 READY · 4431 PENDING). 5건의 마지막 코멘트 사실 주장을 **직접 조회로 재확인** → **전건 일치** → **정정 코멘트 0건 · 상태 전이 0건 · 이슈 쓰기 0건** (아래 표) |

### [E] 최근 CI run 8건 (전부 success)

| run id | branch | headSha | conclusion |
|---|---|---|---|
| 41430489808 | main | db2ed82 | success |
| 41430222762 | fix/overtime-log-port-output-leak-20261102 | 29825f8 | success |
| 41394112774 | main | f3ae1ed | success |
| 41393973543 | feat/giip4429-overtime-split-a1 | a182593 | success |
| 41384332988 | main | d459b17 | success |
| 41384168048 | fix/compare-script-pr-link-evidence | 0762adc | success |
| 41377808488 | main | 6bf6d93 | success |
| 41377247357 | chore/csn70424-maint68-20261102-1008 | ca9cd1d | success |

## [H] 최근 코멘트 논리 재검증 — 5건 전건 일치

- 조회: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\listRecentCommentIssues.ps1" -Csn 70424 -HoursBack 2 -Json` → **0건**
- 조회: 같은 스크립트 `-HoursBack 24` → **5건**: isn 4411(DONE) · 4429(DONE) · 4334(PENDING) · 4434(READY) · 4431(PENDING)
- **자기 자신 제외 대상 0건** — 76차가 남긴 코멘트는 없다.
- 5건의 `cSn` 을 `get-issue.sh` 로 전건 재확인 → **전건 `cSn: 70424`**(작업 CSN 일치).
- 시간축 주의(`KNOW-026`): JSON 의 `/Date(ms)/` 는 **DB 저장 UTC − 9h** 다. 2시간·24시간 창 판정은 SQL 측
  `DATEDIFF` 가 정확하므로 창 자체는 믿어도 된다. **읽을 때만 +9h** 를 보정한다.
- tKB 조회는 이 저장소가 아니라 **정본 lowyworkenv 체크아웃 cwd** 에서 실행했다
  (`scripts/gissue/tkb.js` 는 lowyworkenv 에 있다 — 이 저장소에는 없다).

| isn | 상태 | 마지막 코멘트의 검증 가능한 사실 주장 | 76차의 재확인 방법·결과 | 판정 |
|---|---|---|---|---|
| 4411 | DONE | 72차 정정 코멘트(regdate `2026-11-02T12:18:49Z`): ① tKB `KNOW-049`(lowyworkenv)= **kbSn 6835** · csn 33 · "regDt 2026-11-02T10:40:25.383" ② `GIIP_GissueLiveness_Hourly` = State **Ready** / Enabled **True** / Trigger StartBoundary `2026-11-02T00:37:00+09:00` / Action `check-gissue-liveness.ps1 -MaxSilentHours 3 -Notify -OpsCsn 70424` / LastTaskResult `0` ③ `scripts/gissue/logs/gissue_liveness_state.json` **불존재** ④ tKB `KNOW-021`(csn 70424)= **6805** ⑤ 정본 PR 340 · 이식 PR 1062 | `node scripts/gissue/tkb.js list --csn 33 --search "KNOW-049" --json` → **kbSn 6835** · csn **33** · `modDt 2026-11-02T10:40:25.383`(값 일치) · `regDt 2026-11-02T08:20:46.89` / `node scripts/gissue/tkb.js list --csn 70424 --search "KNOW-021" --json` → **kbSn 6805** / `Get-ScheduledTask -TaskName 'GIIP_GissueLiveness_Hourly'` → State **Ready** · Enabled **True** · StartBoundary `2026-11-02T00:37:00+09:00` · Action 인자 `-MaxSilentHours 3 -Notify -OpsCsn 70424` · WorkingDirectory `…\lowyworkenv\scripts\gissue` · LastTaskResult `0` · LastRun `2026-11-03 06:37:37`(정시 실행 중이라 자동 갱신 — 점시 관측값의 정상 갱신) / `ls scripts/gissue/logs/gissue_liveness_state.json` → **No such file** / `gh pr view 340` → MERGED `b10cf068` / `gh pr view 1062 --repo LowyShin/Lowyworkenv` → MERGED `0e0e7266` | 일치 |
| 4429 | DONE | Live 유지 결정 기록: lowyworkenv `scripts/gissue/lib/overtime-host-default.ps1` = `'Live'`(PR 1068) · `GISSUE_OVERTIME_SPLIT_MODE` 는 Process/User/Machine 모두 미설정 · 정본 giip-fde-agent 기본값은 Shadow · 18:52 관찰: `[OVERTIME] 결과 mode=Shadow reason=run steps=no-issue-in-flight final=NONE writes=0 errors=1` + 빈 `[OVERTIME][WARN]` | `grep -n HostDefaultMode scripts/gissue/lib/overtime-host-default.ps1` → **19: `$script:GissueOvertimeHostDefaultMode = 'Live'`** / 환경변수 3단계 **모두 미설정** / 정본 `scripts/gissue/lib/overtime-split.ps1:48` → `$v = … elseif ($env:GISSUE_OVERTIME_SPLIT_MODE) { … } else { 'Shadow' }` · `:52` default `'Shadow'` · 정본 `scripts/gissue/lib/` 에 `overtime-host-default.ps1` **없음**(호스트 상수 없음 → Shadow) / `gissue_csn70424.log` → `[2026-11-02 18:52:03] [CSN 70424] [OVERTIME] 결과 mode=Shadow reason=run steps=no-issue-in-flight final=NONE children= writes=0 errors=1` + `[2026-11-02 18:52:03] [CSN 70424] [OVERTIME][WARN] `(빈 줄) | 일치 |
| 4334 | PENDING | 체크리스트 판정 Live 전환 기록: lowyworkenv PR **1069** 머지 · 공유 체크아웃 반영 `35154499` · `checklist-host-default.ps1` 상수 `'Live'` · 해석 순서 param > env > 상수 · env `GISSUE_CHECKLIST_MODE` Process/User/Machine 모두 미설정 · 로그 증거 `gissue_csn47.log` `2026-11-02 18:13:18` → `체크리스트 판정 모드: Live (source=default-constant)` · 정본(giip-fde-agent)은 Shadow 유지 · 담당 CSN = enabled **14개**(2·33·47·70335·70371·70374·70417·70422·70423·70424·70426·70427·70428·70432, 70418 제외) | `gh pr view 1069 --repo LowyShin/Lowyworkenv` → MERGED · mergeCommit `351544992916a20d38459b3caf054ab405a1ae41` / `grep -n HostDefaultMode scripts/gissue/lib/checklist-host-default.ps1` → **20: `$script:GissueChecklistHostDefaultMode = 'Live'`** / 환경변수 3단계 **모두 미설정** / `grep -a "체크리스트 판정 모드" scripts/gissue/logs/gissue_csn47.log` → `2026-11-02 18:13:18` 행 **문자열 그대로 일치**(이후 3회 추가 관측도 동일) / 정본 `scripts/gissue/lib/` 에 `checklist-host-default.ps1` **없음** / `node -e` 로 `csn-projects.json` 의 enabled 14개 목록 **정확히 일치** · 70418 항목 **부재** | 일치 |
| 4434 | READY | **코멘트 0건**(`get-issue.sh 4434 70424` → `comments: []`) — 검증 대상 주장 0건 | 조회 결과 코멘트 없음 확인 | 대상 없음 |
| 4431 | PENDING | **코멘트 0건**(`get-issue.sh 4431 70424` → `comments: []`) — 검증 대상 주장 0건 | 조회 결과 코멘트 없음 확인 | 대상 없음 |

### 관찰(정정 대상 아님) — 4411 코멘트의 필드명 표기
- 72차 정정 코멘트는 tKB `KNOW-049` 의 **"regDt 2026-11-02T10:40:25.383"** 라고 적었으나,
  `tkb.js list --json` 실측에서 `2026-11-02T10:40:25.383` 은 **`modDt`** 이고
  **`regDt` 는 `2026-11-02T08:20:46.89`** 다(값 자체는 정확).
- 해당 코멘트의 결론("직전 코멘트(16:02 KST) 이후에 등록되었다")은 **regDt 기준으로도 성립**하므로
  [H] 정정 대상(성립하지 않는 사실 주장)이 아니다 → **이슈 쓰기 0건**으로 두고 여기만 기록한다.

### 이슈 상태 — 전부 유지 (전이 0건)
- 4411 DONE · 4429 DONE · 4334 PENDING · 4434 READY · 4431 PENDING — **5건 전부 변경하지 않았다.**
- [H] 는 READY 복귀까지만 허용하며 **TESTED/DONE 전이는 하지 않았다**.

## [F] 죽은 세션 워크트리 잔재 처리

- `git stash list` → **0건**. 그 자리에 워크트리 형태의 죽은 세션 잔재 2건을 실측했다.
- 표:
  | 워크트리 | 브랜치 / HEAD | 76차 처리 |
  |---|---|---|
  | `maint-69-1308` | `chore/csn70424-maint76-20261103-0616` / `db2ed82` (커밋 0건 · **미커밋 산출물 8건**) | **계승 → 실제 마감** |
  | `maint-62-2331` | `chore/csn70424-maint64-20261102-0250` / `b10cf06` (미커밋 2건) | **보류** |

### 1) maint-69-1308 — 70·71·75차 산출물 실제 마감 (핵심 처리)

75차가 워크트리를 실측한 결과, 74차(그리고 그 이전 70·71차)가 남긴 **미커밋 산출물 8건**이 있었다.

| 구분 | 파일 | 71·75차 기록의 서술 | 76차 실측 |
|---|---|---|---|
| 수정 | `.agent/k_layer/notes/INDEX.md` | "4개 칸 채움 + KNOW-027 행 추가 → 커밋" | **커밋 안 됨**(미커밋 수정) — 내용은 `KNOW-023`→6825 · `KNOW-024`→6826 · `KNOW-025`→6831 · `KNOW-026`→6832 · `KNOW-027`→6837 로 **실측값과 일치** |
| 수정 | `docs/WHATS_NEW.md` | "68차 항목 음절 복구 + 70·71차 항목 추가 → 커밋" | **커밋 안 됨**(미커밋 수정) |
| 신규 | `.agent/k_layer/notes/KNOW-025_llm_written_korean_can_be_silently_garbled.md` | "→ 커밋" | **untracked** |
| 신규 | `.agent/k_layer/notes/KNOW-026_giip_issue_regdate_is_utc_but_json_date_is_minus_9h.md` | "→ 커밋" | **untracked** |
| 신규 | `.agent/k_layer/notes/KNOW-027_runner_diagnostics_use_write_output_not_the_execution_log.md` | "→ 커밋" | **untracked** |
| 신규 | `.agent/work_history/20261102_1512_csn70424_repo-maintenance.md` (70차 기록) | "→ 커밋" | **untracked** |
| 신규 | `.agent/work_history/20261102_1723_csn70424_repo-maintenance.md` (71차 기록) | "→ 커밋" | **untracked** |
| 신규 | `.agent/work_history/20261103_0318_csn70424_repo-maintenance.md` (75차 기록) | "→ 커밋" | **untracked** |

- **핵심 발견 — 75차 기록의 "완료" 서술은 실행되지 않았다.** 75차 기록은
  "75차는 같은 워크트리에서 이어받아 커밋·PR 로 마감했다" 라고 적었으나 실제 커밋은 0건이다.
  75차의 `<!--GATE_RESULTS-->` 플레이스홀더가 비어 있는 것도 게이트 미실행의 증거다.
  → **76차는 이 사실을 `> 정정(...)` 블록으로 75차 기록에 명시**했다(rule 73 · `KNOW-013` · `KNOW-022`).
  **이것은 `KNOW-013` 의 2회 연속 재현**(71차 → 75차)이다. 신규 KNOW 노트는 만들지 않는다.
- **같은 거짓 서술의 다른 2곳도 함께 정정했다**(rule 73 — 같은 문구를 레포 전체에서 찾아 고친다):
  ① 70차 기록의 `> **정정(2026-11-03, 75차):**` 블록 안 "75차가 … 커밋·PR 로 마감했다" ·
  ② 71차 기록의 `> **정정(2026-11-03, 75차):**` 블록 안 "75차가 … 커밋·PR 로 마감했다" ·
  ③ `docs/WHATS_NEW.md` 의 71차 항목 본문 "… 규칙 61 에 따라 **커밋·PR 로 마감하고**" —
  ③ 은 `docs/WHATS_NEW.md` 에 이미 있던 65차 항목의 `> **정정(2026-11-02, 66차):**` 줄과 같은 형식으로
  71차 항목 바로 아래에 `> **정정(2026-11-03, 76차):**` 줄을 추가했다.
- **tKB 등록은 이미 되어 있었다**(rule 61 의 "등록은 커밋으로 성립한다" 가 깨지던 지점):
  `node scripts/gissue/tkb.js list --csn 70424 --search "KNOW-0NN" --json` 실측 —
  `KNOW-022`=**6817** · `KNOW-023`=**6825** · `KNOW-024`=**6826** · `KNOW-025`=**6831** ·
  `KNOW-026`=**6832** · `KNOW-027`=**6837**.
  즉 **tKB 행은 있는데 커밋이 없어 저장소에는 없던** 상태였다. 76차는 `INDEX.md` 의 kbSn 칸이
  이 실측값과 정확히 일치하는지 대조했다(일치) → **수정 없이 커밋**한다.
- **76차의 실제 처리**: 워크트리를 계승해 브랜치를 `chore/csn70424-maint76-20261103-0616` 로 재명명하고,
  정정 블록 추가 → 게이트 **실제 실행** → 명시적 경로 스테이징 → 커밋 → PR 생성.

### 2) maint-62-2331 — 보류(삭제하지 않음)

- 정본 도구(`cleanup-worktrees.ps1`) 판정은 "브랜치명에 머지된 PR 이 있는가" 기준인데,
  64차 산출물은 **다른 브랜치의 PR(#341)로 이관**되어 이 브랜치에는 머지 PR 이 없어
  영구히 `MANUAL-REVIEW` 로 남는다. **정본 도구 판정을 우회해 강제 삭제하지 않는다**(rule 48).
- 68차 실측: 워크트리의 미커밋 diff 를 `origin/main` 기준으로 대조한 결과
  `docs/HISTORY.md` 는 diff 0건, `docs/WHATS_NEW.md` 는 이미 main 에 머지된 65·66·68차 항목의
  되돌림이었다 → 워크트리 내용은 main 보다 **오래된 스냅샷**이며 커밋하면 회귀 PR 이 된다(`KNOW-023`).
- **보류 사유(기록)**: 정본 도구 판정을 우회하지 않는다. 사유를 기록하고 남긴다.

## 로컬 검증 (게이트) — 76차가 실제로 실행

76차는 **작업 워크트리 안에서** 아래 3종을 직접 실행했다(공유 체크아웃이 아니라 워크트리).

### 1) `node scripts/gissue/lib/relative-links.mjs`

```
[MD-LINK] 마크다운 547개 · 전체 링크 1143건 · 상대링크 761건
[MD-LINK] 스캐폴딩(예외) 21건 · 실제 결함 0건
```
- **exit code 0**

### 2) `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/check-ps1-parse.ps1 -All`

```
[PS1-PARSE] 결과: 검사 80개 전부 통과 (구문 + BOM)
```
- **exit code 0**

### 3) `sh .agent/scripts/pre-push-pure-source-guard.sh .`

```
[pre-push-guard] 가드 모듈 없음(비대상 레포) — 스킵
```
- **exit code 0** — 본 저장소는 가드 모듈 대상이 아니므로 스킵된다(스킵 = 통과, 차단 아님).

**3종 모두 exit 0** — 실패 없음, 실패를 성공으로 덮지 않았다.

## What's New 롤링 창 처리 (rule 36)

- `docs/WHATS_NEW.md` 상단 `기준일 (as of)` 을 **2026-11-03** 으로 갱신.
- `## 2026-11-03` 섹션을 **신규 생성**하고 **75차 항목 1건 + 76차 항목 1건**을 추가(최신 날짜 섹션이 맨 위).
- **이관 1건** — `## 2026-10-26` 섹션(기준일 2026-11-03 기준 **8일 경과** → 7일 창 초과)을
  `docs/HISTORY.md` 에 항목 단위로 이관했다(정보 손실 없이, 원문에서 `**` 마크업만 제목 쪽 제거).
  이관 형식(기존 형식과 동일):
  `- 20261026: What's New 롤링 7일 창 만료로 HISTORY 이관 — <원문 제목> — <원문 본문>`
  (원문 17개 항목 전부 이관 — 빠뜨리지 말 것. 옮긴 뒤 `## 2026-10-26` 섹션은 `docs/WHATS_NEW.md` 에서 제거.)
  - **배치 위치(76차 실측)**: `docs/HISTORY.md` 의 이관 블록은 **날짜 내림차순**이므로 17줄은
    **파일 끝이 아니라 첫 `- 20261025:` 줄(삽입 전 90행) 바로 위**에 넣었다.
    삽입 후 실측 — `- 20261026:` 첫 줄 **90행** · 17건 · `- 20261025:` 첫 줄 **107행** · 37건 ·
    `docs/HISTORY.md` 총 행수 **188 → 205**(+17) · `git diff --numstat` → **17 삽입 / 0 삭제**.
    (기존 파일에 `- 20261004`·`- 20261006` 같은 옛 항목이 63·64행에 있어, `^- 202610` 앞쪽 3줄로
    검증하면 이관 블록을 잡지 못한다 — `^- 2026102` 로 좁혀야 한다.)
  - **줄 형식**: 접두사 `- 20261026: What's New 롤링 7일 창 만료로 HISTORY 이관 — ` + **제목의 `**` 래퍼만 제거**
    + ` — ` + **본문은 `**` 를 제거하지 않고 그대로**(예: 본문의 `**#319**` · `**MERGED**` 유지) +
    끝의 `→ [작업 기록](...)` 링크 **그대로 유지**.
- **줄바꿈 주의**: 이 저장소는 `core.autocrlf=true` 라 `docs/WHATS_NEW.md` 와 `docs/HISTORY.md` 는
  **CRLF** 로 저장돼 있다. 새 줄은 **바이트 단위 CRLF** 로 저장했다(LF 로 섞으면 diff 폭이 부풀어 보인다).

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- `KNOW-025`·`KNOW-026`·`KNOW-027` 노트에도 **CSN 70424 외 번호·고객명·환경 이름을 넣지 않았다**(rule 54).
- 외부 저장소(lowyworkenv)를 언급한 부분은 **이 저장소의 스케줄러가 참조하는 정본 스크립트 경로**이며 고객 정보가 아니다.

## 문서 동기화 (giip 2377 4항목)

1. **정본 사양서 갱신** — **갱신 대상 없음**(저장소 위생 기록 회차이며 코드·동작 변경이 없다).
2. **유저가이드 갱신** — **갱신 대상 없음**(사용자 대면 동작 변경이 없다).
3. **k-layer + tKB** — `KNOW-025`(6831)·`KNOW-026`(6832)·`KNOW-027`(6837) 는
   70·71차가 tKB 등록을 **이미 실행**했으나 **커밋이 없어 저장소에 없던** 상태였다.
   76차는 **kbSn 을 실측 대조**(6817/6825/6826/6831/6832/6837 전건 일치)한 뒤 커밋으로 성립시킨다(rule 61).
   `KNOW-013`·`KNOW-022` 가 같은 교훈을 이미 담고 있어 **중복 신규 노트는 만들지 않았다**.
   → tKB 는 이번 세션에서 **신규 등록 0건 · 갱신 0건**(이미 등록된 행을 커밋으로 성립시키는 것이 이번 act).
4. **반영 파일 경로 전부** — 아래 §결과 저장처 / 소비처 에 나열.

## 결과 저장처 / 소비처

- 수정/신규 파일 10건을 나열하라:
  `.agent/work_history/20261103_0616_csn70424_repo-maintenance.md`(신규 — 본 파일, 76차 기록) ·
  `.agent/work_history/20261103_0318_csn70424_repo-maintenance.md`(수정 — 75차 기록, `> 정정(2026-11-03, 76차)` 블록 추가 · `<!--GATE_RESULTS-->` 대체) ·
  `.agent/work_history/20261102_1512_csn70424_repo-maintenance.md`(신규 — 70차 기록, `> 정정(2026-11-03, 76차)` 블록 추가) ·
  `.agent/work_history/20261102_1723_csn70424_repo-maintenance.md`(신규 — 71차 기록, `> 정정(2026-11-03, 76차)` 블록 추가) ·
  `.agent/k_layer/notes/KNOW-025_llm_written_korean_can_be_silently_garbled.md`(신규 — 70차 산출물) ·
  `.agent/k_layer/notes/KNOW-026_giip_issue_regdate_is_utc_but_json_date_is_minus_9h.md`(신규 — 70차 산출물) ·
  `.agent/k_layer/notes/KNOW-027_runner_diagnostics_use_write_output_not_the_execution_log.md`(신규 — 71차 산출물) ·
  `.agent/k_layer/notes/INDEX.md`(수정 — KNOW-023·024 kbSn 채움 + KNOW-025·026·027 행 추가) ·
  `docs/WHATS_NEW.md`(수정 — 기준일 갱신 + 2026-11-03 섹션 신규 + 75차·76차 항목 + 71차 항목 정정 줄 + 2026-10-26 섹션 이관) ·
  `docs/HISTORY.md`(수정 — `## 2026-10-26` 섹션 17개 항목 이관)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  tKB 지식 정본 색인(`INDEX.md`) · 정본 도구(`cleanup-worktrees.ps1`) 삭제 판정의 MANUAL-REVIEW 예시 ·
  `KNOW-025` → "긴 한글 요약은 원문 복사로만 안전" 판정 · `KNOW-026` → "JSON 시각은 +9h 보정" 판정 ·
  `KNOW-027` → "로그 지침이 `Write-Output` 대상이면 성립하지 않는다" 판정

## 남은 사항 (후속)

1. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW` 상태로 남는다(`KNOW-023` 참조).
   `chore/csn70424-maint64-20261102-0250` 분기에는 머지 PR 이 없어 자동 정리 대상이 되지 않는다.
2. **PR 상태** — 76차 PR 은 **생성만 하고 머지는 하지 않는다.** CI(Repo Gates 워크플로) 판정으로
   최종 확인한다. (PR 번호는 커밋 시점에 아직 없으므로 기록에 넣지 않는다. 후속 회차가 실측해 기록한다.)
3. **원격 잔여 브랜치 `fix/overtime-log-port-output-leak-20261102`** — PR #347 이 MERGED 인데 원격 ref 가
   남아 있다. 76차 실측 결과 `git diff origin/main origin/fix/overtime-log-port-output-leak-20261102` 가
   **빈 출력**(내용이 이미 main 에 있음) → 정리 대상. **76차는 이 정리(원격 브랜치 삭제)를 하지 않는다**
   (PR 머지 후 후속 세션이 정리할 항목). 사유를 여기 남긴다.
4. **로컬 고아 브랜치 3건**(`chore/csn70424-maint69-20261102-1308` · `chore/csn70424-maint70-20261102-1512` ·
   `chore/csn70424-maint71-20261102-1900`)은 `git branch --merged origin/main` 에 모두 포함된다
   (즉 전부 머지 완료) → 정리 대상. **76차는 삭제하지 않고 사유만 남긴다.**
5. **giip 4429 note 의 확인 경로** — lowyworkenv 러너의 시작 모드 줄을 로그에 남기려면
   `Write-Output` → `Write-Log` 변경 또는 스케줄러 태스크 stdout 리다이렉트 추가가 필요하다.
   **lowyworkenv 는 본 세션의 작업 범위 밖**이라 수정하지 않았다. 정본(giip-fde-agent) 러너는
   시작 모드 줄 자체가 없어 정본 쪽 조치도 불필요하다(`KNOW-027`).
