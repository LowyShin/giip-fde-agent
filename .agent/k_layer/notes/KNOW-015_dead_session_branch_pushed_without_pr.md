---
name: 죽은 세션의 원격 브랜치만 남아 있는 경우 — "열린 PR 0건"은 "할 일 없음"이 아니다
description: PR 생성 전에 죽은 세션은 커밋·push 까지만 남긴다 — 원격 브랜치가 살아 있으면 그 브랜치로 PR 을 만들어 계승한다
metadata:
  type: project
---

# "열린 PR 0건"은 "할 일이 없다"의 증거가 아니다

## 핵심

저장소 정비 세션이 **커밋과 push 까지만 하고 PR 생성 전에 죽으면**, 저장소에는
**원격 브랜치만** 남는다. `gh pr list --state open` 은 **0건**인데 작업 산출물은 **있다**.
"열린 PR 0건 → 조용히 건너뜀"으로 끝내면 산출물이 원격에 방치된다.

## 사례 — CSN 70424 저장소 정비 56차 사후 세션 (2026-10-26 실측)

### 남은 것

- 06:00 사후 세션이 워크트리 `maint-56-post-0600` 에서 커밋 `8cbab44` 를 만들고
  원격 브랜치 `chore/csn70424-maint56-post-20261026-0600` 로 **push 까지 완료**했다.
- 그러나 **PR 은 만들지 못했다**(세션이 그 앞에서 종료).
  → `gh pr list --state all --json number,headRefName` 에서 이 headRefName 의 PR 이 **0건**이었다.
  → 반면 `git ls-remote --heads origin` 에는 해당 원격 ref 가 **살아 있었다**.

### 계승 절차 (실측 성공)

1. **원격 ref 존재 확인** — `git ls-remote --heads origin` 로 push 까지만 남은 브랜치를 찾는다.
2. **기존 PR 이 정말 없는지 확인** — `gh pr list --state all --head <branch>` (열린 것만 조회하면
   이미 머지된 PR 을 놓친다).
3. **그 브랜치 그대로 PR 로 만든다** — `gh pr create --base main --head <branch>`.
   새 브랜치를 만들고 cherry-pick 하지 않는다(이미 원격에 있는 산출물이므로).
   → PR **#310** 생성 → 자동 머지 스윕이 **MERGED**(merge 커밋 `1d38978`).
4. **게이트를 push 전에 재실행** — `scripts/gissue/run-repo-gates.ps1` 를 워크트리에서 직접 실행하고
   exit 0 을 확인한 뒤 PR 을 올린다(죽은 세션의 산출물이라 검증이 없었으므로).

## 죽은 세션이 남길 수 있는 4가지 상태와 회수 절차

| 남은 것 | 확인 명령 | 회수 절차 |
|---|---|---|
| 워크트리(미커밋 파일) | `git worktree list` | 계승하거나 정본 도구 `cleanup-worktrees.ps1` 로 회수 |
| 로컬 브랜치 | `git branch -a` | 머지된 PR headRefName 으로 rename 후 회수, 잔여는 `git branch -D` |
| **원격 브랜치(PR 없음)** | `git ls-remote --heads origin` | **그 브랜치로 PR 을 만든다** |
| stash | `git stash list` | 매칭 가능하면 이슈 브랜치로 옮기고 drop, 애매하면 그대로 두고 note |

## 재사용 규칙

1. **[0]/[E] 단계에서 "열린 PR 0건"을 확인하면 `git ls-remote --heads origin` 을 같이 본다.**
   원격 ref 가 남아 있으면 그 브랜치에 PR 이 없는 것이므로 계승 대상으로 분류한다.
2. **PR 이 이미 있는 경우와 없는 경우의 회수 절차가 다르다.** 전자는 정리(merge 후 회수),
   후자는 생성(그 브랜치로 PR 생성)이다.
3. **죽은 세션의 산출물은 재검증 없이 머지하지 않는다.** 게이트를 직접 재실행하고 exit 0 을 확인한다.
4. **"PR 이 없다"는 사실 확인과 "할 일이 없다"는 판단은 다르다.** 첫 번째는 명령으로 확인하고,
   두 번째는 그 확인 뒤에만 한다.
5. 과거 기록은 고쳐 쓰지 않는다 — 남은 상태는 `> 정정(날짜): …` 블록으로 덧붙인다(rule 73).

## 관련

- [KNOW-013](KNOW-013_work_history_completion_claim_may_be_unexecuted_plan.md) — 회차 기록의 "완료" 서술은 실행되지 않은 계획일 수 있다
- [KNOW-008](KNOW-008_cleanup_worktrees_classification_and_builtin_idle_gate.md) — 정리 도구 판정 Status 5종
- [KNOW-009](KNOW-009_cleanup_onlypath_separator_silent_zero.md) — `cleanup-worktrees.ps1 -OnlyPath` 는 백슬래시 경로로만 동작

## 근거

- 2026-10-26 CSN 70424 저장소 정비 57차 세션 실측
  (`gh pr list --state all` 에서 PR 0건 · `git ls-remote --heads origin` 에서 원격 ref 잔존 ·
  그 원격 브랜치로 PR #310 생성 → MERGED(merge 커밋 `1d38978`) · CI run `40235391994` 3건 pass)
