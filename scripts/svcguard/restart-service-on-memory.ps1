<#
restart-service-on-memory.ps1 — Windows 서비스 상주 메모리 임계 초과 시 조건부 재기동 + 증가 원인 측정 로그

#>
# 목적
#   어떤 Windows 서비스가 svchost.exe 안에 호스팅되어 있을 때, 그 호스팅 프로세스의 PrivateBytes
#   가 임계값 이상으로 오래 상주하면 조건부로 서비스를 재기동하고, 동시에
#   "메모리 증가 속도 vs 프로세스 생성량" 을 추적할 수 있는 측정 로그(JSONL)를 남긴다.
#
# 왜 측정까지 하는가
#   재기동은 증상을 없앨 뿐 원인을 규명하지 않는다. 어떤 서비스가 "많이 실행된 프로그램 수에 비례해"
#   메모리를 누적하는지는 로그를 몇 시간/일 단위로 모아야 알 수 있다. 그래서 이 스크립트의
#   1순위는 재기동이 아니라 **측정**이고, 재기동은 임계 초과가 지속될 때의 안전장치다.
#
# 기본값이 아닌 것은 모두 인자로 바꾼다(범용 스크립트 — 특정 PC/서비스에 묶지 않는다):
#   -ServiceName              대상 서비스 이름 (기본: Windows 내장 "프로그램 호환성 도우미" 서비스)
#   -ThresholdMB              재기동 기준 PrivateBytes(MB)
#   -MinRestartIntervalMinutes 재기동 최소 간격(분) — 연속 재기동 방지 가드
#   -LogPath / -StateFile     로그·상태 파일 경로 (기본: 스크립트 옆 logs\ 하위)
#   -BaselineSampleCount      기준선 계산에 쓰는 최근 샘플 개수
#   -WhatIf                   재기동하지 않고 측정만
#   -UseSecurityAuditCount    Security 4688(프로세스 생성 이벤트) 카운트를 함께 기록 (감사정책 필요, 기본 off)
#   -DiagnoseBurst            1초 간격 샘플로 짧은 급증(초 단위 배증)을 포착 (기본 off)
#
# 동작 요약
#   1) 대상 서비스의 호스팅 PID 를 찾고 PrivateBytes/WorkingSet/시스템 프로세스 수를 측정한다.
#   2) 기준선 PrivateBytes = 최근 N개 샘플의 **최솟값** — 1~3초짜리 급증 순간 값은 최솟값에
#      반영되지 않으므로 "급증에 과민반응" 하지 않는다.
#   3) 기준선 >= 임계값 이고 마지막 재기동 이후 최소 간격이 지났을 때만 Restart-Service.
#   4) 관리자 권한이 없어 재기동에 실패해도 **측정 로그는 남기고 정상 종료**한다(예약 태스크가 죽지 않게).
#
# 사용 예
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\restart-service-on-memory.ps1 -WhatIf
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\svcguard\restart-service-on-memory.ps1 -ServiceName MySvc -ThresholdMB 512
#>
param(
    [string]$ServiceName = 'PcaSvc',
    [int]$ThresholdMB = 1024,
    [int]$MinRestartIntervalMinutes = 60,
    [string]$LogPath = '',
    [string]$StateFile = '',
    [int]$BaselineSampleCount = 24,
    [switch]$WhatIf,
    [switch]$UseSecurityAuditCount,
    [switch]$DiagnoseBurst,
    [int]$BurstSeconds = 10,
    [int]$BurstIntervalSeconds = 1
)

$ErrorActionPreference = 'Stop'

# 이 PC 의 콘솔 기본 출력 인코딩은 cp932 라서 한글 출력이 '?' 로 뭉개진다 (check-ps1-parse.ps1 과 동일 처리).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $LogPath) { $LogPath = Join-Path $ScriptDir ("logs\svcguard-{0}.jsonl" -f $ServiceName) }
if (-not $StateFile) { $StateFile = Join-Path $ScriptDir ("logs\svcguard-{0}.state.json" -f $ServiceName) }

