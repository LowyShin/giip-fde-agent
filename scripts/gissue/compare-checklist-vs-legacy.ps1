# compare-checklist-vs-legacy.ps1 - 신·구 되돌림 판정 병행 비교 (giip #4334 변경 지시 8-a, 읽기 전용)
#
# 용도: 최근 N일(기본 14일) 동안 실제로 REVIEW/DONE -> READY 로 되돌려진 이슈 표본에 대해
#   "구룰(PR 유무 중심 게이트)은 되돌렸다" vs "신룰(의뢰 체크리스트 판정)은 어떻게 판정하는가"를 병행 비교한다.
#   핵심 지표 = 구룰 되돌림 중 신룰로는 유지(KEEP) 판정되는 건수(= 오판 추정).
# 처리: giipIssues / giipIssueComments 를 GET 으로 읽고, 되돌림 시점 직전까지의 코멘트로 신룰 판정(LLM, 도구 없음)을
#   돌린다. **이슈 코멘트·상태 쓰기를 하지 않는다**(쓰기 함수를 호출하지 않는다).
# 결과 저장: 표준출력 요약 + (선택) -OutFile JSON. 별도 DB/KVS 기록 없음. 소비처: 이슈 4334 롤아웃 보고(사람).
#
# 한계(결과 해석 시 반드시 함께 보고): PR 증거는 "지금" 시점의 PR 상태다(되돌림 당시 상태가 아님). 되돌림 이후
#   작업자가 PR 을 머지했다면 신룰이 코드 항목을 더 관대하게 볼 수 있다. 코멘트는 되돌림 직전까지로 자른다.
#
# 롤아웃 (b) 확인 모드: -LiveSince <UTC 시각> 를 주면, 그 시각 이후 "체크리스트 코멘트 없는 되돌림 전이"
#   (구 게이트 되돌림 마커 코멘트, 또는 '## 의뢰 체크리스트 판정' 절 없는 CHECKLIST-REVERT)를 세어 0건인지 보고한다.
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File compare-checklist-vs-legacy.ps1 -Csn <csn> -Workdir "<프로젝트 workdir>" `
#       [-ApiKey <SK> | -AccountsFile <giip-accounts.json>] [-Days 14] [-MaxSamples 30] [-OutFile <json>] [-LiveSince 2026-11-01T00:00:00Z]
param(
    [Parameter(Mandatory = $true)][int]$Csn,
    [string]$Workdir = '',
    [string]$ApiKey = '',
    [string]$AccountsFile = '',
    [string]$ApiBaseUrl = 'https://giipfaw.azurewebsites.net/api',
    [int]$Days = 14,
    [int]$MaxSamples = 30,
    [string]$OutFile = '',
    [string]$LiveSince = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'gissue-audit-lib.ps1')
. (Join-Path $PSScriptRoot 'gissue-gate-tally-lib.ps1')

function Write-CmpLog($msg) { Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [compare-checklist] $msg" }

function ConvertTo-Utc($s) {
    if (-not $s) { return $null }
    try { return [datetime]::Parse([string]$s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { return $null }
}

# SK 해석: -ApiKey > -AccountsFile(resolve-sk.js) > <레포>/slack-bot/.secrets/giip-accounts.json
if (-not $ApiKey) {
    if (-not $AccountsFile) { $AccountsFile = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'slack-bot\.secrets\giip-accounts.json' }
    if (-not (Test-Path -LiteralPath $AccountsFile)) { throw "ApiKey(SK)가 없고 AccountsFile 도 없습니다: $AccountsFile" }
    $ApiKey = ((& node (Join-Path $PSScriptRoot 'lib\resolve-sk.js') $AccountsFile "$Csn") | Out-String).Trim()
    if (-not $ApiKey) { throw "AccountsFile 에 csn=$Csn 의 SK 가 없습니다(작업 CSN 의 키만 쓴다)." }
}

$repos = @()
if ($Workdir -and (Test-Path -LiteralPath $Workdir)) { $repos = Get-NestedRepoPaths $Workdir }
Write-CmpLog "시작: csn=$Csn days=$Days maxSamples=$MaxSamples repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',') (읽기 전용 - 코멘트/상태 쓰기 없음)"

$since = (Get-Date).ToUniversalTime().AddDays(-$Days)
$defs = @(Get-GateRevertSourceDefs | Where-Object { $_.Key -ne 'checklist' })

# 1) 후보 이슈 수집(모든 상태 - 되돌림 후 상태가 바뀌었을 수 있다). last_comment_date 가 창 안인 것만.
$cands = @{}
foreach ($st in @('READY', 'IN_PROGRESS', 'REVIEW', 'DONE', 'NEEDS_DECISION', 'WARN', 'TESTED')) {
    try { $resp = Invoke-GiipApiGet "$ApiBaseUrl/giipIssues?status=$st&csn=$Csn" $ApiKey } catch { Write-CmpLog "$st 조회 실패: $($_.Exception.Message)"; continue }
    $rows = if ($resp -is [array]) { $resp } elseif ($resp.issues) { $resp.issues } elseif ($resp.data) { $resp.data } else { @() }
    foreach ($r in @($rows)) {
        $c = if ($null -ne $r.cSn) { $r.cSn } else { $r.csn }
        if (-not $r.isn -or "$c" -ne "$Csn") { continue }
        $lcd = $null
        if ($r.PSObject.Properties['last_comment_date']) { $lcd = ConvertTo-Utc $r.last_comment_date }
        if ($lcd -and $lcd -lt $since) { continue }
        $cands[[int]$r.isn] = $r
    }
}
Write-CmpLog "창(${Days}일) 내 코멘트된 후보 이슈 $($cands.Count)건 - 코멘트 스캔 중."

# 2) 되돌림 코멘트 표본 수집
$samples = @()
$liveSinceUtc = if ($LiveSince) { ConvertTo-Utc $LiveSince } else { $null }
$checklistLess = @()
$commentsByIsn = @{}
foreach ($isn in @($cands.Keys)) {
    $comments = @(Get-IssueComments $isn $ApiKey $ApiBaseUrl)
    $commentsByIsn[$isn] = $comments
    foreach ($c in $comments) {
        $content = "$($c.content)"
        if (-not $content) { continue }
        $rd = ConvertTo-Utc $c.regdate
        if (-not $rd -or $rd -lt $since) { continue }
        $hit = $null
        foreach ($d in $defs) { if ($content.Contains($d.Marker)) { $hit = $d; break } }
        if ($hit) {
            $samples += [pscustomobject]@{ Isn = $isn; At = $rd; Gate = $hit.Key; Title = "$($cands[$isn].title)"; NowStatus = "$($cands[$isn].status)" }
            if ($liveSinceUtc -and $rd -ge $liveSinceUtc) { $checklistLess += "isn=$isn gate=$($hit.Key) at=$($c.regdate)" }
        } elseif ($content.Contains($script:ChecklistMarkerRevert) -and $liveSinceUtc -and $rd -ge $liveSinceUtc -and -not $content.Contains('## 의뢰 체크리스트 판정')) {
            $checklistLess += "isn=$isn gate=checklist(본문에 체크리스트 없음) at=$($c.regdate)"
        }
    }
}
$allCount = @($samples).Count
$samples = @($samples | Sort-Object At -Descending | Select-Object -First $MaxSamples)
Write-CmpLog "구룰 되돌림 코멘트 $allCount 건 발견 -> 표본 $(@($samples).Count)건(최신순, 상한 $MaxSamples)으로 신룰 판정."

# 3) 신룰 병행 판정
$results = @()
foreach ($s in $samples) {
    $isn = $s.Isn
    $before = @($commentsByIsn[$isn] | Where-Object { $t = ConvertTo-Utc $_.regdate; $t -and $t -lt $s.At })
    $content = "$($cands[$isn].content)"
    if (-not $content) { $d = Get-IssueDetail $isn $ApiKey $ApiBaseUrl; if ($d -and $d.content) { $content = "$($d.content)" } }
    $pr = if ($repos.Count -gt 0) { Get-ChecklistPrEvidence $isn $repos } else { @{ Known = $false; HasMerged = $false; HasAny = $false; Text = '(PR 조회 불가 - Workdir 미지정)' } }
    $a = Invoke-ChecklistAssessment $isn $content $before $pr
    $unmet = @($a.Items | Where-Object { $_.Verdict -eq 'UNMET' } | ForEach-Object { $_.Text })
    $results += [pscustomobject]@{
        isn = $isn; revertedAt = $s.At.ToString('o'); legacyGate = $s.Gate; nowStatus = $s.NowStatus
        newOk = [bool]$a.Ok; newDecision = $a.Decision; reason = $a.Reason; unmet = $unmet; rawHeadIfFailed = $(if ($a.Ok) { '' } else { $h = ("$($a.Raw)" -replace '\s+', ' '); $h.Substring(0, [Math]::Min(300, $h.Length)) })
    }
    Write-CmpLog ("isn={0} 구룰={1}(REVERT) 신룰={2}{3} - {4}" -f $isn, $s.Gate, $a.Decision, $(if ($a.Ok) { '' } else { '(판정실패)' }), $a.Reason)
}

# 4) 요약
$ok = @($results | Where-Object { $_.newOk })
$keep = @($ok | Where-Object { $_.newDecision -eq 'KEEP' })
$rev = @($ok | Where-Object { $_.newDecision -eq 'REVERT' })
$hold = @($ok | Where-Object { $_.newDecision -eq 'HOLD' })
$failed = @($results | Where-Object { -not $_.newOk })
$byGate = @($results | Group-Object legacyGate | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
$summary = [ordered]@{
    csn = $Csn; days = $Days; legacyRevertCommentsInWindow = $allCount; samples = @($results).Count; byLegacyGate = $byGate
    newJudged = $ok.Count; newKeep_legacyMisjudgeEstimate = $keep.Count; newRevert = $rev.Count; newHold = $hold.Count; newJudgeFailed = $failed.Count
    legacyRevertsWithoutChecklist_baseline = $allCount
    checklistLessRevertsSinceLive = $(if ($liveSinceUtc) { @($checklistLess).Count } else { 'n/a (-LiveSince 미지정)' })
}
Write-CmpLog '== 요약 =='
foreach ($k in $summary.Keys) { Write-Output ("  {0} = {1}" -f $k, $summary[$k]) }
if ($liveSinceUtc -and $checklistLess.Count -gt 0) { Write-CmpLog "체크리스트 없는 되돌림 전이 발견(Live 전환 금지/롤백 사유):"; $checklistLess | ForEach-Object { Write-Output "  $_" } }
if ($OutFile) {
    ([ordered]@{ summary = $summary; results = $results } | ConvertTo-Json -Depth 6) | Out-File -LiteralPath $OutFile -Encoding utf8
    Write-CmpLog "결과 JSON: $OutFile"
}
