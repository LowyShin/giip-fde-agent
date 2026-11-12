# KNOW-042 — 큐의 elapsed 기준은 상태전이 시각이 아니라 "최신 코멘트 시각" 이다

> 근거: 2026-11-12 CSN 70424 저장소 정비 102차 세션 실측 · 발행: 2026-11-12 · 상태: 검증됨(직접 재측정)

## 요지

작업 큐(`list-issues.js --csn <N> --queue`)의 "얼마나 오래 그 상태였는가" 판정 기준은 **상태 전이 시각이
아니라 이슈 행의 `last_comment_date`(최신 코멘트 시각)** 이다. READY 는 경과 60분 지난 것만 큐에 들어온다
(`minAge: 60`).

⇒ **READY 이슈에 어떤 코멘트든 남기면 — 상태 전이 없는 `[H]` 정정·재검증 코멘트도 포함 — elapsed 가 0 으로
다시 시작하고 큐 진입이 최대 60분 밀린다.** 부수 효과이며 의도된 동작이다.
⇒ 큐 측정값의 신뢰성은 **① 측정 시각 ② `last_comment_date` 의 반영 지연** 두 축에 좌우된다.

## 소스 근거 (`scripts/gissue/list-issues.js`)

| 위치 | 내용 |
|---|---|
| 38~39행 (헤더 주석) | "elapsed 기준: 최신 코멘트 시각(없으면 이슈 등록일). 단 `[USER-REQUEST]` 코멘트가 있는 이슈는 등록일 기준" |
| 182·211행 | `lastCmtDate = issue.last_comment_date` (이슈 목록 API 값) → `const basis = isUserReq ? regdate : (lastCmtDate \|\| regdate);` |
| 144행 | `{ status: 'READY', label: 'READY', qprio: 2, minAge: 60, dedup: false }` — READY 진입 임계값 |
| 216행 | `if (spec.minAge > 0 && elapsed < spec.minAge) continue;` |

`basis` 에 **상태 전이 코멘트 시각은 들어가지 않는다.** 상태 전이 시각을 읽는 *다른* 경로
(`--min-age-minutes` 의 `extractStatusEnteredAt()`) 와는 다른 기준이다.

## 실측 (2026-11-12 102차 — CSN 70424)

| 확인 지점 | 결과 |
|---|---|
| 19:56 KST 큐 조회 | 큐 **23건 중 10건이 `[OPS]`** — `giip 4870` elapsed **76분** · `giip 4860` elapsed **74분** |
| 19:56 KST 측정의 기준시각 | 두 건의 `last_comment_date` 는 **되돌림 시각** — 4870 = 18:37:35(되돌림)·18:37:44(상태전이) / 4860 = 18:39:10·18:39:17 |
| 19:54:25 / 19:54:32 KST | `giip 4870` `[H]` 재검증 · `giip 4860` `[H]` 정정 코멘트 — 두 건 모두 **READY 유지 · 상태전이 없음** |
| 20:29 KST 큐 조회 | 큐 **35건 중 22건이 `[OPS]`** — 20:18 KST 예측(37건 중 24건) 대비 **정확히 2건 차이**(4870·4860) · 비[OPS] **13건은 19:56 KST 와 동일** |
| 20:29 KST `liveness-ops-issue.js find` | 열린 같은 제목 **24건 전부 READY** — 상태 변화가 아니라 경과 60분 미달로 큐에서 빠진 것 |
| 20:37 KST 재측정(후속 세션) | 큐 **35건 중 22건이 `[OPS]`** — 20:29 상태 유지 · 두 건 여전히 큐 밖(elapsed 43분) |

