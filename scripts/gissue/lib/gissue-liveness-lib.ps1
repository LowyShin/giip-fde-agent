# gissue-liveness-lib.ps1 — gissue 처리 "무소식" 판정 순수 함수 (giip 4411)
#
# 배경(실사고): 스케줄러 태스크가 이슈 처리 본체(run-gissue-claude.ps1)가 아닌 다른 스크립트를 가리키도록
#   바뀌어, 처리 본체가 6일 넘게 한 번도 돌지 않았다. 태스크는 매시 정상 종료(LastTaskResult=0)였기 때문에
#   아무도 몰랐다. "스케줄러가 돈다"는 사실은 Task Scheduler 결과코드로는 알 수 없다 → 처리 산출물
#   (CSN별 처리 로그 gissue_csn<N>.log)가 신선한지를 본다. run-gissue-claude.ps1 는 CSN 마다 매 실행
#   Write-Log 를 남기므로(이슈가 0건이어도 [LANG] 등 한 줄 이상), 정상 가동 중이면 로그는 매시 갱신된다.
#
# 이 파일은 함수만 정의한다(부작용 없음, 파일 쓰기 없음). 판정은 읽기 전용이다.
#   · Get-LivenessCsnList   — 점검 대상 CSN 목록(csn-projects.json 의 enabled, 없으면 로그 파일명에서)
#   · Get-LivenessLock      — gissue_csn<N>.lock 해석(PID|시작|마지막로그, 생존/나이)
#   · Get-CsnLiveness       — CSN 1건 판정(OK / RUNNING / SILENT / NO_LOG)
#   · Get-GissueLiveness    — 전체 판정(OK / PARTIAL_SILENT / ALL_SILENT / NO_TARGETS)
#   · Test-LivenessNotifyDue — 알림 쿨다운 판정(동일 상태면 쿨다운 동안 재알림 안 함)

function Get-LivenessCsnList {
    param([string]$ConfigPath, [string]$LogDir)
    $list = @()
    $fromConfig = $false
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.csn) {
                $fromConfig = $true
                foreach ($p in $cfg.csn.PSObject.Properties) {
                    if ($p.Name -notmatch '^\d+$') { continue }   # "<CSN番号>" 같은 예시 키 제외
                    $enabled = $true
                    if ($p.Value.PSObject.Properties['enabled'] -and $p.Value.enabled -eq $false) { $enabled = $false }
                    if ($enabled) { $list += [int]$p.Name }
                }
            }
        } catch { $fromConfig = $false; $list = @() }
    }
    if (-not $fromConfig -and $LogDir -and (Test-Path -LiteralPath $LogDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter 'gissue_csn*.log' -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^gissue_csn(\d+)\.log$') { $list += [int]$Matches[1] }
        }
    }
    return @($list | Sort-Object -Unique)
}

