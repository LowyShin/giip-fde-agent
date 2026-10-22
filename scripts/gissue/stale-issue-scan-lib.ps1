# stale-issue-scan-lib.ps1 — "특정 상태로 오래 방치된 이슈" 탐지 공용 구현 (giip #2645)
#
# 왜 이 파일이 있나
#   `run-list-stale-pending.ps1`(PENDING)과 `run-list-stale-review.ps1`(REVIEW)은 대상 상태만 다르고
#   나머지(대상 CSN 해석 / 조회 / 결과 보존 / 로깅)가 같다. 원본 lowyworkenv 판은 두 러너가 서로 다른
#   구조(1단 DB INSERT vs giipdb mgmt 2단 호출)로 갈라져 있었고, 그래서 한쪽만 고쳐지는 사고가 실제로
#   있었다(giip #2429: REVIEW 쪽 러너가 파싱 불가인 채 등록돼 한 번도 돌지 못함 / giip #2431: PENDING
#   쪽 러너 파일이 아예 없는 채 태스크가 Ready). 이식하면서 공통부를 한 곳으로 모은다
#   (이 환경 방침: 파일은 최대한 분리 + 같은 일은 한 곳에서).
#
# ── 원본과의 차이: DB 직접접속을 쓰지 않는다 (giip #2645) ──────────────────────────────
#   원본 lowyworkenv 판은
#     · run-list-stale-pending.ps1 → `giipdb/mgmt/execSQLFile.ps1` 로 tAuditStalePendingResult 에 INSERT
#     · run-list-stale-review.ps1  → `giipdb/mgmt/list-stale-review.ps1` 호출(그 안에서 DB INSERT)
#   이었다. `giip-fde-agent` 에는 DB 직접접속 수단(`dbconfig.json` / `execSQLFile.ps1`)이 없으므로
#   정본 문서 §4("혼용 이식 금지")대로 **이 레포에 실제로 있는 API 도구**로 교체한다:
#     · 조회: `scripts/gissue/list-issues.js` (giipfaw API 경유)
#   존재하지 않는 경로를 참조하면 매 실행이 그 단계에서 조용히 실패하기 때문이다.
#
#   [저장되는 곳 / 소비처] 이 스캔의 결과물은
#     · `scripts/gissue/audit-results/<label>-csn<N>-<yyyyMMdd-HHmmss>.json` (전체 목록)
#     · `scripts/gissue/audit-results/<label>-csn<N>.log` (실행 로그, 1행 요약)
#   두 파일뿐이다. 원본이 적재하던 giipdb 테이블 `tAuditStalePendingResult` /
#   `tAuditStaleReviewResult`(소비처: 대시보드 SP `pApiGIIPIssueStalePendingListbyAK` 등)로의 적재는
#   이 레포에서 **수행하지 않는다** — DB 접속 수단이 없기 때문이며, 기능을 없앤 것이 아니라
#   그 적재가 필요한 배포(lowyworkenv, csn 47)에는 원본 러너가 그대로 남아 있다.
#
# ── 판정 기준의 차이(정확히 적어둔다 — 같은 이름이라고 같은 수치가 아니다) ─────────────
#   원본(DB)은 "마지막 활동(최신 코멘트 regdate, 없으면 이슈 등록일) 이후 경과일"로 방치를 쟀다.
#   이 API 판은 `list-issues.js --min-age-minutes` 를 쓰는데, 그 값은 **그 상태에 들어간 뒤 경과 시간**
#   (상태 전이 코멘트 "状態遷移: OLD -> NEW" + "**日時(When)**" 에서 역산)이다. 상태가 오래 안 바뀐
#   이슈를 잡는다는 목적은 같지만, 그 사이에 코멘트가 달린 이슈도 잡힌다는 점이 다르다.
#   또한 `list-issues.js` 는 전이 코멘트를 못 찾으면 age=null 로 두고 **누락 방지를 위해 포함**시킨다.
#   방치 탐지에서 그것을 그대로 "방치"로 세면 오탐이 되므로, 이 라이브러리는 age=null 건을
#   `undetermined`(판정불가)로 분리해 별도 집계한다 — 숫자를 부풀리지 않고, 놓치지도 않는다.