**19:56 측정은 19:54 코멘트를 아직 이슈 행에 반영하지 못한 값**이었다 — elapsed 76/74분은 그 시점의 기준이
19:54 코멘트가 아니라 **되돌림 시각(18:37~18:39)** 이었다는 뜻이다(반영됐다면 2분 미만이어야 한다).
반영 후 두 건은 큐에서 빠졌다. ⇒ 102차 예측 "20:18 KST 예상 큐 = 37건 중 24건" 은 **2건 과다**였고 초과분은
정확히 **코멘트를 남긴 2건**이었다 — 기준시각이 19:54 로 밀려 큐 진입이 **20:54 KST** 로 밀렸다
(19:54:25/19:54:32 + 60분).

**집계 기준**: `[OPS]` 건수는 **감지 제목(`[OPS] gissue 처리 무소식 감지`)의 정확한 일치**로 센다 —
`[OPS]` 문자열을 *포함*하는 후속 이슈(`giip 4907`)가 섞이면 어긋난다(20:37 KST 기준 substring 23건 ·
정확 일치 22건). 위 표의 10건/22건은 **정확 일치 기준**이다.

## 규칙

1. **READY 이슈에 어떤 코멘트든 남기면 큐 진입이 최대 60분 뒤로 밀린다.** 상태 전이 없는 `[H]` 코멘트도
   포함 — 부수 효과이며 의도된 동작이다.
2. **큐 측정값의 신뢰성은 ① 측정 시각 ② `last_comment_date` 의 반영 지연 두 축에 좌우된다.** 측정값이
   이상하면 두 축을 모두 의심한다.
3. **큐 감소를 관측하면 "큐 제외 구현" 과 "elapsed 재시작" 을 구분한다.** READY 유지면 **큐 제외가 아니라
   큐 진입 지연**이다.
4. **큐 오염 실측값은 코멘트 시점에 따라 달라진다.** 측정 시각과 대상 이슈의 **최신 코멘트 시각**을 함께
   기록한다.
5. **`[OPS]` 건수 집계는 감지 제목의 정확한 일치로 한다.**
6. **공개 저장소 기록에 다른 CSN 번호를 넣지 않는다** (`.agent/rules/54_generic_agent_no_customer_info.md`) —
   저장소 자기 CSN 기재만 예외.

## 절차 (측정 → 해석)

1. **측정 시각을 기록하고 큐를 스냅샷한다.** — `node scripts/gissue/list-issues.js --csn <N> --queue --json`
2. **빠진 이슈가 있으면 상태와 최신 코멘트 시각·상태전이 시각을 함께 확인한다.** —
   `node scripts/gissue/lib/liveness-ops-issue.js find --title-file <제목파일> --ops-csn <N>` ·
   `scripts/gissue/get-issue.sh <isn> <N> --comment-file <파일> --role .agent/roles/orchestrator.md`
   (코멘트 조회는 공유 체크아웃 cwd 에서 실행 — 시크릿 파일 부재.)
3. **상태가 READY 이고 경과 60분 미만이면 "큐 진입 지연" 으로 해석한다**(상태 변화 아님).
4. **60분 뒤 재측정해 진입 여부를 확인한다.** (예측 시각 = 최신 코멘트 시각 + 60분)

## 관련

- `KNOW-041` — 완료 게이트의 되돌림이 자동 감지 `[OPS]` 이슈를 큐에 다시 넣어 "큐 오염"을 재발시킬 수 있다
  (같은 세션 산출물 · 본 노트는 그 큐의 **진입 판정 기준**을 다룬다)
- `KNOW-039` — 무소식 감지 `[OPS]` 이슈가 작업 큐를 오염시키고 세션 1회분을 소비한다
- `scripts/gissue/list-issues.js` (`--queue` · 기준시각 211행) ·
  `scripts/gissue/lib/liveness-ops-issue.js` (`find`)
- work_history: `.agent/work_history/20261112_1958_csn70424_repo-maintenance.md`
- 후속 작업 이슈: [giip 4907](https://giip.littleworld.net/ko/admin/giip-issues/4907) · 실측 대상:
  [giip 4870](https://giip.littleworld.net/ko/admin/giip-issues/4870) ·
  [giip 4860](https://giip.littleworld.net/ko/admin/giip-issues/4860)