function Get-LivenessLock {
    # 락 형식(run-gissue-claude.ps1): "PID|시작시각|마지막로그시각" (구형 "PID|시작시각" 도 허용).
    param([string]$LockPath, [datetime]$Now, [double]$StaleLockHours)
    if (-not (Test-Path -LiteralPath $LockPath)) { return [pscustomobject]@{ Exists = $false; State = 'NONE'; Pid = $null; AgeHours = $null } }
    $item = Get-Item -LiteralPath $LockPath
    $lockPid = $null; $start = $null
    try {
        $raw = (Get-Content -LiteralPath $LockPath -Raw -ErrorAction Stop).Trim()
        if ($raw -match '^(\d+)\|([^|]+)') {
            $lockPid = [int]$Matches[1]
            try { $start = [DateTime]::Parse($Matches[2], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime() } catch { $start = $null }
        } elseif ($raw -match '^(\d+)$') {
            $lockPid = [int]$Matches[1]
        }
    } catch { }
    if (-not $start) { $start = $item.LastWriteTime }
    $age = ($Now - $start).TotalHours
    $alive = $true   # PID 를 못 읽으면 나이만으로 판정한다
    if ($null -ne $lockPid) {
        $alive = $false
        try { $null = Get-Process -Id $lockPid -ErrorAction Stop; $alive = $true } catch { $alive = $false }
    }
    $state = if (-not $alive) { 'STALE_DEAD_PID' } elseif ($age -ge $StaleLockHours) { 'STALE_OLD' } else { 'LIVE' }
    return [pscustomobject]@{ Exists = $true; State = $state; Pid = $lockPid; AgeHours = [math]::Round($age, 2) }
}

function Get-CsnLiveness {
    param([int]$Csn, [string]$LogDir, [datetime]$Now, [double]$MaxSilentHours, [double]$StaleLockHours)
    $logPath  = Join-Path $LogDir "gissue_csn$Csn.log"
    $lockPath = Join-Path $LogDir "gissue_csn$Csn.lock"
    $lock = Get-LivenessLock -LockPath $lockPath -Now $Now -StaleLockHours $StaleLockHours
    $lastLog = $null; $silentHours = $null
    if (Test-Path -LiteralPath $logPath) {
        $lastLog = (Get-Item -LiteralPath $logPath).LastWriteTime
        $silentHours = [math]::Round(($Now - $lastLog).TotalHours, 2)
    }
    $status = 'OK'; $reason = ''
    if ($lock.State -eq 'LIVE') {
        # 살아있는 락 = 지금 처리 중(긴 실행). 로그가 잠잠해도 오탐하지 않는다.
        $status = 'RUNNING'; $reason = "처리 중(락 PID $($lock.Pid), 시작 후 $($lock.AgeHours)h)"
    } elseif ($null -eq $silentHours) {
        $status = 'NO_LOG'; $reason = "처리 로그 없음($logPath)"
    } elseif ($silentHours -gt $MaxSilentHours) {
        $status = 'SILENT'
        $reason = "처리 로그 ${silentHours}h 동안 갱신 없음(기준 ${MaxSilentHours}h)"
        if ($lock.State -eq 'STALE_DEAD_PID') { $reason += "; 죽은 프로세스의 락 방치(PID $($lock.Pid))" }
        elseif ($lock.State -eq 'STALE_OLD')  { $reason += "; 락이 ${StaleLockHours}h 이상 묵음(PID $($lock.Pid), 멈춘 실행 의심)" }
    }
    return [pscustomobject]@{
        Csn = $Csn; Status = $status; Reason = $reason
        LastLog = if ($lastLog) { $lastLog.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        SilentHours = $silentHours; LockState = $lock.State; LockPid = $lock.Pid; LockAgeHours = $lock.AgeHours
    }
}

function Get-GissueLiveness {
    param(
        [string]$LogDir, [string]$ConfigPath,
        [double]$MaxSilentHours = 3, [double]$StaleLockHours = 2,
        [datetime]$Now = (Get-Date)
    )
    $csns = @(Get-LivenessCsnList -ConfigPath $ConfigPath -LogDir $LogDir)
    $rows = @()
    foreach ($c in $csns) { $rows += Get-CsnLiveness -Csn $c -LogDir $LogDir -Now $Now -MaxSilentHours $MaxSilentHours -StaleLockHours $StaleLockHours }
    $bad = @($rows | Where-Object { $_.Status -in @('SILENT', 'NO_LOG') })
    $overall = if ($rows.Count -eq 0) { 'NO_TARGETS' }
               elseif ($bad.Count -eq 0) { 'OK' }
               elseif ($bad.Count -eq $rows.Count) { 'ALL_SILENT' }
               else { 'PARTIAL_SILENT' }
    $summary = switch ($overall) {
        'OK'             { "정상: CSN $($rows.Count)건 모두 최근 ${MaxSilentHours}h 이내 처리 흔적(또는 처리 중)" }
        'NO_TARGETS'     { "판정 불가: 점검 대상 CSN 이 없다(csn-projects.json 의 enabled CSN 도, 처리 로그 파일도 없음) — 스케줄러가 한 번도 돌지 않았거나 로그 디렉터리가 사라진 상태" }
        'ALL_SILENT'     { "무소식(전체): CSN $($rows.Count)건 전부 ${MaxSilentHours}h 넘게 처리 흔적 없음 — 스케줄러 자체가 멈췄을 가능성(태스크가 다른 스크립트를 가리키는지 확인)" }
        'PARTIAL_SILENT' { "무소식(일부): CSN $($rows.Count)건 중 $($bad.Count)건($((@($bad | ForEach-Object { $_.Csn })) -join ','))만 ${MaxSilentHours}h 넘게 처리 흔적 없음 — 스케줄러는 도는데 해당 CSN 만 건너뛰는 상태" }
    }
    return [pscustomobject]@{
        Overall = $overall; Healthy = ($overall -eq 'OK'); Summary = $summary
        MaxSilentHours = $MaxSilentHours; StaleLockHours = $StaleLockHours
        CheckedAt = $Now.ToString('yyyy-MM-dd HH:mm:ss')
        Silent = @($bad | ForEach-Object { $_.Csn }); Csns = $rows
    }
}

function Test-LivenessNotifyDue {
    # 알림 쿨다운. 상태 서명(overall + 무소식 CSN 목록)이 바뀌면 즉시, 같으면 CooldownHours 이후에만 재알림.
    param($Result, $State, [double]$CooldownHours = 6, [datetime]$Now = (Get-Date))
    if ($Result.Healthy) { return [pscustomobject]@{ Due = $false; Why = '정상 — 알릴 것 없음'; Signature = '' } }
    $sig = "$($Result.Overall):$((@($Result.Silent) | Sort-Object) -join ',')"
    if (-not $State -or -not $State.lastNotifiedAt) { return [pscustomobject]@{ Due = $true; Why = '첫 알림'; Signature = $sig } }
    if ("$($State.signature)" -ne $sig) { return [pscustomobject]@{ Due = $true; Why = "상태 변화($($State.signature) -> $sig)"; Signature = $sig } }
    $last = $null
    try { $last = [DateTime]::Parse($State.lastNotifiedAt, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    if (-not $last) { return [pscustomobject]@{ Due = $true; Why = '직전 알림 시각 해석 불가'; Signature = $sig } }
    $h = ($Now - $last).TotalHours
    if ($h -ge $CooldownHours) { return [pscustomobject]@{ Due = $true; Why = "쿨다운 경과(${h}h >= ${CooldownHours}h)"; Signature = $sig } }
    return [pscustomobject]@{ Due = $false; Why = "쿨다운 중(마지막 알림 $([math]::Round($h,2))h 전 < ${CooldownHours}h)"; Signature = $sig }
}
