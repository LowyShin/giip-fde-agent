# KNOW-045 — detached HEAD 검증 워크트리는 자동 회수 경로가 없다

> 근거: 2026-11-13 CSN 70424 저장소 정비 109차 세션 실측 · 발행: 2026-11-13 · 상태: 검증됨(직접 실측)

## 요지

에이전트가 **검증용 스크래치 워크트리를 detached HEAD 로 만들면** 그 워크트리는 **자동으로 회수되지 않는다**.

- (a) 정본 정리 도구 `scripts/gissue/cleanup-worktrees.ps1` 는 detached HEAD 를 **MANUAL-REVIEW** 로
  분류해 삭제하지 않는다 (`scripts/gissue/worktree-safety.ps1` 의 `if ($e.Detached -or (-not $e.Branch))` 분기).
- (b) 원시 `git worktree remove` 는 대량삭제 훅 `check-bulk-delete.sh` 이 **deny** 한다 —
  화이트리스트는 **정본 정리 도구 호출만** 허용한다.

⇒ **rule 57**(모든 에이전트 작업은 종료 시 자신이 만든 git worktree 를 제거한다)과 정본 도구의
**fail-closed 정책**(판정 불가면 삭제하지 않는다)이 **막다른 길**을 만든다 — "자동 회수" 경로가 존재하지
않으므로 **사람 확인**으로만 빠져나올 수 있다.

## 실측 (2026-11-13 109차)

- 대상: `D:\temp\worktrees\giip-fde-agent\verify-5054-main`
  (detached HEAD `41de980` · `clean` · HEAD == `origin/main` · **고유 커밋 0** · **stash 0**).
- 정본 정리 도구 실행:

  ```
  scripts/gissue/cleanup-worktrees.ps1 -RepoPath <공유 체크아웃> -OnlyPath <대상 경로> -MinIdleMinutes 0
  ```

  → `MANUAL-REVIEW(detached HEAD, 브랜치 없음)` ·
  요약 `삭제 0건 / locked 제외 0건 / 수동확인 필요 1건`.
- 원시 `git worktree remove` 는 **대량삭제 훅에 의해 deny** 되었다(우회하지 않았다).

⇒ 결론: detached HEAD 스크래치 워크트리는 **자동 회수 경로가 없다** → 사람 확인 대기로 남기고 보고해야 한다.

## 규칙

1. **검증용 스크래치 워크트리도 브랜치를 붙여서 만든다**
   (`git worktree add <경로> -b <고유브랜치명> <base>`) — 머지 후에는 정본 정리 도구가
   `gh pr list --state merged` 기준 머지확인으로 회수한다.
2. **detached 가 불가피하면 `MANUAL-REVIEW` 로 남기고 사람 확인 대기로 보고한다** —
   훅을 우회하지 않는다(따옴표·패턴 변형 같은 우회는 금지).
3. **정본 도구의 MANUAL-REVIEW 판정은 우회하지 않는다.**
4. **"내용 유실 위험 없음"을 말할 때는 `clean` + `HEAD == origin/main` + 고유 커밋 0 + stash 0 을
   기계로 확인한 뒤에만 쓴다.**

## 근거

- `57_worktree_cleanup_on_completion.md` — 작업 종료 시 자신이 만든 worktree 를 제거한다(→ detached 는 자동 회수 불가).
- `47_auto_cleanup_safety_requirements.md` — 자동 정리(worktree·잔해)의 안전 요건
  (이 저장소 규칙 번호 체계 기준 · lowyworkenv 측 번호로는 rule 55 — 인용은 KNOW-028 원칙대로
  이 저장소에 실제로 존재하는 파일명 기준으로 적는다).
- `scripts/gissue/worktree-safety.ps1` — `if ($e.Detached -or (-not $e.Branch))` → MANUAL-REVIEW 분류.
- 109차 세션 실측 — work_history `20261113_1023_csn70424_repo-maintenance.md`.

## 관련

- [KNOW-008](KNOW-008_cleanup_worktrees_classification_and_builtin_idle_gate.md) — 정리 도구 판정 Status 5종과 built-in idle 게이트
- [KNOW-009](KNOW-009_cleanup_onlypath_separator_silent_zero.md) — `-OnlyPath` 는 경로 구분자를 정규화하지 않는다
- [KNOW-023](KNOW-023_dead_session_uncommitted_diff_can_be_older_than_main.md) — MANUAL-REVIEW 보류분은 미접촉 유지 대상
- [KNOW-044](KNOW-044_log_callback_pollutes_the_return_value_of_a_value_returning_function.md) — 같은 정리 엔진의 fail-open 결함(fail-closed 로 교정된 축)
