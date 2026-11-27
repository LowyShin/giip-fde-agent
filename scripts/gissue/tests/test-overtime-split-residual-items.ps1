# test-overtime-split-residual-items.ps1 — 2시간 초과 분할 잔여 작업 추출기 회귀 테스트 (giip 5200)
#
# 배경(giip 5200): overtime-split.ps1 의 Get-GissueRemainingChecklistItems 가 "## 완료조건" 절의
#   미체크 체크박스(- [ ])만 읽어, "## 남은 결함 (구현 대상)"·"## 해야 할 일" 처럼 번호 목록·일반
#   불릿으로 적힌 잔여 작업을 0건으로 오판 → 분할 불가(Splittable=$false)로 처리하는 결함이 있었다.
#
# 고정하는 것(이슈 완료조건 (a)~(d)):
#   (a) "## 남은 결함 (구현 대상)" 처럼 번호 목록(1. )으로 적힌 잔여 작업이 추출된다.
#   (b) "## 해야 할 일" 처럼 일반 불릿(- )으로 적힌 잔여 작업이 추출된다.
#   (c) "## 완료조건" 절의 서술형 불릿은 잔여 작업으로 잡히지 않는다(검증 설명이지 잔여 작업이 아님).
#   (d) 기존 체크박스 경로("## 완료조건" 의 - [ ])가 그대로 유지된다.
#   추가: 잔여 작업 절은 있으나 인식 가능한 항목이 0건이면 분할 불가 사유를 '항목 형식 미인식'으로
#         구분한다(오판 방지). / 체크된 체크박스(- [x])는 제외. / verify 코드펜스 안은 건너뛴다.
#         / 추출된 잔여 작업으로 2~5건 분할하고 각 자식이 원본 verify 를 승계한다(rule 69).
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-overtime-split-residual-items.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'lib/overtime-split.ps1')
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')

$script:fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}
function Texts($items) { @($items | ForEach-Object { $_.Text }) }

Write-Host '[A] (a) 번호 목록 잔여 작업 추출 + (c) 완료조건 서술형 불릿 제외'
$bodyA = @'
## 증상

어떤 결함을 관찰했다.

## 완료조건

- 번호 목록으로 적힌 잔여 작업이 추출되는지 검증한다
- 완료조건 절의 서술형 불릿이 잔여 작업으로 잡히지 않는지 검증한다

## 남은 결함 (구현 대상)

1. 추출기가 번호 목록을 인식하도록 고친다
2. 사유 문구를 오판 없이 구분한다
'@
$ra = Get-GissueRemainingChecklistItems $bodyA @()
$ta = Texts $ra
Assert (@($ra).Count -eq 2) "(a) 번호 목록 잔여 작업 2건 추출 (실제: $(@($ra).Count))"
Assert ($ta -contains '추출기가 번호 목록을 인식하도록 고친다' -and $ta -contains '사유 문구를 오판 없이 구분한다') '(a) 번호 목록 항목 본문이 정확히 추출'
Assert (-not ($ta -match '서술형 불릿') -and -not ($ta -match '검증한다$')) '(c) 완료조건 절의 서술형 불릿은 잔여 작업으로 잡히지 않음'

Write-Host '[B] (b) 일반 불릿 잔여 작업 추출'
$bodyB = @'
## 배경

경위 설명.

## 해야 할 일

- 할 일 하나를 처리한다
- 할 일 둘을 처리한다
- 할 일 셋을 처리한다
- 할 일 넷을 처리한다
'@
$rb = Get-GissueRemainingChecklistItems $bodyB @()
Assert (@($rb).Count -eq 4) "(b) 일반 불릿 잔여 작업 4건 추출 (실제: $(@($rb).Count))"
Assert ((Texts $rb) -contains '할 일 하나를 처리한다' -and (Texts $rb) -contains '할 일 넷을 처리한다') '(b) 불릿 항목 본문이 정확히 추출'

Write-Host '[C] (d) 기존 체크박스 경로 유지 — 완료조건의 - [ ] 만, - [x] 와 verify 펜스 제외'
$bodyC = @'
## 완료조건

- [x] 이미 끝난 항목
- [ ] 첫 번째 잔여 항목
- [ ] 두 번째 잔여 항목

```verify
echo original-verify
```
'@
$rc = Get-GissueRemainingChecklistItems $bodyC @()
Assert (@($rc).Count -eq 2) "(d) 완료조건 미체크 체크박스 2건만 추출 (실제: $(@($rc).Count))"
Assert ((Texts $rc) -contains '첫 번째 잔여 항목' -and -not ((Texts $rc) -contains '이미 끝난 항목')) '(d) 체크된 항목(- [x])은 제외, verify 펜스 안 미추출'

