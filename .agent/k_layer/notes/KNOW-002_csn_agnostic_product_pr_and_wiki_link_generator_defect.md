# KNOW-002: 제품 레포 변경은 CSN 무관 PR 허용(2026-10-15 개정) + wiki 링크 생성기 결함

- 작업 CSN: 70424
- 관련 파일: `.agent/rules/51_giip_product_changes_csn47_only.md` + 진입점 7개
  (`CLAUDE.md`·`AGENTS.md`·`CODEX.md`·`COPILOT_INSTRUCTIONS.md`·`.cursorrules`·`.windsurfrules`·
  `GEMINI.md`) + 규칙 `00`/`41`/`46` + `docs/51-features/wiki-sync/wiki_sync.js` + `wiki/` 3개 파일
- 근거: (1) 사용자 직접 지시 **2026-10-15** — "전체 제품 레포에 CSN 무관 PR 허용"(정본:
  `lowyworkenv/.agent/rules/71_giip_product_changes_csn47_only.md` 개정(2026-10-15) 절).
  폐기된 규칙의 원 출처는 giip 2679(2026-09-18 사용자 직접 지시)이며 그 PR 이
  `.agent/rules/51_giip_product_changes_csn47_only.md` 를 신설했다(커밋 `48e1ab2`).
  (2) wiki 생성기 결함 — `wiki_sync.js` 는 커밋 `0ced92e` 로 현 위치로 옮겨졌고, 최초 구현 커밋은
  `0936248` 이다. wiki 페이지 커밋도 `0936248`·`72112e0` lineage다.

## 1. 원인분석 — "CSN 47 로만" 규칙이 이 레포에 남은 이유

2026-09-18 사용자 지시("giip 코어·프론트 기능 수정은 모두 csn 47로서만 등록 및 처리")가
`giip-fde-agent/.agent/rules/51_giip_product_changes_csn47_only.md` 로 이식되었고, 같은 문장이
에이전트 진입점 7개(`CLAUDE.md`·`AGENTS.md`·`CODEX.md`·`COPILOT_INSTRUCTIONS.md`·`.cursorrules`·
`.windsurfrules`·`GEMINI.md`)과 규칙 색인/참조 3개에 **복제**돼 있었다.

2026-10-15 사용자 지시("(a) 전체 제품 레포에 CSN 무관 PR 허용")로 그 대전제가 바뀌었으나, 오케스트레이션
레포(`lowyworkenv`)의 정본 규칙 71 만 개정되고 **이 레포의 사본은 갱신되지 않았다.** 정본과 어긋난
결과로, 이 레포에서 도는 에이전트는 **적법한 제품 레포 수정·PR 요청을 거부**하고(CSN 47 로 이관 후
원 이슈 닫기) 사용자에게 되묻게 된다 — 실제로 하는 일이 없는 경로.

즉 이 건은 "문서 하나가 오래됐다"가 아니라 **정본 변경이 파생 사본에 전파되지 않은** 유형이다.
파생 사본이 한 벌(진입점 7 + 규칙 4)씩 존재하는 구조는, 개정 시 **복제 지점 전체를 grep 으로 찾아**
같은 문구로 갱신해야 한다는 사실을 사례로 남긴다.

## 2. 재발방지

- 개정 반영 시 grep 기준을 "파일명" 이 아니라 **문구**로 잡는다:
  `git grep -n "CSN 47 only\|under CSN 47\|CSN 47 로만"` — 파일명이 `csn47_only` 로 남아 있어
  파일명 grep 만으로는 놓친다.
- 규칙 문서에는 **"개정(YYYY-MM-DD)" 절을 앞에 두고** 과거 본문은 삭제 없이 `[개정으로 폐지]` 표시만
  붙여 보존한다(rule 73 — 과거 기록은 고쳐 쓰지 않는다). 파일명은 유지한다(링크 파괴 방지).
