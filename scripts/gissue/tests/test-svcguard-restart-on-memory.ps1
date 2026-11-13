# test-svcguard-restart-on-memory.ps1 — svcguard 측정/조건부 재기동 회귀 테스트
#
# 무엇을 막는가:
#   svcguard 러너는 "측정 → 임계 판정 → 최소 간격 가드 → 조건부 재기동" 판단을 로그로 남긴다.
#   판단 로직이 깨지면 두 가지 사고가 난다.
#     (1) 임계 초과인데 재기동하지 않는다 → 증상이 계속된다(도구가 없는 셈).
#     (2) 임계 미만/최소 간격 안 됨에도 재기동한다 → 필요 없는 서비스 중지가 반복된다.
#   특히 (2) 는 "측정 도구가 사고를 유발하는 도구"가 되므로 반드시 양방향으로 고정한다.
#
# 안전장치:
#   모든 러너 실행은 **-WhatIf** 로만 한다 → 어떤 서비스도 재기동되지 않는다.
#   등록 스크립트도 `-Action Register -WhatIf` 로만 호출한다 → 예약 태스크가 만들어지지 않는다.
#   (등록 후 "태스크가 없음" 을 실제로 확인한다.)
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-svcguard-restart-on-memory.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$Runner = Join-Path $RepoRoot 'scripts\svcguard\restart-service-on-memory.ps1'
$Registrar = Join-Path $RepoRoot 'scripts\svcguard\register-svcguard-scheduler.ps1'
$TargetGuard = Join-Path $RepoRoot 'scripts\gissue\task-target-guard.ps1'

$fail = 0
$pass = 0
$skip = 0

function Add-Result {
    param([bool]$Ok, [string]$Label, [string]$Detail = '')
    if ($Ok) {
        $script:pass++
        Write-Output ("PASS  {0}" -f $Label)
    } else {
        $script:fail++
        Write-Output ("FAIL  {0}{1}" -f $Label, $(if ($Detail) { " — $Detail" } else { '' }))
    }
}

function Add-Skip {
    param([string]$Label, [string]$Reason)
    $script:skip++
    Write-Output ("SKIP  {0} — {1}" -f $Label, $Reason)
}

if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    Write-Output "FAIL  러너를 찾을 수 없습니다: $Runner"
    exit 1
}
if (-not (Test-Path -LiteralPath $Registrar -PathType Leaf)) {
    Write-Output "FAIL  등록 스크립트를 찾을 수 없습니다: $Registrar"
    exit 1
}

$TmpRoot = Join-Path $env:TEMP ('svcguard-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $TmpRoot -Force | Out-Null

function Invoke-Runner {
    param([string]$ServiceName, [string]$LogPath, [string]$StatePath, [string[]]$Extra = @())
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Runner`"", '-ServiceName', $ServiceName,
        '-LogPath', "`"$LogPath`"", '-StateFile', "`"$StatePath`"")
    $argList += $Extra
    $out = & powershell @argList 2>&1
    return @{ code = $LASTEXITCODE; output = $out }
}

function Get-LastRecord {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) { return $null }
    try { return ($lines[-1] | ConvertFrom-Json) } catch { return $null }
}

# ── 0) 측정 가능한 실행 중 서비스 찾기 ─────────────────────────────────────────
# 스크립트는 서비스 이름을 인자로 받는다(하드코딩 없음). 테스트는 실제로 읽을 수 있는
# 서비스를 골라 붙여 "임의 서비스에 대해 동작한다" 를 확인한다.
function Get-MeasurableService {
    $candidates = @()
    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "State='Running'" -ErrorAction Stop
        $candidates = @($svc)
    } catch {
        try {
            $candidates = @(Get-Service | Where-Object { $_.Status -eq 'Running' })
        } catch { return $null }
    }
    foreach ($c in $candidates) {
        $name = $null
        $rawPid = 0
        if ($c.PSObject.Properties.Name -contains 'Name' -and $c.PSObject.Properties.Name -contains 'ProcessId') {
            $name = [string]$c.Name
            try { $rawPid = [int]$c.ProcessId } catch { $rawPid = 0 }
        } else {
            $name = [string]$c.Name
        }
        if (-not $name -or $rawPid -le 0) { continue }
        try {
            $p = Get-Process -Id $rawPid -ErrorAction Stop
            if ($p.PrivateMemorySize64 -gt 0) { return $name }
        } catch {
            continue
        }
    }
    return $null
}

$testService = Get-MeasurableService

