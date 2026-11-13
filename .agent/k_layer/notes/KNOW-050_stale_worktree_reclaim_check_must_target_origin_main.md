# KNOW-050 — 자동 회수가 막힌 워크트리 판정은 워크트리의 HEAD 가 아니라 `origin/main` 을 기준으로 한다

> 근거: 2026-11-14 CSN 70424 저장소 정비 119차 세션 실측 (work_history 20261114_0613) · 발행: 2026-11-14 · 상태: 검증됨(파일 단위 실측)
>
> 관련 파일: `scripts/gissue/cleanup-worktrees.ps1` · `scripts/gissue/worktree-safety.ps1`
> · 선행 지식 [KNOW-023](KNOW-023_dead_session_uncommitted_diff_can_be_older_than_main.md)
> · [KNOW-045](KNOW-045_detached_scratch_worktree_has_no_automatic_reclaim_path.md)
> · [KNOW-049](KNOW-049_claude_isolation_worktree_family_is_not_unconditionally_excluded.md)

## 요지

정본 정리 도구가 워크트리를 `MANUAL-REVIEW` 로 분류하면(미커밋 변경 · detached HEAD · 머지된 PR 없음),
그 분류를 곧바로 **"사람이 회수해야 할 미완성 작업"** 으로 보고하기 쉽다. 하지만 그 분류는
**회수 게이트의 판정 결과**일 뿐 **유실 위험의 판정이 아니다.**

119차는 워크트리 6건(그중 미커밋 3건)을 파일 단위로 `origin/main` 과 대조해
**유실 위험 0건** 을 실측했다. 대조 기준을 잘못 잡으면 같은 데이터로 반대 결론이 나온다.

## 세 가지 대조 함정 (119차 실측)

### 1. 대조 기준은 `origin/main` 이다 — 워크트리의 HEAD 아니면 "이미 반영된 내용" 이 "미커밋 변경" 으로 보인다

`giip-5054-refine` 의 `.agent/tasks/giip-5054.md`(152줄)는 `git status` 에서 **스테이징된 신규 추가(`A`)** 다.
워크트리의 HEAD(`57397cb`) 에는 이 파일이 없으므로 `git diff --cached` 는 **152 insertions** 를 보고한다.

그런데 같은 파일을 `origin/main` 과 비교하면 **빈 출력**(= 완전히 동일)이고,
`git show origin/main:<파일>` 출력과 워크트리 파일은 **바이트 동일**(13089 bytes · CRLF 0)이었다.

⇒ **"미커밋 152줄" 을 읽고 미완성 작업으로 단정하면 사실과 반대다.** 판정식은 `origin/main` 기준이다.

### 2. 미추적 파일도 대조 대상이다 — `git diff` 에는 아예 보이지 않는다

