# [giip 4431 항목 1] 잡 종료 후처리(Complete-Run 의 5~7개 사후 스윕)를 마감 판정 루프와 분리하고,
# 반복당 시간예산 안에서만 처리해 한 스윕이 길어도 다른 잡의 마감 판정을 막지 않음을 검증한다.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-complete-run-nonblocking.ps1
# 네트워크/파일 쓰기 없음. lib/run-finalize.ps1 의 순수 함수(가짜 시계·실행 포트)와, 러너 소스의
# 배선 위치가 맞는지만 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/run-finalize.ps1')).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

# 가짜 단조 시계. Run 포트가 각 항목의 .Secs 만큼 시계를 진전시켜 "스윕에 걸린 시간"을 모의한다.
# 포트 스크립트블록은 오직 script 스코프 변수($script:*)만 참조한다 — 스크립트블록은 기본 비클로저라
# lib 스코프에서 실행되므로, 함수-로컬을 캡처하려 하면 null 로 풀리고 GetNewClosure 는 $script:fakeNow
# 까지 스냅샷해 버린다. $script:* 는 실행 스코프와 무관하게 이 스크립트의 live 변수로 해석된다.
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$script:throwOnKey = $null
function New-Queue($durations) {
    $q = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($d in $durations) { $i++; [void]$q.Add([pscustomobject]@{ Key = "step$i"; Secs = [double]$d }) }
    return , $q   # 쉼표로 감싸 ArrayList 가 반환 시 언롤(Object[] 로 붕괴)되지 않게 한다
}
$ports = @{
    Now = { $script:fakeNow }
    Run = { param($item)
        if ($script:throwOnKey -and $item.Key -eq $script:throwOnKey) { throw 'boom' }
        $script:fakeNow = $script:fakeNow.AddSeconds($item.Secs)
    }
}

# ── (A) 비차단 증명: 예산 90초, 항목마다 60초 → 한 번 호출로 전부 돌지 않고 예산 넘으면 양보한다 ──
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$q = New-Queue @(60, 60, 60, 60, 60)
$resA = Step-GissuePostProcessQueue $q 90 $ports
Check 'A1 예산 내에서 일부만 처리(전부 아님)' ($resA.Remaining -gt 0) "Remaining=$($resA.Remaining)"
Check 'A2 최소 1건은 진행(기아 방지)' (@($resA.Ran).Count -ge 1) "Ran=$(@($resA.Ran).Count)"
Check 'A3 예산(90초)을 크게 넘겨 다 돌지 않는다(60초 항목 5개=300초를 한 번에 돌면 위반)' (@($resA.Ran).Count -le 2) "Ran=$(@($resA.Ran).Count)"

# 반복 호출로 큐가 결국 비워진다(루프가 여러 바퀴 돌며 마감 판정과 번갈아 처리).
$guard = 0
while (@($q).Count -gt 0 -and $guard -lt 20) { $null = Step-GissuePostProcessQueue $q 90 $ports; $guard++ }
Check 'A4 반복 호출로 큐가 결국 모두 비워진다' (@($q).Count -eq 0) "남음=$(@($q).Count)"

# ── (B) 빠른 스윕은 한 번에 다 처리 ──
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$q = New-Queue @(1, 1, 1, 1, 1)
$resB = Step-GissuePostProcessQueue $q 90 $ports
Check 'B1 빠른 스윕 5건은 예산 내 한 번에 전부 처리' (@($resB.Ran).Count -eq 5 -and $resB.Remaining -eq 0) "Ran=$(@($resB.Ran).Count) Remaining=$($resB.Remaining)"

# ── (C) -Drain 은 예산 무시하고 남은 전부 처리(루프 종료 후) ──
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$q = New-Queue @(60, 60, 60, 60, 60)
$resC = Step-GissuePostProcessQueue $q 10 $ports -Drain
Check 'C1 Drain 은 예산(10초)과 무관하게 5건 전부 처리' (@($resC.Ran).Count -eq 5 -and $resC.Remaining -eq 0) "Ran=$(@($resC.Ran).Count) Remaining=$($resC.Remaining)"

# ── (D) 최소 1건 보장: 예산 0, 한 항목이 999초여도 그 1건은 처리하고 즉시 양보(영구 기아 방지) ──
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$q = New-Queue @(999, 60, 60)
$resD = Step-GissuePostProcessQueue $q 0 $ports
Check 'D1 예산 0 이어도 최소 1건 처리' (@($resD.Ran).Count -eq 1) "Ran=$(@($resD.Ran).Count)"
Check 'D2 그 1건 뒤 즉시 양보(나머지 남김)' ($resD.Remaining -eq 2) "Remaining=$($resD.Remaining)"

