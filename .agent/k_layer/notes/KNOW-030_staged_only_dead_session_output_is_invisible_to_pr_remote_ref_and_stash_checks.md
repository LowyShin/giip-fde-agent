# KNOW-030 — "스테이징만 하고 죽은 세션"의 산출물은 PR·원격ref·stash 검사에서 전부 안 보인다

> 근거: 2026-11-03 저장소 정비 81차 세션 실측 (work_history 20261103_1428) · 발행: 2026-11-03 · 상태: 검증됨(실측)

## 요지

**`git add` 까지만 하고(커밋·push 전) 세션이 종료되면**, 산출물은 **워크트리의 스테이징 영역에만** 남는다.
이 상태는 `[0]`/`[E]`/`[F]` 의 **검사 4종이 전부 "할 일 없음"을 반환한다** —
열린 PR·원격 ref·stash·공유 체크아웃 status 조회를 **모두** 놓친다.

`KNOW-015` 의 "원격 ref 확인" 도 **push 전에 죽으면 원격 ref 가 없다** 는 이유로 통과하지 못한다.

→ **세 가지를 모두 통과한 "빈 상태"는 여전히 회수 대상이 남아 있을 수 있다.**

## 실측 (2026-11-03, 81차)

80차 세션(2026-11-03 13:31)이 `git add` 까지만 마친 채 종료됐다.
81차가 그 산출물을 발견할 때, **모든 표준 검사기가 "대상 0건"을 반환했다**:

| 검사 | 명령 | 결과 | 놓친 이유 |
|---|---|---|---|
| [0]/[E] 열린 PR | `gh pr list --state open` | `[]` | PR 이 없음(당연) |
| [0]/[E] 원격 ref | `git ls-remote --heads origin` | `refs/heads/main` **1건뿐** | **push 된 적이 없어** 원격 branch 가 없음 |
| [E] main CI | `gh run list --branch main --limit 8` | **8건 전부 success** | 기록 2건은 커밋되지 않아 main 에 없음 |
| [F] stash | `git stash list` | **0건** | stash 가 아니라 **stage** 상태 |
| 공유 체크아웃 | `git status --short` | **clean** | 산출물은 **워크트리 안에만** 있음 |
| 과거 PR | `gh pr list --state all --head <branch>` | `[]` | PR 이 만들어진 적 없음 |

**발견한 방법은 하나뿐**이었다 — 워크트리마다 `git status` 를 보는 것:

```
git worktree list
  → D:/temp/worktrees/giip-fde-agent/maint-80-1331  b10cf06 [chore/csn70424-maint80-20261103-1331]
git -C D:/temp/worktrees/giip-fde-agent/maint-80-1331 status --short
  A  .agent/work_history/20261103_1331_csn70424_repo-maintenance.md
  M  docs/WHATS_NEW.md
```

`git branch -a` 에도 **그 브랜치만 로컬 분기로 보이고**( stash 에는 없다 ), PR·원격 ref 어디에도 없다.

## 회수 절차 (81차에서 실제로 수행·검증)

1. **워크트리 안에서 스테이징 상태 확인** — `git -C <worktree> status --short` ·
   `git -C <worktree> diff --cached --name-only` · `git -C <worktree> diff --name-only`(미스테이징).
   살아 있는 세션의 미커밋 변경까지 함께 걸려 있을 수 있으므로 **명시적 경로 스테이징**으로 커밋한다
   (rule 50 — `git add -A` 금지).
2. **그 워크트리의 기존 브랜치에서 커밋** — 새 브랜치를 만들지 않는다. 이미 작업이 배선된 브랜치다.
3. **push → PR 생성 → CI green 확인 → squash merge.**
4. **정본 정리 도구로 워크트리 회수** — `cleanup-worktrees.ps1 -RepoPath <repo> -OnlyPath <worktree>`.
   머지 확인이 통과하면 자동 삭제된다(81차 실측: `삭제됨(머지 확인, idle 가드 비활성, 인접 레포 무결성 재검증 통과)`).
5. **남은 stale ref 정리** — PR 머지로 원격 branch 는 지워지지만 **로컬 remote-tracking ref 는 남는다** →
   `git remote prune origin` (81차 실측: `[pruned] origin/chore/csn70424-maint80-20261103-1331`).

## 함정 — idle 가드가 방금 죽은 세션의 워크트리를 건너뛴다

정리 도구의 기본 idle 임계값은 **120분**이다. **방금 죽은 세션의 워크트리는 activity 가 방금이므로
"사람/다른 세션이 작업 중" 으로 보고 SKIP 된다.** 81차 실측:

```
SKIP(최근 9분 전 활동(gitadmin) — 사람/다른 세션이 작업 중일 수 있음, MinIdleMinutes=120):
  D:/temp/worktrees/giip-fde-agent/maint-80-1331
```

→ **자기 세션이 만든 워크트리이고 머지 PR 확인이 이미 끝났다면** `-MinIdleMinutes 0` 으로 지정해 회수한다.
(다른 세션이 작업 중인 워크트리는 idle 가드가 지켜준다 — 게이트를 끄는 것은 **본인 워크트리에 한정**할 것.)

## 교훈

1. **"열린 PR 0건"·"원격 ref 1건"·"stash 0건"·"공유 체크아웃 clean" 이 모두 성립해도 끝이 아니다.**
   `git worktree list` 로 등록된 워크트리마다 `git status --short` 를 돌려 스테이징 잔재를 확인한다.
   이 검사 한 줄이 `[0]`/`[E]`/`[F]` 어디에도 없으면 그 세 단계는 그만큼 빈틈이 있다.
2. **워크트리 스테이징은 PR 로 인정되지 않는다** — commit 전이라 diff 도 remote 에도 없다.
   새 브랜치를 새로 만들지 말고 **그 워크트리에 이미 배선된 브랜치를 그대로** 쓴다.
3. **커밋 전에 `git diff --cached --name-only` 로 스테이징 범위를 확인한다** —
   살아 있는 다른 세션의 변경이 같은 워크트리에 있을 수 있다(rule 50).
4. **정리 도구 판정과 idle 가드는 별개다** — MANUAL-REVIEW(미머지)는 보류, idle SKIP 은
   `-MinIdleMinutes 0` 으로 재시도한다. 어느 쪽이든 **정본 판정을 우회하지 않는다**(rule 48).
5. **과거 기록은 고쳐 쓰지 않는다** — 80차 기록에 `> 정정(...)` 블록을 덧붙인다. **81차는 이 블록을 넣지
   못한 채 종료됐고 82차가 실제로 추가했다**(82차 작업 기록).

## 관련

- `KNOW-013` — 회차 기록의 "완료" 서술은 실행되지 않은 계획일 수 있다
- `KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다(원격 ref 확인 절차)
- `KNOW-023` — 죽은 세션 워크트리의 미커밋 diff 는 main 보다 오래됐을 수 있다(staleness 대조)
- 규칙 `41_issue_session_safety_index.md` · `42_completion_by_execution_evidence.md` ·
  `47_auto_cleanup_safety_requirements.md` · `48_single_source_safety_predicate.md` ·
  `50_bot_pr_scope_discipline.md`
- 81차 작업 기록: `.agent/work_history/20261103_1428_csn70424_repo-maintenance.md`
