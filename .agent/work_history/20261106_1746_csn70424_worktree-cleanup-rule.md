# 작업 기록 — 규칙 57 신설: 작업 종료 시 worktree·작업 브랜치 정리 (giip 4699)

- 일시: 2026-11-06 17:46 JST
- 근거: 사용자 직접 지시 (워크트리 미삭제로 호스트 디스크 용량 폭발 → 재발 방지 규칙을
  `.agent` 에 반영). 등록 이슈 giip 4699 (PENDING 으로 등록 · 상세 페이지 재확인済).

## 변경 파일 (6건)

1. `.agent/rules/57_worktree_cleanup_on_completion.md` — 신설. 핵심:
   - 모든 에이전트 작업은 종료 시점에 자기 worktree 를 `git worktree remove` 로 제거하고
     작업 브랜치도 삭제한다.
   - 미커밋 변경이 있는 worktree 는 삭제하지 않고 보고한다.
   - gissue 스케줄러가 만든 worktree 도 태스크 종료와 함께 같은 규칙을 적용한다.
   - 종료의 정의: PR 머지 확인 또는 결과 보고 + 연결 이슈 DONE/종료 확인.
     push · CI 대기 · REVIEW 는 종료가 아니다 (rule 47 의 실측 교훈 연결).
   - 절차: 미커밋 확인 → locked 확인 → `git worktree remove`(`--force` 금지) →
     `git branch -d` 안전 삭제(미머지 시 강제 삭제 금지 · 보고) → `git worktree prune` →
     제거 · 보류 내역을 완료 보고에 포함.
2. `.agent/rules/43_delegation_safety_block.md` — §4 에 상호참조 추가: 종료 확정 후 정리는
   rule 57 이 정본이며 작업 단위를 소유한 세션이 수행한다. 하위 세션의 종료 확정 전
   임의 삭제 금지는 유지.
3. `.agent/rules/41_issue_session_safety_index.md` — 규칙 57 색인 행 추가.
4. `GEMINI.md` — Additional Operational Rules 에 규칙 57 항목 추가.
5. `AI_MUST_READ.md` — 작업 전 체크리스트 1번에 종료 시 정리 명시.
6. `docs/WHATS_NEW.md` — 2026-11-06 항목 추가, 기준일 갱신.

## 설계 판단

- 배치: gissue 워크플로 단계가 아니라 **rule 파일 신설**을 택했다. 적용 범위가 스케줄러뿐
  아니라 모든 에이전트 작업(대화형 · 위임 · 스케줄러)이라, 특정 워크플로 안에 넣으면
  나머지 실행 경로가 규칙 밖에 남는다.
- rule 43 §4 · rule 47 과의 정합: 과거 사고(#2432 #2445 #2463)는 "작업 중인 worktree 를
  지운" 사고이고, 이번 사고는 "아무도 지우지 않은" 사고다. 둘을 가르는 기준은 **종료 확정
  여부**로 통일했다 — 확정 전 삭제 금지(43 · 47), 확정 후 소유 세션의 정리 의무(57),
  소유자가 놓친 잔해는 rule 47 의 백스톱 정리 로직이 회수한다.

## 검증

- 커밋 전 `git diff` 로 추가 줄에 고객 식별 문자열 · 타 CSN 번호가 없는지 확인한다.
- 상대 링크(41 · 43 · GEMINI · AI_MUST_READ → 57 파일) 대상 존재를 확인한다.
- 이 작업 자체의 worktree(`wt-rule57`)는 PR 머지 전이므로 rule 57 에 따라 아직 지우지
  않는다. 머지 후 소유 세션이 정리하는 것이 이 규칙의 첫 적용 사례다.
