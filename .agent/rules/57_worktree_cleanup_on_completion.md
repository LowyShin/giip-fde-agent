# 57. 작업 종료 시 worktree·작업 브랜치 정리

> **HARD RULE** — 워크트리는 작업 공간이지 보관소가 아니다.
> 배경: 에이전트 작업들이 만든 git worktree 를 종료 시 제거하지 않아 호스트 디스크 용량이
> 폭발한 사고(2026-11). 사용자 직접 지시로 신설했다.
> 근거 giip: #4699 (이 규칙의 등록 이슈)

## 기본 동작 — 모든 에이전트 작업

1. **모든 에이전트 작업은 종료 시점에 자신이 만든 git worktree 를 `git worktree remove` 로
   제거하고, 작업 브랜치도 삭제한다.**
2. **스케줄러(gissue)가 태스크 처리용으로 만든 worktree 도 태스크 종료와 함께 같은 규칙을
   적용한다.** 스케줄러는 태스크가 끝났는데 worktree 만 남는 상태를 만들지 않는다.

## "종료"의 정의 — push 는 종료가 아니다

- 종료 = 결과 반영이 확정된 시점이다. PR 이 있는 작업은 **PR 머지 확인**, 머지가 없는 작업은
  **결과 보고 + 연결 이슈의 DONE/종료 확인**이 종료다.
- push 직후 · CI 대기 · REVIEW 상태는 중간 지점이다
  ([`47_auto_cleanup_safety_requirements.md`](47_auto_cleanup_safety_requirements.md) 의 실측 교훈:
  에이전트는 push 이후에도 CI 확인 · 머지 · 코멘트 · 문서 갱신을 한다).
- 연결된 이슈가 `PENDING/READY/IN_PROGRESS/REVIEW/TESTED/NEEDS_DECISION` 이면 그 worktree 는
  종료가 아니다. 지우지 않는다.

## 정리 절차

1. **미커밋 변경 확인** — `git -C <worktree> status --porcelain` 결과가 비어 있지 않으면
   **삭제하지 않고**, worktree 경로와 상태를 작업 보고에 남긴다. 미커밋 변경은 다른 세션의
   유일한 산출물일 수 있다(KNOW-013 · KNOW-030).
2. **잠금 확인** — `git worktree list` 에 `locked` 로 표시돼 있으면 건너뛰고 보고한다.
3. **제거** — `git worktree remove <path>`. `--force` 는 쓰지 않는다. force 가 필요해 보이면
   그 자체가 미커밋 · 사용 중 신호이므로 중단하고 보고한다.
4. **브랜치 삭제** — 로컬 브랜치는 `git branch -d <branch>`(안전 삭제)로 지운다. 미머지라
   실패하면 `-D` 로 강제 삭제하지 않고 보고한다. 원격 브랜치는 PR 머지 시 함께 삭제한다
   (머지 시 자동 삭제 또는 머지 직후 수동 삭제). 미머지 원격 브랜치의 강제 삭제는 금지다.
5. **마무리** — `git worktree prune` 으로 메타데이터 잔재를 정리하고, 제거한 경로 · 브랜치와
   보류한 항목(사유)을 작업 완료 보고에 포함한다.

## 위임된 하위 세션

- 하위(서브) 세션은 자기 판단으로 자기 worktree 를 지우지 않는다 —
  [`43_delegation_safety_block.md`](43_delegation_safety_block.md) §4 를 유지한다. 종료 판정과
  정리는 **작업 단위를 소유한 세션(위임자)** 이 위 절차로 수행하고, 하위 세션은 종료 시
  worktree 경로를 보고한다.
- 작업 단위 전체를 단독으로 소유한 세션은 본인이 직접 정리한다.

## 기존 정리 로직과의 관계

- 이 규칙이 **1차 정리**다. 소유자가 종료 정리를 놓친 잔해(orphan)는
  [`47_auto_cleanup_safety_requirements.md`](47_auto_cleanup_safety_requirements.md) 의 안전
  요건 5가지를 모두 갖춘 별도 정리 로직이 백스톱으로 회수한다
  (`docs/60-operations/hourly-issue-scheduler.md` §10).
- 남의 worktree 는 이 규칙으로 지우지 않는다. 자신이 만들었거나, 작업 단위를 소유한 것만
  대상이다.

## 금지 사항

- ❌ 미커밋 변경이 있는 worktree 삭제 (보고가 정답)
- ❌ `git worktree remove --force`, `git branch -D` 를 정리 수단으로 사용
- ❌ 종료 확정 전 삭제 (push = 종료 아님)
- ❌ 남의 세션 worktree 임의 삭제
