# KNOW-035 — Windows PowerShell 5.1 의 `ConvertFrom-Json` 은 JSON 배열을 전개하지 않는다 — 다건 응답이 "행 1개"가 된다

> 근거: 2026-11-04 CSN 70424 세션 실측 (giip 4434 · 정본 러너 `FindOpenChildren` 포트 구동) · 발행: 2026-11-04 · 상태: 검증됨(스텁 API 실측)

## 요지

Windows PowerShell **5.1**(운영 런타임)의 `ConvertFrom-Json` 은 JSON **배열**을 **배열 1개(단일 파이프라인 항목)** 로 돌려준다.
그래서 이 방식은 안전하지 **않다**:

```powershell
$rows = @($json | ConvertFrom-Json)      # PS 5.1 → 원소 1개(그 원소가 배열이다)
```

`ForEach-Object` 는 **1번만** 돈다. 결과적으로 "행"이 1개가 되고, 그 행의 속성(`isn`/`status`/`title`)은
**배열**이 된다. PS 7 에서는 전개되므로 **같은 코드가 엔진에 따라 다른 결과**를 낸다.

## 사례 (giip 4434 — 정본 러너의 find-children)

정본 러너의 `FindOpenChildren` 포트(`scripts/gissue/run-gissue-claude.ps1`)가
`$rows = @($json | ConvertFrom-Json)` 를 쓰고, 그 결과를 실제 소비 함수
`Find-GissueOpenSplitChildren`(`scripts/gissue/lib/overtime-split.ps1`)가 받는다.

스텁 API 로 실측(2026-11-04 · Windows PowerShell 5.1.19041.6456):

| API 응답 | 포트가 돌려준 것 | 소비 함수의 결과 |
|---|---|---|
| 1건 | 행 1개 · `Isn=9001`(스칼라) | 정상 — 자식 1건 판정 |
| **2건** | **행 1개** · `Isn=Object[]{9001,9002}` · `Title`=제목 연결 문자열 | **예외** — `[int]$_.Isn` 캐스트 실패(`Cannot convert the "System.Object[]" value…`) |
| `[]` | 행 1개 · 속성이 모두 null | 무해 — 제목 정규식이 안 맞아 걸러짐 |

2건 이상이면 소비 함수가 예외를 던지고 → 오케스트레이터는 `find-children` 실패로 처리해
**rule 69-4 중복 서브이슈 감지가 무력화**된다. 안전 방향(분해 보류)이지만 증상은
giip 4434(원본: `execSQLFile` 출력 모드 착오)와 **같다** — 원인이 다르다.

> **운영 런타임은 5.1 이다** — 실측: Windows 작업 스케줄러 태스크 `GIIP_Gissue_Claude` 의 액션이
> `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe -File …\run-gissue-claude.ps1` 이다.
> 등록 스크립트(`scripts/register-hourly-issue-scheduler.ps1`)도 `powershell.exe` 로 등록한다.

## 규칙

1. **JSON 배열 파싱 후에는 배열을 명시적으로 전개한다.**
   `$parsed = ConvertFrom-Json $json` → `foreach ($r in $parsed)` 또는 `$parsed | ForEach-Object { $_ }`.
   `@($json | ConvertFrom-Json)` 한 줄짜리는 **PS 5.1 에서 안전하지 않다.**
2. **"행 개수"와 "행 안의 값"을 따로 단언한다.** 값만 보면 통과하고, 행 개수는 1로 잘못된다.
   (검증에서 값만 보고 통과시키는 것이 이 사고의 형태다.)
3. **PS 버전을 가정하지 않는다** — 5.1 과 7 의 `ConvertFrom-Json` 전개 동작이 다르다.
4. **소비 함수가 `[int]$row.Prop` 로 캐스트하면 "배열이 올 수 있다"는 전제로 방어한다.**
   배열이 오면 캐스트가 예외를 던지고, 그것은 "조회 실패"(fail-closed)로 오인되어 분해를 보류시킨다.

## 적용

- PowerShell 5.1 로 도는 스케줄러/작업 스크립트에서 JSON 배열을 파싱할 때.
- "행이 1개로 합쳐져서 필터가 안 걸린다" 증상이 나올 때.
- API 응답 개수에 따라 분기가 달라져야 하는 로직을 만들 때.

## 관련

- `KNOW-029` — DB 조회 출력은 모드가 둘(텍스트/객체) · 성공 판정을 출력 모양으로 하지 않는다
- `KNOW-025` — LLM 이 쓴 한국어가 조용히 깨진다(U+FFFD 0건이면 자동 탐지가 발화하지 않는다)
- 정본 러너 `scripts/gissue/run-gissue-claude.ps1` · 소비 함수 `scripts/gissue/lib/overtime-split.ps1`
- 회귀 테스트 `scripts/gissue/tests/test-overtime-findchildren-port.ps1` (내용 계약만 고정 · 행 개수는 고정하지 않음)