Write-Host '[D] 잔여 작업 절에서 체크된 체크박스 제외 + 번호/미체크 혼합'
$bodyD = @'
## 남은 결함

- [x] 이미 처리한 결함
- [ ] 아직 안 한 결함
1. 번호로 적은 잔여 결함
'@
$rd = Get-GissueRemainingChecklistItems $bodyD @()
$td = Texts $rd
Assert (@($rd).Count -eq 2 -and $td -contains '아직 안 한 결함' -and $td -contains '번호로 적은 잔여 결함') '잔여 절: 미체크 체크박스+번호 추출, 체크된 항목 제외'
Assert (-not ($td -contains '이미 처리한 결함')) '잔여 절: 체크된 체크박스(- [x])는 완료로 보고 제외'

Write-Host '[E] 잔여 작업 절 판정 — Test-GissueHasResidualWorkSection'
Assert (Test-GissueHasResidualWorkSection $bodyA) 'A 본문: "## 남은 결함" 절을 잔여 작업 절로 인식'
Assert (Test-GissueHasResidualWorkSection $bodyB) 'B 본문: "## 해야 할 일" 절을 잔여 작업 절로 인식'
$bodyNoResidual = @'
## 완료조건

- [x] 전부 끝남
'@
Assert (-not (Test-GissueHasResidualWorkSection $bodyNoResidual)) '완료조건만 있는 본문은 잔여 작업 절 없음(완료조건은 allowlist 아님)'

Write-Host '[F] 분할 불가 사유 구분(오판 방지) — 잔여 절 유무'
# 잔여 작업 절은 있으나 인식 가능한 항목 형식이 없는 본문(산문만)
$bodyResidualNoItems = @'
## 남은 작업

아직 손대지 못한 부분이 있지만 항목 형식으로 정리하지 못했다. 다음 세션이 정리한다.
'@
$itemsNone = Get-GissueRemainingChecklistItems $bodyResidualNoItems @()
Assert (@($itemsNone).Count -eq 0) '산문만 있는 잔여 절에서는 항목 0건'
$hasResidual = Test-GissueHasResidualWorkSection $bodyResidualNoItems
$planResidual = New-GissueOvertimeSplitPlan 500 '제목' $itemsNone @() 'u' 'c' 5 $hasResidual
Assert (-not $planResidual.Splittable -and $planResidual.Reason -match '잔여 작업 절은 있으나 인식 가능한 항목 형식이 없어') '잔여 절 있음+항목 0건 -> 사유=항목 형식 미인식(오판 방지)'
$planEmpty = New-GissueOvertimeSplitPlan 500 '제목' @() @() 'u' 'c' 5 $false
Assert (-not $planEmpty.Splittable -and $planEmpty.Reason -match '원본에 잔여 체크리스트 항목이 없어') '잔여 절 없음+항목 0건 -> 기존 사유 유지'

Write-Host '[G] 추출된 잔여 작업으로 2~5건 분할 + 각 자식이 원본 verify 승계 (rule 69)'
$bodyPlan = @'
## 완료조건

- 이 불릿은 검증 설명이다

```verify
echo original-verify
```

## 남은 결함 (구현 대상)

1. 결함 하나를 고친다
2. 결함 둘을 고친다
3. 결함 셋을 고친다
'@
$itemsPlan = Get-GissueRemainingChecklistItems $bodyPlan @()
Assert (@($itemsPlan).Count -eq 3) '잔여 번호 항목 3건 추출(완료조건 서술 불릿 제외)'
$vb = Get-GissueVerifyBlocks $bodyPlan
$plan = New-GissueOvertimeSplitPlan 500 '원본 제목' $itemsPlan $vb 'https://example.invalid/giip-issues/500' '원인요약' 5 (Test-GissueHasResidualWorkSection $bodyPlan)
Assert ($plan.Splittable -and $plan.Children.Count -ge 2 -and $plan.Children.Count -le 5) "분할 2~5건 (실제 $($plan.Children.Count))"
Assert (@($plan.Children | Where-Object { $_.Content -match 'echo original-verify' }).Count -eq $plan.Children.Count) '각 자식이 원본 verify 블록을 승계'
Assert ($plan.Children[0].Title -match '원본 giip 500 분해 1/' ) '자식 제목 관례 (원본 giip <isn> 분해 i/N)'

if ($script:fail -gt 0) { Write-Host "`n실패 $($script:fail)건" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
