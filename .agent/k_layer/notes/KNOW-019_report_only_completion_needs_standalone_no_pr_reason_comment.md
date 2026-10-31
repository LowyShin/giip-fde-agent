---
name: PR 없는 조사/답변형 완료는 첫 줄이 [NO-PR-REASON] 인 독립 코멘트와 항목별 결론이 있어야 게이트를 통과한다
description: 마커는 상태전이 사유가 아니라 별도 코멘트의 첫 줄이어야 하고, 보고형 완료 판정은 의뢰와 결과의 1:1 대응을 본다 (giip 4231)
metadata:
  type: project
---

# PR 없는 완료 보고와 PR 완료 게이트 (giip 4231)

## 핵심

1. PR 완료 게이트는 REVIEW 이슈에 대응 PR 이 없으면 READY 로 되돌린다. 코드 변경이 없는 조사/답변형은 PR 이 있을 수 없어 최대 3회 되돌림 후 사람 확인으로 에스컬레이션된다.
2. 면제 조건(`Test-HasNoPrReasonMarker`): 어떤 코멘트의 첫 줄이 `[NO-PR-REASON]` 이고 그 아래 비어 있지 않은 사유가 있어야 한다. 상태전이 사유(Why)는 `## [actor] 상태전이` 가 첫 줄로 붙으므로 안 된다 — 행위자 헤더 없는 독립 코멘트로 보낸다(`giip-task.maybeCommentRaw`).
3. 마커만으로는 부족하다. 보고형 완료 판정이 의뢰와 결과를 대조하므로, 본문에 의뢰 요약 / 요청 항목별 결과 / 실행자 결론 / 최종 판정을 담는다.
4. 실행자 결과물(`resultContent`)이 try 블록 안의 `const` 라 코멘트 생성 지점에서 스코프 밖이던 것이 결론이 giip 에 안 실린 원인이었다.

## 구현

`slack-bot/no-pr-report.js`, `slack-bot/handlers.js`(onComplete), `slack-bot/giip-task.js`(`maybeCommentRaw`), `slack-bot/i18n-ui.js`, 테스트 `slack-bot/tests/no-pr-report.test.js`. 사양: `docs/60-operations/hourly-issue-scheduler.md` 해당 절. 관련: KNOW-016.
