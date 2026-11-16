# 토큰 사용량 기록 1단계 — 시간창 상한 + 호출 카운트 의미 확정 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 호스트 로컬 토큰 합산(`Get-GissueTranscriptTokenUsage`)이 ① 실행 시간 범위를 **닫힌 구간**으로
고정할 수 있게 하고, ② `engines[].calls` 의 의미를 "4분류 중 하나라도 토큰이 계수된 엔진 호출 수"로
확정해 `<synthetic>` 같은 로컬 생성 레코드가 호출 수·호출당 평균을 왜곡하지 않게 한다.

**Architecture:**
1. **시간창 상한** — `Get-GissueTranscriptTokenUsage` 에 선택적 `-UntilUtc` 를 추가한다. 구간은 반열린
   `[SinceUtc, UntilUtc)` 이며, 상한이 없으면 기존처럼 하한만 적용된다(기존 호출부 하위 호환).
2. **호출 카운트 의미** — 4분류(freshIn/cacheCreate/cacheRead/out) 합계가 0 인 레코드는 "계측된 엔진 호출"이
   아니므로 `engines[]` 에 넣지 않는다. 판정 근거는 §2 의 실측(아래).
3. **문서 동기화** — 설계 문서(§3.2 레코드·§5 도입 순서)와 가이드 §17-2 기록 표, What's New 를 갱신한다.

**Tech Stack:** PowerShell 5.1(Windows) / `scripts/gissue/lib/token-usage.ps1` / `scripts/gissue/tests/test-token-usage.ps1`

---

## 근거(실측) — 이 계획이 필요한 이유

1. **구간을 고정할 수 없다.** 1단계 합산 함수는 `-SinceUtc`(하한)만 받아 "실행 시간 범위 안"을 만들지
   못한다. 하한만 있으면 값이 계속 늘어나 A/B/C 3자 대조의 기준 구간이 재현되지 않는다.
2. **`<synthetic>` 이 `calls` 를 오염시킨다.** 엔진 세션 기록(JSONL) 전체 실측 결과 `model=`<synthetic>`
   742건 — 전부 4분류 토큰 0 · content type=text · stop_reason=stop_sequence · 본문은
   "You've hit your weekly limit" / "API Error: Request rejected (429)" 등 CLI 로컬 생성 메시지.
   이 레코드의 message id 가 실제 모델 레코드와 겹치는 건 0/742 → 엔진 호출이 아니라 로컬 알림이다.
   그런데 현재 구현은 이것도 `calls` 에 세고 `engines[]` 에 `<synthetic>` 이라는 **가짜 모델 행**을 만든다.
   - 호출 수 부풀림 → "호출당 평균 토큰"(설계 §1 의 근거 수치)이 실제보다 낮게 왜곡된다.
   - `<synthetic>` 은 모델이 아니다 → 설계 §3.3 의 롤업 차원(CSN × 일자 × **모델** × 분류)에 잡히면 안 된다.
   - limit/429 발생 사실은 이미 별도 채널(`scheduler_alarm` kind=`LIMIT`)이 담당한다 → 여기서 중복 계수할
     이유가 없다.

---

## Task 1: 실패하는 테스트를 먼저 추가

**Files:**
- Test: `scripts/gissue/tests/test-token-usage.ps1`

**Step 1: 픽스처 추가** — 기존 픽스처는 건드리지 않고, 별도 워크디렉터리(`D:\work\csn-repo2`)에 새 픽스처를
만든다(기존 기대값을 흔들지 않기 위함). 줄 4개:
- `06:40` `<synthetic>` 4분류 모두 0 → **제외되어야 한다**
- `06:41` MiniMax-M3 `10/0/20/2` (위 레코드와 **같은 message id** `s1`) → 살아남아야 한다(0-토큰 레코드가
  먼저 나와도 id 를 미리 소비해 버리면 안 된다)
- `07:00` MiniMax-M3 `1000/0/0/1000` → 상한 경계 처리 확인용
- `07:30` MiniMax-M3 `2000/0/0/2000` → 상한 밖

**Step 2: 기대값 명시** —
- 상한 없음: 모델 행 1개(`<synthetic>` 행 0개), `calls=3`, `freshIn=3010`, `cacheRead=20`, `out=3002`
- `-UntilUtc 07:15Z`: `calls=2` (07:30 제외 — **필터가 실제로 동작함을 증명하는 기대 FAIL 케이스**)
- `-UntilUtc 07:00Z`: `calls=1` (경계 07:00 자체는 반열린 구간이라 제외)

**Step 3: 실행해 RED 확인** —
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-token-usage.ps1`
→ `FAIL 0-토큰 레코드 제외 후 모델 1종 : expected [1] got [2]` 처럼 **실패해야 한다**.
실패하지 않으면 테스트가 원하는 동작을 검사하지 못한 것이다(rule 42).

