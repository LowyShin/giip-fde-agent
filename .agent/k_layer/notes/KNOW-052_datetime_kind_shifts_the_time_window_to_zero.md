# KNOW-052 — `DateTime.Kind` 가 섞이면 시간창이 조용히 0건이 된다: UTC 기준 파라미터는 함수 안에서 정규화한다

> 근거: 2026-11-16 CSN 70424 저장소 정비 149차 세션 실측 (work_history 20261116_1607) · 발행: 2026-11-16 · 상태: 검증됨(수정 전 FAIL · 수정 후 PASS 직접 실행 대조)
>
> 관련 파일: `scripts/gissue/lib/token-usage.ps1` · `scripts/gissue/tests/test-token-usage.ps1` · `docs/60-operations/token-usage-metering.md`

## 요지

**UTC 기준이라고 명시된 시각 파라미터에 어떤 `DateTime` 을 넘기느냐에 따라 시간창이 조용히 밀린다.**
`DateTime` 비교 연산자는 `Kind` 를 무시하고 **원시 tick 만** 비교한다. 그래서

- `Kind=Utc` 값과 `Kind=Local` 값은 **같은 instant** 이어도 tick 이 UTC 오프셋만큼 다르다,
- 그 결과 비교 결과가 뒤집혀 **오류 없이 0건**이 나온다.

0건은 "조용한 실패"다. 예외도 없고 로그도 없다. **측정 모듈에서 0건은 '측정값 0' 으로 오독된다** —
실제로 데이터가 있다고 보고하는 사람이 "이 구간은 사용량이 없었다" 라고 잘못 결론 내리게 된다.

## 실측 (2026-11-16, UTC+9 호스트)

호출부: `Get-GissueTranscriptTokenUsage -Roots 'C:\Users\lowys\.claude' -Workdir <저장소> -SinceUtc 2026-11-16T06:00:00Z`

| 형태 | `SinceUtc` 의 Kind | 결과 |
|---|---|---|
| `-SinceUtc 2026-11-16T06:00:00Z` (문자열 그대로) | `Local` (PowerShell 캐스트가 로컬로 변환) | **rows=0** — 창이 9시간 밀려 전부 탈락 |
| `-SinceUtc ([datetime]::Parse(..., AdjustToUniversal))` | `Utc` | rows=2 — 정상 |

- 근본: `[datetime]'2026-11-16T06:00:00Z'` 는 Kind=Local 이고 값이 `2026-11-16 15:00 +09:00` 이다
  (instant 는 맞지만 tick 표현이 로컬 기준). `LastWriteTimeUtc` 는 UTC tick 이므로 비교가 어긋난다.
- **UTC+0 호스트에서는 이 결함이 드러나지 않는다** → "CI 가 green 이면 멀쩡하다" 는 근거가 안 된다.
  회귀 테스트는 Kind 를 **명시적으로** 만들어(host TZ 와 무관하게) 이 차이를 고정해야 한다.

## 규칙

1. **UTC 기준 파라미터는 함수 안에서 정규화한다.** 호출자가 어떤 `Kind` 로 넘겨도 같은 instant 로 해석되게 한다.
   - `Kind=Utc` → 그대로
   - `Kind=Local` → `.ToUniversalTime()`
   - `Kind=Unspecified` → `SpecifyKind(..., Utc)` (파라미터 계약이 UTC 이므로 벽시계 유지)
2. **파라미터 이름이 `...Utc` 면 계약까지 검증한다.** 함수 시그니처는 값을 강제하지 못한다.
3. **"조용한 0건" 은 실패로 다룬다.** 0을 정상 결과로 돌려주지 말고, 호출자가 "빈 결과" 와 "창이 밀린 0" 을 구분할 수 있게 한다.
4. **회귀 테스트는 수정 전 코드에 FAIL 하는 것을 증명한다** — 수정 후 PASS 만 남기면 검사기 자체가 고장나도 조용히 통과한다.

## 적용

- 종점·시각 파라미터가 있는 함수(합산·창 선택·로그 구간 추출)를 새로 만들면 **입력 정규화** 를 넣는다.
- 시간 필터가 있는 테스트는 **호스트 TZ 와 무관하게** 차이를 고정한다(Kind 를 명시적으로 지정한 값으로 비교).
- 호출 예시 를 문서에 적을 때는 **문자열 형태 그대로** 적고, 그 형태가 실제로 동작하는지 확인한다
  (문서에는 모듈이 Kind 를 정규화한다고 명시한다).

## 관련

- 작업 기록: [149차 저장소 정비](../../work_history/20261116_1607_csn70424_repo-maintenance.md)
- 구현: `scripts/gissue/lib/token-usage.ps1` (`ConvertTo-GissueUtcDateTime` · `Get-GissueTranscriptTokenUsage`)
- 회귀 테스트: `scripts/gissue/tests/test-token-usage.ps1`
- 설계: `docs/60-operations/token-usage-metering.md` §5
