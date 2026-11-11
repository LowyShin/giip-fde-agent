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
#   · Get-LivenessSignature  — 상태 서명(전체 판정 + 무소식 CSN 목록)
#   · Get-LivenessSilentSince— 침묵 시작 시각(추정) 계산
#   · Get-LivenessEpisode       — 상태 파일에서 에피소드 기록 꺼내기(없으면 null)
#   · Get-LivenessEpisodeState — 에피소드 상태 갱신(침묵 시작 시각은 고정)
#   · Test-LivenessEpisodeCommentDue — 열린 이슈에 진행 보고를 남길 시점인가
#   · New-LivenessStatusComment / New-LivenessRecoveryComment — 진행 보고·회복 보고 본문

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

function Get-LivenessSignature {
    # 상태 서명: 전체 판정 + 무소식 CSN 목록. 알림 쿨다운과 진행 보고의 "변화 감지" 기준이 된다.
    param($Result)
    if (-not $Result) { return '' }
    return "$($Result.Overall):$((@($Result.Silent) | Sort-Object) -join ',')"
}

function Get-LivenessSilentSince {
    # 침묵 시작 시각(추정). 무소식 CSN 별 "마지막 로그 + 기준시간" 중 가장 이른 값을 쓴다
    # (로그가 10h 전이고 기준이 3h 면 7h 전부터 침묵이었다). NO_LOG CSN 은 로그가 없어 알 수 없다 → null.
    param($Result, [datetime]$Now = (Get-Date))
    if (-not $Result) { return $null }
    $best = $null
    foreach ($r in @($Result.Csns)) {
        if (@('SILENT', 'NO_LOG') -notcontains $r.Status) { continue }
        if (-not $r.LastLog) { continue }
        $t = $null
        try { $t = [DateTime]::Parse("$($r.LastLog)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $t = $null }
        if (-not $t) { continue }
        $est = $t.AddHours([double]$Result.MaxSilentHours)
        if ($null -eq $best -or $est -lt $best) { $best = $est }
    }
    return $best
}

function Get-LivenessEpisodeState {
    # 에피소드 상태(순수 — 파일을 쓰지 않는다). 침묵 시작 시각은 처음 판정한 값을 유지한다
    # (매 시간 다시 계산하면 경과 시간이 흔들려 "얼마나 오래 침묵인가"가 읽히지 않는다).
    param($State, $Issues, $Result, [datetime]$Now = (Get-Date))
    $sig = Get-LivenessSignature -Result $Result
    $prev = Get-LivenessEpisode -State $State
    $first = @(@($Issues) | Sort-Object isn)[0]
    $since = $null
    if ($prev -and ($prev.PSObject.Properties.Name -contains 'silentSince') -and $prev.silentSince) {
        try { $since = [DateTime]::Parse("$($prev.silentSince)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $since = $null }
    }
    if (-not $since) { $since = Get-LivenessSilentSince -Result $Result -Now $Now }
    if (-not $since) { $since = $Now }
    $count = 0
    if ($prev -and ($prev.PSObject.Properties.Name -contains 'commentCount') -and $prev.commentCount) { $count = [int]$prev.commentCount }
    $firstSeen = $Now.ToString('yyyy-MM-ddTHH:mm:ss')
    if ($prev -and ($prev.PSObject.Properties.Name -contains 'firstSeenAt') -and $prev.firstSeenAt) { $firstSeen = "$($prev.firstSeenAt)" }
    # [pscustomobject] 로 감싼다 — hashtable 을 그대로 쓰면 PSObject.Properties 에 키가 노출되지 않아
    # "이 필드가 있는가" 판정(PSObject.Properties.Name -contains ... )이 항상 거짓이 된다.
    return [pscustomobject][ordered]@{
        isn           = if ($first) { [int]$first.isn } else { $null }
        csn           = if ($first) { [int]$first.cSn } else { $null }
        silentCsns    = @(@($Result.Silent) | Sort-Object)
        silentSince   = $since.ToString('yyyy-MM-ddTHH:mm:ss')
        firstSeenAt   = $firstSeen
        lastCommentAt = $Now.ToString('yyyy-MM-ddTHH:mm:ss')
        commentCount  = $count + 1
        lastSignature = $sig
    }
}

function Test-LivenessEpisodeCommentDue {
    # 이미 열린 [OPS] 이슈에 진행 보고 코멘트를 남길 시점인가?
    #   · 처음 발견            → 즉시 (에피소드 시작)
    #   · 상태 서명이 바뀜    → 즉시 (침묵 CSN 이 늘었/줄었다)
    #   · 다른 이슈로 전환    → 즉시 (이전 이슈가 닫혔거나 새로 열렸다)
    #   · 같은 상태가 쿨다운  → 주기적 경과 보고(CooldownHours)만
    param($Result, $State, $Issues, [double]$CooldownHours = 6, [datetime]$Now = (Get-Date))
    $list = @($Issues)
    if ($list.Count -eq 0) { return [pscustomobject]@{ Due = $false; Why = '열린 [OPS] 이슈 없음' } }
    $sig = Get-LivenessSignature -Result $Result
    $prev = Get-LivenessEpisode -State $State
    if (-not $prev) { return [pscustomobject]@{ Due = $true; Why = '에피소드 첫 기록 — 진행 보고' } }
    $first = @($list | Sort-Object isn)[0]
    $prevIsn = 0
    if ($prev.PSObject.Properties.Name -contains 'isn' -and $prev.isn) { $prevIsn = [int]$prev.isn }
    if ($prevIsn -ne [int]$first.isn) { return [pscustomobject]@{ Due = $true; Why = "다른 이슈로 전환(기존 #$prevIsn -> #$($first.isn))" } }
    $lastSig = ''
    if ($prev.PSObject.Properties.Name -contains 'lastSignature' -and $prev.lastSignature) { $lastSig = "$($prev.lastSignature)" }
    if ($lastSig -ne $sig) { return [pscustomobject]@{ Due = $true; Why = "상태 변화($lastSig -> $sig)" } }
    $last = $null
    if ($prev.PSObject.Properties.Name -contains 'lastCommentAt' -and $prev.lastCommentAt) {
        try { $last = [DateTime]::Parse("$($prev.lastCommentAt)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $last = $null }
    }
    if (-not $last) { return [pscustomobject]@{ Due = $true; Why = '직전 진행 보고 시각 해석 불가' } }
    $h = ($Now - $last).TotalHours
    if ($h -ge $CooldownHours) { return [pscustomobject]@{ Due = $true; Why = "진행 보고 주기 경과($([math]::Round($h,2))h >= ${CooldownHours}h)" } }
    return [pscustomobject]@{ Due = $false; Why = "쿨다운 중(마지막 진행 보고 $([math]::Round($h,2))h 전 < ${CooldownHours}h)" }
}

function New-LivenessStatusComment {
    # 진행 보고 본문: 침묵 중인 CSN 목록 · 침묵 시작 시각 · 경과 · 상태 서명.
    param($Result, $State, [datetime]$Now = (Get-Date))
    $sig = Get-LivenessSignature -Result $Result
    $ep = Get-LivenessEpisode -State $State
    $since = $null
    if ($ep -and ($ep.PSObject.Properties.Name -contains 'silentSince') -and $ep.silentSince) {
        try { $since = [DateTime]::Parse("$($ep.silentSince)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $since = $null }
    }
    if (-not $since) { $since = Get-LivenessSilentSince -Result $Result -Now $Now }
    if (-not $since) { $since = $Now }
    $elapsed = [math]::Round(($Now - $since).TotalHours, 1)
    $silent = @(@($Result.Silent) | Sort-Object)
    $lines = @('[gissue-liveness] gissue 처리 무소식 — 진행 보고', '')
    if ($ep -and ($ep.PSObject.Properties.Name -contains 'isn') -and $ep.isn) { $lines += "에피소드 이슈: #$($ep.isn)" }
    $lines += @(
        "- 보고 시각: $($Now.ToString('yyyy-MM-dd HH:mm:ss'))",
        "- 상태 서명: $sig",
        "- 침묵 중인 CSN: $(if ($silent.Count -gt 0) { $silent -join ', ' } else { '(없음)' })",
        "- 침묵 시작(추정): $($since.ToString('yyyy-MM-dd HH:mm:ss'))",
        "- 경과: ${elapsed}h",
        "- 판정: $($Result.Summary)",
        ''
    )
    foreach ($r in @($Result.Csns)) {
        if (@('SILENT', 'NO_LOG') -notcontains $r.Status) { continue }
        $lines += "- CSN $($r.Csn): $($r.Status) — $($r.Reason)"
    }
    $lines += @(
        '',
        '(auto: check-gissue-liveness.ps1 — 같은 제목 이슈가 열려 있는 동안 침묵이 이어지는 한 여기에 경과를 누적한다)'
    )
    return ($lines -join "`n")
}

function Get-LivenessEpisode {
    # 상태 파일에서 에피소드 기록을 꺼낸다(없으면 null).
    # pscustomobject 로 감싸야 "이 필드가 있는가" 판정(PSObject.Properties.Name -contains ...)이 성립한다.
    param($State)
    if (-not $State) { return $null }
    if (-not ($State.PSObject.Properties.Name -contains 'episode')) { return $null }
    $ep = $State.episode
    if (-not $ep) { return $null }
    return $ep
}

function New-LivenessRecoveryComment {
    # 회복(처리 흔적 복귀) 보고 본문. 이 이슈를 DONE 으로 닫기 직전에 남긴다.
    # -Issue: 에피소드 기록이 없을 때의 대체 근거(이슈 등록 시각 regdate).
    #         예: 이전 버전이 등록해 둔 이슈(에피소드 기록 없음) — 침묵 시작 시각을 0h 로 잘못 쓰지 않게 한다.
    param($Result, $State, [datetime]$Now = (Get-Date), $Issue = $null)
    $ep = Get-LivenessEpisode -State $State
    $since = $null
    if ($ep -and ($ep.PSObject.Properties.Name -contains 'silentSince') -and $ep.silentSince) {
        try { $since = [DateTime]::Parse("$($ep.silentSince)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $since = $null }
    }
    $fromIssue = $false
    if (-not $since -and $Issue -and $Issue.regdate) {
        try { $since = [DateTime]::Parse("$($Issue.regdate)", [System.Globalization.CultureInfo]::InvariantCulture) } catch { $since = $null }
        if ($since) { $fromIssue = $true }
    }
    if (-not $since) { $since = Get-LivenessSilentSince -Result $Result -Now $Now }
    if (-not $since) { $since = $Now }
    $elapsed = [math]::Round(($Now - $since).TotalHours, 1)
    # "이전 침묵 CSN" 은 **에피소드에 기록된 값**을 쓴다(회복 시점의 현재 판정은 정상이라 목록이 비어 있다).
    $silent = @()
    $silentNote = ''
    if ($ep -and ($ep.PSObject.Properties.Name -contains 'silentCsns') -and $ep.silentCsns) { $silent = @($ep.silentCsns) }
    if ($silent.Count -eq 0 -and -not $fromIssue) { $silent = @(@($Result.Silent) | Sort-Object) }
    if ($silent.Count -eq 0) { $silentNote = ' (에피소드 기록 없음 — 이슈 등록 시각 기준)' }
    $lines = @('[gissue-liveness] gissue 처리 무소식 — 회복 감지', '')
    if ($ep -and ($ep.PSObject.Properties.Name -contains 'isn') -and $ep.isn) { $lines += "에피소드 이슈: #$($ep.isn)" }
    $lines += @(
        "- 회복 시각: $($Now.ToString('yyyy-MM-dd HH:mm:ss'))",
        "- 이전 침묵 CSN: $(if ($silent.Count -gt 0) { $silent -join ', ' } else { '(없음)' })$($silentNote)",
        "- 침묵 시작(추정): $($since.ToString('yyyy-MM-dd HH:mm:ss'))",
        "- 총 경과: ${elapsed}h",
        "- 현재 판정: $($Result.Summary)",
        ''
    )
    foreach ($r in @($Result.Csns)) {
        $last = if ($r.LastLog) { $r.LastLog } else { '(로그 없음)' }
        $lines += "- CSN $($r.Csn): $($r.Status) — 마지막 처리 흔적 $last"
    }
    $lines += @(
        '',
        '(auto: check-gissue-liveness.ps1 — 처리 흔적이 복귀해 무소식 에피소드가 종료되었다. 이 이슈는 DONE 으로 닫는다)'
    )
    return ($lines -join "`n")
}

function Test-LivenessNotifyDue {
    # 알림 쿨다운. 상태 서명(overall + 무소식 CSN 목록)이 바뀌면 즉시, 같으면 CooldownHours 이후에만 재알림.
    param($Result, $State, [double]$CooldownHours = 6, [datetime]$Now = (Get-Date))
    if ($Result.Healthy) { return [pscustomobject]@{ Due = $false; Why = '정상 — 알릴 것 없음'; Signature = '' } }
    $sig = Get-LivenessSignature -Result $Result
    if (-not $State -or -not $State.lastNotifiedAt) { return [pscustomobject]@{ Due = $true; Why = '첫 알림'; Signature = $sig } }
    if ("$($State.signature)" -ne $sig) { return [pscustomobject]@{ Due = $true; Why = "상태 변화($($State.signature) -> $sig)"; Signature = $sig } }
    $last = $null
    try { $last = [DateTime]::Parse($State.lastNotifiedAt, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    if (-not $last) { return [pscustomobject]@{ Due = $true; Why = '직전 알림 시각 해석 불가'; Signature = $sig } }
    $h = ($Now - $last).TotalHours
    if ($h -ge $CooldownHours) { return [pscustomobject]@{ Due = $true; Why = "쿨다운 경과(${h}h >= ${CooldownHours}h)"; Signature = $sig } }
    return [pscustomobject]@{ Due = $false; Why = "쿨다운 중(마지막 알림 $([math]::Round($h,2))h 전 < ${CooldownHours}h)"; Signature = $sig }
}
