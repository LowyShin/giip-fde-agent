# 잡 시작 스크립트 존재 확인 가드 — Get-Command 금지 (정본)

- 일시: 2026-11-26 01:40 JST
- 작업자: subagent (부모: lowyworkenv CSN 33 사이드챗)
- 읽은 파일: giip-fde-agent `AI_MUST_READ.md`, role `.agent/roles/developer.md`, rules `.agent/rules/00_core_principles.md`, `.agent/rules/39_conduct_toward_customers.md`, `.agent/rules/28_response_report_rule.md`, `.agent/rules/42_completion_by_execution_evidence.md`, `.agent/rules/43_delegation_safety_block.md`, `.agent/rules/55_information_lookup_order_and_feedback.md`, `.agent/rules/59_documentation_sync_with_work.md`, `.agent/rules/35_commit_push_per_task.md`, `.agent/rules/57_worktree_cleanup_on_completion.md`, `.agent/rules/11_structured_commit.md`, `.agent/rules/50_bot_pr_scope_discipline.md`, 양 레포 `AGENTS.md`.

## 배경 (호스트 실측, 부모 제공 + CQE 확인)
- 매시 스케줄러 회차가 시작 단계에서 5분 만에 `State=Failed` 로 죽고 이슈 0건 처리. 로그: `Running startup script threw an error: The term 'Get-GissueGairSkForCsn' is not recognized...`
- 호출처 특정 결과: 레포 안에 보호 없는 직접 호출은 없다. 모든 참조는 `Get-Command` 가드 뒤에 있다. 진짜 호출처는 잡의 `InitializationScript` 에서 닷소싱되는 라이브러리의 **최상위 적재 가드 자체**였다.
- 메커니즘 실측 (이 VM pwsh 7.4.6, 호스트 PS 5.1 오류 문구와 일치):
  - A: `Get-Command <없는 명령> -ErrorAction SilentlyContinue` 를 잡 init 에서 실행 → 가드 로직은 동작했으나 잡은 Failed. `SilentlyContinue` 는 표시만 억제하고 오류는 `$Error` 에 남으며, 잡 인프라는 시작 스크립트가 오류를 남기면 잡 전체를 실패로 만든다.
  - B: `-ErrorAction Ignore` → 잡 Completed. C: `SilentlyContinue` + `$Error.Clear()` → Completed. D: `Test-Path function:\<없는 명령>` → Completed, `$Error` 0건. E: 가드 없음 → Completed.
- 호스트 대조 (CQE mslsn 8261, ksn 51468974): 호스트 HEAD 04aef7c7, tracked 파일 diff 0건, `lib/gair-sk.ps1` 존재, `Get-GissueGairSkForCsn` 참조 6건 전부 가드 뒤 — 호스트 이탈이 아니라 코드 결함이다.
- 정본 범위 판단: 정본에는 `engine-lib.ps1`·`lib/gair-sk.ps1`·`Get-GissueGairSkForCsn` 이 없고 잡 init 주입 기법도 없다. 정본에 존재하는 동일 패턴은 `gissue-audit-lib.ps1:19` 최상위 가드(`Test-GissueGairCsnAllowed` 존재 확인) 1곳뿐이며, 이를 같은 방식으로 고치고 회귀 테스트를 붙이는 것이 정본 PR의 내용이다. 이식본(low) 쪽의 실제 발화점(`engine-lib.ps1:53` + `gissue-audit-lib.ps1:25`)은 이식 PR에서 처리한다.

## 변경
- `scripts/gissue/gissue-audit-lib.ps1:19` — 최상위 가드의 존재 확인을 `Get-Command ... -ErrorAction SilentlyContinue` 에서 `Test-Path function:\Test-GissueGairCsnAllowed` 로 교체. 함수 안의 호출 시점 `Get-Command`(:851 등)는 그대로 둔다.
- `scripts/gissue/tests/test-job-init-audit-lib-guard.ps1` (신규, 3건) — A1 잡 init 닷소싱 완료+함수 적재, F1 [기대 FAIL 음성 대조군] 구 패턴 잡 init 실패 재현, C1 최상위 코드 줄 `Get-Command` 부재.
- `docs/60-operations/hourly-issue-scheduler-runtime.md` — "잡 시작 스크립트 존재 확인 (job-init guard) — Get-Command 금지" 절 추가.
- `docs/WHATS_NEW.md` — 2026-11-26 항목 추가.

## 테스트
- 신규 `test-job-init-audit-lib-guard.ps1`: 3/3 PASS. 구 코드(origin/main 추출본)에서는 A1 FAIL(실패 문구가 호스트 로그와 동일)·C1 FAIL·F1 PASS — 테스트가 구 코드를 검출함을 확인했다.
- 기존 회귀: `test-gair-gate` ALL PASS, `test-gair-judges` ALL PASS, `test-gh-cache` 21/21, `test-bounded-process` 44/44, `test-worktree-cleanup-timebox` 60/60, `test-worktree-merge-gate-failclosed` 18/18 (`TEMP=/tmp` 지정 시; 미지정 시 `$env:TEMP` null 로 line 64에서 실패하는데, origin/main 에서도 동일하게 실패하는 이 VM 환경 문제이지 회귀가 아니다).
- 파스: 변경 파일 2건 파스 OK.

## 후속 (미구현, 별도 이슈로 이관)
- 같은 최상위 `Get-Command` 패턴이 있는 다른 파일(`lib/unmapped-csn-guard.ps1:36,39`, `page-feedback-analyze.ps1:60`)은 잡 init 경로가 아니라 스윕·독립 스크립트에서만 닷소싱되므로 이번 PR 범위 밖이다. 같은 방식으로 교체하는 후속 작업이 필요하다.
