---
name: 런타임 전용 커밋이 PR 로 머지되는 사고와 게이트-세션 레이스 — 스테이징 제외 + PR 억제 + 디바운스
description: .agent/runtime/** 는 커밋·PR 대상이 아니다(스테이징 제외 + 산출물 없는 PR 억제). 게이트의 3회 누적 에스컬레이션은 작업 세션이 방금 움직인 이슈를 건드리면 handoff 와 레이스한다
metadata:
  type: project
---

# 런타임 전용 PR + 게이트 레이스 (giip 4300)

## 핵심

1. 작업 브랜치 커밋이 `git add -A` 이면 `.agent/runtime/**`(봇이 쓰는 기록) 만 담긴 커밋이 생기고, 실제 산출물 없이 PR 이
   열려 기본 브랜치에 머지될 수 있다. 저장소 규칙 문서에 "런타임은 커밋하지 않는다"가 있어도 **코드가 강제하지 않으면 지켜지지 않는다.**
   - 방어 2겹: (a) 스테이징 제외(`runtime-artifact-guard.js` `stageDeliverables`), (b) 산출물 없는 PR 억제(`branchHasDeliverables`, `ensurePR` 입구).
   - 둘 다 필요하다: (a) 만으로는 이미 런타임이 커밋된 브랜치(타 경로·수동 커밋)가 PR 로 나가고, (b) 만으로는 런타임이 산출물 커밋에 섞여 올라간다.
2. PR 이 **누구에 의해 머지되는지**는 봇 코드 안에서 `pr merge` 호출이 없었다 — 저장소 측 auto-merge/브랜치 보호 설정이라
   이쪽에서 특정할 수 없다. 코드로 PR 생성을 막는 것은 머지 경로 차단의 대체가 아니다.
3. 게이트(PR-gate/audit)의 3회 누적 에스컬레이션은 이슈가 IN_PROGRESS 로 활발히 작업 중인 구간의 체크에도 가산되면 세션의 정상
   handoff(REVIEW 전이)와 분 단위로 레이스한다. **마지막 작업 코멘트가 N분 이내면 한 틱 미룬다.** 이때 게이트 자신의 코멘트를
   활동으로 세면 자기참조로 무한 연장되므로 제외해야 한다(`Test-GateOwnComment`).

## 한계

- 동시 세션이 같은 isn 을 중복 수행하는 문제(세션 간 가시성)는 이 디바운스로 해결되지 않는다 — 별도 후속 이슈.

## 근거

giip 4300. 정본 위치: `slack-bot/runtime-artifact-guard.js`, `scripts/gissue/gissue-gate-tally-lib.ps1`(`Get-IssueActivityDebounce`),
사양 `docs/60-operations/hourly-issue-scheduler.md` §13-4, 테스트 `slack-bot/tests/runtime-artifact-guard.test.js`·`scripts/gissue/tests/test-gate-debounce.ps1`.