# ── (E) 스윕이 예외를 던져도 Errors 에 담고 큐는 계속 진행 ──
$script:fakeNow = [datetime]'2026-01-01T00:00:00Z'
$script:throwOnKey = 'step2'
$q = New-Queue @(1, 1, 1)
$resE = Step-GissuePostProcessQueue $q 90 $ports
$script:throwOnKey = $null
Check 'E1 예외 항목은 Errors 에 담긴다' (@($resE.Errors).Count -eq 1 -and "$($resE.Errors[0])" -match 'step2.*boom') "Errors=$(@($resE.Errors) -join '|')"
Check 'E2 예외가 있어도 나머지 2건은 처리(던진 step2 포함 3건 모두 pop)' (@($resE.Ran).Count -eq 2 -and $resE.Remaining -eq 0) "Ran=$(@($resE.Ran).Count) Remaining=$($resE.Remaining)"

# ── (F) Get-GissuePostProcessItems: 종료한 잡 1건이 7개 스윕을 Csn/Workdir 값과 함께 큐잉한다 ──
$items = Get-GissuePostProcessItems 70424 '/work/x'
Check 'F1 7개 스윕 항목 생성' (@($items).Count -eq 7) "count=$(@($items).Count)"
Check 'F2 Csn/Workdir 를 값으로 담는다($r 클로저 함정 회피)' (@($items | Where-Object { $_.Csn -eq 70424 -and $_.Workdir -eq '/work/x' }).Count -eq 7) ''
$labels = @($items | ForEach-Object { $_.Label })
foreach ($need in @('PrGateSweep', 'ReviewDoneAudit', 'PrAttributionSweep', 'WorktreeCleanup', 'WorktreeDailySweep', 'LogShip', 'RepairRootOwned')) {
    Check "F3 스윕 '$need' 포함" ($labels -contains $need) "labels=$($labels -join ',')"
}

# ── (G) 예산 파싱 ──
Check 'G1 환경변수 없음 → 기본 90' ((Resolve-GissuePostProcessBudgetSec $null) -eq 90) ''
Check 'G2 양의 정수 사용' ((Resolve-GissuePostProcessBudgetSec '30') -eq 30) ''
Check 'G3 0/음수/비정수는 기본값' ((Resolve-GissuePostProcessBudgetSec '0') -eq 90 -and (Resolve-GissuePostProcessBudgetSec '-5') -eq 90 -and (Resolve-GissuePostProcessBudgetSec 'abc') -eq 90) ''

# ── (H) 러너 소스 배선 점검 ──
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
Check 'H1 lib/run-finalize.ps1 를 소싱한다' ($src -match "lib/run-finalize\.ps1") ''
Check 'H2 Complete-Run 이 Done 표시 후 사후 스윕을 큐잉한다' ($src -match '\$r\.Done = \$true\s*\r?\n\s*foreach \(\$item in \(Get-GissuePostProcessItems') ''
Check 'H3 스윕 분기 함수(Invoke-GissuePostProcessStep)가 있다' ($src -match 'function Invoke-GissuePostProcessStep') ''
Check 'H4 while 루프 안에서 큐 펌프를 돌린다' ($src -match '(?m)Invoke-GissuePostProcessPump\s*\r?\n') ''
Check 'H5 루프 종료 후 Drain 으로 남은 큐를 비운다' ($src -match 'Invoke-GissuePostProcessPump -Drain') ''
# 사후 스윕 7개 함수 호출이 분기 함수 안으로 이동했고(동기 연달아 호출 제거), 분기 함수에만 남아 있다.
$posStep = $src.IndexOf('function Invoke-GissuePostProcessStep')
$posCompleteEnd = $src.IndexOf('$r.Done = $true')
Check 'H6 PrGateSweep 호출이 Complete-Run 본문(동기 구간) 밖, 분기 함수 안에 있다' (($src.IndexOf('Invoke-GissuePrGateSweep $item.Csn') -gt $posStep)) ''
# Complete-Run 의 빠른 경로(Done 세팅 지점)와 분기 함수 사이에 옛 동기 스윕 7줄이 남아 있지 않은지:
$fastSeg = if ($posCompleteEnd -ge 0 -and $posStep -gt $posCompleteEnd) { $src.Substring($posCompleteEnd, $posStep - $posCompleteEnd) } else { '' }
Check 'H7 Complete-Run 빠른 경로에 동기 스윕 호출이 남지 않았다' (($fastSeg -notmatch 'Invoke-GissueReviewDoneAudit \$r\.Csn') -and ($fastSeg -notmatch 'Invoke-GissueWorktreeCleanup \$r\.Csn')) ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
