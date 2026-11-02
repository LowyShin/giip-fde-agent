# KNOW-026 — giip 이슈 regdate 는 UTC 저장인데 JSON 의 /Date(ms)/ 는 -9h 값이다

> 근거: 2026-11-02 저장소 정비 70차 세션 실측 (work_history 20261102_1512) · 발행: 2026-11-02 · 상태: 검증됨(실측)

## 요지

**`listRecentCommentIssues.ps1` 가 출력하는 JSON 의 `lastCommentAt` 을 UTC 로 읽으면 9시간 과거로 보인다.**
DB(`tGiipIssue.regdate`·`tGiipIssueComment.regdate`)는 **UTC 로 저장**하고,
PowerShell 5.1 의 `ConvertTo-Json` 은 그 값을 로컬(KST) 로 간주해 UTC 로 밀어 쓴다 → `/Date(ms)/` = **저장값 − 9h**.

| 조회 대상 | DB 저장값(UTC) | JSON `/Date(ms)/` 를 UTC 로 읽은 값 | +9h |
|---|---|---|---|
| giip 4429 완료 보고 코멘트 | 2026-11-02 05:35:42 | 2026-11-01 20:35:42 | 2026-11-02 05:35:42 |
| giip 4411 완료 보고 코멘트 | 2026-11-01 18:43:29 | 2026-11-01 09:43:29 | 2026-11-01 18:43:29 |

## 판정 규칙

1. **SQL 쪽 시간창 필터는 정확하다.** `DATEDIFF(MINUTE, lastActivity, GETDATE()) <= N` 은 DB 서버(=UTC) 기준이라
   그대로 믿어도 된다. **틀리는 것은 JSON 을 사람이 읽는 쪽**이다.
2. JSON 시각을 사람이 읽을 때는 **+9h** 를 더해 DB 저장값(=실제 UTC) 을 얻고, KST 가 필요하면 **+18h**(=+9h 를 두 번) 한다.
3. GitHub 의 `mergedAt` 등 외부 시각과 대조할 때는 **같은 축(UTC)** 으로 맞춘다. 70차가 `giip 4429` 의 "PR #346 머지 커밋" 주장과
   `verify-runner.mjs 4429 70424` → PASS(1/1) 를 대조할 때 이 축이 맞지 않으면 **정상 PR 을 "먼저/나중" 으로 잘못 판정**한다.

## 관련

- `KNOW-021` — 스케줄러 생존은 로그 신선도로 판정
- 작업 기록: `.agent/work_history/20261102_1512_csn70424_repo-maintenance.md`
