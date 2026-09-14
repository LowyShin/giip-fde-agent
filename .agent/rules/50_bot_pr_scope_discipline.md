# 50. 봇 PR 의 변경 범위 규율 (Bot PR Scope Discipline)

> **HARD RULE** — 봇이 내는 PR 은 그 이슈가 요구한 파일만 담는다. 워킹트리에 있던 무관한 변경을
> 쓸어담지 않는다.
> 근거 giip: #2424 #2459 (2026-09-14 실측 — 무관한 파일 변경이 섞여 죽은 코드가 조용히 머지됨).

## 실측 사고

봇 세션이 `git add -A` / `git commit -a` 류로 워킹트리 전체를 커밋해, 이전 세션이 남긴 미완성
변경과 실험용 파일이 함께 PR 에 담겼다. PR 제목·본문은 이슈 내용만 말하고 있었고 CI 는 green 이었기
때문에 **리뷰 없이 머지**됐고, 그 결과 **아무도 의도하지 않은 죽은 코드가 본선에 들어갔다.**

## 규칙

1. **`git add -A` / `git add .` / `git commit -a` 를 쓰지 않는다.** 이번 작업에서 자신이 만들거나
   고친 파일을 **경로로 명시해** 스테이징한다.
2. 커밋 전에 `git status --porcelain` 으로 **스테이징되지 않은 잔여 변경이 무엇인지** 확인하고,
   그것이 자기 작업이 아니면 건드리지 않는다(stash 도 하지 않는다 — 남의 작업일 수 있다).
3. PR 을 올린 뒤 `gh pr view <번호> --json files` 로 **실제 담긴 파일 목록**을 확인한다.
   이슈가 요구하지 않은 파일이 있으면 머지 전에 제거한다.
   - 자동 머지 대상 PR 이라면 이 확인이 **머지 전 마지막 게이트**다. CI green 은 범위 검증이 아니다.
4. 작업 중 발견한 **무관하지만 고쳐야 할 것**은 이 PR 에 끼워 넣지 말고 별도 이슈로 등록해 링크한다.
5. 워크트리 격리([`43_delegation_safety_block.md`](43_delegation_safety_block.md))를 지키면 1~2 의
   위험이 구조적으로 크게 줄어든다 — 공유 체크아웃에서 작업하면 남의 미커밋 변경과 자기 변경을
   구분할 방법이 없다.

## "머지됨"과 "반영됨"은 다르다

PR 이 머지됐다는 사실은 **요청한 내용이 실제로 담겼다**는 근거가 아니다. 완료 보고에는
`gh pr view <번호> --json files` 출력(또는 그에 준하는 diff 목록)을 근거로 붙인다.
([`42_completion_by_execution_evidence.md`](42_completion_by_execution_evidence.md))

## 관련 규칙

- [`35_commit_push_per_task.md`](35_commit_push_per_task.md) — 작업 단위 커밋(무엇을 한 커밋으로 묶는가).
- [`11_structured_commit.md`](11_structured_commit.md) — 커밋 메시지 규약.
- [`41_issue_session_safety_index.md`](41_issue_session_safety_index.md) — 이 규칙군 색인.
