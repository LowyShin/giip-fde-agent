# run-summary.ps1 — gissue "실행 종료 요약"(RunEnd summary) 조립 순수 로직 (giip #6214)
#
# ── 왜 필요한가 ───────────────────────────────────────────────────────────────────
# 스케줄러 실행 이력(tSchedulerAgentRun.summary)에는 지금 **종료 상태 한 줄**만 들어간다
# ("DONE" / "TIMEOUT (105분) — 중단"). 그래서 사후에 물어볼 수 없는 것이 두 가지다.
#   1) "이 실행이 어느 코드로 돌았는가" — 실행 체크아웃의 git HEAD 를 알 수 없다.
#      (머지된 코드가 호스트에 반영됐는지 여부도 §17-3 의 agentCommit 대조가 전부다.)
#   2) "이 실행이 어떤 엔진 경로로 돌았는가" — gair 경유였는지, 프로브 실패로 종전 경로로
#      폴백했는지, 어떤 이슈가 강제 claude 였는지 알 수 없다.
# 그리고 **기록 호출 자체가 실패한 경우**가 세션 로그의 WARN 한 줄로만 남아, 실행 이력에서는
# "기록이 없음"과 "기록 실패"가 구분되지 않는다(조용한 실패 — 사양서 §"근본 원인"이 바로 이 실패다).
#
# ── 이 파일이 하는 일 ─────────────────────────────────────────────────────────────
# 순수 함수만 둔다(파일/DB/네트워크 접근 없음). 러너가 잡 출력 줄에서 [GAIR]/[ENGINE] 마커를
# 집계해 요약을 만들고, RunEnd summary 문자열을 조립한다.
#   - `Get-GissueEngineLineKind`  : 한 줄 → 마커 종류(파싱)
#   - `Add-GissueEnginePathMarker`: 여러 줄 → 집계(누적)
#   - `Format-GissueEnginePathSummary` : 집계 → 한 줄 요약
#   - `Get-GissueSchedulerStateFailures` : 기록 호출 실패 줄 추출
#   - `Format-GissueRunEndSummary` : 최종 summary 조립(길이 제한 포함)
#
# 마커 종류(라벨):
#   maint-probe-disabled / maint-probe-ok / maint-probe-fail   — 저장소 정비 세션의 gair 프로브
#   issue-probe-disabled / issue-probe-ok / issue-probe-fail   — 일반 이슈 세션의 gair 프로브
#   path-gair         — gair 경로로 엔진을 시도했다
#   path-gair-failed  — gair 시도가 실패해 종전 경로로 폴백했다
#   path-legacy       — 종전 경로(MiniMax→Claude)를 선택했다
#   path-claude-forced— 강제 claude(REVIEW/TESTED 재검증) 경로를 선택했다
#
# 소비처: run-gissue-claude.ps1(Complete-Run) + tests/test-run-summary.ps1(네트워크 없음).
# PowerShell 5.1 호환.

# ── 집계기 초기값 ─────────────────────────────────────────────────────────────────
function New-GissueEnginePathMarker {
    return [pscustomobject]@{
        Gair            = 0   # gair 경로 시도 횟수
        GairFailed      = 0   # 그중 실패(폴백) 횟수
        Legacy          = 0   # 종전 경로(MiniMax→Claude) 선택 횟수
        ClaudeForced    = 0   # 강제 claude 선택 횟수
        MaintProbe      = ''  # 정비 세션 프로브 결과(ok/fail/disabled)
        IssueProbe      = ''  # 일반 이슈 세션 프로브 결과(ok/fail/disabled)
        FallbackReasons = @{} # 폴백 사유 → 횟수
    }
}

# ── 한 줄의 마커 종류 판정 ────────────────────────────────────────────────────────
# 판정 순서가 중요한다: '[REPO-MAINT][GAIR]' 문자열은 '[GAIR]' 를 **포함**하므로 정비 쪽을 먼저 본다.
# 반환: 마커 종류 문자열 또는 $null(마커 아님).
function Get-GissueEngineLineKind {
    param([string]$Line)
    if (-not $Line) { return $null }
    $l = "$Line"
    if ($l -match '\[REPO-MAINT\]\[GAIR\]') {
        if ($l -match 'GISSUE_REPO_MAINT_GAIR=0') { return 'maint-probe-disabled' }
        if ($l -match 'AK 파생 성공') { return 'maint-probe-ok' }
        if ($l -match 'AK 파생 실패') { return 'maint-probe-fail' }
        return $null
    }
    if ($l -match '\[GAIR\]') {
        if ($l -match 'GISSUE_GAIR=0') { return 'issue-probe-disabled' }
        if ($l -match 'AK 파생 성공') { return 'issue-probe-ok' }
        if ($l -match 'AK 파생 실패') { return 'issue-probe-fail' }
        return $null
    }
    if ($l -match '\[ENGINE\]') {
        if ($l -match 'gair 시도 실패') { return 'path-gair-failed' }
        if ($l -match 'gair 우선 시도') { return 'path-gair' }
        if ($l -match 'MiniMax 우선 시도') { return 'path-legacy' }
        if ($l -match '강제 기동') { return 'path-claude-forced' }
        return $null
    }
    return $null
}

