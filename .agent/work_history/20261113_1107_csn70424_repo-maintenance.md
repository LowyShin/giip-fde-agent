# CSN 70424 저장소·PR 레벨 정비 110차 (2026-11-13 11:07 KST)

> 세션 성격: **저장소/PR 레벨 정비**(CSN 70424 저장소 전체 스코프) — 단일 이슈 처리가 아니다.
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증
> 4축을 돌고, **워크트리 인벤토리·회수 1건**과 **stale 로컬 브랜치 정리 1건**까지만 수행했다.
> **코드 변경 0건 · 이슈 쓰기 0건 · 상태 전이 0건.**

## 착수 상태 점검

- 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` — 세션 시작 시 이미
  로컬 `main` == `origin/main` == `a139f35` 로 **ff-sync 상태**였다
  (직전 회차의 PR #408 머지본 `102a2e2` 와 PR #409 머지본 `a139f35` 가 모두 반영된 상태).
  `git fetch origin --prune` 로 고아 추적 ref 정리. **ff-sync 불필요.**
- 공유 체크아웃은 **읽기 전용**으로만 썼다(커밋·스테이징 0건).
- 작업 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-110-1115`
  (브랜치 `chore/csn70424-maint110-20261113-1115`, base = `origin/main` `a139f35`).
  **머지된 브랜치를 재사용하지 않고** `origin/main` 에서 새로 분기했다.
- 사전 락 불요 — 이 저장소는 CSN 70424 소관이며 lowyworkenv 자신(다른 CSN)이 아니다
  (`scripts/gissue/csn-projects.json` 매핑 실측: csn 70424 → giip-fde-agent, lowyworkenv 자신은 다른 CSN 매핑).
  프롬프트의 "대상 저장소가 lowyworkenv 자신의 CSN 일 때만 락" 조건 = false → 락 미획득·미해제.

## [0] PR merge conflict — 대상 0건

- `gh pr list --state open --repo LowyShin/giip-fde-agent` → **0건** → 병합충돌 대상 0건 · 조치 0건.
- nested 관리 대상 레포 0건 — `find . -maxdepth 3 -name .git` 결과 저장소 자신만 나오고,
  서브모듈은 외부 벤더(`.gemini/extensions/bkit`) 하나뿐이라 PR 대상이 아니다.
- 원격 ref = `main` + orphan 3건 `bot/task-giip-4804/4805/4806`.
  **소유 축을 직접 재확인**했다 — `scripts/gissue/get-issue.sh <isn> 70424` 응답 본문의 `cSn` 을
  읽으니 3건 전부 **이 세션 CSN(70424) 밖(타 CSN)** 이었다(105차 KNOW-043 축).
  ⇒ 소유축 미통과 → **계승·삭제·쓰기 0건**(rule 76 · rule 46).
  (타 CSN 번호는 이 공개 저장소 기록에 쓰지 않는다 — 규칙 54.)

## [E] 열린 PR 의 CI/검증 실패 — 대상 0건

- 열린 PR 0건 → CI 실패 대상 0건.
- 원격 CI 상태 — `gh run list` 실측:

