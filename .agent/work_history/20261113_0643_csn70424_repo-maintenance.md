# CSN 70424 저장소·PR 레벨 정비 107차 (2026-11-13 06:43 KST)

> 세션 성격: **저장소/PR 레벨 정비**(CSN 70424 저장소 전체 스코프) — 단일 이슈 처리가 아니다.
> 106차 세션이 남긴 산출물(워크트리 `maint-106-0235`)을 **계승**해 **직접 실행으로 검증**하고,
> 규칙 자가점검에서 걸린 항목을 교정한 뒤 PR 로 land 하고, 106차 기록에 대한 **사후 기록**을 남긴다.

## 착수 상태 점검

- 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` — `git status` clean, `main` = `1d7366c`
  (origin/main 보다 1커밋 뒤처짐). 작업은 전용 워크트리에서 진행하고 공유 체크아웃은 **커밋하지 않았다**.
  작업 시작 후 `--ff-only` 로 `a533600` 까지 갱신했다(읽기 전용 공유 체크아웃의 동기화 — 커밋 없음).
- 계승 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-106-0235`
  (브랜치 `chore/csn70424-maint106-20261113-0235`, base = `origin/main` `1d7366c`).
- 사후 기록 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-107-0643`
  (브랜치 `chore/csn70424-maint107-20261113-0643`, base = `origin/main` `a533600`).
  **머지된 브랜치를 재사용하지 않았다** — 같은 브랜치 재사용은 다음 PR 을 구조적으로 CONFLICTING 으로 만든다(46차 실측).
- 사전 락 불요 — 이 저장소는 CSN 70424 소관이며 lowyworkenv 자신이 아니다(104·105·106차 기록과 동일).

## 계승 산출물 — 보고서가 아니라 **직접 실행**으로 검증했다

106차 세션의 산출물을 그 세션의 보고서만 믿고 받아들이지 않고, **이번 세션이 직접 실행**해 확인했다.

| 검증 대상 | 방법 | 결과 |
|---|---|---|
| 신규 회귀 테스트(수정 후) | `test-worktree-merge-gate-failclosed.ps1` 직접 실행 | **PASS=18 / FAIL=0 · exit 0** |
| **수정 전 코드**에 같은 테스트 | `origin/main` 원본 `worktree-safety.ps1` + 신규 테스트 | **PASS=10 / FAIL=8 · exit 1** — B-1 이 `removed=...wt-candidate` 로 **삭제 예약 자체를 잡아냄** (fail-open 직접 증명) |
| 저장소 전체 게이트 | `run-repo-gates.ps1` 직접 실행 | **ps1 36건 / mjs 7건 / 링크스캔 1 / 실패 0건 · exit 0** |
| PS1 구문+BOM | 게이트 단계 1 | **검사 92개 전부 통과** |
| 마크다운 상대링크 | 게이트 단계 4 | **마크다운 611개 · 링크 1250건 · 실제 결함 0건** |
| 106차 수정이 `origin/main` 에 없었음 | `git show origin/main:scripts/gissue/worktree-safety.ps1` | 수정 전 상태 — 계승 근거 성립 ✓ |
| 인코딩 | 5개 파일 전부 strict UTF-8 디코드 | **FFFD=0 · C1 제어문자 0건** · `.ps1` 3종 BOM 유지 ✓ |

## [0] PR merge conflict — 대상 0건

- 착수 시 `gh pr list --state open` → **0건** → 병합충돌 대상 0건 · 조치 0건.
- nested 관리 대상 레포 0건(외부 벤더 서브모듈 `.gemini/extensions/bkit` 만 존재).
- 원격 ref = `main` + 타 CSN 소관 `bot/task-giip-4804/4805/4806` 3건.

## [E] 열린 PR CI/검증 실패 — 대상 0건

- 열린 PR 0건 → CI 실패 대상 0건.
- **이번 세션이 만든 PR #403** 의 CI 3종 — **PS1 게이트(1m42s) · MJS 게이트(36s) · GitGuardian(1s) 전건 SUCCESS**
  (병합 전에 `gh pr checks --watch` 로 확인했다). 병합 후 `origin/main` 에 `a533600` 으로 반영된 것까지 확인.

## [F] Orphan `auto-unblock ` stash — 대상 0건

- `git stash list` → **빈 목록**(0건) → 오판 stash 0건.

## [H] 최근 코멘트 논리 재검증 — 2시간 창 24건 / 24시간 창 43건, **정정 0건**

`listRecentCommentIssues.ps1 -Csn 70424 -HoursBack {2|24} -Json` 로 직접 뽑고, **코멘트를 신뢰하지 않고**
이슈별 `get-issue.sh <isn> 70424` 로 전건 재조회해 대조했다.

| 검증 항목 | 결과 |
|---|---|
| 작업 CSN 일치 | **43건 전건 `cSn` = 70424** ✓ (이 CSN 밖 이슈 없음) |
| BUDGET 코멘트의 `isn`/`status` 주장 | 18건 중 **17건은 API 실조회 상태와 정확히 일치** |
| 나머지 1건(isn 4116) | 코멘트는 `status=STALE_IN_PROGRESS`, API 상태는 `IN_PROGRESS` — **큐 파생 라벨**이라 오정이 아니다. `scripts/gissue/list-issues.js:142` 가 `{ status: 'IN_PROGRESS', label: 'STALE_IN_PROGRESS', ... }` 로 API 상태와 반환 라벨을 분리한다. **상태를 고쳐 쓰지 않았다** |
| 스케줄 태스크 주장 | `GIIP_Gissue_Claude` = **Running / PT1H** · Action → `run-gissue-claude.ps1` · LastTaskResult **267014** ✓ / `GIIP_GIssueLiveness_Hourly` = Ready / PT1H · Action → `check-gissue-liveness.ps1 -MaxSilentHours 3 -Notify -OpsCsn 70424` · LastTaskResult **0** ✓ |
| 죽은 프로세스 락 주장 | PID **70504 DEAD** ✓ (프로세스 없음) |
| 정본 반영 주장 | PR #389 **MERGED** · merge 커밋 `22bc20b` · `git merge-base --is-ancestor` 기준 **`origin/main` 의 조상** ✓ |
| 무소식 회복 주장 | `check-gissue-liveness.ps1` **exit 0** · "CSN 14건 모두 최근 3h 이내 처리 흔적(또는 처리 중)" · CSN 70424 로그 0.55h 전 ✓ |
| isn 4434 완료 주장 | `test-overtime-findchildren-port.ps1` **재실행 → 전체 통과 · exit 0** ✓ |
| isn 4681 완료 주장 | 게이트가 스캔한 5개 저장소 전부 `--search "4681"` → **PR 0건** ✓ · `[NO-PR-REASON]` 마커 존재 ✓ · 상태 DONE ✓ |

⇒ **[H] 규칙대로 조용히 통과**: 정정 코멘트 0건 · 상태 전이 0건 · 이슈 쓰기 0건.

## 별도 act — 106차 산출물에 대한 규칙 자가점검 교정

### ① 규칙 54(범용 에이전트 — 특정 고객정보 금지)

이 저장소는 PUBLIC 범용 에이전트다. **이 저장소 자신의 CSN(70424) 은 예외**지만 **타 CSN 번호는 금지**다.

- 106차 기록에 남아 있던 **타 CSN 번호 표기 1건** → `타 CSN(<csn>)` 로 일반화했다.
- 규칙 54 가 제시한 예시 grep `\b7[0-9]{4}\b` 는 **번호가 식별자 뒤에 붙어 있는 형태를 놓친다**
  (식별자 마지막 글자와 숫자 사이에 단어 경계가 없다). 붙어 있는 형태까지 보려면
  `([Cc][Ss][Nn][-_ ]?)[0-9]{4,6}` 로 봐야 한다 — **이 자가점검을 통과했다고 착각할 수 있는 함정**이다.

### ② 규칙 60(이슈 표기)

- 본문에서 giip 이슈를 단순 언급할 때는 샵 없이 `giip 2463` 형식이다(샵을 쓰면 렌더러가 이 저장소의
  GitHub 이슈로 자동링크한다). KNOW-044 노트와 106차 기록의 **샵이 붙은 표기** → 샵 없는 `giip 2463` 형식으로 교정했다.
- 106차 기록의 **정정 블록 안 예시 표기 3곳**에도 같은 형태가 남아 있어 **같은 PR 에서 표기만** 바로잡았다
  (기록된 사실·조치 내용 변경 없음 · 106차 기록의 정정 블록에 ⑤로 덧붙임).
- `PR #403` 처럼 GitHub PR 표기는 `PR #` 형식을 유지한다.
- `.ps1` 회귀 테스트의 주석은 원본 `worktree-safety.ps1` 명세 문장을 **그대로 인용**한 것이므로 원문 그대로 뒀다.