# ── 로그 ────────────────────────────────────────────────────────────────────────
function Write-SvcGuardLog {
    # [IDictionary] 로 받는 이유: [ordered]@{}(OrderedDictionary) 를 hashtable 로 강제 변환하면
    # 키 순서가 사라져 로그 JSON 의 필드 순서가 매번 달라진다.
    param([System.Collections.IDictionary]$Record)
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Record | ConvertTo-Json -Depth 6 -Compress)
    # BOM 없는 UTF-8 로 덧붙인다 (AppendAllText 는 BOM 을 붙이지 않는다).
    [System.IO.File]::AppendAllText($LogPath, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

# ── 상태 파일 ───────────────────────────────────────────────────────────────────
function Read-SvcGuardState {
    param([string]$Path)
    $empty = [ordered]@{ lastRestartUtc = $null; samples = @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $empty }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $empty }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $st = [ordered]@{ lastRestartUtc = $null; samples = @() }
        if ($obj.PSObject.Properties.Name -contains 'lastRestartUtc' -and $obj.lastRestartUtc) {
            $st.lastRestartUtc = [string]$obj.lastRestartUtc
        }
        if ($obj.PSObject.Properties.Name -contains 'samples' -and $obj.samples) {
            $st.samples = @($obj.samples)
        }
        return $st
    } catch {
        # 상태 파일이 깨졌으면 새로 시작한다 (측정 로그는 살아 있다).
        return $empty
    }
}

function Save-SvcGuardState {
    param([string]$Path, $State)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($State | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ── 서비스/프로세스 측정 ────────────────────────────────────────────────────────
function Get-SvcGuardServiceInfo {
    param([string]$Name)
    $info = [ordered]@{ found = $false; servicePid = $null; state = $null; startMode = $null; pidSource = $null }
    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction Stop
        if ($svc) {
            $info.found = $true
            $info.state = [string]$svc.State
            $info.startMode = [string]$svc.StartMode
            $info.pidSource = 'Win32_Service'
            $rawPid = 0
            try { $rawPid = [int]$svc.ProcessId } catch { $rawPid = 0 }
            if ($rawPid -gt 0) { $info.servicePid = $rawPid }
            return $info
        }
    } catch {
        # WMI 를 못 쓰는 환경 → Get-Service 로 존재 여부만 확인한다(측정값은 없을 수 있다).
    }
    try {
        $gs = Get-Service -Name $Name -ErrorAction Stop
        if ($gs) {
            $info.found = $true
            $info.state = [string]$gs.Status
            $info.pidSource = 'Get-Service'
        }
    } catch {
    }
    return $info
}

function Get-SvcGuardMemory {
    param([int]$ProcessId)
    $mem = [ordered]@{
        privateBytesMB = $null
        workingSetMB = $null
        processStartTimeUtc = $null
        uptimeMinutes = $null
        memoryAccessDenied = $false
        measurementSource = $null
    }
    if ($ProcessId -le 0) { $mem.measurementSource = 'no-pid'; return $mem }

    $gotProcess = $false
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        $mem.privateBytesMB = [math]::Round(($proc.PrivateMemorySize64 / 1MB), 2)
        $mem.workingSetMB = [math]::Round(($proc.WorkingSet64 / 1MB), 2)
        $mem.measurementSource = 'Get-Process'
        $gotProcess = $true
        try {
            $started = $proc.StartTime
            $mem.processStartTimeUtc = $started.ToUniversalTime().ToString('o')
            $mem.uptimeMinutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
        } catch {
            # 시스템 소유 프로세스의 StartTime 은 관리자 권한 없이는 읽히지 않는다 → 아래 폴백에서 채운다.
        }
    } catch {
        $mem.memoryAccessDenied = $true
    }

    if (-not $gotProcess -or $null -eq $mem.processStartTimeUtc) {
        # 폴백: Win32_Process 는 WorkingSetSize 와 CreationDate 를 준다(PrivateBytes 는 못 얻는다).
        try {
            $wp = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId={0}" -f $ProcessId) -ErrorAction Stop
            if ($wp) {
                if (-not $gotProcess) {
                    $mem.workingSetMB = [math]::Round(($wp.WorkingSetSize / 1MB), 2)
                    $mem.measurementSource = 'Win32_Process(workingSetOnly)'
                }
                if ($null -eq $mem.processStartTimeUtc -and $wp.CreationDate) {
                    $created = [datetime]$wp.CreationDate
                    $mem.processStartTimeUtc = $created.ToUniversalTime().ToString('o')
                    $mem.uptimeMinutes = [math]::Round(((Get-Date) - $created).TotalMinutes, 1)
                }
            }
        } catch {
        }
    }

    if (-not $mem.measurementSource) { $mem.measurementSource = 'unavailable' }
    return $mem
}

