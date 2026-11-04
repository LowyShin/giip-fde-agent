# KNOW-037 — Node 24 의 `node --test <디렉터리>` 는 거짓음성 — 이슈 verify 블록이 완료조건을 잘못 FAIL 로 만든다

> 근거: 2026-11-04 CSN 70424 · giip 4219 세션 실측 (work_history 20261104_2006) · 발행: 2026-11-04 · 상태: 검증됨(실측)

## 요지

Node v24.13.0 에서 `node --test <디렉터리>` 는 **디렉터리를 모듈로 해석**해
`Error: Cannot find module '<경로>'` (`code: 'MODULE_NOT_FOUND'`) 로 죽는다(exit 1).
같은 테스트를 **글로브/파일 인자**로 돌리면 통과한다.

→ 이슈 완료조건 verify 블록이 디렉터리 인자형이면 **코드가 정상이어도 검증이 실패**한다.
이 실패는 감사 게이트에서 "완료조건 verify 실행" 항목의 **판정불가(UNDETERMINED)** 로 바뀌어
이슈가 DONE 으로 갈 수 없게 만든다 — **구조적 함정**이다.

## 실측 (2026-11-04, giip-fde-agent / Node v24.13.0)

| 명령 | 결과 |
|---|---|
| `node --test slack-bot/tests/` | **exit 1** — `Cannot find module '<abs>\slack-bot\tests'` · tests 1 / pass 0 / fail 1 |
| `node --test "slack-bot/tests/*.test.js"` | **exit 0** — tests 60 / pass 60 / fail 0 |

## 실제 피해 (giip 4221)

4221 의 감사 코멘트 `[REVIEW-AUDIT:CHECKLIST-HOLD]`(2026-11-04T08:05:24Z) 에서
C10 "완료조건 verify 블록 실행" 이 **UNDETERMINED** 로 판정되었고, 근거란에
"node --test "$T/..." 거짓음성 (Node v24 비호환), 글로브형 60/0 PASS" 가 적혀 있었다.
19초 뒤(08:05:43Z) **REVIEW → NEEDS_DECISION** 전이가 발생했다.

판정 로직(`scripts/gissue/gissue-audit-lib.ps1` 의 `Get-ChecklistDecision`):
미충족 0건 + 판정불가 1건 → **HOLD**(NEEDS_DECISION) · 미충족 1건 이상 → **REVERT**(READY) · 전부 충족 → KEEP.

## 두 번째 결함 — 부분 추출

`git archive origin/main slack-bot` 처럼 **디렉터리만** 추출하면 형제 `slack-bot-minimax/` 가 없어
`slack-bot/tests/dashboard.test.js` 의 `require('../slack-bot-minimax/dashboard.js')` 가 MODULE_NOT_FOUND 로 죽는다(exit 1).
→ verify 블록은 저장소 전체를 추출하거나, 필요한 형제까지 포함해야 한다.

## 판정 규칙

1. `node --test <디렉터리>` 의 exit 1 을 **테스트 실패로 읽지 말 것.** 먼저 글로브형으로 재실행해 구분한다.
2. 이슈 verify 블록이 디렉터리 인자형이면 그것은 "구현 결함"이 아니라 **"verify 블록 호출 형식 결함"** 이다.
3. UNDETERMINED 항목이 나오면 자동 판정(KEEP/REVERT)에 맡기지 말고, 그 항목의 **재현 절차(글로브형 실행 결과)** 를
   코멘트로 남겨 판정 가능하게 만든다.
4. verify 블록은 저장소 전체를 추출한 뒤 실행한다(`git archive origin/main` 전체).

## 적용

- 이슈 완료조건에 `node --test` 를 쓸 때 — 디렉터리 인자 금지, 글로브/파일 인자 사용.
- verify 실행 결과(exit 1)를 근거로 "구현 실패"를 주장할 때 — 형식 결함 가능성을 먼저 배제.
- REVIEW→NEEDS_DECISION 전이 사유가 "증거 부족"일 때 — verify 블록 형식부터 본다.

## 관련

- `KNOW-013` — 회차 기록의 "완료" 서술은 실행되지 않은 계획일 수 있다
- `KNOW-022` — PR 머지는 이슈 측 쓰기 실행의 증거가 아니다
- `KNOW-033` — verify-runner exit 4 는 "검증 미실행" 이다
- 작업 기록: `.agent/work_history/20261104_2006_csn70424_giip-4219-jev-spec-status-sync.md`