### ③ 게이트 기대 건수 교정 (`run-repo-gates.ps1`)

기대 건수는 **하한선**이다 — "발견된 파일 수가 기대값보다 **적으면** 실패". 즉 **테스트가 사라져도 통과**하게 되는 구조다.

- ps1 35 → **36** (이번에 추가한 회귀 테스트 1건 반영).
- mjs 6 → **7** — PR #389 가 `test-liveness-ops-issue.mjs` 를 추가하면서 기대값을 올리지 않아,
  실재 7건인데 기대값 6 이었다. **mjs 사라짐 검사가 죽어 있던 상태**였다.

### ④ tKB 갱신 — 단건 upsert

KNOW-044 본문 1자 변경에 맞춰 tKB 를 갱신했다.

- `sync-klayer`(디렉터리 전체 재기록)는 **무관 노트까지 CRLF/LF 불일치로 덮어쓸 위험**이 있어 쓰지 않았다.
- 대신 **단건 `upsert`** → **kbSn 7044 갱신(created 1 → updated 1 · 중복 0)**.
- 재조회 대조: 저장 본문 = 로컬 파일 3467자 **+ 서버가 덧붙이는 끝 줄바꿈 1자**(나머지 바이트 동일 · LF 동일) ✓,
  교정 전 표기(샵이 붙은 형태) 잔존 0건. **LF 사본에서 sync** 했으므로 저장소 blob(LF)과도 일치한다.

