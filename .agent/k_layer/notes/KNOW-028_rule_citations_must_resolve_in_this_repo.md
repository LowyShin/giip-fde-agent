# KNOW-028 — 작업 기록의 규칙 인용은 "이 저장소에 실제로 존재하는 파일명"만 쓴다

> 근거: 2026-11-03 저장소 정비 79차 세션 실측 (work_history 20261103_1145) · 발행: 2026-11-03 · 상태: 검증됨(실측)

## 요지

**작업 기록(`.agent/work_history/*.md`)의 "적용한 규칙" 목록은 이 저장소 `.agent/rules/` 에 실제로 있는
파일명만 적어야 한다.** gissue 스케줄러 프롬프트는 lowyworkenv 측 규칙 목록을 제공하는데, 그 목록을
그대로 옮기면 **이 저장소에서 경로가 깨진 인용**이 된다 — 번호는 겹쳐도 파일명이 다르다.

## 실측 (2026-11-03, 79차)

- 이 저장소 `.agent/rules/` 실파일 **53개** (`ls .agent/rules/`).
- `.agent/work_history/*.md` 전수에서 `.agent/rules/` 경로로 인용된 규칙 파일명을 전수 대조 →
  **이 저장소에 존재하지 않는 파일명 10종 / (파일×이름) 79쌍 / 기록 35개 파일**에서 발견.
- "아직 추가되지 않은 것"이 아니라 **"이 저장소 이력 전체에도 추가된 적 없다"** 를 확인:
  `git log --all --diff-filter=A -- .agent/rules/<파일명>` → 10종 전부 0건.

## 두 규칙 번호 체계가 겹친다 — 같은 번호가 다른 내용을 가리킨다

| 번호 | lowyworkenv(스케줄러 프롬프트 출처) | 이 저장소(giip-fde-agent) |
|---|---|---|
| 36 | `36_no_md_in_nongit.md` | `36_whats_new_maintenance.md` |
| 41 | `41_branch_lifecycle_pr.md` | `41_issue_session_safety_index.md` |
| 51 | (없음) | `51_giip_product_changes_csn47_only.md` |
| 55 | `55_destructive_cleanup_incident_gate.md` | `55_information_lookup_order_and_feedback.md` |
| 71 | `71_giip_product_changes_csn47_only.md` | `51_giip_product_changes_csn47_only.md` |
| 72 | `72_klayer_in_project_tkb_via_sk.md` | `55_information_lookup_order_and_feedback.md` |
| 73 | `73_fix_wrong_docs_on_discovery.md` | (없음) |
| 76 | `76_keep_working_csn.md` | `46_cross_csn_write_scope.md` |
| 77 | `77_encoding_corruption_fix_on_discovery.md` | (없음) |
| — | `PROTOCOL_ACTIONFLOW_TEST_GATE.md` | (없음) |

**55번이 특히 위험하다** — 두 저장소 모두 55번이 있고 내용이 완전히 다르다.
"55번 규칙" 이라는 구두 인용만 남기면 어느 쪽 규칙인지 알 수 없다.

## 대응표 (인용된 파일명 → 이 저장소의 실제 파일)

| 인용된 파일명 | 이 저장소에서의 실제 대응 |
|---|---|
| `36_no_md_in_nongit.md` | 동등 규칙 없음 — `33_artifact_hygiene.md`(정본 분리)가 가장 가까움 |
| `41_branch_lifecycle_pr.md` | `41_issue_session_safety_index.md` + `35_commit_push_per_task.md` |
| `55_destructive_cleanup_incident_gate.md` | `47_auto_cleanup_safety_requirements.md` |
| `61_klayer_registration_must_be_committed.md` | `35_commit_push_per_task.md` + `55_information_lookup_order_and_feedback.md` |
| `71_giip_product_changes_csn47_only.md` | `51_giip_product_changes_csn47_only.md` (파일명·내용 동일, 번호만 다름) |
| `72_klayer_in_project_tkb_via_sk.md` | `55_information_lookup_order_and_feedback.md` |
| `73_fix_wrong_docs_on_discovery.md` | 동등 규칙 없음 — `29_tool_usage_and_verification.md` + `33_artifact_hygiene.md` |
| `76_keep_working_csn.md` | `46_cross_csn_write_scope.md` |
| `77_encoding_corruption_fix_on_discovery.md` | 동등 규칙 없음 — `29_tool_usage_and_verification.md` |
| `PROTOCOL_ACTIONFLOW_TEST_GATE.md` | 동등 프로토콜 없음 — `PROTOCOL_PROGRESS_COMMENT.md` + `45_gate_cap_needs_decision.md` |

## 왜 위험한가

기록을 읽는 사람이 "이 규칙은 어디에 있는가" 를 물으면 **이 저장소에는 답이 없다** — 경로를 따라가면 404 다.
`29_tool_usage_and_verification.md` §1(암시된 파일도 실제 존재 여부 확인)이 요구하는 바로 그 상태다.

다만 **작업 내용을 지킨 근거 자체는 사라지지 않는다** — 인용이 가리키는 lowyworkenv 규칙은 실제로 존재하고
그 규칙을 따랐다는 사실은 유효하다. 고쳐야 하는 것은 **경로가 깨진 인용 표기**다.

## 교훈

1. **규칙 인용은 경로로 검증한다** — `.agent/rules/` 에 실제로 있는 파일명만 적는다.
   검증 명령: `ls .agent/rules/` + `git log --all --diff-filter=A -- .agent/rules/<파일명>`.
2. **과거 기록은 고쳐 쓰지 않는다** — `> 정정(날짜, 회차): ...` 블록을 덧붙인다.
3. **같은 번호 체계가 겹치면 번호가 아니라 파일명을 쓴다.**

## 관련

- `KNOW-013` — 회차 기록의 "완료" 서술은 실행되지 않은 계획일 수 있다
- `KNOW-015` — "열린 PR 0건"은 "할 일 없음"의 증거가 아니다
- 규칙 `29_tool_usage_and_verification.md` §1 · `33_artifact_hygiene.md`
- 79차 작업 기록: `.agent/work_history/20261103_1145_csn70424_repo-maintenance.md`