try {
    # ── 1) 대상 서비스가 없을 때 ────────────────────────────────────────────────
    $log1 = Join-Path $TmpRoot 'notfound.jsonl'
    $state1 = Join-Path $TmpRoot 'notfound.state.json'
    $r1 = Invoke-Runner -ServiceName 'svcguard-test-no-such-service' -LogPath $log1 -StatePath $state1
    $rec1 = Get-LastRecord -Path $log1
    Add-Result ($r1.code -eq 0) '대상 서비스 없음 → 종료코드 0' ("exit=" + $r1.code)
    Add-Result ($null -ne $rec1 -and $rec1.serviceFound -eq $false) '대상 서비스 없음 → 로그에 serviceFound=false'

    if (-not $testService) {
        Add-Skip '재기동 판정 케이스' 'PrivateBytes 를 읽을 수 있는 실행 중 서비스를 찾지 못했습니다'
    } else {
        # ── 2) 임계 초과 + 최소 간격 통과 + -WhatIf → 재기동하지 않고 "할 수 있었음" ──
        $log2 = Join-Path $TmpRoot 'eligible.jsonl'
        $state2 = Join-Path $TmpRoot 'eligible.state.json'
        $r2 = Invoke-Runner -ServiceName $testService -LogPath $log2 -StatePath $state2 -Extra @('-WhatIf', '-ThresholdMB', '0')
        $rec2 = Get-LastRecord -Path $log2
        Add-Result ($r2.code -eq 0) '임계 초과(-WhatIf) → 종료코드 0' ("exit=" + $r2.code)
        Add-Result ($null -ne $rec2 -and $rec2.restartEligible -eq $true) '임계 초과 → restartEligible=true' ('측정 서비스: ' + $testService)
        Add-Result ($null -ne $rec2 -and $rec2.restartTriggered -eq $false) '임계 초과 → -WhatIf 이므로 실제 재기동 없음'
        Add-Result ($null -ne $rec2 -and $rec2.restartBlockedReason -eq 'whatif') '임계 초과 → restartBlockedReason=whatif'
        Add-Result ($null -ne $rec2 -and $rec2.privateBytesMB -gt 0) 'PrivateBytes 측정값이 기록됨'

        # ── 3) 임계 미만 → 재기동 대상 아님 ────────────────────────────────────
        $log3 = Join-Path $TmpRoot 'below.jsonl'
        $state3 = Join-Path $TmpRoot 'below.state.json'
        $r3 = Invoke-Runner -ServiceName $testService -LogPath $log3 -StatePath $state3 -Extra @('-WhatIf', '-ThresholdMB', '99999999')
        $rec3 = Get-LastRecord -Path $log3
        Add-Result ($r3.code -eq 0) '임계 미만 → 종료코드 0' ("exit=" + $r3.code)
        Add-Result ($null -ne $rec3 -and $rec3.restartEligible -eq $false) '임계 미만 → restartEligible=false'
        Add-Result ($null -ne $rec3 -and $rec3.restartBlockedReason -eq 'below-threshold') '임계 미만 → restartBlockedReason=below-threshold'

        # ── 4) 최소 간격 미경과 → 재기동 대상 아님 ─────────────────────────────
        $log4 = Join-Path $TmpRoot 'interval.jsonl'
        $state4 = Join-Path $TmpRoot 'interval.state.json'
        $seed = [ordered]@{ lastRestartUtc = (Get-Date).ToUniversalTime().ToString('o'); samples = @() }
        [System.IO.File]::WriteAllText($state4, ($seed | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        $r4 = Invoke-Runner -ServiceName $testService -LogPath $log4 -StatePath $state4 -Extra @('-WhatIf', '-ThresholdMB', '0')
        $rec4 = Get-LastRecord -Path $log4
        Add-Result ($r4.code -eq 0) '최소 간격 내 → 종료코드 0' ("exit=" + $r4.code)
        Add-Result ($null -ne $rec4 -and $rec4.restartEligible -eq $false) '최소 간격 내 → restartEligible=false'
        Add-Result ($null -ne $rec4 -and $rec4.restartBlockedReason -eq 'min-interval') '최소 간격 내 → restartBlockedReason=min-interval'

        # ── 4b) 임계 미만 + 최소 간격 내 (두 사유가 겹칠 때의 우선순위) ──────────
        # 두 조건이 동시에 걸리면 "왜 안 했는가"를 로그에서 하나로 읽을 수 있어야 한다.
        # 판정 순서는 임계 확인 → 최소 간격 확인 이므로 사유는 'below-threshold' 이 먼저 온다.
        $log4b = Join-Path $TmpRoot 'interval-and-below.jsonl'
        $state4b = Join-Path $TmpRoot 'interval-and-below.state.json'
        $seed4b = [ordered]@{ lastRestartUtc = (Get-Date).ToUniversalTime().ToString('o'); samples = @() }
        [System.IO.File]::WriteAllText($state4b, ($seed4b | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        $r4b = Invoke-Runner -ServiceName $testService -LogPath $log4b -StatePath $state4b -Extra @('-WhatIf', '-ThresholdMB', '99999999')
        $rec4b = Get-LastRecord -Path $log4b
        Add-Result ($r4b.code -eq 0) '임계 미만 + 최소 간격 내 → 종료코드 0' ("exit=" + $r4b.code)
        Add-Result ($null -ne $rec4b -and $rec4b.restartEligible -eq $false) '임계 미만 + 최소 간격 내 → restartEligible=false'
        Add-Result ($null -ne $rec4b -and $rec4b.restartBlockedReason -eq 'below-threshold') '임계 미만 + 최소 간격 내 → restartBlockedReason=below-threshold(사유 우선순위 고정)'

        # ── 5) 로그 JSON 스키마 ─────────────────────────────────────────────────
        $required = @('timestampUtc', 'mode', 'serviceName', 'serviceFound', 'serviceRunning', 'servicePid',
            'privateBytesMB', 'workingSetMB', 'baselinePrivateBytesMB', 'thresholdMB', 'systemProcessCount',
            'deltaPrivateBytesMB', 'deltaProcessCount', 'growthMBPerHour', 'growthMBPerNewProcess',
            'restartEligible', 'restartTriggered', 'restartBlockedReason',
            'privateBytesBeforeRestartMB', 'privateBytesAfterRestartMB', 'minutesSinceLastRestart')
        $missing = @()
        foreach ($f in $required) {
            if ($null -eq $rec2 -or -not ($rec2.PSObject.Properties.Name -contains $f)) { $missing += $f }
        }
        Add-Result ($missing.Count -eq 0) '측정 로그에 필수 필드가 모두 존재' ("누락: " + ($missing -join ', '))
        Add-Result ($null -ne $rec2 -and $rec2.mode -eq 'sample') '측정 로그 mode=sample'
        Add-Result ($null -ne $rec2 -and $rec2.timestampUtc -match '^\d{4}-\d{2}-\d{2}T') '측정 로그에 UTC 시각 기록'
    }

    # ── 6) 등록 스크립트: 미리보기는 아무것도 등록하지 않는다 ─────────────────
    $previewService = if ($testService) { $testService } else { 'svcguard-test-sample' }
    $previewOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Registrar -Action Register -WhatIf -ServiceName $previewService 2>&1
    $previewRc = $LASTEXITCODE
    Add-Result ($previewRc -eq 0) '등록 미리보기(-WhatIf) → 종료코드 0' ("exit=" + $previewRc)
    $previewText = ($previewOut | Out-String)
    Add-Result ($previewText -match 'SYSTEM') '등록 미리보기 → SYSTEM 계정으로 표시'
    Add-Result ($previewText -match 'restart-service-on-memory\.ps1') '등록 미리보기 → 러너 경로 표시'
    Add-Result ($previewText -match [regex]::Escape($previewService)) '등록 미리보기 → 대상 서비스 이름 표시'
    $taskName = "giip-svcguard-$previewService"
    $taskExists = $null
    try { $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch { }
    Add-Result ($null -eq $taskExists) '등록 미리보기 → 예약 태스크가 만들어지지 않음'

    # ── 7) 등록 스크립트: 상태 조회는 실패하지 않는다 ──────────────────────────
    $statusOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Registrar -Action Status -ServiceName $testService 2>&1
    $statusRc = $LASTEXITCODE
    Add-Result ($statusRc -eq 0) '등록 상태 조회 → 종료코드 0' ("exit=" + $statusRc)
    Add-Result ((($statusOut | Out-String) -match 'svcguard')) '등록 상태 조회 → 결과 문자열 출력'

    # ── 8) 등록 대상 게이트: 임시 worktree 경로 등록은 막아야 한다 ────────────
    if (Test-Path -LiteralPath $TargetGuard -PathType Leaf) {
        $guardScript = ". '$TargetGuard'; if (Test-TaskTargetPathForbidden -FullPath 'D:\temp\worktrees\giip-fde-agent\fake\x.ps1') { 'BLOCKED' } else { 'ALLOWED' }"
        $guardOut = & powershell -NoProfile -ExecutionPolicy Bypass -Command $guardScript 2>&1
        Add-Result ((($guardOut | Out-String).Trim() -eq 'BLOCKED')) '등록 게이트 → 임시 worktree 경로 거부'

        $guardScript2 = ". '$TargetGuard'; if (Test-TaskTargetPathForbidden -FullPath 'C:\Program Files\app\x.ps1') { 'BLOCKED' } else { 'ALLOWED' }"
        $guardOut2 = & powershell -NoProfile -ExecutionPolicy Bypass -Command $guardScript2 2>&1
        Add-Result ((($guardOut2 | Out-String).Trim() -eq 'ALLOWED')) '등록 게이트 → 일반 경로는 허용'
    } else {
        Add-Skip '등록 대상 게이트' "게이트 파일을 찾을 수 없습니다: $TargetGuard"
    }
} finally {
    if (Test-Path -LiteralPath $TmpRoot) {
        Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ""
Write-Output ("결과: PASS {0}건 / FAIL {1}건 / SKIP {2}건" -f $pass, $fail, $skip)
if ($fail -gt 0) { exit 1 }
exit 0