function Get-SvcGuardProcessCount {
    try {
        return @((Get-Process -ErrorAction SilentlyContinue)).Count
    } catch {
        return $null
    }
}

function Get-SvcGuardProcessCreateEventCount {
    param([string]$SinceUtc)
    # Security 4688(프로세스 생성) — 감사정책이 켜져 있어야 이벤트가 쌓인다. 꺼져 있으면 null.
    if (-not $SinceUtc) { return $null }
    try {
        $since = [datetime]::Parse($SinceUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4688; StartTime = $since } -ErrorAction Stop
        return @($events).Count
    } catch {
        return $null
    }
}

# ── 급증 진단(선택) ─────────────────────────────────────────────────────────────
# 분 단위 샘플로는 1~3초짜리 순간 급증을 포착할 수 없다. -DiagnoseBurst 를 주면
# 1초 간격으로 N초간 연속 샘플을 남겨 배증/회복 구간을 그대로 본다.
if ($DiagnoseBurst -and $BurstSeconds -gt 0) {
    $burstEnd = (Get-Date).AddSeconds($BurstSeconds)
    while ((Get-Date) -lt $burstEnd) {
        $bInfo = Get-SvcGuardServiceInfo -Name $ServiceName
        $bPid = 0
        if ($bInfo.servicePid) { $bPid = [int]$bInfo.servicePid }
        $bMem = Get-SvcGuardMemory -ProcessId $bPid
        Write-SvcGuardLog -Record ([ordered]@{
            timestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
            mode                = 'burst'
            serviceName         = $ServiceName
            serviceFound        = [bool]$bInfo.found
            serviceRunning      = ($bPid -gt 0)
            servicePid          = $bPid
            privateBytesMB      = $bMem.privateBytesMB
            workingSetMB        = $bMem.workingSetMB
            measurementSource   = $bMem.measurementSource
            memoryAccessDenied  = [bool]$bMem.memoryAccessDenied
            systemProcessCount  = (Get-SvcGuardProcessCount)
        })
        if ($BurstIntervalSeconds -gt 0) { Start-Sleep -Seconds $BurstIntervalSeconds }
    }
}

# ── 본 측정 + 조건부 재기동 ─────────────────────────────────────────────────────
$now = Get-Date
$nowUtc = $now.ToUniversalTime()
$state = Read-SvcGuardState -Path $StateFile

$info = Get-SvcGuardServiceInfo -Name $ServiceName
$servicePid = 0
if ($info.servicePid) { $servicePid = [int]$info.servicePid }

if (-not $info.found) {
    Write-SvcGuardLog -Record ([ordered]@{
        timestampUtc       = $nowUtc.ToString('o')
        mode               = 'sample'
        serviceName        = $ServiceName
        serviceFound       = $false
        serviceRunning     = $false
        servicePid         = $null
        measurementSource  = 'service-not-found'
        note               = '대상 서비스를 찾지 못했습니다 — 측정 대상 없음(정상 종료)'
    })
    exit 0
}

