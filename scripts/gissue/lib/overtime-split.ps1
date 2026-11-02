# overtime-split.ps1 — 2시간 초과 실행 처리 규칙(giip 4429, giip 4428 후속) 순수 로직 + 오케스트레이션
#
# 용도
#   매시 :07 gissue 스케줄러(run-gissue-claude.ps1)의 한 프로세스가 작업 스케줄러 ExecutionTimeLimit(PT2H)에
#   걸려 외부에서 강제 종료되면 러너가 클레임/락을 정리할 기회가 없다. 이 파일은 러너가 **스스로 정한 마감시각**을
#   넘긴 처리 실행에 대해 사용자 지시(2026-11-02) 4규칙을 수행하는 로직을 모은다.
#     1. 원인을 그 이슈 코멘트에 보고한다(무엇을 하다 어디서 시간이 걸렸는지).
#     2. 남은 작업을 나눌 수 있으면 새 서브 이슈로 쪼개 등록한다(원본 체크리스트 잔여 항목 기준).
#     3. 그 뒤 과시간 실행을 종료하고 이 실행이 만든 클레임/락만 정리한다.
#     4. 원본에는 서브 이슈 번호를 코멘트(첫 줄 [SPLIT-CLOSE], "분할 이전" 명시)로 달고 DONE 처리한다.
#
# 처리 내용 / 저장 위치 / 소비처 (코드 문서화 규칙: 용도·처리·저장·소비를 구체적으로)
#   - 이 파일은 파일/DB 에 직접 아무것도 쓰지 않는다. 모든 쓰기는 호출부가 넘기는 포트(스크립트블록)를 통한다.
#       PostComment  -> giip 이슈 코멘트(tGiipIssueComment, get-issue.sh --comment-file 경유)
#       RegisterChild-> 서브 이슈 행(tGiipIssue, register-issue.js 경유)
#       SetStatus    -> 원본 이슈 상태(get-issue.sh --status)
#       StopJob / RemoveLocks -> 과시간 CSN 잡 1개와 logs/gissue_csn<N>.lock, repo-lock 파일
#   - 소비처: run-gissue-claude.ps1 Phase 2 대기 루프(Invoke-GissueOvertimeCheck),
#             tests/test-overtime-split.ps1(가짜 포트로 전 경로 검증).
#   - 감사 면제: Test-HasSplitCloseMarker(gissue-audit-lib.ps1)가 [SPLIT-CLOSE] 코멘트를 인식해
#     review-done-audit 이 이 DONE 을 "PR 없음"으로 되돌리지 않는다.
#
# 모드(Get-GissueOvertimeMode): Off | Shadow(기본) | Live
#   Shadow = 무엇을 할지 [OVERTIME-SHADOW] 로그만. 코멘트·등록·종료·정리·상태전이 쓰기 0건.
#   Live   = 규칙 1~4 실제 수행. 명시적으로 켜야 한다(-OvertimeSplitMode Live 또는 GISSUE_OVERTIME_SPLIT_MODE=Live).
#
# 설정값과 근거 (환경변수; 사양서 docs/60-operations/hourly-issue-scheduler.md 에도 같은 표)
#   GISSUE_OVERTIME_RUN_DEADLINE_MIN 기본 105 — 태스크 제한(120분)에서 직렬 후처리·정리용 15분을 뺀 값
#                                     (giip 1572 가 정한 RunTimeoutMin=105 와 같은 근거).
#                                     "프로세스 시작 시각" 기준이다(잡 launch 기준이 아니다).
#   GISSUE_OVERTIME_ISSUE_MIN        기본 105 — 이슈 1건 처리 시작([ISSUE-T0]) 기준 경과 임계.
#   GISSUE_TASK_LIMIT_MIN            기본 120 — 작업 스케줄러 ExecutionTimeLimit 을 러너에 알려준다.
#                                     마감시각은 (제한 - 10분) 이하로 강제 보정한다.
#
# 이 파일은 자기완결적이다(러너의 다른 함수를 부르지 않는다). 테스트 가능하도록 현재 시각·프로세스 시작
# 시각·설정은 전부 인자로 받는다. PowerShell 5.1 호환.

$script:GissueOvertimeDefaultRunDeadlineMin = 105
$script:GissueOvertimeDefaultIssueMin = 105
$script:GissueOvertimeDefaultTaskLimitMin = 120
$script:GissueOvertimeSafetyMarginMin = 10
$script:GissueOvertimeMaxChildren = 5
$script:GissueSplitCloseMarker = '[SPLIT-CLOSE]'