# 콘솔 출력 인코딩 고정(이 PC 기본은 cp932 라 한글이 깨진다 — check-ps1-parse.ps1 과 동일한 이유).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function Get-StaleScanTargetCsn {
    <#
        대상 CSN 목록을 정한다.
          · $Csn > 0            → 그 CSN 하나
          · $Csn = 0            → csn-projects.json 의 enabled 항목 전부
        csn-projects.json 은 gitignore 대상이라 배포마다 직접 채운다(csn-projects.json.example 참고).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptDir,
        [int]$Csn = 0
    )

    if ($Csn -gt 0) { return @($Csn) }

    $mapFile = Join-Path $ScriptDir 'csn-projects.json'
    if (-not (Test-Path -LiteralPath $mapFile)) { return @() }
    try {
        $map = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return @()
    }
    if (-not $map -or -not $map.csn) { return @() }

    $list = @()
    foreach ($prop in $map.csn.PSObject.Properties) {
        $entry = $prop.Value
        if ($entry -and $entry.enabled -eq $false) { continue }
        $n = 0
        if ([int]::TryParse($prop.Name, [ref]$n) -and $n -gt 0) { $list += $n }
    }
    return @($list)
}

function Invoke-StaleIssueScan {
    <#
        한 CSN 에 대해 "$Status 상태로 $DaysThreshold 일 이상 머문 이슈"를 조회하고 결과를 보존한다.
        반환: [pscustomobject] @{ Csn; Stale; Undetermined; JsonFile; ExitCode }
        ExitCode 0 = 조회 성공(대상 0건도 성공), 1 = 조회 실패.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptDir,
        [Parameter(Mandatory = $true)][int]$Csn,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$DaysThreshold = 7,
        # SK 저장소 경로. 미지정 시 list-issues.js 의 기본값(<RepoRoot>/slack-bot/.secrets/
        # giip-accounts.json)을 쓴다. 시크릿을 다른 곳에 두는 배포/검증용으로만 지정한다.
        [string]$AccountsFile = '',
        [scriptblock]$Logger = $null
    )

    # 로그는 반드시 Write-Host(정보 스트림)로 낸다. 이 함수의 **출력 스트림은 반환값 전용**이라,
    # 로그를 Write-Output 으로 내보내면 호출자가 `$r = Invoke-StaleIssueScan ...` 로 받을 때 로그 줄이
    # 반환 객체와 함께 배열로 묶여 화면에 한 줄도 안 나온다(실측 2026-09-17).
    function Write-Line($msg) {
        if ($Logger) { & $Logger $msg } else { Write-Host $msg }
    }

    $lister = Join-Path $ScriptDir 'list-issues.js'
    if (-not (Test-Path -LiteralPath $lister -PathType Leaf)) {
        Write-Line "ERROR: 조회 도구를 찾을 수 없습니다: $lister"
        return [pscustomobject]@{ Csn = $Csn; Stale = 0; Undetermined = 0; JsonFile = ''; ExitCode = 1 }
    }

    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) {
        Write-Line 'ERROR: node 실행파일을 찾을 수 없습니다(PATH 확인)'
        return [pscustomobject]@{ Csn = $Csn; Stale = 0; Undetermined = 0; JsonFile = ''; ExitCode = 1 }
    }

    $minAge = [int]$DaysThreshold * 1440

    # ⚠ 인코딩 — `& node ...` 로 그냥 받으면 안 된다(실측, giip #2431):
    #   PowerShell 은 네이티브 프로세스 stdout 을 [Console]::OutputEncoding 으로 디코딩한다. 콘솔이
    #   붙은 대화형 실행에서는 어쩌다 통과하지만, **작업 스케줄러가 콘솔 없이 실행하면 cp932 로
    #   디코딩**돼 한글 title 이 mojibake 가 되고 ConvertFrom-Json 이 죽는다.
    #   그래서 StandardOutputEncoding 을 UTF-8 로 명시한 Process 로 직접 띄운다.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $nodeArgs = @($lister, '--csn', "$Csn", '--status', $Status, '--min-age-minutes', "$minAge", '--json')
    if ($AccountsFile) { $nodeArgs += @('--accounts-file', $AccountsFile) }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $nodeExe
    $psi.Arguments              = (($nodeArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $psi.WorkingDirectory       = $ScriptDir
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = $utf8NoBom
    $psi.StandardErrorEncoding  = $utf8NoBom

    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $stdout  = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $rc     = $proc.ExitCode
    $stderr = $errTask.Result

    if ($rc -ne 0) {
        $e = ''
        if ($stderr) {
            $e = ($stderr -replace '\s+', ' ').Trim()
            if ($e.Length -gt 500) { $e = $e.Substring(0, 500) + ' …(생략)' }
        }
        Write-Line "ERROR: list-issues.js exit=$rc (csn=$Csn status=$Status) $e"
        return [pscustomobject]@{ Csn = $Csn; Stale = 0; Undetermined = 0; JsonFile = ''; ExitCode = 1 }
    }

    $text = "$stdout".Trim()
    if (-not $text) {
        Write-Line "ERROR: list-issues.js 출력이 비어 있습니다(csn=$Csn status=$Status)"
        return [pscustomobject]@{ Csn = $Csn; Stale = 0; Undetermined = 0; JsonFile = ''; ExitCode = 1 }
    }

    # ⚠ PowerShell 5.1 의 ConvertFrom-Json 은 빈 배열 '[]' 을 $null 로 돌려주고, 1건짜리 배열은
    #   배열이 아닌 단일 객체로 돌려준다. @() 로만 감싸면 빈 배열이 **1건**으로 세어진다(실측 사고 이력).
    #   그래서 $null 을 명시적으로 걸러낸다.
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch {
        $msg = ($_.Exception.Message -replace '\s+', ' ').Trim()
        if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + ' …(생략)' }
        Write-Line "ERROR: JSON 파싱 실패(csn=$Csn status=$Status) — $msg"
        return [pscustomobject]@{ Csn = $Csn; Stale = 0; Undetermined = 0; JsonFile = ''; ExitCode = 1 }
    }
    $items = @(@($parsed) | Where-Object { $null -ne $_ })

    $stale        = @($items | Where-Object { $null -ne $_.ageMinutes })
    $undetermined = @($items | Where-Object { $null -eq $_.ageMinutes })

    $resultDir = Join-Path $ScriptDir 'audit-results'
    if (-not (Test-Path $resultDir)) { New-Item -ItemType Directory -Path $resultDir -Force | Out-Null }

    $checkedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    $stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonFile  = Join-Path $resultDir ("{0}-csn{1}-{2}.json" -f $Label, $Csn, $stamp)

    $payload = [ordered]@{
        checkedAt     = $checkedAt
        csn           = $Csn
        status        = $Status
        daysThreshold = $DaysThreshold
        minAgeMinutes = $minAge
        source        = 'list-issues.js (giipfaw API)'
        stale         = $stale.Count
        undetermined  = $undetermined.Count
        issues        = @($stale | ForEach-Object {
            [ordered]@{ isn = $_.isn; title = $_.title; ageMinutes = $_.ageMinutes; daysInStatus = [Math]::Round($_.ageMinutes / 1440.0, 1) }
        })
        undeterminedIssues = @($undetermined | ForEach-Object {
            [ordered]@{ isn = $_.isn; title = $_.title; reason = '상태 전이 코멘트를 찾지 못해 경과시간 산출 불가' }
        })
    }
    [System.IO.File]::WriteAllText($jsonFile, ($payload | ConvertTo-Json -Depth 5), $utf8NoBom)

    Write-Line ("csn={0} status={1}: 방치 {2}건 / 판정불가 {3}건 (기준 {4}일) -> {5}" -f `
        $Csn, $Status, $stale.Count, $undetermined.Count, $DaysThreshold, (Split-Path -Leaf $jsonFile))

    return [pscustomobject]@{ Csn = $Csn; Stale = $stale.Count; Undetermined = $undetermined.Count; JsonFile = $jsonFile; ExitCode = 0 }
}
