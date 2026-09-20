# 41. 이슈 처리 세션 안전 규칙 — 색인 및 주입 계약 (Injection Contract)

> **HARD RULE** — 무인(스케줄러) 세션과 대화형 세션 모두에 적용된다.
> 이 파일 하나가 42~51 규칙의 **단일 진입점**이다. 프롬프트/위임문에서는 이 파일만 가리키면 된다.

## 이 규칙군이 존재하는 이유

2026-09-14 하루 동안 같은 계열 사고가 10건 확인됐고, **공통점은 전부 "규칙은 문서에 있는데 매번
기억해서 지켜야 하는" 형태였다는 것**이다. 문서에만 있던 규칙은 지켜지지 않았고, 세션 프롬프트에
주입되거나 훅으로 강제된 규칙만 실제로 지켜졌다(giip #2442 에서 실증 — 규칙을 만든 당사자 세션이
자기가 만든 훅에 차단당했다).

따라서 이 규칙군의 핵심은 내용뿐 아니라 **전달 경로**다. 아래 "주입 계약"을 깨면 규칙 본문이
아무리 정확해도 효과가 없다.

## 주입 계약 (Injection Contract)

1. 이슈를 자동 처리하는 세션(매시 스케줄러의 `[A]`~`[H]` 전 단계)은 **처리 착수 전에 이 파일을
   읽고, 이 파일이 가리키는 42~51 중 해당 상황의 규칙을 읽는다.**
2. 프롬프트 템플릿에는 **이 블록을 단 한 번만** 둔다. 단계별([C] READY 처리 / [D] stale
   IN_PROGRESS 회수 등)로 같은 문단을 복붙하지 않는다 — 복붙하면 나중에 한쪽만 고쳐지는 사고가
   난다(giip #2425 실측, 상세는 `48_single_source_safety_predicate.md`).
3. 다른 PC/CSN 으로 이식할 때 **이 `.agent/rules/` 디렉터리를 함께 복사**하고, 이식한 프롬프트가
   실제로 이 파일을 로드하는지 드라이런으로 확인한다
   (`docs/60-operations/hourly-issue-scheduler.md` §12 참조).

## 규칙 목록

| 파일 | 한 줄 요약 | 근거 giip |
|---|---|---|
| [42_completion_by_execution_evidence.md](42_completion_by_execution_evidence.md) | 완료 판정은 실행 결과로만. "등록했다/머지했다"는 근거가 아니다 | #2415 #2425 #2429 #2431 #2436 |
| [43_delegation_safety_block.md](43_delegation_safety_block.md) | 커밋/push/PR 을 시키는 위임 프롬프트에 반드시 넣을 4개 안전 문구 | #2390~#2397 #2432 #2442 |
| [44_no_pr_reason_marker.md](44_no_pr_reason_marker.md) | PR 이 성립하지 않는 이슈의 탈출구 `[NO-PR-REASON]` | #2415 #2425 |
| [45_gate_cap_needs_decision.md](45_gate_cap_needs_decision.md) | 게이트 3회 캡 이후 `NEEDS_DECISION` + 4분기 재판정 | #2415 #2425 |
| [46_cross_csn_write_scope.md](46_cross_csn_write_scope.md) | 자기 CSN 매핑에 없는 CSN 은 읽기만, 쓰기 전면 금지 | #1053 #1079 |
| [47_auto_cleanup_safety_requirements.md](47_auto_cleanup_safety_requirements.md) | 자동 정리(worktree 등)의 최소 안전 요건 5가지 | #2432 #2445 #2463 #1540 |
| [48_single_source_safety_predicate.md](48_single_source_safety_predicate.md) | 안전 판정은 공용 함수 1개. 복붙 중복 금지 | #2440 #2463 #2425 |
| [49_human_confirmation_false_positive.md](49_human_confirmation_false_positive.md) | "사람 확인 필요" 탐지 시 주어·시제 구분(오탐이 잘 지킨 이슈를 벌준다) | #2424 #2457 |
| [50_bot_pr_scope_discipline.md](50_bot_pr_scope_discipline.md) | 봇 PR 은 이슈 범위 밖 파일을 쓸어담지 않는다 | #2424 #2459 |
| [51_giip_product_changes_csn47_only.md](51_giip_product_changes_csn47_only.md) | giip 제품 레포(`giipv3`/`giipdb`/`giipfaw` 등) 변경은 CSN 47 로만. 이 레포 자신은 대상 아님 | giip 2679 (사용자 직접 지시) |

코멘트 작성 시각을 추정하지 않는 규칙은 신설하지 않고 기존
[`PROTOCOL_PROGRESS_COMMENT.md`](PROTOCOL_PROGRESS_COMMENT.md) 의 "시각(When)" 절을 확장했다
(근거 giip #2442). 같은 주제의 규정이 두 파일로 갈라지는 것을 피하기 위한 판단이다.

## 기존 규칙과의 경계

이 규칙군은 아래 기존 규칙을 **대체하지 않고 보강**한다. 중복 서술을 만들지 말고 링크로 잇는다.

- [`29_tool_usage_and_verification.md`](29_tool_usage_and_verification.md): "확인 없이 추정한 정보를
  사실처럼 제시하지 않는다" — 정보 신뢰성 일반론. 42 는 그중 **완료/게이트 동작 판정**만을 다룬다.
- [`35_commit_push_per_task.md`](35_commit_push_per_task.md): 작업마다 커밋·push. 43 은 그 커밋·push 를
  **서브에이전트에 위임할 때** 붙여야 하는 안전 문구를 다룬다.
- [`34_adversarial_review.md`](34_adversarial_review.md): 설계 승인 **전** 실패 가능성 점검.
  42 는 구현 **후** 완료 판정을 다룬다.
- [`00_project_repository_scope.md`](00_project_repository_scope.md): 레포 스코프. 46 은 같은 취지의
  **CSN(고객사/프로젝트 식별자) 스코프**를 다룬다.
