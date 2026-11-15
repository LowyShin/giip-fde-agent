# 작업 기록 — ORM·동적 SQL 지양 + static/파라미터 원칙을 rule·튜닝 role에 명문화 (giip 5349)

- 일시: 2026-11-15 13:32 JST
- 근거: 사용자 직접 지시 — "작업 rule 또는 튜닝 role에서 아래 내용에 해당하는 문서에는 필수로
  언급해줘. ORM 또는 동적 SQL은 가급적 쓰지 마세요. 불가피하면 SQL 본문은 static으로 고정하고
  값은 변수(파라미터)로만 전달해 주세요 — SQL injection 방지가 최우선입니다."
  같은 취지의 지시가 같은 날 다른 프로젝트의 결정 코멘트로도 먼저 남았고, 이번에
  giip-fde-agent 규칙 체계로 명문화한다. 등록 이슈 giip 5349 (PENDING).

## 조사 (범위를 먼저 확정)

- `.agent/rules`(58개) · `roles`(24개) · `workflows` 전수에서 ORM·동적 SQL·dynamic sql·
  injection·인젝션으로 검색. 적중 파일 다수는 "information" · "platform" 같은 부분 문자열
  오탐이었다.
- 실제로 SQL 작성·튜닝을 다루는 문서는 2건뿐:
  1. `rules/40_no_query_hints_at_scale.md` — SQL·SP·쿼리 작성의 HARD RULE이지만 ORM·동적
     SQL·injection 언급이 없었다.
  2. `roles/database_tuner.md` — Absolute prohibitions #3에 동적 SQL 금지는 있으나,
     "불가피하면 static 본문 + 값은 파라미터로만"이라는 폴백 정식화와 ORM 지양 · injection
     최우선 문구가 없었다.
- bkend-expert(특정 BaaS 플랫폼 역할), security_specialist(위협 인텔 자동화 역할)는 SQL
  작성을 다루지 않아 제외했다.

## 변경 파일 (4건)

1. `.agent/rules/40_no_query_hints_at_scale.md` — §6 신설: 지시 문구를 "필수 문구"로 전문
   수록 + 기본 경로(파라미터화 SP · 정적 SQL) + 불가피한 동적 실행의 조건(본문 static 고정,
   값은 바인딩 파라미터로만, 본문에 값을 끼워 넣는 코드는 그 자체로 취약점) + Why +
   database_tuner #3 상호 참조. 적용 시점에 ORM · 동적 SQL 항목 추가.
2. `.agent/roles/database_tuner.md` — Absolute prohibitions #3 보강: ORM · 동적 SQL 지양,
   불가피하면 static 본문 + 값은 바인딩 파라미터로만(never interpolated), "SQL injection
   prevention outranks every other concern here" 명시, 정본으로 rule 40 §6 링크.
3. `docs/WHATS_NEW.md` — 2026-11-15 항목 추가.
4. 이 작업 기록.

## 검증

- 커밋 전 `git diff` 로 추가 줄에 타 CSN 번호 · 고객 식별 문자열이 없는지 확인한다
  (공개 레포라 지시의 출처 프로젝트·이슈 번호는 레포 문서에 적지 않는다 — rule 54).
- 상대 링크 2건(../roles/database_tuner.md, ../rules/40_no_query_hints_at_scale.md)은
  실재 파일로 연결됨을 확인한다.
- 이 작업의 worktree(`wt-sqlrule`)는 PR 머지 후 rule 57 에 따라 정리한다.
