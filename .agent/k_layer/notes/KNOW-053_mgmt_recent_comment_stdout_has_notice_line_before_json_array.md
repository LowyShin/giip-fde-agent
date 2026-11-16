# KNOW-053 — [H] 조회 stdout 은 "안내문 1줄 + JSON 배열" — "배열이 아니다" 로 오진단하지 않는다

> 근거: 2026-11-16 CSN 70424 저장소 정비 150차 세션 실측 · 발행: 2026-11-16 · 상태: 검증됨(파싱 2회 실측)
>
> 관련 파일: `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1` (이 저장소 밖 · giipdb 관리 도구) · `scripts/gissue/get-issue.sh`

## 요지

`listRecentCommentIssues.ps1 -Csn <csn> -HoursBack <h> -Json` 의 stdout 은 **① `Write-Host` 안내문 1줄 + ② JSON 배열** 이다.

- **배열은 진짜 배열이다** — 스크립트가 `ConvertTo-Json` 결과를 파일에 써서 되읽은 것이므로 `[ {...}, {...} ]` 형태다.
- **문제는 배열 "앞"에 안내문 줄이 붙는 것** — stdout 전체를 `JSON.parse` 에 넣으면
  `Unexpected token 'L', "Listing is"... is not valid JSON` 로 **실패**한다.
- 안내문 줄만 건너뛰면(첫 `[` 부터) **배열 파싱은 정상**이다.

## 실측 (2026-11-16, 150차)

| 대상 | 조작 | 결과 |
|---|---|---|
| stdout 전체 | `JSON.parse` | **실패** — `Unexpected token 'L', "Listing is"... is not valid JSON` |
| 첫 `[` 부터 | `JSON.parse` | **성공** — 배열 len=2 (2시간 창: isn 5449 · 5438) |

- **오진단 주의** — "배열이 아니라 객체가 이어진 JSON 이다"(concatenated) 라고 읽으면 괄호 깊이 스캐너를 먼저 짜게 된다.
  실제는 **배열 1개**이고 앞의 안내문만 걸러내면 된다. 파싱 단계를 생략하고 "파싱 실패" 라고 단정하면
  [H] 창 건수를 **0건 으로 오독**한다(조용히 사라지는 방향의 오류).

## 시각 축 — −9h 의 원인은 KNOW-026 · 150차는 API 쪽 참 UTC 만 교차 검증

- mgmt 의 `lastCommentAt` 은 `\Date(ms)` 형태이며 **DB 저장값(UTC) 보다 9h 이른 값**으로 직렬화된다.
  → 원인과 보정 규칙은 **[KNOW-026](KNOW-026_giip_issue_regdate_is_utc_but_json_date_is_minus_9h.md)** 에 이미 있다(여기서 되풀이하지 않는다).
- 150차가 **추가로 확정한 것** — **API(`get-issue.sh`) 쪽 `regdate` 가 참 UTC** 라는 교차 검증.
  - giip 5438 코멘트 regdate `2026-11-16T10:41:15Z` vs GitHub PR #473 `mergedAt` `2026-11-16T10:40:32Z` → **+43초**.
    (PR #473 은 "PR #473 으로 머지 완료" 라고 적는 그 코멘트의 대상 PR 이라 시간 순서가 성립한다.)
  - 같은 instant 의 mgmt 표시값 = `2026-11-16T01:41:15Z` → **정확히 −9h**.
  - → **"언제인가" 판정은 API `regdate` 로 한다**(mgmt 표시값을 UTC 로 읽지 않는다).
  - 24시간 창 12건 전건에서 같은 −9h 가 재현됐다(5053 · 4699 · 4556 · 4130 · 4300 · 4211 · 5398 · 2648 · 1968 · 4530 · 5438 · 5449).

## 규칙

1. **stdout 파싱은 "첫 `[` 부터" 잘라서 배열로** — 괄호 깊이 스캐너를 먼저 짜지 않는다.
2. **건수(창 포함 여부)는 mgmt 값을 쓴다** — 시간창 필터가 DB 기준이라 정확하다.
3. **시각 판정은 API `regdate` 로 한다** — mgmt 표시값을 UTC 로 읽지 않는다(KNOW-026 · 위 교차 검증).
4. **해석이 갈리는 시각은 두 소스를 대조한다** — 표에 "mgmt 표시값" 과 "API `regdate`" 를 **둘 다** 적어
   출처를 드러내고, 결론은 더 신뢰할 수 있는 쪽으로 내린다.

## 적용

- [H] 파싱 스크립트는 "첫 `[` 부터" 잘라 `JSON.parse` **한 번** 으로 끝낸다.
- [H] 기록의 시각 표는 두 소스를 **둘 다** 적어 출처를 드러낸다.

## 관련

- 작업 기록: [150차 저장소 정비](../../work_history/20261116_1907_csn70424_repo-maintenance.md)
- 짝지음 — [KNOW-026](KNOW-026_giip_issue_regdate_is_utc_but_json_date_is_minus_9h.md)(−9h 원인과 보정) ·
  [KNOW-054](KNOW-054_origin_main_ref_must_be_refreshed_before_it_is_used_as_the_comparison_base.md)(기준 ref 신선도)