- 유지되는 규칙을 개정 절에 **명시적으로 나열**한다: 작업 CSN 규칙 · PR 경유 · 전 CSN 공통 ·
  giipdb SQL 규칙 · 플랫폼 경계. "허용" 만 적으면 다음 개정이 경계를 넓힐 여지가 생긴다.

## 3. 원인분석 — wiki 링크 생성기 결함(2종)

`docs/51-features/wiki-sync/wiki_sync.js` 가 만든 wiki 링크는 **전량이 죽어 있었다.** 원인 2가지가
겹쳐 있었다.

1. **링크 형식**: `[${c.file}](file:///.agent/knowledge/notes/${c.file})` — 파일시스템 루트 기준
   절대경로이며 `file://` 스킴이 존재하지 않는다. → wiki 페이지 기준 **상대경로**
   (`path.relative` + `/` 정규화)로 변경.
2. **표가 치환되지 않음**: 표 치환 정규식이 separator 행을 2열(`| :--- | :--- |`)로 가정했으나 실제
   표 헤더는 3열(`| :--- | :--- | :--- |`)이고, 커밋된 wiki 파일은 **CRLF** 이므로 `\n` 요구도
   어긋났다. 정규식이 **한 번도 매칭되지 않아** 생성기가 기존 페이지를 갱신하지 못했다(페이지가
   통째로 stale 로 남고 링크가 죽은 채 방치된 원인). → separator 정규식을 3열 + `\r?\n` 허용으로 수정.

검증 방식: 저장소 wiki 에 직접 돌리지 않고 **격리된 샌드박스**에서 생성기를 실행한 뒤 상대링크를
전수 검사했다 → checked=30, broken=0.

## 4. 재발방지(생성기 쪽)

- 생성기 산출물은 **실행 후 링크가 실제로 resolve 되는지 검사**한 뒤에 커밋한다(생성기 = 링크를 만드는
  도구이므로 산출물 검증이 곧 회귀 게이트).
- 생성기를 저장소 wiki 에 그대로 돌리기 **전에** 무엇이 새로 유입되는지 확인한다. 이번 세션에서는
  `deployment-gotchas.md` 의 고객 claim(공개 도메인·IP·리소스 이름)이 wiki 페이지로 유입될 수 있어
  **링크 형식만** 고치고 표 재동기화는 보류했다(rule 54 — PUBLIC 범용 레포에 고객 특정 내용 금지).

## 5. 결과가 저장되는 곳

- 규칙 정본: `.agent/rules/51_giip_product_changes_csn47_only.md`(개정 절 추가, git-tracked).
- 진입점 링크: 진입점 7개 파일의 "GIIP PRODUCT SCOPE" 절(7곳 동일 문구로 갱신).
- 생성기: `docs/51-features/wiki-sync/wiki_sync.js`.
- 작업 기록: `.agent/work_history/20261023_081900_csn70424_repo-maintenance.md`.
- 이 노트: `.agent/k_layer/notes/KNOW-002_csn_agnostic_product_pr_and_wiki_link_generator_defect.md` + `INDEX.md`.

## 6. 소비처

이 레포에서 giip 제품 레포를 수정하려 할 때 "CSN 47 로 이관 후 원 이슈 닫기"를 먼저 떠올리는
에이전트/사람은 이 노트와 규칙 51 개정 절을 먼저 읽을 것. knowledge wiki 를 재생성하는 사람은
`wiki_sync.js` 를 돌리기 전에 §4 의 유입 점검을 할 것.

## 7. 남은 과제(본 노트 범위 밖)

- `.agent/tasks/giip-37xx.md`·`.agent/reports/giip-378x-*.md`·`.agent/specs/uregi-*`·
  `.agent/knowledge/notes/uregi-*`·`.agent/knowledge/notes/deployment-gotchas.md` 에 남아 있는
  고객 특정 내용 정리(규칙 54 "정리 대기 중인 알려진 위반 후보").
- wiki 표 재동기화(위 고객 claim 정리가 선행되어야 함).