if ($servicePid -le 0) {
    Write-SvcGuardLog -Record ([ordered]@{
        timestampUtc       = $nowUtc.ToString('o')
        mode               = 'sample'
        serviceName        = $ServiceName
        serviceFound       = $true
        serviceRunning     = $false
        serviceState       = $info.state
        serviceStartMode   = $info.startMode
        servicePid         = $null
        measurementSource  = 'service-not-running'
        note               = '서비스가 실행 중이 아니어서 측정 대상 프로세스가 없습니다 (정상 종료)'
    })
    exit 0
}

$mem = Get-SvcGuardMemory -ProcessId $servicePid
$processCount = Get-SvcGuardProcessCount

# 기준선 = 최근 N개 샘플의 최솟값. 순간 급증(값이 순간적으로 2배)은 최솟값에 반영되지 않는다.
$samples = @($state.samples)
if ($null -ne $mem.privateBytesMB) {
    $samples += @([ordered]@{ t = $nowUtc.ToString('o'); mb = [double]$mem.privateBytesMB; pc = $processCount })
}
if ($BaselineSampleCount -gt 0 -and $samples.Count -gt $BaselineSampleCount) {
    $samples = @($samples[($samples.Count - $BaselineSampleCount)..($samples.Count - 1)])
}

$baselineMB = $null
if ($samples.Count -gt 0) {
    $mins = @($samples | ForEach-Object { [double]$_.mb } | Measure-Object -Minimum)
    if ($mins.Count -gt 0) { $baselineMB = [double]$mins.Minimum }
}

