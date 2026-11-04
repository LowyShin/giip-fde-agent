# CSN 70424 Repo Maintenance — 2026-11-04 10:07 (저장소 정비 94차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **94차 저장소 정비 세션** — 2026-11-04 10:07 KST. 이슈별 세션이 아니라 CSN 저장소 전체 스코프의
  [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- 직전 완료 회차 = **93차**(2026-11-04 07:32 KST · PR #362 merge `38402f6`). 그 뒤 **09:43 KST 에
  giip 4220 처리 세션**이 실행되어 PR #364(`4cdeaa6`)·PR #366(`f96df28`)을 머지했다 — 94차 기준
  `origin/main` = `f96df28`.
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-94-1030` (**신규 생성**) · 기준 `origin/main` = `f96df28`
- 작업 브랜치: `chore/csn70424-maint94-20261104-1030`
- 공유 체크아웃은 **커밋·스테이징 없이** 읽기 전용으로만 사용했다(저장소 락 미획득 — 아래 사유).
- 적용 role: `.agent/roles/orchestrator.md` · 적용 rule: `.agent/rules/55_destructive_cleanup_incident_gate.md`,
  `.agent/rules/60_giip_issue_link_format.md`, `.agent/rules/73_fix_wrong_docs_on_discovery.md`,
  `.agent/rules/76_keep_working_csn.md`, `.agent/rules/77_encoding_corruption_fix_on_discovery.md`

### 위임 판단 — Agent 도구(서브에이전트)를 쓰지 않은 사유

- 저장소 정비 러너는 git 조작(fetch/커밋·push·PR)을 **직접 수행**하도록 지시되어 있고(세션 프롬프트),
  이 회차 산출물은 **4단계 실측 결과 + 기록 2건**뿐이라 검증된 사실을 새 서브에이전트에 옮겨
  되돌려받을 대상이 없다. 위임하면 실측 근거가 서브에이전트 요약으로 희석된다(giip 1503 교훈).
- `MODEL_USAGE_SPEC.md`(경로 명시 — 이 저장소에는 없고 `lowyworkenv\MODEL_USAGE_SPEC.md`에 있다)의
  "MiniMax 메인 → Claude 폴백/QA" 원칙상, 이 세션은 이미 폴백 실행자다.

### 저장소 락 — **94차는 락을 획득하지 않았다**(사유 기록)

- 사전 락 요건은 **작업 CSN 의 workdir 이 lowyworkenv 자신일 때**의 것이다.
  `scripts/gissue/csn-projects.json` 실측 → `"70424": {"project":"giip-fde-agent","workdir":"C:\\Users\\lowys\\Downloads\\projects\\giip-fde-agent"}`
  — 70424 의 workdir 은 lowyworkenv 가 아니라 **giip-fde-agent** 다. 94차는 **lowyworkenv 를 커밋·push 하지
  않는다**(모든 산출물은 giip-fde-agent 워크트리).
- read-only 조회(`giipprj/giipdb/mgmt/listRecentCommentIssues.ps1`)만 lowyworkenv 밖 정본 스크립트로
  수행했고 **쓰기는 하지 않았다** — 남의 락을 빼앗지 않는다(rule 48).

## [0]/[E]/[F]/[H] 4단계 결과

| 단계 | 결과 | 실측 근거 |
|---|---|---|
| [0] PR 머지 충돌 | **대상 0건** | `gh pr list --repo LowyShin/giip-fde-agent --state open` → `[]` · `git ls-remote --heads origin` → `refs/heads/main` **1건뿐** · nested 관리 대상 저장소 **0건**(`ls -d */.git`·`ls -d */*/.git` → 0건) |
| [E] 열린 PR CI/검증 실패 | **대상 0건** | 열린 PR 0건 → 실패 체크 보유 PR 0건 · green 별도 확인: `gh run list --branch main --limit 6` → **6건 전부 success**(최신 `41751806515` = `f96df28` = HEAD) · 로컬 `run-repo-gates.ps1` **exit 0**(ps1 28 · mjs 5 · 링크스캔 1 · 실패 0건 · md 578 · 링크 1,174 · 상대 789 · 스캐폴딩 21 · **실제 결함 0건**) |
| [F] orphan stash / 워크트리 잔재 | **stash 1건 처리 · 워크트리 잔재 2건** | `git stash list` → `auto-unblock` 접두 **1건** — 본문이 giip 2855 의 **이미 등록된 코멘트 4건과 정규화 완전 동일**임을 실측 → 이관할 산출물이 아니므로 drop(산출물 0건) · `giip-fde-agent-isn4220`(PR #366 MERGED) 정본 도구 회수 **Removed 1건** · `maint-62-2331` **보류**(MANUAL-REVIEW) · `aux-sched-2645` **미접촉** · 머지 완료 로컬 브랜치 2건 정리 |
| [H] 최근 코멘트 논리 재검증 | **2시간 창 5건 · 24시간 창 12건** | 아래 §[H] — 93차 기록을 신뢰하지 않고 **직접 명령으로 전건 재확인** → **전건 일치**(식별자·행번호 표기 차이 2건은 실질 주장과 무관) → **정정 0건 · 전이 0건 · 이슈 쓰기 0건** |

**별도 act 2건** — ① **orphan stash 정리**(내용이 이미 이슈 코멘트로 전달됨을 실측 후 drop) ·
② **머지 완료 워크트리·로컬 브랜치 정리**(PR #366 머지 후 회수, PR #360·#363 머지 후 브랜치 삭제).
신규 KNOW 노트 없음(순수 0-target 회차) · tKB sync 대상 0건 · 이슈 쓰기 0건.

---

## [0] PR 머지 충돌 — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url` → **`[]`**.
  열린 PR 이 0건이므로 `mergeable=CONFLICTING` 대상도 0건 — 병합 편집·콘텐츠 보존 검증 게이트 대상이 없었다.
- 10분 이내 커밋 SKIP 판정 대상도 0건(열린 PR 자체가 없음).
- **원격 ref 확인(`KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다)**:
  `git fetch origin --prune` → `origin/docs/giip4220-verify-record` · `origin/feature/giip-4220-intent-route`
  **2건이 stale 로 정리**(둘 다 09:43 KST 세션이 머지·종료한 PR 의 잔재) → `git ls-remote --heads origin`
  → **`refs/heads/main` 1건뿐** → PR 없이 원격에 갇힌 브랜치 **0건**.
- nested 관리 대상 저장소 **0건** — `ls -d */.git`·`ls -d */*/.git` 0건(`.gemini/extensions/bkit` 는
  외부 원본 서브모듈이라 이 저장소의 PR 관리 대상이 아니다).

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → 실패 체크 보유 PR 0건 → 조치 대상 없음.
- **green 확인은 별도 수행했다**(열린 PR 이 없으면 자동 green 확인이 0건이므로):
  `gh run list --repo LowyShin/giip-fde-agent --branch main --limit 6` →
  `41751806515`(`f96df28`) · `41749416194`(`4cdeaa6`) · `41744407746`(`4637f84`) · `41739638333`(`38402f6`) ·
  `41725442433`(`396ce20`) · `41718856336`(`6fe4a0b`) → **6건 전부 success**. 최신 run 이 현재 HEAD(`f96df28`)와 일치.
- **로컬 게이트도 실행했다**(CI green 외에 "워크트리 green ≠ main green" 배제):
  `scripts/gissue/run-repo-gates.ps1` (공유 체크아웃, 기준 `f96df28`) → **exit 0** ·
  **ps1 28건 / mjs 5건 / 링크스캔 1 / 실패 0건** · 마크다운 578개 · 전체 링크 1,174건 · 상대링크 789건 ·
  스캐폴딩(예외) 21건 · **실제 결함 0건**.
- **산출물 추가 후 링크스캔 재실행** — 게이트 실행 시점에는 94차 작업 기록 파일이 아직 생성 전이라
  마크다운 수가 578개였다. 기록·What's New 갱신을 마친 뒤 워크트리에서 링크 스캔을 단독 재실행해
  새로 추가한 상대링크(What's New → 작업 기록)가 정상 해결됨을 확인한다(실제 결함 0건 유지).

## [F] orphan stash · 워크트리 · 로컬 브랜치

### stash 1건 — **drop**(이미 전달된 코멘트 본문 사본)

- `git stash list` → 1건:
  `On fix/giip-2855-entrypoint-phantom-dir: auto-unblock 2026-11-04 10:12:52: early unblock on fix/giip-2855-entrypoint-phantom-dir (merged into origin/main)`
- 구조: **추적 파일 변경 0건**(`git diff --name-status stash@{0}^1 stash@{0}` → 0줄) + **untracked 4개만**
  (`.agent/tmp/isn2855-claim.md` · `isn2855-result.md` · `isn2855-testresult.md` · `isn2855-usertest.md`).
- **소관 매칭(실측)** — `get-issue.sh 2855 70424` 로 giip 2855 의 코멘트 11건 본문을 받아
  stash 4개 파일과 **정규화(공백 제거) 완전 동일 비교**:
  | stash 파일 | 대응 코멘트 | 정규화 완전동일 | 정규화 길이 |
  |---|---|---|---|
  | `isn2855-claim.md` | 코멘트[7] `[진행 코멘트 — 착수]` | **true** | 902 = 902 |
  | `isn2855-testresult.md` | 코멘트[8] `[테스트 결과]` | **true** | 1,398 = 1,398 |
  | `isn2855-usertest.md` | 코멘트[9] `[사용자 테스트 방법]` | **true** | 1,057 = 1,057 |
  | `isn2855-result.md` | 코멘트[10] `[결과]` | **true** | 2,101 = 2,101 |
- **판정**: 4개 파일은 **giip 2855 의 이슈 코멘트로 이미 전달된 본문의 사본**이다(이슈 코멘트가 이 워크플로의
  전달 채널). PR 로 이관할 산출물이 아니며, `.agent/tmp/` 스코치 파일을 PUBLIC 레포에 커밋하는 것은 부적절하다.
  → **이관 없이 `git stash drop`** (내용은 이슈 DB 에 그대로 보존됨을 위 표로 입증).
  → drop 후 `git stash list` **0건**.
- stash 생성 주체는 스케줄러의 auto-unblock(브랜치가 이미 `origin/main` 에 머지돼 있어 잔재를 치운 동작)이며,
  **원격에 갇힌 브랜치가 아니다**(`git ls-remote --heads origin` → main 1건).

### 워크트리 잔재

| 경로 | 상태 | 94차 조치 |
|---|---|---|
| `D:\temp\worktrees\giip-fde-agent\maint-94-1030` | 브랜치 `chore/csn70424-maint94-20261104-1030` · HEAD `f96df28` | 94차 작업 워크트리(신규) — 본 세션이 커밋·PR·머지 후 회수 |
| `D:\temp\worktrees\giip-fde-agent-isn4220` | 브랜치 `docs/giip4220-verify-record` · HEAD `7f3153e` · clean · PR #366 **MERGED** | **정본 도구로 회수** — DryRun "제거 대상 1건" 확인 → 본 실행 **Removed 1건** · 로컬 브랜치도 함께 정리 |
| `D:\temp\worktrees\giip-fde-agent\maint-62-2331` | 브랜치 `chore/csn70424-maint64-20261102-0250` · HEAD `b10cf06` · 미커밋 `docs/HISTORY.md`·`docs/WHATS_NEW.md` | **보류** — 정본 도구 DryRun 재확인 결과 `ManualReview`(머지 PR 없음) · `KNOW-023` · rule 47·48 · 78·86·92·93차와 동일 판단 |
| `D:\temp\worktrees\giip-fde-agent\aux-sched-2645` | lowyworkenv 정식 등록 워크트리(`feat/giip-2645-fde-aux-schedulers`) | **미접촉** — idle 과 무관하게 건드리지 않는다 |

- 정본 도구 호출 위치(실측): **공유 체크아웃 cwd** 에서 실행 —
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent" -OnlyPath "D:\temp\worktrees\giip-fde-agent-isn4220" -MinIdleMinutes 0`
  (DryRun → 본 실행). `-OnlyPath` 는 **백슬래시 경로**여야 한다(슬래시면 조용히 0건 — 46차 실측).
  제거 후 인접 저장소 무결성 검증은 정본 도구(`worktree-safety.ps1` `Compare-GissueRepoIntegrity`)가 수행했고
  위반 0건이다.

### 로컬 잔여 브랜치 2건 — 정리

- `fix/giip-2855-entrypoint-phantom-dir` — PR #363 **MERGED**(`4637f84`) → 삭제
- `task/giip-2855-entrypoint-phantom-dir` — PR #360 **MERGED**(`6fe4a0b`) → 삭제
- squash 머지라 `git merge-base --is-ancestor` 판정이 불가능하므로 **머지 판정은 `gh pr list --state merged`** 로
  내렸다(rule 55 §4 — squash-merge 컨벤션). 정리 후 `git branch -a` → `main` + `origin/main` +
  워크트리에 묶인 2개(보류·본 세션)뿐, `git ls-remote --heads origin` → main 1건.

## [H] 최근 코멘트 논리 재검증 — 2시간 창 5건 · 24시간 창 12건 · **전건 일치 → 정정 0건**

- 조회: `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **5건**
  (4220 · 4219 · 2855 · 4231 · 4211) · `-HoursBack 24 -Json` → **12건**
  (+ 4434 · 4139 · 4431 · 4334 · 4222 · 4221 · 4411). **창 건수는 매 회차 실측** — 93차는 7건/10건이었다.
- **자기 코멘트 제외**: 94차는 **이슈 쓰기 0건**이므로 자기 코멘트도 없다.
- **코멘트 본문 읽기**: mgmt JSON 출력은 한글이 cp932 로 소실되고 `\/Date()\/` escape 가 깨지므로
  **API 경로(`get-issue.sh <isn> <csn>`)로 전건 직접 읽었다**(mgmt JSON 은 isn·status·작성시각 대조용).
- **판정 원칙(giip 1146 재발 방지)**: 마지막 코멘트를 신뢰하지 않고, 그 안의 **검증 가능한 사실 주장**을
  직접 조회로 재확인했다. [H] 의 조치 대상은 "틀린 사실 주장 + 그로 인해 잘못 잠긴(주로 REVIEW) 블로커"다.

### 재확인 결과 (저장소 기준 명시 — 오탐의 근본원인이 "엉뚱한 워크트리 조회"였으므로)

| isn | 상태 | 마지막 코멘트의 검증 가능한 사실 주장 | 94차 직접 재확인 | 결론 |
|---|---|---|---|---|
| 4220 | READY | PR #365 중복 close · PR #366 머지 `f96df28` · 변경 파일 1건 · 열린 PR 없음 | `gh pr view 366` → MERGED mc=`f96df28` · files 3건(작업기록 2 + `docs/WHATS_NEW.md`) · `gh pr list --state open` → `[]` | **일치**(변경 파일은 3건 중 1건 표기 — 부분 표기일 뿐 부정 주장 아님) |
| 4219 | READY | tPrivateKB(csn 70424) **kbSn 6918** 신규 등록 | `privatekb.py get --csn 70424 --kbsn 6918` → 제목·본문 일치 · `list --search 사후검증` → 1건 | **일치** |
| 2855 | REVIEW | PR #363 CI 전건 green · giipv3 PR #1000 CI 전건 green | `gh pr checks 363` → 3건 pass · `gh pr checks 1000 --repo SHINSEMA/giipv3` → 5건 pass | **일치** |
| 4231 | REVIEW | "정확 헤딩 `## Test Procedure` 는 본문에만 있고 코멘트 이력에는 없다" | 코멘트 3건 전문에 `^\s*##\s*Test Procedure` 정규식 카운트 → **0건** | **일치** |
| 4211 | REVIEW | "코멘트 이력 전체에 `## Test Procedure` 단 한 건도 없다" | 코멘트 4건 전문 정규식 카운트 → **0건** | **일치** |
| 4221 | READY | "작업 지시서를 task 유형 코멘트(**cSn=37800**)로 등록" | task 유형 코멘트 **실재**(`gicSn=37802`, 본문 = `[B/3] slack-bot intent.js 에 Jev …` 지시서) | **실질 주장 일치**(task 지시서 등록) · **식별자 표기만 37800↔37802 로 2 차이** → 조치 없음(보수적 · 블로커 미잠김) |
| 4222 | READY | "`grep -ni jev\|JEV_INTENT_ENABLED slack-bot/intent.js` → 0건" · "`INTENT_ROUTING_JEV_EVAL.md` 없음" | `git grep -E "jev\|JEV_INTENT_ENABLED" origin/main -- slack-bot/intent.js` → **exit 1(0건)** · `git cat-file -e origin/main:slack-bot/docs/INTENT_ROUTING_JEV_EVAL.md` → **부재** | **일치** |
| 4431 | READY | refine 지시서 등록·선점 해제(계획 서술) | 검증 가능한 부재/존재 주장 없음 | 조치 없음 |
| 4334 | DONE | `scripts/gissue/review-done-audit.ps1` 에 `[CHECKLIST-GUARD]` 존재 · 도입 PR #329/#334/#338/#345 | `git grep` **origin/main** → **343행**(발언은 342행 — **1행 드리프트**, 실질 일치) · 4개 PR 모두 MERGED, mc `de9759e`/`cb1d51c`/`c342b2b`/`d459b17` **전부 일치** | 조치 없음(행번호 1행 드리프트 · 블로커 미잠김 · DONE 정상 종결) |
| 4411 | DONE | KNOW-049 **kbSn 6835** · `regDt`/`modDt` 구분 · liveness 태스크 동작 | `tkb.js list --csn <lowyworkenv CSN> --search KNOW-049 --json` → kbSn 6835 · `regDt 2026-11-02T08:20:46.89` / `modDt 2026-11-02T10:40:25.383` → **라벨 구분 주장 일치** · `Get-ScheduledTask GIIP_GissueLiveness_Hourly` → State **Ready** · Enabled **True** | **일치** |
| 4139 | REVIEW | `[BUDGET]` 노트(예산 소진 안내) | 검증 가능한 블로커 주장 없음(정상 REVIEW 대기) | 조치 없음 |
| 4434 | READY | `[BUDGET]` 노트(동일) | 동일 | 조치 없음 |

- **종합** — 틀린 사실 주장 **0건** · 잘못 잠긴 블로커 **0건**(REVIEW 인 4139·4231·4211 은 각자 정상 대기 상태) →
  **정정 코멘트 0건 · 상태 전이 0건 · 이슈 쓰기 0건**. 식별자·행번호 표기 차이 2건(4221 cSn, 4334 행번호)은
  **부정 주장이 아니고 블로커를 잠그지 않으므로** 정정 대상이 아니라 기록으로만 남겼다.

## 이 저장소(PUBLIC) rule 54 자가 점검

- 이번 커밋에 **이 저장소 자신의 CSN(70424) 외 다른 CSN 번호 0건**, 고객·환경 특정 정보 0건.
- 이슈 번호(4220·4219·2855·4231·4211·4221·4222·4431·4334·4411·4139·4434)와 PR 번호(PR #360·#362·#363·#364·#366)는
  추적성 표시용이며 고객 식별자가 아니다. `MODEL_USAGE_SPEC.md` 인용은 **경로를 명시**했다.

## 결과 저장처 / 소비처

- 수정/신규 파일(94차 커밋 대상):
  `.agent/work_history/20261104_1007_csn70424_repo-maintenance.md`(신규 — 본 파일) ·
  `docs/WHATS_NEW.md`(수정 — 94차 항목 1건 추가)
- 소비처: 다음 회차 세션의 인수 매체 · `docs/WHATS_NEW.md` → `README.md` 최상단 링크 ·
  `KNOW-013`(기록의 완료·후속 서술은 실행되지 않은 계획일 수 있다) ·
  `KNOW-015`(원격에 남은 죽은 세션 브랜치는 PR 로 계승 · stale ref 는 prune) ·
  `KNOW-023`(오래된 스냅샷 워크트리는 커밋하면 회귀 PR · MANUAL-REVIEW 판정은 우회하지 않는다) ·
  `KNOW-030`(스테이징만 하고 죽은 세션의 산출물은 PR·원격ref·stash 검사에서 전부 안 보인다) ·
  `KNOW-033`(verify-runner exit 4 = 검증 미실행 · exit 1 = 검증 실패)

## 남은 사항 (후속)

1. **이 회차 PR 번호·머지 커밋·CI run id 는 이 기록의 작성 시점 미확정** — 적지 않는다.
   확정값은 **PR 코멘트**와 **다음 회차 기록**이 실측해 인계한다(기록에 예정형 서술을 남기지 않는다 — `KNOW-013`).
2. **`maint-94-1030` 워크트리 회수** — 이 PR 이 머지된 뒤 정본 도구
   (`cleanup-worktrees.ps1 -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-94-1030" -MinIdleMinutes 0`)로
   **공유 체크아웃 cwd 에서** 회수하고, 실행 결과(Removed 건수)를 PR 코멘트에 실측값으로 남긴다.
3. **`maint-62-2331` 워크트리 보류** — 정본 도구 판정 `MANUAL-REVIEW`(머지 PR 없음) 상태로 남는다.
   사람이 확인 후 수동 제거가 필요하다(`KNOW-023` · rule 47 · rule 48).
4. **`giip 4221` 의 task 코멘트 식별자** — 지시서 코멘트는 `gicSn=37802` 로 실재한다(발언은 37800).
   실질 주장(작업지시서 task 등록)은 일치하므로 정정 코멘트는 남기지 않았다. 다음 회차도 동일 기준으로 확인한다.