# 모드 해석: 명시값 -> 환경변수 GISSUE_OVERTIME_SPLIT_MODE -> 'Shadow'. 알 수 없는 값은 Shadow(안전 쪽).
# Live 는 정확히 'Live' 일 때만 켜진다.
function Get-GissueOvertimeMode($Explicit = $null) {
    $v = if ($Explicit) { "$Explicit" } elseif ($env:GISSUE_OVERTIME_SPLIT_MODE) { "$env:GISSUE_OVERTIME_SPLIT_MODE" } else { 'Shadow' }
    switch -Regex ($v.Trim()) {
        '^(?i)off$'  { return 'Off' }
        '^(?i)live$' { return 'Live' }
        default      { return 'Shadow' }
    }
}

function ConvertTo-GissueOvertimePositiveInt($Value, [int]$Default) {
    if ($null -eq $Value) { return $Default }
    $s = "$Value".Trim()
    $n = 0
    if ([int]::TryParse($s, [ref]$n) -and $n -gt 0) { return $n }
    return $Default
}

# 설정 해석: 명시값 -> 환경변수 -> 기본값. 마감시각은 (태스크 제한 - 안전여유) 이하로 보정한다.
function Get-GissueOvertimeSettings($ExplicitMode = $null, $RunDeadlineMin = $null, $IssueMin = $null, $TaskLimitMin = $null) {
    $limit = ConvertTo-GissueOvertimePositiveInt $(if ($null -ne $TaskLimitMin) { $TaskLimitMin } else { $env:GISSUE_TASK_LIMIT_MIN }) $script:GissueOvertimeDefaultTaskLimitMin
    $run = ConvertTo-GissueOvertimePositiveInt $(if ($null -ne $RunDeadlineMin) { $RunDeadlineMin } else { $env:GISSUE_OVERTIME_RUN_DEADLINE_MIN }) $script:GissueOvertimeDefaultRunDeadlineMin
    $iss = ConvertTo-GissueOvertimePositiveInt $(if ($null -ne $IssueMin) { $IssueMin } else { $env:GISSUE_OVERTIME_ISSUE_MIN }) $script:GissueOvertimeDefaultIssueMin
    $maxAllowed = $limit - $script:GissueOvertimeSafetyMarginMin
    $clamped = $false
    if ($maxAllowed -lt 1) { $maxAllowed = 1 }
    if ($run -gt $maxAllowed) { $run = $maxAllowed; $clamped = $true }
    if ($iss -gt $maxAllowed) { $iss = $maxAllowed; $clamped = $true }
    [pscustomobject]@{
        Mode           = Get-GissueOvertimeMode $ExplicitMode
        RunDeadlineMin = $run
        IssueMin       = $iss
        TaskLimitMin   = $limit
        Clamped        = $clamped
    }
}

# 과시간 판정(순수). ProcessStart 는 러너 프로세스 시작 시각, IssueStart 는 처리 중 이슈의 시작 시각(없으면 $null).
function Test-GissueOvertime([datetime]$Now, [datetime]$ProcessStart, $IssueStart, $Settings) {
    $runMin = ($Now - $ProcessStart).TotalMinutes
    $issMin = $null
    if ($null -ne $IssueStart) { $issMin = ($Now - [datetime]$IssueStart).TotalMinutes }
    $reason = ''
    if ($null -ne $issMin -and $issMin -ge $Settings.IssueMin) { $reason = 'issue' }
    elseif ($runMin -ge $Settings.RunDeadlineMin) { $reason = 'run' }
    [pscustomobject]@{
        Over            = [bool]$reason
        Reason          = $reason
        RunElapsedMin   = [math]::Round($runMin, 1)
        IssueElapsedMin = if ($null -ne $issMin) { [math]::Round($issMin, 1) } else { $null }
    }
}

