# giip-fde-agent k-layer 색인

| KNOW | 제목 | 근거 giip | tKB kbSn |
|---|---|---|---|
| [KNOW-001](KNOW-001_csn_auto_language_resolution_undocumented_gap.md) | CSN 기반 응답 언어 자동해석은 이미 구현돼 있었으나 규칙 문서가 없었다 | giip 1252 | 1304 (이 INDEX.md 자체는 1303) |
| [KNOW-002](KNOW-002_csn_agnostic_product_pr_and_wiki_link_generator_defect.md) | 제품 레포 변경은 CSN 무관 PR 허용(2026-10-15 개정) — 이 레포의 폐기 규칙 사본 갱신 + wiki 링크 생성기 결함(링크 형식·표 정규식) | giip 2679 (폐기 규칙 원 출처) + 2026-10-15 사용자 직접 지시 (개정) | 6271 |
| [KNOW-003](KNOW-003_worktree_safety_dotsource_pitfall.md) | worktree-safety 모듈 dot-source 실패 → 링크 선검사 없이 삭제 진행 위험(fail-open) | 2026-10-23 CSN 70424 저장소 정비 세션 실측 (work_history 20261023_091900 T3) | 6274 |
| [KNOW-004](KNOW-004_fallback_root_relative_paths_and_other_human_mention_guard.md) | 폴백 루트별 상대경로(결함 A)·다른 사람 멘션 가드(결함 B)는 순수 함수 분리 + 회귀 테스트로 고정 | giip 4045 | 6299 |
| [KNOW-005](KNOW-005_child_process_output_tests_are_console_codepage_dependent.md) | 자식 프로세스 출력을 비교하는 테스트는 콘솔 코드페이지(cp932)에 종속 — "워크트리 green ≠ main green" | 2026-10-24 CSN 70424 저장소 정비 세션 실측 (work_history 20261024_043000 T1-1·§정정 A, PR #234/#235) | 6346 |
| [KNOW-006](KNOW-006_repo_gates_not_wired_to_ci.md) | 저장소 자체 게이트(check-ps1-parse + 회귀 테스트 24건)가 CI 에 결선돼 있지 않아 결함이 검증 없이 main 에 유입될 수 있었다 → 단일 진입점 `run-repo-gates.ps1` + CI 워크플로 | 2026-10-24 CSN 70424 저장소 정비 세션 실측 (work_history 20261024_051500) | 6349 |
