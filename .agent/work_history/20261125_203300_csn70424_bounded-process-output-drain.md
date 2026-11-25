# 작업 기록 — bounded-process 출력 배수(drain) 결함 수정 (giip 6331)

- 일시: 2026-11-25 20:33 JST
- 작업자: mochi (서브에이전트, lowyworkenv 채팅 위임)
- CSN: 70424 (giip-fde-agent 정본)
- 관련: giip-fde-agent PR #566 (gh-call-timeout, 머지 d352d42) 후속 결함 수정
- 읽은 파일: `AI_MUST_READ.md`, role `.agent/roles/developer.md`, rules `00_core_principles.md`·`39_conduct_toward_customers.md`·`28_response_report_rule.md`·`42_completion_by_execution_evidence.md`·`43_delegation_safety_block.md`·`55_information_lookup_order_and_feedback.md`·`59_documentation_sync_with_work.md`·`35_commit_push_per_task.md`·`57_worktree_cleanup_on_completion.md`·`11_structured_commit.md`·`50_bot_pr_scope_discipline.md`, repo `AGENTS.md`, lowyworkenv repo `AGENTS.md`, 스킬 `.agent/skills/giip-fde-agent-project/SKILL.md`, rule `00_project_repository_scope.md`

## 배경 — 결함 발견 경위

PR #566 머지 후 이식(lowyworkenv) 작업 중 `test-bounded-process.ps1` 이 간헐적으로
실패했다(6회 중 3회, 매번 다른 단언): C-5 "머지판정 불가(origin remote 없음)",
E-2/E-3(삭제 경로 미실행), D-5/D-6(ManualReview=0). 세 실패는 모두 같은 서명이다 —
`git` 호출이 ExitCode=0 인데 stdout 이 비어 읽혔다. 직접 재현으로 확인했다:
`git remote get-url origin` 을 bounded 헬퍼로 10회 반복하자 1회(7번째)가
Started=True·ExitCode=0·StdOut='' 로 돌아왔다.

## 원인 — WaitForExit(타임아웃)의 출력 펌프 경합

.NET 문서에 명시된 동작이다: `WaitForExit(타임아웃)` 이 true 를 돌려줘도
리다이렉트된 비동기 출력 처리가 끝나지 않았을 수 있다. Unix(.NET Core)에서
파일 리다이렉트는 파이프+펌프 스레드로 구현되므로, 프로세스 종료 직후 파일을
읽으면 펌프가 아직 복사 중이어서 빈 파일·잘린 내용을 읽는다. 부하가 걸린
공유 CPU(1.5코어) 환경에서 펌프 스레드가 밀리면 간헐적으로 발동한다.
이것이 이식 테스트의 C-5/E-2/D-5 실패 전부(및 정본에서 한 번 나왔다가
재현되지 않았던 D-9 일시 실패)의 실체이다 — 테스트 결함이 아니라
`Invoke-GissueBoundedProcess` 의 실제 결함이다.

## 수정 — `scripts/gissue/lib/bounded-process.ps1`

유한 대기가 true 를 돌려준 뒤 파일을 읽기 전에 인자 없는 `WaitForExit()` 를
한 번 더 호출한다(.NET 문서 권장 패턴 — 비동기 출력 처리가 끝날 때까지
기다린다). 프로세스는 이미 종료했으므로 이 호출은 펌프 비우기만 기다리고,
타임아웃 경로(Kill 뒤)에는 적용하지 않는다(그쪽 출력은 버린다).
헤더 주석에도 경합 원인과 실측 수치를 기록했다.

## 회귀 테스트 — `scripts/gissue/tests/test-bounded-process.ps1` A-15

`git -C <repo> remote get-url origin` 을 bounded 헬퍼로 20회 반복 호출해
매번 ExitCode=0 이고 온전한 URL 이 돌아오는지 확인한다.

- 구 코드(수정 전 lib) + 신규 테스트 3회: 44/44, **43/44(A-15 실패 — 1/20회 빈 stdout)**,
  42/44(A-15 통과, 다른 간헐 실패 2건) — 테스트가 결함을 잡아낸다.
- 수정 코드 + 신규 테스트 6회 연속: **44/44 전건 통과**.

## 기타 테스트 (이 VM, pwsh 7.4.6, TEMP=/tmp)

- `test-gh-cache.ps1` 21/21 PASS
- `test-worktree-cleanup-timebox.ps1` 60/60 PASS
- `test-worktree-merge-gate-failclosed.ps1` 18/18 PASS
- `check-ps1-parse.ps1` 2/2 통과 (bounded-process.ps1, test-bounded-process.ps1)

## 문서 (rule 59)

- `docs/60-operations/hourly-issue-scheduler-runtime.md` — 외부 호출 타임아웃 절의
  테스트 수 43건→44건, drain 회귀 A-15 설명 추가.
- `docs/WHATS_NEW.md` — 같은 절의 테스트 수 43건→44건, drain 결함·수정 설명 추가.

## PR

(정본 PR 번호·머지 SHA는 PR 생성 후 기입)