# 잡 출력에서 "지금 처리 중인 이슈"를 찾는다. 러너가 이슈 시작 시 [ISSUE-T0] isn=<n> status=<S> utc=<iso>,
# 이슈 종료(다음 이슈 시작 직전/루프 종료) 시 [ISSUE-END] isn=<n> 을 출력한다. 마지막 T0 뒤에 END 가 없으면 처리 중.
function Get-GissueInFlightIssue($OutputLines) {
    $last = $null
    $ended = $false
    foreach ($line in @($OutputLines)) {
        $s = "$line"
        if ($s -match '^\s*\[ISSUE-T0\]\s+isn=(\d+)\s+status=(\S+)\s+utc=(\S+)') {
            $when = $null
            try { $when = [datetime]::Parse($Matches[3], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { }
            $last = [pscustomobject]@{ Isn = [int]$Matches[1]; Status = $Matches[2]; StartUtc = $when }
            $ended = $false
        } elseif ($last -and $s -match '^\s*\[ISSUE-END\]\s+isn=(\d+)' -and [int]$Matches[1] -eq $last.Isn) {
            $ended = $true
        }
    }
    if ($last -and -not $ended) { return $last }
    return $null
}

# 규칙 1: 원인 요약(순수). 잡 출력에서 확인되는 사실만 쓰고, 확인 안 되는 것은 "미상"이라고 쓴다.
function Get-GissueOvertimeCause($OutputLines, $Isn, $IssueStartUtc, [datetime]$NowUtc, $Over) {
    $lines = @($OutputLines | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
    $stageRe = '^\s*\[(REPO-MAINT|QUEUE|ISSUE|ISSUE-T0|ENGINE|WAIT|TIMEBOX|BUDGET|COMMENT-BACKFILL|DECOMPOSE|READY|CODE-FRESHNESS-JOB|WARN|ALERT)[^\]]*\]'
    $stage = @($lines | Where-Object { $_ -match $stageRe })
    $tail = @($stage | Select-Object -Last 6 | ForEach-Object { if ($_.Length -gt 170) { $_.Substring(0, 170) + '...' } else { $_ } })
    $known = ($stage.Count -gt 0)
    $stageText = '미상(잡 출력에서 단계 줄을 찾지 못했다)'
    if ($known) {
        $lastLine = $stage[-1]
        if ($lastLine -match '재시도') { $stageText = '엔진 호출(MiniMax 재시도 구간) — 호출이 끝나지 않은 채 대기 중이었다' }
        elseif ($lastLine -match '^\s*\[ENGINE\]') { $stageText = '엔진 호출(응답 대기 중이었다)' }
        elseif ($lastLine -match '^\s*\[REPO-MAINT\]') { $stageText = '저장소 정비 세션' }
        elseif ($lastLine -match '^\s*\[ISSUE(-T0)?\]') { $stageText = '이슈 처리 세션' }
        elseif ($lastLine -match '^\s*\[WAIT\]') { $stageText = '다른 프로세스의 작업 디렉터리 점유 대기' }
        elseif ($lastLine -match '^\s*\[TIMEBOX\]') { $stageText = '이슈 시간 캡 초과 정리 직후' }
        else { $stageText = '단계 표식 마지막 줄: ' + ($lastLine -replace '\s+', ' ') }
    }
    $issueElapsed = $null
    if ($null -ne $IssueStartUtc) { $issueElapsed = [math]::Round(($NowUtc - ([datetime]$IssueStartUtc)).TotalMinutes, 1) }
    $sb = New-Object System.Text.StringBuilder
    if ($null -ne $Over) {
        [void]$sb.AppendLine("- 판정: 프로세스 시작 후 $($Over.RunElapsedMin)분" + $(if ($null -ne $Over.IssueElapsedMin) { ", 이 이슈 처리 시작 후 $($Over.IssueElapsedMin)분" } else { '' }) + " 경과 (임계 초과 기준: $($Over.Reason))")
    }
    if ($Isn) {
        $startTxt = if ($null -ne $IssueStartUtc) { ([datetime]$IssueStartUtc).ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' } else { '미상' }
        [void]$sb.AppendLine("- 처리 중이던 이슈: isn=$Isn, 이슈 처리 시작: $startTxt" + $(if ($null -ne $issueElapsed) { " (경과 ${issueElapsed}분)" } else { '' }))
    }
    [void]$sb.AppendLine("- 마지막으로 확인된 단계: $stageText")
    if ($tail.Count -gt 0) {
        [void]$sb.AppendLine('- 잡 출력에서 확인된 마지막 단계 줄:')
        foreach ($t in $tail) { [void]$sb.AppendLine("    > $t") }
    }
    [void]$sb.AppendLine('- 한계: 잡 출력은 이슈 세션 안의 엔진 출력까지 담지 못한다(내부 잡이 끝나야 회수된다). 위 단계 이후에 엔진이 실제로 무엇을 했는지는 **미상**이다.')
    [pscustomobject]@{ Known = $known; Stage = $stageText; Summary = $sb.ToString().TrimEnd(); TailLines = $tail }
}

function Format-GissueOvertimeCauseComment($Isn, $Cause, $Settings, [string]$StatusNow = '') {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[OVERTIME-REPORT] (보고 시각: $ts)")
    [void]$sb.AppendLine("상태: $(if ($StatusNow) { $StatusNow } else { '처리 중' }) / 로드한 역할: 없음 (스케줄러 스크립트가 LLM 없이 남기는 자동 코멘트)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("이 이슈를 처리하던 스케줄러 실행이 자기 마감시각(프로세스 시작 후 $($Settings.RunDeadlineMin)분 / 이슈 시작 후 $($Settings.IssueMin)분, 작업 스케줄러 제한 $($Settings.TaskLimitMin)분)을 넘겼습니다. 외부 강제 종료 전에 아래 순서로 정리합니다: 원인 보고 -> 서브 이슈 분할 -> 실행 종료/락 정리 -> 원본 DONE(서브 이슈가 등록된 경우에만).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 원인 (무엇을 하다 어디서 시간이 걸렸는지)')
    [void]$sb.AppendLine($Cause.Summary)
    $sb.ToString().TrimEnd()
}

# 규칙 2 입력: 원본 본문 "## 완료조건" 섹션의 코드펜스 밖 미체크 항목 + (있으면) 최근 CHECKLIST-REVERT 미충족 항목.
function Get-GissueRemainingChecklistItems($IssueContent, $Comments) {
    $items = New-Object System.Collections.ArrayList
    $seen = @{}
    $add = {
        param($text, $src)
        $t = ("$text").Trim()
        if (-not $t) { return }
        $key = ($t.ToLowerInvariant() -replace '\s+', ' ')
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$items.Add([pscustomobject]@{ Text = $t; Source = $src })
    }
    # 1) 최근 CHECKLIST-REVERT 코멘트의 미충족 항목(gissue-audit-lib.ps1 이 로드돼 있을 때만)
    if (Get-Command Get-LatestUnmetChecklistItems -ErrorAction SilentlyContinue) {
        try { foreach ($u in @(Get-LatestUnmetChecklistItems @($Comments))) { & $add $u.Text 'checklist-revert' } } catch { }
    }
    # 2) 본문 "## 완료조건" 섹션의 미체크 항목 (verify 코드펜스 안은 건너뛴다)
    $inSection = $false
    $inFence = $false
    foreach ($line in ("$IssueContent" -split '\r?\n')) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($line -match '^##\s*완료\s*조건') { $inSection = $true; continue }
        if ($inSection -and $line -match '^##\s') { break }
        if ($inSection -and $line -match '^\s*[-*]\s*\[\s\]\s*(.+)$') { & $add $Matches[1] 'body' }
    }
    return @($items)
}

# 원본 본문의 ```verify 블록 본문들(승계용).
function Get-GissueVerifyBlocks($IssueContent) {
    $blocks = @()
    $m = [regex]::Matches("$IssueContent", '(?ms)^\s*```verify[^\r\n]*\r?\n(.*?)^\s*```')
    foreach ($x in $m) { $b = $x.Groups[1].Value.TrimEnd(); if ($b.Trim()) { $blocks += $b } }
    return $blocks
}

# 규칙 2: 분할 계획(순수). 항목 0건이면 분할 불가. 서브 이슈는 2~5건이 적정하되 항목 수가 적으면 항목 수만큼.
function New-GissueOvertimeSplitPlan($Isn, $Title, $Items, $VerifyBlocks, $IssueUrl, $CauseSummary, [int]$MaxChildren = 5) {
    $arr = @($Items | Where-Object { $_ })   # 함수 반환으로 빈 배열이 $null 로 풀려 들어와도 0건으로 센다
    if ($arr.Count -eq 0) {
        return [pscustomobject]@{ Splittable = $false; Reason = '원본에 잔여 체크리스트 항목이 없어 나눌 단위가 없다'; Children = @() }
    }
    $n = [math]::Min($MaxChildren, $arr.Count)
    $size = [math]::Ceiling($arr.Count / $n)
    $children = @()
    for ($i = 0; $i -lt $n; $i++) {
        $chunk = @($arr | Select-Object -Skip ($i * $size) -First $size)
        if ($chunk.Count -eq 0) { continue }
        $idx = $children.Count + 1
        $head = ($chunk[0].Text -replace '\s+', ' ')
        if ($head.Length -gt 48) { $head = $head.Substring(0, 48) + '...' }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('## 배경')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("giip $Isn 의 처리 실행이 스케줄러 자기 마감시각을 넘겨 스케줄러가 원인을 보고하고 남은 작업을 이 이슈로 분할했습니다(giip 4429 규칙). 원본: $IssueUrl")
        [void]$sb.AppendLine("원본 제목: $Title")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 이 조각의 범위 (원본 체크리스트 잔여 항목)')
        [void]$sb.AppendLine('')
        foreach ($it in $chunk) { [void]$sb.AppendLine("- $($it.Text)") }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 완료조건')
        [void]$sb.AppendLine('')
        foreach ($it in $chunk) { [void]$sb.AppendLine("- [ ] $($it.Text)") }
        [void]$sb.AppendLine('')
        if (@($VerifyBlocks).Count -gt 0) {
            [void]$sb.AppendLine('원본의 기계 검증 블록을 승계합니다(원본 전체 기준이므로 이 조각을 끝내도 다른 조각이 남아 있으면 FAIL 일 수 있습니다 — 착수 세션이 이 조각 범위의 명령으로 좁혀 교체하십시오).')
            foreach ($vb in @($VerifyBlocks)) {
                [void]$sb.AppendLine('')
                [void]$sb.AppendLine('```verify')
                [void]$sb.AppendLine($vb)
                [void]$sb.AppendLine('```')
            }
        } else {
            [void]$sb.AppendLine('원본에 기계 검증 블록이 없어 이 조각의 검증 명령을 자동 생성할 수 없습니다. 아래 블록은 **의도적으로 실패**합니다 — 착수 세션이 이 조각의 완료조건을 검증하는 명령으로 교체해야 DONE 으로 갈 수 있습니다(rule 57).')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('```verify')
            [void]$sb.AppendLine('echo "TODO: 이 서브 이슈의 완료조건을 검증하는 명령으로 교체하십시오 (giip 4429)" && exit 1')
            [void]$sb.AppendLine('```')
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## 원인 보고 (원본 코멘트와 동일 요약)')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("$CauseSummary")
        $children += [pscustomobject]@{ Index = $idx; Title = "$head (원본 giip $Isn 분해 $idx/$n)"; Content = $sb.ToString().TrimEnd(); Items = $chunk }
    }
    # N 은 실제 생성 수로 다시 맞춘다
    $total = $children.Count
    for ($k = 0; $k -lt $total; $k++) { $children[$k].Title = ($children[$k].Title -replace '분해 \d+/\d+\)$', "분해 $($k + 1)/$total)") }
    [pscustomobject]@{ Splittable = $true; Reason = ''; Children = $children }
}

# 규칙 69-4: 같은 원본의 미해결 후속/서브 이슈 찾기(순수). Rows = {Isn, Status, Title}.
function Find-GissueOpenSplitChildren($Rows, $OriginIsn) {
    $re = '원본\s*giip\s*#?' + [regex]::Escape("$OriginIsn") + '(?!\d)'
    @($Rows | Where-Object {
        $_ -and "$($_.Title)" -match $re -and "$($_.Status)".Trim().ToUpperInvariant() -notin @('DONE', 'CANCELLED') -and [int]$_.Isn -ne [int]$OriginIsn
    })
}

# 규칙 3: 정리 대상 락 선별(순수). Records = {Kind:'csn-lock'|'repo-lock', Path, Csn, Pid, Holder}.
#   csn-lock : 같은 CSN 이고 락의 PID 가 이 러너 프로세스(RunnerPid)인 것만(다른 인스턴스의 락은 건드리지 않는다).
#   repo-lock: holder 가 gissue-csn<이 CSN>:<pid> 이고 pid 가 이 잡 소유(JobPids)이거나 죽은 것만.
function Get-GissueOvertimeLockTargets($Records, $Csn, [int]$RunnerPid, $JobPids, [scriptblock]$IsAlive) {
    $targets = @()
    $skipped = @()
    foreach ($r in @($Records)) {
        if (-not $r) { continue }
        if ($r.Kind -eq 'csn-lock') {
            if ("$($r.Csn)" -ne "$Csn") { $skipped += [pscustomobject]@{ Path = $r.Path; Why = '다른 CSN 의 락' }; continue }
            if ([int]$r.Pid -ne $RunnerPid) { $skipped += [pscustomobject]@{ Path = $r.Path; Why = "다른 인스턴스(PID $($r.Pid))의 락" }; continue }
            $targets += [pscustomobject]@{ Kind = 'csn-lock'; Path = $r.Path; Why = '이 러너 프로세스가 만든 CSN 락' }
        } elseif ($r.Kind -eq 'repo-lock') {
            if ("$($r.Holder)" -notmatch '^gissue-csn(\d+):(\d+)') { $skipped += [pscustomobject]@{ Path = $r.Path; Why = 'gissue 잡 holder 형식이 아님' }; continue }
            $hc = $Matches[1]; $hp = [int]$Matches[2]
            if ($hc -ne "$Csn") { $skipped += [pscustomobject]@{ Path = $r.Path; Why = "다른 CSN($hc)의 holder" }; continue }
            $own = (@($JobPids) -contains $hp)
            $dead = $false
            if (-not $own) { try { $dead = -not [bool](& $IsAlive $hp) } catch { $dead = $false } }
            if ($own -or $dead) { $targets += [pscustomobject]@{ Kind = 'repo-lock'; Path = $r.Path; Holder = $r.Holder; Why = $(if ($own) { '이 잡이 소유한 repo 락' } else { "죽은 PID($hp)의 repo 락" }) } }
            else { $skipped += [pscustomobject]@{ Path = $r.Path; Why = "PID $hp 생존 — 다른 실행의 락" } }
        }
    }
    [pscustomobject]@{ Targets = $targets; Skipped = $skipped }
}

# 규칙 4 코멘트. 첫 줄 [SPLIT-CLOSE], "분할 이전" 명시, 서브 이슈 번호 포함 — Test-HasSplitCloseMarker 가 이 형식을 인식한다.
function Format-GissueSplitCloseComment($Isn, $ChildIsns, [string]$IssueUrlBase, $Settings) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($script:GissueSplitCloseMarker + " (종결 시각: $ts)")
    [void]$sb.AppendLine('상태: DONE(분할 이전 종결) / 로드한 역할: 없음 (스케줄러 스크립트가 LLM 없이 남기는 자동 코멘트)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("이 이슈는 **분할 이전** 상태에서 종결합니다 — 처리 실행이 자기 마감시각(프로세스 시작 후 $($Settings.RunDeadlineMin)분)을 넘겨, 남은 작업을 아래 서브 이슈로 나눠 등록한 뒤 실행을 종료했습니다. 이 DONE 은 구현 완료가 아니라 **남은 작업이 서브 이슈로 이전됐다**는 뜻입니다(rule 69-5: 분해 완료 판정은 DB 에 등록된 자식 이슈로 한다).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 서브 이슈')
    foreach ($c in @($ChildIsns)) { [void]$sb.AppendLine("- giip $c — $IssueUrlBase$c") }
    $sb.ToString().TrimEnd()
}

function Format-GissueNoSplitComment($Isn, [string]$Reason, $Settings) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[OVERTIME-NOSPLIT] (판단 시각: $ts)")
    [void]$sb.AppendLine('상태: READY(복귀) / 로드한 역할: 없음 (스케줄러 스크립트가 LLM 없이 남기는 자동 코멘트)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("처리 실행이 자기 마감시각을 넘겨 종료했지만 **서브 이슈로 분할하지 못했습니다**: $Reason")
    [void]$sb.AppendLine('분할된 서브 이슈가 없으므로 이 이슈를 DONE 으로 올리지 않습니다(완료 위조 금지). 기존 시간 캡 처리(TIMEBOX)와 같은 관례로 READY 로 되돌려 다음 실행이 이어받게 합니다.')
    $sb.ToString().TrimEnd()
}

# 오케스트레이션. 쓰기는 전부 $Ports 를 통한다. Ports(스크립트블록):
#   Log($msg)  FindOpenChildren($originIsn)->rows  PostComment($isn,$body)->bool  RegisterChild($title,$content)->isn|$null
#   StopJob()  ListLocks()->records  RemoveLocks($targets)  SetStatus($isn,$status,$reason)->bool
# Ctx: Isn(없으면 $null) Title Csn Status Content Comments OutputLines Over Settings IssueStartUtc NowUtc RunnerPid JobPids IsAlive IssueUrlBase
# 반환: Steps(실행/예정 단계 토큰, 순서 보존) WriteCalls(실제 쓰기 포트 호출 수) FinalStatus Splittable ChildIsns Errors NeedsRunnerTimeout
function Invoke-GissueOvertimeSplit($Ctx, [string]$Mode, $Ports) {
    $res = [pscustomobject]@{
        Mode = $Mode; Steps = (New-Object System.Collections.ArrayList); WriteCalls = 0; FinalStatus = 'NONE'
        Splittable = $false; ChildIsns = @(); Errors = (New-Object System.Collections.ArrayList); NeedsRunnerTimeout = $false
    }
    if ($Mode -eq 'Off') { [void]$res.Steps.Add('off'); return $res }
    $live = ($Mode -eq 'Live')
    $tag = if ($live) { '[OVERTIME]' } else { '[OVERTIME-SHADOW]' }
    $log = { param($m) try { $null = & $Ports.Log "$tag $m" } catch { } }   # 포트 출력(Write-Log 의 Write-Output 등)이 결과 객체와 섞이지 않게 버린다
    $step = { param($s) [void]$res.Steps.Add($s) }

    $isn = $Ctx.Isn
    $cause = Get-GissueOvertimeCause $Ctx.OutputLines $isn $Ctx.IssueStartUtc $Ctx.NowUtc $Ctx.Over
    & $log "과시간 감지 — $($Ctx.Over.Reason) 기준 (프로세스 $($Ctx.Over.RunElapsedMin)분 / 이슈 $($Ctx.Over.IssueElapsedMin)분). 마지막 단계: $($cause.Stage)"

    # 처리 중인 이슈가 없다(저장소 정비 등): 규칙 1·2·4 대상이 없다. 규칙 3(종료)은 러너의 기존 TIMEOUT 경로가 수행한다.
    if (-not $isn) {
        & $step 'no-issue-in-flight'
        & $log "처리 중인 이슈 없음(저장소 정비/대기 단계) — 원인만 기록: $($cause.Summary -replace '\r?\n', ' | ')"
        if ($live) { $res.NeedsRunnerTimeout = $true; & $step 'defer-to-runner-timeout' }
        else { & $log 'would: 러너의 TIMEOUT 경로로 이 잡을 종료(외부 강제 종료보다 먼저)' }
        return $res
    }

    # ── 규칙 1: 원인 코멘트 ─────────────────────────────────────────────
    $causeBody = Format-GissueOvertimeCauseComment $isn $cause $Ctx.Settings $Ctx.Status
    $causeOk = $false
    if ($live) {
        & $step 'cause-comment'; $res.WriteCalls++
        try { $causeOk = [bool](& $Ports.PostComment $isn $causeBody) } catch { [void]$res.Errors.Add("cause-comment: $($_.Exception.Message)") }
        if (-not $causeOk) { & $log "원인 코멘트 등록 실패 — 서브 이슈 분할·DONE 은 건너뛴다(보고 없이 진행하지 않는다)" }
    } else { & $step 'would:cause-comment'; & $log "would: 원인 코멘트 등록 isn=$isn" }

    # ── 규칙 2: 서브 이슈 ────────────────────────────────────────────────
    $childIsns = @()
    $plannedChildren = 0     # Shadow 에서 "등록했다면 몇 건"
    $registerFailed = 0
    $splitReason = ''
    $existing = @()
    $findFailed = $false   # 조회 실패 = 중복 등록 위험 -> 새로 등록하지 않는다(fail-closed)
    try { $existing = @(Find-GissueOpenSplitChildren (& $Ports.FindOpenChildren $isn) $isn) } catch { $findFailed = $true; [void]$res.Errors.Add("find-children: $($_.Exception.Message)") }
    if ($live -and -not $causeOk) {
        $splitReason = '원인 코멘트를 등록하지 못해 분할을 보류했다'
    } elseif ($findFailed) {
        $splitReason = '기존 서브/후속 이슈 조회에 실패해 중복 등록 위험이 있어 분할을 보류했다(rule 69-4)'
        & $step 'find-children-failed'
    } elseif ($existing.Count -gt 0) {
        $childIsns = @($existing | ForEach-Object { [int]$_.Isn })
        $res.Splittable = $true
        & $step "reuse-existing-children:$($childIsns -join ',')"
        & $log "같은 원본의 미해결 서브/후속 이슈가 이미 있어 새로 등록하지 않는다(rule 69-4): $($childIsns -join ', ')"
    } else {
        $items = Get-GissueRemainingChecklistItems $Ctx.Content $Ctx.Comments
        $plan = New-GissueOvertimeSplitPlan $isn $Ctx.Title $items (Get-GissueVerifyBlocks $Ctx.Content) "$($Ctx.IssueUrlBase)$isn" $cause.Summary $script:GissueOvertimeMaxChildren
        $res.Splittable = $plan.Splittable
        if (-not $plan.Splittable) {
            $splitReason = $plan.Reason
            & $step 'not-splittable'
            & $log "분할 불가: $splitReason"
        } else {
            foreach ($c in $plan.Children) {
                if ($live) {
                    & $step 'register-child'; $res.WriteCalls++
                    $newIsn = $null
                    try { $newIsn = & $Ports.RegisterChild $c.Title $c.Content } catch { [void]$res.Errors.Add("register-child: $($_.Exception.Message)") }
                    if ($newIsn) { $childIsns += [int]$newIsn; & $log "서브 이슈 등록: giip $newIsn — $($c.Title)" }
                    else { $registerFailed++; & $log "서브 이슈 등록 실패: $($c.Title)" }
                } else {
                    & $step 'would:register-child'
                    $plannedChildren++
                    & $log "would: 서브 이슈 등록 — $($c.Title) (항목 $($c.Items.Count)건)"
                }
            }
        }
    }
    $res.ChildIsns = $childIsns

    # ── 규칙 3: 종료·정리 (Live 에서 분할 성패와 무관하게 항상 수행 — 외부 강제 종료가 곧 온다) ─────
    if ($live) {
        & $step 'stop-job'; $res.WriteCalls++
        try { $null = & $Ports.StopJob } catch { [void]$res.Errors.Add("stop-job: $($_.Exception.Message)") }
        $recs = @()
        try { $recs = @(& $Ports.ListLocks) } catch { [void]$res.Errors.Add("list-locks: $($_.Exception.Message)") }
        $sel = Get-GissueOvertimeLockTargets $recs $Ctx.Csn $Ctx.RunnerPid $Ctx.JobPids $Ctx.IsAlive
        foreach ($sk in $sel.Skipped) { & $log "락 유지: $($sk.Path) — $($sk.Why)" }
        & $step 'cleanup-locks'; $res.WriteCalls++
        try { $null = & $Ports.RemoveLocks $sel.Targets } catch { [void]$res.Errors.Add("remove-locks: $($_.Exception.Message)") }
        foreach ($t in $sel.Targets) { & $log "락 정리: $($t.Path) — $($t.Why)" }
    } else {
        & $step 'would:stop-job'; & $step 'would:cleanup-locks'
        & $log 'would: 이 잡만 종료하고, 이 러너가 만든 CSN 락과 이 잡 소유/죽은 PID 의 repo 락만 정리'
    }

    # ── 규칙 4: 원본 코멘트 + DONE (서브 이슈가 전부 등록된 경우에만) ──────────────────────────
    $childCount = if ($live) { $childIsns.Count } else { $childIsns.Count + $plannedChildren }
    $doneEligible = ($childCount -gt 0 -and $registerFailed -eq 0 -and ($causeOk -or -not $live))
    if ($doneEligible) {
        $closeBody = Format-GissueSplitCloseComment $isn $childIsns $Ctx.IssueUrlBase $Ctx.Settings
        if ($live) {
            & $step 'close-comment'; $res.WriteCalls++
            $closeOk = $false
            try { $closeOk = [bool](& $Ports.PostComment $isn $closeBody) } catch { [void]$res.Errors.Add("close-comment: $($_.Exception.Message)") }
            if ($closeOk) {
                & $step 'set-status:DONE'; $res.WriteCalls++
                $ok = $false
                try { $ok = [bool](& $Ports.SetStatus $isn 'DONE' "2시간 초과 실행 분할 이전 종결 — 서브 이슈 $($childIsns -join ', ') (giip 4429)") } catch { [void]$res.Errors.Add("set-status: $($_.Exception.Message)") }
                $res.FinalStatus = if ($ok) { 'DONE' } else { 'NONE' }
            } else { & $log '[SPLIT-CLOSE] 코멘트 등록 실패 — DONE 으로 올리지 않는다'; $res.FinalStatus = 'NONE' }
        } else {
            & $step 'would:close-comment'; & $step 'would:set-status:DONE'
            & $log "would: [SPLIT-CLOSE] 코멘트(서브 이슈 ${childCount}건) 후 DONE"
            $res.FinalStatus = 'DONE(would)'
        }
    } else {
        if (-not $splitReason) {
            if ($registerFailed -gt 0) { $splitReason = "서브 이슈 $registerFailed 건 등록 실패 — 일부만 등록돼 DONE 으로 올리지 않는다" }
            elseif ($childIsns.Count -eq 0) { $splitReason = '등록된 서브 이슈가 없다' }
        }
        $noSplitBody = Format-GissueNoSplitComment $isn $splitReason $Ctx.Settings
        if ($live) {
            & $step 'nosplit-comment'; $res.WriteCalls++
            try { [void](& $Ports.PostComment $isn $noSplitBody) } catch { [void]$res.Errors.Add("nosplit-comment: $($_.Exception.Message)") }
            & $step 'set-status:READY'; $res.WriteCalls++
            $ok = $false
            try { $ok = [bool](& $Ports.SetStatus $isn 'READY' "2시간 초과 실행 — 분할 불가/불완전($splitReason), DONE 하지 않고 READY 복귀 (giip 4429)") } catch { [void]$res.Errors.Add("set-status: $($_.Exception.Message)") }
            $res.FinalStatus = if ($ok) { 'READY' } else { 'NONE' }
        } else {
            & $step 'would:nosplit-comment'; & $step 'would:set-status:READY'
            & $log "would: 분할 불가 사유 코멘트 후 READY 복귀 (DONE 안 함) — $splitReason"
            $res.FinalStatus = 'READY(would)'
        }
    }
    return $res
}

# 러너 Phase 2 가 부르는 진입점. Base: NowUtc ProcessStartUtc OutputLines Settings Csn RunnerPid JobPids IsAlive IssueUrlBase
#   LoadIssue($isn)->{Title,Status,Content,Comments}. 임계 미만이면 아무것도 하지 않고 Over=$false 를 돌려준다.
function Invoke-GissueOvertimeGuard($Base, [string]$Mode, $Ports) {
    if ($Mode -eq 'Off') { return [pscustomobject]@{ Over = $false; Reason = 'off'; Result = $null; Check = $null } }
    $inflight = Get-GissueInFlightIssue $Base.OutputLines
    $issueStart = $null
    if ($inflight) { $issueStart = $inflight.StartUtc }
    $check = Test-GissueOvertime $Base.NowUtc $Base.ProcessStartUtc $issueStart $Base.Settings
    if (-not $check.Over) { return [pscustomobject]@{ Over = $false; Reason = 'under-threshold'; Result = $null; Check = $check } }
    $title = ''; $status = ''; $content = ''; $comments = @()
    $isn = $null
    if ($inflight) {
        $isn = $inflight.Isn; $status = $inflight.Status
        try {
            $d = & $Base.LoadIssue $isn
            if ($d) { $title = "$($d.Title)"; $content = "$($d.Content)"; $comments = @($d.Comments); if ($d.Status) { $status = "$($d.Status)" } }
        } catch { }
    }
    $ctx = [pscustomobject]@{
        Isn = $isn; Title = $title; Csn = $Base.Csn; Status = $status; Content = $content; Comments = $comments
        OutputLines = $Base.OutputLines; Over = $check; Settings = $Base.Settings; IssueStartUtc = $issueStart
        NowUtc = $Base.NowUtc; RunnerPid = $Base.RunnerPid; JobPids = $Base.JobPids; IsAlive = $Base.IsAlive; IssueUrlBase = $Base.IssueUrlBase
    }
    # 방어: 어떤 포트가 출력을 흘려도 결과는 Steps 를 가진 마지막 객체 1개로 고정한다(흘린 문자열이 섞이면 errors 계수가 틀어진다).
    $res = @(Invoke-GissueOvertimeSplit $ctx $Mode $Ports | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties['Steps'] }) | Select-Object -Last 1
    [pscustomobject]@{ Over = $true; Reason = $check.Reason; Result = $res; Check = $check }
}