`giip-5142-svcguard` 의 미추적 7건 중 4건(`scripts/svcguard/` 3 + 회귀 테스트 1)은
**main 과 바이트 동일**(PR #430 머지본)이었다 — 이미 반영된 작업의 잔재. 나머지 3건은 `.tmp-*` 스크래치.
`git diff` 는 미추적 파일을 전혀 보여주지 않으므로, `git status --porcelain -uall` 로 펼쳐 각각 비교해야 한다.

### 3. 줄 집합 비교는 "이관된 항목" 을 "유실" 로 오판한다

`maint-62-2331` 의 `docs/WHATS_NEW.md` 를 줄 집합으로 비교하면 "main 에 없는 34줄" 로 보인다.
실제로 확인한 결과 — **28줄은 main 의 `docs/HISTORY.md` 로 이관**돼 있었다(`docs/WHATS_NEW.md` 는
롤링 7일 창이라 만료 항목이 HISTORY 로 옮겨간다). 나머지 6줄은 날짜 헤더(`## 2026-10-26` 등)와
"기준일 (as of)" 문구 같은 **구조물**이었다.

⇒ 줄 집합(`comm`) 비교로 "유실" 을 단정하지 않는다. **본문(윈도우) 대조**로 본문을 확인한다.

## 실측 표 (2026-11-14, 119차)

| 워크트리 | 워크트리 상태 | `origin/main` 대비 실측 | 판정 |
|---|---|---|---|
| `giip-5054-refine` | staged 신규 추가 `A` (152줄) | numstat **빈 출력**(= 동일) · 워크트리 파일이 main 과 바이트 동일 | 유실 위험 0 |
| `giip-5142-svcguard` | tracked 4 + 미추적 7 | `.gitignore` 동일 · 나머지 3건(`docs/HISTORY.md` 1/1 · `docs/WHATS_NEW.md` 1/8 · `run-repo-gates.ps1` 3/6)은 **main 이 신선본**(`$ExpectedPs1TestCount` 40→41) · 미추적 4건은 main 과 바이트 동일(PR #430) | 유실 위험 0 |
| `maint-62-2331` | tracked 2 | `docs/HISTORY.md` **0/68**(worktree 188줄 전건 main 에 존재 · main 이 68줄 더 최신) · `docs/WHATS_NEW.md` 38/43 — 유일 34줄 중 28줄이 main HISTORY 본문과 일치, 6줄은 구조물 | 유실 위험 0 |
| `verify-4139-c7` · `verify-5054-main` · `verify-5174-main` | clean · detached | HEAD 가 `origin/main` 조상(고유 커밋 0) | 유실 위험 0 |

## 판정 규칙

1. **게이트 분류를 유실 위험 판단으로 재사용하지 않는다.** `MANUAL-REVIEW` 는 "도구가 지우지 않는다" 의
   의미이지 "사람이 회수해야 한다" 의 의미가 아니다. 회수 보고에는 **게이트 사유와 대조 결과를 함께** 적는다.
2. **대조 기준은 `origin/main`.** 워크트리의 HEAD 는 오래된 스냅샷이라 이미 반영된 내용을 "미커밋 변경" 으로
   보여준다. `git -C <worktree> diff --numstat origin/main -- <파일>` 로 판정한다.
3. **미추적 파일도 대조한다.** `git status --porcelain -uall` 로 펼쳐 각각 `origin/main` 과 비교한다.
   이미 main 에 있는 미추적 파일은 "미완성 작업" 이 아니라 "이미 반영된 작업의 잔재" 다.
4. **줄 집합이 아니라 본문으로 비교한다.** 문서 형식(롤링 창 이관·재문구)으로 같은 내용이 다른 파일에
   옮겨갈 수 있으므로, 본문 윈도우 대조로 확인한다.
5. **대조 결과와 회수 여부를 분리한다.** 대조가 "유실 위험 0" 이면 회수 여부는
   `scripts/gissue/cleanup-worktrees.ps1` 의 게이트로 판단한다(정본 판정 단일화 — rule 48).

## 적용

- 저장소 정비 세션의 워크트리 인벤토리에는 목록만으로 "사람 회수 대상" 을 쓰지 말고 각 항목에
  **파일 단위 대조 결과** 를 붙인다. 대조 없이 다음 회차에 복사되면 같은 MANUAL-REVIEW 목록이 계속 쌓이고,
  실제로는 "유실 위험 0건" 이라는 다른 결론이 나온다.

## 관련

- 작업 기록: [119차 저장소 정비](../../work_history/20261114_0613_csn70424_repo-maintenance.md)
- 선행 지식은 위쪽 "선행 지식" 링크 3건([KNOW-023](KNOW-023_dead_session_uncommitted_diff_can_be_older_than_main.md) ·
  [KNOW-045](KNOW-045_detached_scratch_worktree_has_no_automatic_reclaim_path.md) ·
  [KNOW-049](KNOW-049_claude_isolation_worktree_family_is_not_unconditionally_excluded.md))
