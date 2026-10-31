---
name: 조회 가드는 요청한 csn 이 아니라 응답이 실제로 돌려준 cSn 을 믿어야 한다
description: 서버는 멤버가 아닌 csn 요청을 홈 csn 으로 조용히 클램프한다. 요청값을 결과에 붙이는 가드는 거짓 양성 코멘트를 대량으로 남긴다 (giip 4116/4139)
metadata:
  type: project
---

# 응답 cSn 대조 (giip 4116 / 4139)

## 핵심

1. 이슈 목록 API 는 호출자가 멤버가 아닌 csn 을 요청하면 오류 대신 홈 csn 의 이슈를 돌려준다(클램프). 가드가 "요청한 csn 의 이슈"라고 믿고 판정하면 정상 csn 의 이슈에 `미등록` 경고 코멘트가 대량으로 달린다(실사고: 한 번의 실행에서 5건).
2. 방어선은 응답 행의 `cSn` 과 요청 csn 의 대조다. 다르면 `SKIP-CLAMP`, 필드가 없으면 `SKIP-NOCSN` 으로 버리고 로그만 남긴다 — 거짓 코멘트 1건의 비용이 누락 1건보다 크다.
3. 부정 판정("등록 안 됨")도 검증 대상이다. 게시 단위는 이슈별 코멘트가 아니라 csn 1건당 운영 이슈 1건이며, 남의 CSN 에 쓰지 않도록 대상 CSN 은 명시 설정(`GISSUE_CSNGUARD_OPS_CSN`)이 있을 때만 쓴다.

## 구현

- `scripts/gissue/lib/csn-guard.ps1` `Select-GissueRowsMatchingCsn`, `scripts/gissue/list-issues.js`(`cSn` 보존), `scripts/gissue/tests/test-csn-guard-clamp.ps1`.
- 사양: `docs/60-operations/hourly-issue-scheduler.md` 의 "미매핑 CSN 가드" 절.