# 직전 샘플 대비 증가량 → "프로세스 생성량 대비 증가 속도"
$prev = $null
if ($samples.Count -ge 2) { $prev = $samples[$samples.Count - 2] }
$deltaMB = $null
$deltaCount = $null
$deltaMinutes = $null
$growthMBPerHour = $null
$growthMBPerNewProcess = $null
if ($null -ne $prev) {
    if ($null -ne $mem.privateBytesMB -and $null -ne $prev.mb) {
        $deltaMB = [math]::Round(([double]$mem.privateBytesMB - [double]$prev.mb), 2)
    }
    if ($null -ne $processCount -and $null -ne $prev.pc) {
        $deltaCount = [int]$processCount - [int]$prev.pc
    }
    try {
        $prevTime = [datetime]::Parse([string]$prev.t, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $deltaMinutes = [math]::Round(($nowUtc - $prevTime).TotalMinutes, 2)
        if ($null -ne $deltaMB -and $deltaMinutes -gt 0) {
            $growthMBPerHour = [math]::Round(($deltaMB / $deltaMinutes) * 60, 3)
        }
    } catch {
    }
    if ($null -ne $deltaMB -and $null -ne $deltaCount -and $deltaCount -gt 0) {
        $growthMBPerNewProcess = [math]::Round(($deltaMB / $deltaCount), 4)
    }
}

# 마지막 재기동 경과 시간(최소 간격 가드)
$minutesSinceLastRestart = $null
if ($state.lastRestartUtc) {
    try {
        $last = [datetime]::Parse([string]$state.lastRestartUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $minutesSinceLastRestart = [math]::Round(($nowUtc - $last).TotalMinutes, 1)
    } catch {
    }
}

# 재기동 판정
$restartEligible = $false
$blockedReason = ''
if ($null -eq $baselineMB) {
    $blockedReason = 'measurement-incomplete'
} elseif ($baselineMB -lt $ThresholdMB) {
    $blockedReason = 'below-threshold'
} elseif ($null -ne $minutesSinceLastRestart -and $minutesSinceLastRestart -lt $MinRestartIntervalMinutes) {
    $blockedReason = 'min-interval'
} else {
    $restartEligible = $true
}

$restartTriggered = $false
$wouldRestart = $restartEligible
$privateBefore = $null
$privateAfter = $null
$restartError = $null

if ($restartEligible) {
    $privateBefore = $mem.privateBytesMB
    if ($WhatIf) {
        $blockedReason = 'whatif'
        $wouldRestart = $false
    } else {
        try {
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop
            $restartTriggered = $true
            $wouldRestart = $false
            $state.lastRestartUtc = $nowUtc.ToString('o')
            # 재기동 직후 값: PID 가 바뀔 수 있으므로 다시 푼다.
            Start-Sleep -Seconds 2
            $afterInfo = Get-SvcGuardServiceInfo -Name $ServiceName
            if ($afterInfo.servicePid) {
                $afterMem = Get-SvcGuardMemory -ProcessId ([int]$afterInfo.servicePid)
                $privateAfter = $afterMem.privateBytesMB
            }
        } catch {
            # 관리자 권한이 없으면 "Cannot open <서비스>" 로 실패한다.
            # 측정 로그는 남기고 정상 종료한다 — 예약 태스크가 실패로 죽으면 다음 샘플이 사라진다.
            $restartError = $_.Exception.Message
            $restartTriggered = $false
            $wouldRestart = $false
            $blockedReason = 'restart-failed'
        }
    }
}

$procCreateCount = $null
if ($UseSecurityAuditCount) {
    $sinceUtc = $null
    if ($null -ne $prev) { $sinceUtc = [string]$prev.t }
    $procCreateCount = Get-SvcGuardProcessCreateEventCount -SinceUtc $sinceUtc
}

$record = [ordered]@{
    timestampUtc              = $nowUtc.ToString('o')
    mode                      = 'sample'
    serviceName               = $ServiceName
    serviceFound              = [bool]$info.found
    serviceRunning            = $true
    serviceState              = $info.state
    serviceStartMode          = $info.startMode
    servicePid                = $servicePid
    privateBytesMB            = $mem.privateBytesMB
    workingSetMB              = $mem.workingSetMB
    baselinePrivateBytesMB    = $baselineMB
    thresholdMB               = $ThresholdMB
    measurementSource         = $mem.measurementSource
    memoryAccessDenied        = [bool]$mem.memoryAccessDenied
    processStartTimeUtc       = $mem.processStartTimeUtc
    serviceUptimeMinutes      = $mem.uptimeMinutes
    systemProcessCount        = $processCount
    deltaPrivateBytesMB       = $deltaMB
    deltaProcessCount         = $deltaCount
    deltaMinutes              = $deltaMinutes
    growthMBPerHour           = $growthMBPerHour
    growthMBPerNewProcess     = $growthMBPerNewProcess
    processCreateEventCount   = $procCreateCount
    processCreateEventAvailable = ($null -ne $procCreateCount)
    minRestartIntervalMinutes = $MinRestartIntervalMinutes
    minutesSinceLastRestart   = $minutesSinceLastRestart
    restartEligible           = $restartEligible
    wouldRestart              = $wouldRestart
    restartTriggered          = $restartTriggered
    restartBlockedReason      = $blockedReason
    privateBytesBeforeRestartMB = $privateBefore
    privateBytesAfterRestartMB  = $privateAfter
    restartError              = $restartError
    whatIf                    = [bool]$WhatIf
}

Write-SvcGuardLog -Record $record

$state.samples = $samples
Save-SvcGuardState -Path $StateFile -State $state

Write-Output ("[svcguard] {0} privateBytes={1}MB baseline={2}MB threshold={3}MB processCount={4} growth={5}MB/h restart={6} ({7})" -f `
    $ServiceName, $mem.privateBytesMB, $baselineMB, $ThresholdMB, $processCount, $growthMBPerHour, $restartTriggered, $blockedReason)

exit 0
