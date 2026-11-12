# KNOW-043 — 원격 orphan 브랜치를 계승하기 전에는 "소유 축"을 확인한다

> 근거: 2026-11-13 CSN 70424 저장소 정비 105차 세션 실측 · 발행: 2026-11-13 · 상태: 검증됨(직접 실측)

## 요지

`KNOW-015` 의 "PR 이 없는 원격 브랜치" 4단계 판정표는 **그 브랜치가 누구 것인지** 를 보지 않는다.
그래서 "PR 이 없다" → "PR 을 만들어야 한다" 로 곧바로 직결되는 구멍이 남아 있다.

⇒ **소유 축(ownership) 1개를 추가한다.** 아래 3개 확인 중 하나라도 걸리면 **계승하지 않는다**.

| # | 확인 | 방법 | 미통과 시 |
|---|---|---|---|
| 1 | 이슈가 이 세션 CSN 소유인가 | `get-issue.sh <isn> <csn>` 응답의 `cSn` 값을 **직접 읽는다** | 계승 금지 |
| 2 | 그 CSN 이 작업 매핑에 있는가 | 러너 호스트의 `csn-projects.json` 매핑에 존재(이 저장소엔 `.example` 템플릿만 있다) | 계승 금지 |
| 3 | 커밋 저자가 이 세션 작업자인가 | `git log -1 --format='%an <%ae>'` | 계승 금지 |

## 실측 (2026-11-13 105차)

- `git ls-remote --heads origin` → orphan ref 3건(모두 `bot/task-giip-<isn>` 패턴).
- `gh pr list --head <branch>` 와 `--search <branch>` **양쪽 모두 `[]`** → "PR 이 없다" 는 사실로 확정.
- 그런데 3건의 이슈 `cSn` 이 **이 세션의 CSN 과 다르다**(축 1 미통과) · 그 CSN 은 러너 호스트의
  `csn-projects.json` 매핑에 **없다**(축 2 미통과 — 이 저장소에는 `.example` 템플릿만 있고 실데이터는
  러너 호스트 저장소에 있다) · 커밋 저자 중 2건은 **다른 운영자 메일**이고
  작업 내용도 **무관한 스케줄러 토큰 절감 3연속 태스크**(축 3 미통과).
- ⇒ **계승 0건 · PR 생성 0건 · 이슈 쓰기 0건**(rule 76 · rule 46 · rule 41).

## 규칙

1. **"PR 이 없다" 와 "계승 대상이다" 는 다르다.** `KNOW-015` 의 자동 publish 예외에 더해
   **소유 축** 을 통과해야 계승한다.
2. **이슈의 `cSn` 은 읽어서 확인한다.** "이 PC 에 키가 없어 못 읽었다" 는 **소유가 확인되지 않았다** 는
   뜻이지 소유가 확인되었다는 뜻이 아니다 — 추측으로 CSN 을 추정하지 않는다.
3. **PR 존재 판정은 `--head` 단독으로 하지 않는다.** `--search` 로 교차 확인한다.
4. **다른 CSN 의 원격 ref 를 지우지 않는다.** 남의 것이고 되돌릴 수 없다 — 정리 대상이 아니다.

## 관련

- [KNOW-015](KNOW-015_dead_session_branch_pushed_without_pr.md) — 죽은 세션이 PR 없이 push 한 원격
  브랜치 계승 절차(소유 축이 빠진 출발점)
- [KNOW-023](KNOW-023_dead_session_uncommitted_diff_can_be_older_than_main.md) — 죽은 세션 워크트리
  diff 가 main 보다 오래된 스냅샷일 수 있음
- `.agent/rules/46_cross_csn_write_scope.md` · `.agent/rules/41_issue_session_safety_index.md`
- work_history: `.agent/work_history/20261113_0115_csn70424_repo-maintenance.md`