| run | 대상 | 결과 |
|---|---|---|
| `43349036203` | `main` push (PR #409 머지본 `a139f35`) | **success** |
| `43348746664` | PR #409 pull_request | **success** |
| `43347772440` | `main` push (PR #408 머지본 `102a2e2`) | **success** |
| `43347434343` | PR #408 pull_request | **success** |

- 로컬 게이트 `scripts/gissue/run-repo-gates.ps1` **2회** 실행(공유 체크아웃 `main` 기준 · 세션 워크트리 기준):

| 시점 | ps1 | mjs | 링크스캔 | 실패 | exit |
|---|---|---|---|---|---|
| 공유 체크아웃(`main` = `a139f35`) | 38건 | 7건 | 1 | 0건 | 0 |
| 세션 워크트리(`maint-110-1115`) | 38건 | 7건 | 1 | 0건 | 0 |

- 마크다운 상대링크 스캔(양쪽 동일) — 마크다운 **616개** · 전체 링크 **1,262건** · 상대링크 **860건** ·
  스캐폴딩(예외) **21건** · **실제 결함 0건**.
- 게이트 기대값과 실측이 일치한다 — `scripts/gissue/run-repo-gates.ps1` 의
  `$ExpectedPs1TestCount = 38` · `$ExpectedMjsTestCount = 7` 과 실측 수치가 같다
  (기대 건수가 **하한선**이므로 일치만으로는 "사라짐" 이 증명되지만, 수치가 정확히 같음을 확인했다).

## [F] Orphan `auto-unblock ` stash — 대상 0건

- `git stash list` → **빈 목록**(0건) → 오판 stash 0건.
- nested 관리 대상 레포가 없어 그쪽도 0건.

## [H] 최근 코멘트 논리 재검증 — 2시간 창 10건 / 24시간 창 44건, **정정 0건**

`listRecentCommentIssues.ps1 -Csn 70424 -HoursBack {2|24} -Json` 로 직접 뽑고,
**코멘트 본문을 신뢰하지 않고** 명령 출력으로 전건 대조했다.

- 2시간 창 → **10건**(작성자: 사람 계정 3 · `gissue-scheduler-watchdog` 7).
- 24시간 창 → **44건**(작성자: watchdog 24 · 사람 계정 15 · `gissue-agent` 5).
  2시간 창 항목은 24시간 창에 전부 포함된다(부분집합).

### 1) watchdog 상태 주장 — **기계 대조**

`[BUDGET]` 코멘트는 `(isn=N, status=STATUS)` 형태로 자기 상태를 명시한다.
이를 목록 조회 결과의 `isn`·`status` 와 **정규식으로 뽑아 기계 대조**했다.

| 창 | 상태 주장 건수 | 일치 | 불일치 |
|---|---|---|---|
| 2시간 | 7건 | **7건** | 0건 |
| 24시간 | 22건 | **21건** | 1건(`4116` — 아래 별도 항목) |

- `4116` 의 `STALE_IN_PROGRESS` 는 API status `IN_PROGRESS` 의 **큐 파생 라벨**이다 —
  `scripts/gissue/list-issues.js:142` 의 `{ status: 'IN_PROGRESS', label: 'STALE_IN_PROGRESS', qprio: 0, minAge: 60 }`
  가 큐 조회 단계에서 라벨을 바꾼 것이므로 **거짓 주장이 아니다** → 정정하지 않는다.

### 2) watchdog `[SKIP-REASON]` (4300 · 4211) — 쿨다운 임계값

- 주장: "REVIEW/TESTED 재검증 쿨다운(마지막 재검증 후 4시간 미만, 새 사람 신호 없음)".
- 재확인: `scripts/gissue/run-gissue-claude.ps1:159` 의 `$ReviewRecheckCooldownHours = 4` 와 일치 ·
  두 이슈의 API status 도 `REVIEW` → **일치**.

### 3) 세션 결과 노트 `5053` — PR #406 파일 목록 주장

- 주장: "PR #406 MERGED(squash) · CI 3종 green · 파일 5건" + 각 파일 +/− 수 + "ExpectedPs1TestCount 36→37".
- 재확인: `gh pr view 406 --repo LowyShin/giip-fde-agent --json files` 실측 —

  | 파일 | 실측 | 주장 |
  |---|---|---|
  | `docs/60-operations/aux-hourly-schedulers.md` | +4/-3 | +4/-3 ✓ |
  | `docs/WHATS_NEW.md` | +1/-0 | +1 ✓ |
  | `scripts/gissue/manage-gissue-scheduler.ps1` | +2/-1 | +2/-1 ✓ |
  | `scripts/gissue/run-repo-gates.ps1` | +2/-1 | +2/-1 ✓ |
  | `scripts/gissue/tests/test-manage-gissue-scheduler.ps1` | +76/-0 | +76 ✓ |

- 문서 정합: `docs/60-operations/aux-hourly-schedulers.md` 가 "보조 스케줄러 **6종**" 이고
  `GIIP_GissueLiveness_Hourly` 행이 존재 → 5종→6종 주장 **일치**.
- "ExpectedPs1TestCount 36→37" 은 **PR #406 시점의 값**이고 현재 값은 **38** 이다 —
  뒤이어 머지된 PR #407 이 회귀 테스트 1건을 더 추가했다. **시점 차이일 뿐 거짓 주장이 아니다.**

### 4) 세션 결과 노트 `5054` · `5101` — 실행 근거 주장

두 노트는 "PR #407 로 이미 구현·머지됐다 + 완료조건 PASS" 를 근거로 READY → DONE 전이한 기록이다.
**코멘트를 믿지 않고 같은 명령을 직접 재실행**해 확인했다.

| 근거 항목 | 재실행 결과 |
|---|---|
| `node scripts/gissue/verify-runner.mjs 5054 70424 --json` | `"status": "PASS"`, exit 0 · 블록 2건 exit 0 (`OK: -LogDir 지정 시 지정 경로의 락이 보인다` / `OK: 기본 경로 동작이 유지된다`) |
| `scripts/gissue/tests/test-manage-gissue-scheduler-logdir.ps1` | `ALL PASS`, exit 0 · **음성 대조 (E) 절** — `$LogDir` 파라미터가 제거된 사본이 검출되지 않음을 **실제로 확인**(상시 PASS 기열 아님) |
| `scripts/gissue/check-ps1-parse.ps1 -Path scripts/gissue/manage-gissue-scheduler.ps1` | `검사 1개 전부 통과 (구문 + BOM)`, exit 0 |
| PR #407 | `gh pr view 407` → **MERGED**, merge 커밋 `41de980` — `origin/main`(`a139f35`)에 반영됨을 `git log` 로 확인 |
| `5101` | 자체 verify 블록이 없어(verify-runner exit 2 = 블록 없음) **동일 요구 범위**의 원본 완료조건 실행 결과로 뒷받침 — 원본과 요구 동일 |

⇒ **정정 코멘트 0건 · [H] 로 인한 상태 전이 0건 · 이슈 쓰기 0건.**

## 별도 act — 0건

109차에서 READY 로 되돌릴 잔여 이슈가 남아 있지 않아, 이번 회차엔 **상태 전이 0건**이다.
(READY 는 경과 60분 뒤 작업 큐에 재진입하므로 — `scripts/gissue/list-issues.js` 의 `--queue` 정책 —
READY 상태로 방치된 이슈가 있으면 다음 :07 실행이 되풀이한다. 이번 24시간 창에 그런 잔여는 확인되지 않았다.)

## 워크트리 인벤토리 · 회수

### 회수 1건 — `maint-109-corr-1057`

- 직전 회차의 KNOW-045 정정 PR **PR #409**(MERGED `a139f35`) 머지 후 남아 있던 워크트리.
  clean · 고유 커밋 0 · PR 머지 확인됨.
- 정본 정리 도구로 회수(공유 체크아웃 cwd · 백슬래시 경로 · DryRun 먼저):
  `scripts/gissue/cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent" -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-109-corr-1057" -MinIdleMinutes 0`
  → **Removed 1건**. 로컬 브랜치 `chore/csn70424-know045-correction-20261113-1057` 와
  **원격 ref 가 함께 정리**됨을 `git branch -a` · `git ls-remote --heads origin` 로 확인했다.

### stale 로컬 브랜치 1건 정리 — `worktree-agent-a59e8d2e3d5f445dd`

- 직전 회차의 Claude Code 내부 워크트리(`<repo>/.claude/worktrees/agent-...`)가 남긴 로컬 브랜치.
  워크트리 디렉터리는 이미 없고 등록도 `git worktree list` 에서 사라진 상태였으나
  **로컬 브랜치만** 남아 있었다(`102a2e2`).
- `git merge-base --is-ancestor worktree-agent-a59e8d2e3d5f445dd origin/main` → **true**
  (PR #408 머지본이 `origin/main` 의 조상) → 손실 위험 0 확인 후 `git branch -d` 로 정리(정상 종료).

### MANUAL-REVIEW 4건 — 미접촉

정본 정리 도구의 `MANUAL-REVIEW` 판정은 **우회하지 않는다**(78차 교훈).

| 워크트리 | 판정 사유 | 비고 |
|---|---|---|
| `maint-62-2331` | 브랜치에 PR 없음 | 미커밋 2건(`docs/HISTORY.md` · `docs/WHATS_NEW.md`) — 기존 보류 유지 |
| `giip-5054-refine` | 브랜치(`docs/giip-5054-task-directive`)에 PR 없음 | 스테이징된 `.agent/tasks/giip-5054.md` 는 `origin/main` 사본과 **바이트 동일**(152줄) — 유실 위험 없음 |
| `verify-4139-c7` | detached HEAD | clean · HEAD == PR #407 머지 이전 커밋 |
| `verify-5054-main` | detached HEAD | clean · HEAD == PR #407 머지본 `41de980` — **detached 워크트리는 자동 회수 경로가 없다**(k-layer KNOW-045) |

### 공유 체크아웃의 미커밋 산출물 — 미접촉

- untracked 3건(`.tmp-gissue-5054-*.md`)은 5054 세션이 남긴 코멘트 본문 임시 파일이다.
  **타 세션 산출물이므로 삭제·스테이징하지 않았다**(정비 세션은 남의 미커밋 변경을 손대지 않는다).
- `.claude/`(untracked) 아래의 `worktrees/` 는 위 내부 워크트리 회수 후 빈 디렉터리로 남아 있다.

## k-layer / tKB

- **신규 없음** — 기록만 하는 회차이므로 k-layer 노트를 새로 만들지 않았다.
  (`tkb.js sync-klayer` 는 **신규 k-layer KNOW 노트를 만들었을 때만** 쓴다 — 대상 0건.)

## 규칙 54 자기검사 — 다른 CSN 식별자 2건(신규 기록) + 2건(직전 회차 기록) 치환

규칙 54("범용 에이전트 — 특정 고객정보를 이 레포에 넣지 않는다")의 자기검사를 커밋 전에 돌렸다.
추가 줄에서 CSN 형태 숫자를 뽑아 확인한 결과, **이 저장소 자신의 CSN 이 아닌 다른 CSN 번호**가 나왔고,
**지금 쓰던 표현("저장소 락 판정 기준 CSN 의 번호")이 정확히 그 지점**이었다.

- **신규 기록(본 파일) 2건** — 사전 락 설명 문장에서 다른 CSN 의 번호를 직접 적고 있었다.
  ⇒ **식별자만 치환**(`<번호>` → "다른 CSN") — 나머지 본문은 한 글자도 바꾸지 않았다.
- **직전 회차 기록 1건(109차 파일) 2건** — 1시간 전 세션이 **같은 문장**으로 같은 위반을 넣었다.
  ⇒ 규칙 73(발견 즉시 그 처리 단위에서 수정) + 규칙 54 의 "과거 기록은 **식별 부분만** 치환" 근거로
  **같은 PR 에서 함께 치환**했다(기술적 주장의 오류가 아니라 식별자 치환이라 정정 블록은 붙이지 않았다).
- **저장소 전체의 잔여 백로그는 이번 PR 범위 밖** — `git grep` 기준 다른 CSN 식별자가 남은 파일이
  **118건** 있으나, 규칙 54 본문의 "정리 대기 중인 알려진 위반 후보" 절이
  "**이 규칙 PR 은 이들을 수정하지 않으며, 별도 후속 정리 대상**이다 / **새로 만드는 기록은** 이 규칙을 따른다"
  로 명시하고 있다 ⇒ **이번에 건드리지 않고 후속 정리 대상으로만 기록**한다.
  (91차의 선례: 숫자만 제거 · 과거 본문 무변경 · 바이트 단위 치환으로 줄바꿈 불변 확인 — 이번에도 동일 방식)

## 결과 요약

- [0] 병합충돌 0건(열린 PR 0 · nested 0) ·
  [E] CI 실패 대상 0건(원격 run 4건 success · 로컬 게이트 공유 체크아웃·워크트리 **양쪽 exit 0** —
  ps1 38 / mjs 7 / 링크스캔 1 / 실패 0건 / 마크다운 616·링크 1,262·상대 860·스캐폴딩 21·**실제 결함 0건**) ·
  [F] 오판 stash 0건 ·
  [H] 2시간 창 10건 · 24시간 창 44건 — **정정 0건 · 상태 전이 0건 · 이슈 쓰기 0건**.
- 별도 act **0건**(READY 잔여 0건) · **코드 변경 0건**.
- 워크트리 회수 **1건**(`maint-109-corr-1057`, 로컬·원격 브랜치 정리 포함) ·
  stale 로컬 브랜치 정리 **1건**(`worktree-agent-a59e8d2e3d5f445dd`) ·
  MANUAL-REVIEW 4건 미접촉.
- orphan 원격 브랜치 3건 — 소유축 재확인 결과 **타 CSN** → 계승·삭제·쓰기 0건.
- 성역(giipApi/giipApiSk2) 미접촉 · main 직접 push 없음 · PR 경유.

## 남은 사항 (다음 회차가 이어받을 것)

- MANUAL-REVIEW 4건은 사람이 판단해야 회수된다(특히 detached HEAD 2건 — 자동 회수 경로 없음).
- `maint-62-2331` 의 미커밋 2건은 기존 보류 상태를 유지한다(105차 KNOW-023 근거).