## PR 반영

- **PR #403** — `fix(worktree-safety): 머지판정 게이트 fail-open 결함 수정 — 판정 불가 시 삭제 금지(fail-closed)`
  · 머지 커밋 `a533600` · 파일 7개(+487/-9).
  포함: `worktree-safety.ps1` 수정 · 회귀 테스트 신규 · `KNOW-044` + `INDEX.md` · 106차 work_history ·
  `docs/WHATS_NEW.md` 106차 항목(rule 36) · 게이트 기대 건수 교정.
- **PR (사후 기록)** — 106차 기록의 샵 표기 교정(3곳 + 정정 블록 ⑤) + 이 기록
  (`.agent/work_history/20261113_0643_...`)만 담는 마무리 PR(2파일).
  **머지된 브랜치를 재사용하지 않고 `origin/main` 에서 새 브랜치**를 만들었다.

## 워크트리 정비

- `maint-106-0235` — PR #403 머지 + 원격 브랜치 삭제 + `git diff origin/main` 빈 상태 확인 후 회수.
- `maint-107-0643` — 이번 세션 전용(사후 기록 PR 머지 후 회수).
- `maint-62-2331` — 정본 도구 판정 `MANUAL-REVIEW` 보류분(사람 확인 필요) → **미접촉 유지**.

## 관찰(이번 PR 에서 조치 안 함)

- 저장소 전체에 bare `#N` 형태의 giip 이슈 참조가 수백 건 남아 있다(규칙 60 기준으로는 GitHub 자동링크 대상).
  **이번에 쓴 텍스트는 규칙 60 에 맞춰 썼다.** 수백 건 일괄 정리는 본 작업과 무관한 대량 diff 가 되므로 별도 세션 대상.
- 머지된 커밋 메시지 본문에는 교정 전 표식을 **인용한** 부분이 남아 있다(문장 안에서
  "→ 샵 없는 형태로 바꿨다" 를 설명하는 부분). 이미 공개된 커밋이므로 **히스토리 재작성 없이 두고**,
  앞으로 새로 쓰는 텍스트는 샵 없이 쓴다.

## 결과 요약

- [0] 병합충돌 0건 · [E] CI 실패 0건(PR #403 은 CI 3종 전건 SUCCESS) · [F] 오판 stash 0건 ·
  [H] 2시간 창 24건·24시간 창 43건 전건 재검증(작업 CSN 일치 · 상태 주장 전건 일치 · 큐 파생 라벨 1건은
  오정 아님) → **정정 0건 · 전이 0건 · 이슈 쓰기 0건**.
- **계승 act** — 106차 산출물을 직접 실행으로 검증(수정 전 코드에서 FAIL 8건으로 fail-open 증명)하고
  규칙 54·60 자가점검 교정 + 게이트 기대 건수 교정 + tKB 단건 갱신 후 **PR #403 로 land**.
- k-layer `KNOW-044`(kbSn 7044) · tKB 본문 대조 완료.
- **사후 PR** — 106차 기록에 남은 샵 표기 3곳(정정 블록 안 예시)을 **표기만** 교정 + 107차 기록 신규(2파일).
- 성역(giipApi/giipApiSk2) 미접촉 · main 직접 push 없음 · PR 경유 · 이슈 쓰기 0건.