# ── 줄 묶음 → 집계 ───────────────────────────────────────────────────────────────
# $Marker 를 **그 자리에서** 갱신한다(호출부가 누적 객체 하나를 들고 다닌다).
# 같은 줄을 두 번 먹어도 값이 달라지지 않도록, 집계는 마커 종류별로 **횟수**만 더한다.
function Add-GissueEnginePathMarker {
    param(
        [Parameter(Mandatory = $true)]$Marker,
        [string[]]$Lines = @()
    )
    foreach ($line in @($Lines)) {
        $kind = Get-GissueEngineLineKind -Line $line
        if (-not $kind) { continue }
        switch ($kind) {
            'maint-probe-disabled' { $Marker.MaintProbe = 'disabled' }
            'maint-probe-ok'       { $Marker.MaintProbe = 'ok' }
            'maint-probe-fail'     { $Marker.MaintProbe = 'fail' }
            'issue-probe-disabled' { $Marker.IssueProbe = 'disabled' }
            'issue-probe-ok'       { $Marker.IssueProbe = 'ok' }
            'issue-probe-fail'     { $Marker.IssueProbe = 'fail' }
            'path-gair'            { $Marker.Gair = $Marker.Gair + 1 }
            'path-gair-failed'     {
                $Marker.GairFailed = $Marker.GairFailed + 1
                $key = 'gair호출실패'
                if ($Marker.FallbackReasons.ContainsKey($key)) { $Marker.FallbackReasons[$key] = $Marker.FallbackReasons[$key] + 1 }
                else { $Marker.FallbackReasons[$key] = 1 }
            }
            'path-legacy'          { $Marker.Legacy = $Marker.Legacy + 1 }
            'path-claude-forced'   { $Marker.ClaudeForced = $Marker.ClaudeForced + 1 }
        }
    }
    return $Marker
}

# ── 집계 → 한 줄 요약 ────────────────────────────────────────────────────────────
# 프로브 결과는 한국어 낱말로(성공/실패/끔) — 운영자가 읽는 기록이라 기계용 코드는 쓰지 않는다.
# 아무 마커도 없으면 "기록없음"을 명시한다(0 을 "문제가 없었다"로 읽게 하지 않기 위해).
function Format-GissueEnginePathSummary {
    param($Marker)
    if ($null -eq $Marker) { return '엔진경로 기록없음' }
    $probe = @()
    if ($Marker.MaintProbe) {
        $probe += "정비=$(@{ 'ok' = '성공'; 'fail' = '실패'; 'disabled' = '끔' }[$Marker.MaintProbe])"
    }
    if ($Marker.IssueProbe) {
        $probe += "일반=$(@{ 'ok' = '성공'; 'fail' = '실패'; 'disabled' = '끔' }[$Marker.IssueProbe])"
    }
    $reasons = @()
    if ($Marker.FallbackReasons -and $Marker.FallbackReasons.Count -gt 0) {
        foreach ($k in @($Marker.FallbackReasons.Keys | Sort-Object)) { $reasons += "$k=$($Marker.FallbackReasons[$k])" }
    }
    $total = $Marker.Gair + $Marker.Legacy + $Marker.ClaudeForced
    if ($total -eq 0 -and $probe.Count -eq 0 -and $reasons.Count -eq 0) { return '엔진경로 기록없음' }
    $text = "엔진경로 gair=$($Marker.Gair)(실패=$($Marker.GairFailed)) 종전=$($Marker.Legacy) claude강제=$($Marker.ClaudeForced)"
    if ($probe.Count -gt 0) { $text += " | 프로브 $($probe -join ',')" }
    if ($reasons.Count -gt 0) { $text += " | 폴백사유 $($reasons -join ',')" }
    return $text
}