---

## Task 2: 최소 구현

**Files:**
- Modify: `scripts/gissue/lib/token-usage.ps1`

**Step 1:** `Get-GissueTranscriptTokenUsage` 파라미터에 `[datetime]$UntilUtc = [datetime]::MaxValue` 추가.
`$untilUtc = ConvertTo-GissueUtcDateTime $UntilUtc` 로 정규화(하한과 같은 Kind 규약).

**Step 2:** 레코드 필터에 `$tsUtc -ge $untilUtc` 면 제외(하한은 `-lt` 로 이미 제외 중).

**Step 3:** 토큰 4분류를 먼저 읽어 지역 변수로 계산하고, 합계가 0 이면 **id 소비 전에** `continue`.
계산 순서가 중요한 이유: 같은 message id 로 0-토큰 레코드가 먼저 나오고 실제 토큰 레코드가 뒤따르면,
0-토큰 쪽에서 id 를 소비해 버리면 그 호출이 통째로 사라진다.

**Step 4:** 합계를 `$row` 에 더하고 `calls` 를 1 증가(기존과 동일).

---

## Task 3: GREEN 확인 + 게이트

**Step 1:** `test-token-usage.ps1` 재실행 → `PASS test-token-usage`, exit 0.

**Step 2:** `test-kvs-report.ps1` 재실행 → `PASS test-kvs-report`, exit 0 (전송 페이로드 회귀 없음).

**Step 3:** `scripts/gissue/run-repo-gates.ps1` 실행 → 전체 게이트 green.

---

## Task 4: 문서 동기화

**Files:**
- Modify: `docs/60-operations/token-usage-metering.md` — §3.2 `calls` 의미 확정 + §5 1단계 상태줄
- Modify: `docs/60-operations/hourly-issue-scheduler.md` — §17-2 기록 표의 `scheduler_token_usage` 행
- Modify: `docs/WHATS_NEW.md` — 항목 추가(규칙 36)
- Add: `docs/plans/2026-11-16-token-usage-window-and-calls-semantics.md` (이 문서)

**주의:** 이 저장소는 PUBLIC 범용 레포다(rule 54) — 실제 CSN 번호·호스트·계정을 새로 쓰지 않는다.

---

## Task 5: PR

- 브랜치 → 커밋(명시적 경로만 `git add`) → push → PR.
- `main` 직접 push 금지. 스테이징은 `git add <경로>` 로 경로를 하나씩 지정(`git add -A` 금지).
- PR 본문에는 이슈 링크를 `https://giip.littleworld.net/ko/admin/giip-issues/5398` 형식으로 쓴다.

---

## 범위 밖

- 2단계(플랫폼 롤업·요율표·청구 라인), 3단계(판단 게이트 시범).
- 라이브 러너(호스트가 실제로 도는 스케줄러 저장소) 반영 — 이 저장소 밖이며 다른 소유권 저장소라
  이번 작업 단위에서는 **요청까지만** 한다(rule 46 — 타 CSN 쓰기 금지).
- 요율·과금 개시 등 §6 정책 결정.