# ── 기록(스케줄러 상태) 호출 실패 추출 ───────────────────────────────────────────
# 러너가 남기는 실패 표식:
#   [WARN][SchedulerState-<action>] 실패: <사유>      (잡 스코프의 upsert/runStart/heartbeat)
#   [WARN][SchedulerState-init] 초기화 실패: <사유>   (잡 시작 직전 초기화)
#   [SchedulerState-runEnd] 실패: <사유>              (종료 기록)
# 반환: "<action>: <사유>" 배열. 실패가 없으면 빈 배열.
function Get-GissueSchedulerStateFailures {
    param(
        [string[]]$Lines = @(),
        [int]$MaxReasonLength = 120
    )
    $out = @()
    foreach ($line in @($Lines)) {
        $l = "$line"
        # `-match` 는 $Matches 를 덮어쓰므로 두 판정 모두 명시적 [regex]::Match 로 한다
        # (두 번째 -match 를 먼저 하면 $Matches[1] 이 사라져 동작 이름이 빈 문자열이 된다).
        $mAction = [regex]::Match($l, 'SchedulerState-([A-Za-z]+)')
        if (-not $mAction.Success) { continue }
        if ($l -notmatch '실패') { continue }
        $action = $mAction.Groups[1].Value
        $reason = ''
        $m = [regex]::Match($l, '실패\s*[:：]?\s*(.*)$')
        if ($m.Success) { $reason = $m.Groups[1].Value.Trim() }
        if ($reason.Length -gt $MaxReasonLength) { $reason = $reason.Substring(0, $MaxReasonLength) + '…' }
        if (-not $reason) { $reason = '(사유 없음)' }
        $out += "$action`: $reason"
    }
    return @($out)
}

# ── 최종 summary 조립 ────────────────────────────────────────────────────────────
# 순서(중요도가 높은 것 먼저 — 길이 제한으로 잘릴 때 실행 판정에 필요한 정보가 살아남도록):
#   1) 종료 상태  2) 이전 실행 stall  3) 기록 호출 실패  4) 실행 코드 버전(HEAD)
#   5) 엔진 경로 요약  6) 자동 반영 결과
# "이전 실행 stall"을 2번째에 두는 이유: 전체를 한꺼번에 자르면 **뒤쪽 항목이 통째로 사라진다.**
# stall 은 앞 실행이 강제종료돼 자기 종료 기록을 못 남긴 신호라, 잘려 나가면 "stall 이 없었다"로
# 읽히게 된다. 기록 호출 실패와 같은 자리(앞쪽)에 두면 어떤 길이 제한에서도 살아남는다.
# $MaxLength 를 넘으면 끝을 '…' 로 자른다(사양서의 detail 500자 절단 관례와 같은 취지).
#
# 항목별 길이 제한이 붙는 이유: 앞 항목이 길어도 뒤 항목(엔진 경로·자동 반영)이 통째로 잘리지 않게.
function Format-GissueSummaryPart {
    param([string]$Text, [int]$MaxLength = 0)
    if (-not $Text) { return '' }
    if ($MaxLength -gt 0 -and $Text.Length -gt $MaxLength) {
        return $Text.Substring(0, [Math]::Max(1, $MaxLength - 1)) + '…'
    }
    return $Text
}

function Format-GissueRunEndSummary {
    param(
        [string]$Status = '',
        [string]$CodeVersion = '',
        [string]$EnginePath = '',
        [string]$SyncInfo = '',
        [string[]]$RecordFailures = @(),
        [string[]]$StallNotes = @(),
        [int]$MaxLength = 500
    )
    $parts = @()
    $s = Format-GissueSummaryPart -Text $Status -MaxLength 60
    if ($s) { $parts += $s }
    # 이전 실행 stall — 두 번째 자리(길이 제한으로 잘려도 살아남는 자리).
    # 마커는 앞 실행의 post-process 단계가 시간 한도에 걸려 남긴 것이다. 그 실행은
    # 자기 종료 기록을 못 남겼으므로, 이 실행의 summary 가 유일한 실행 이력 통로다.
    if (@($StallNotes).Count -gt 0) {
        $n = @($StallNotes).Count
        $first = Format-GissueSummaryPart -Text (@($StallNotes)[0]) -MaxLength 90
        $parts += "이전실행 stall ${n}건(예: $first)"
    }
    # 기록 호출 실패 — 세 번째 자리(길이 제한으로 잘려도 살아남는 자리).
    if (@($RecordFailures).Count -gt 0) {
        $n = @($RecordFailures).Count
        $first = Format-GissueSummaryPart -Text (@($RecordFailures)[0]) -MaxLength 90
        $parts += "기록호출실패 ${n}건(예: $first)"
    }
    $cv = Format-GissueSummaryPart -Text $CodeVersion -MaxLength 48
    if ($cv) { $parts += "코드 $cv" }
    $ep = Format-GissueSummaryPart -Text $EnginePath -MaxLength 130
    if ($ep) { $parts += $ep }
    $si = Format-GissueSummaryPart -Text $SyncInfo -MaxLength 130
    if ($si) { $parts += "자동반영 $si" }
    $text = ($parts -join ' | ')
    if ($MaxLength -gt 0 -and $text.Length -gt $MaxLength) {
        $text = $text.Substring(0, [Math]::Max(1, $MaxLength - 1)) + '…'
    }
    return $text
}
