# test-unmapped-csn-guard-live.ps1 — 미매핑 CSN 가드의 **라이브 실측** (giip 4116 완료 기준 2·3)
#
# 왜 이 파일이 tests/ 아래가 아니라 tests/live/ 아래인가:
#   이 테스트는 **실제 서버와 실제 SK** 가 있어야만 의미가 있다(CI 러너에는 둘 다 없다).
#   저장소 게이트(run-repo-gates.ps1)는 scripts/gissue/tests 직속의 test-*.ps1 만 돌리므로
#   이 파일은 CI 에서 자동 실행되지 않는다 — 사람이 SK 있는 PC 에서 직접 돌리는 실측 스크립트다.
#   그래서 "검사기가 0건을 보고 PASS" 하지 않는다(SKIP 는 종료코드 3 으로 알린다 — rule 42).
#
# 무엇을 실측하는가 (giip 4116 완료 기준 2):
#   (A) 실서버에서 실제로 받아온 **CSN 47 의 이슈 행**을 재료로 쓴다(스텁 데이터 아님).
#   (B) 그 행들을 "요청 csn 이 다른 csn"의 응답으로 제시했을 때 대조 게이트가 SKIP-CLAMP 로
#       버리고 통과 행이 0건이 되는 것을 확인한다.
#       * 현행 /api/giipIssues 는 클램프하지 않는다(요청 csn 을 충실 반환) → 서버가 스스로
#         클램프한 응답을 **직접 만들 수는 없다**. 그래서 검증 방식은 "서버 실응답 행을
#         불일치 csn 요청에 대한 응답으로 제시"하는 분기 검증이다(giip 4139 와 같은 방식).
#   (C) 같은 실서버 행을 요청 csn 과 일치시켜 제시하면 **전부 통과**하는지(대조 게이트가
#       정상 동작하고, 오탐으로 버리지 않음) 확인한다.
#   (D) 가드 본체를 라이브 조건으로 end-to-end 실행한다: 정본(tGissueCsnMapping) 기준 판정 →
#       SKIP-MAPPED-CANONICAL / SKIP-CANONICAL-UNKNOWN, 그리고 **원래 이슈 코멘트 0건**,
#       **새 [OPS] 이슈 0건**을 실행 전후 비교로 확인한다.
#   (E) 워크트리 사본(다른 체크아웃)에서도 같은 결과가 나오는지는 호출부가 비교한다 —
#       이 스크립트는 "지금 실행 중인 체크아웃"만 본다(경로 하드코딩 금지).
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/live/test-unmapped-csn-guard-live.ps1
#     [-AccountsFile <giip-accounts.json 경로>] [-ApiBase <기점>] [-OpsCsn <게시 대상 csn>]
#
# 종료코드: 0 = 전건 PASS / 1 = FAIL / 3 = SKIP(SK·계정 파일·네트워크 부재 → 아무것도 안 하고 나온다)
#
# ⚠ 읽기 전용이다 — 이 스크립트는 API 를 **조회**만 한다. 코멘트 등록·이슈 등록은 없다.
#   게시 스위치(GISSUE_CSNGUARD_OPS_CSN)를 켜되 가드는 -SkipPosting 으로 호출한다 →
#   "뭘 올렸을 것인지"만 로그로 남고 실제로는 아무것도 올라가지 않는다.

param(
    [string]$AccountsFile = '',
    [string]$ApiBase = 'https://giipfaw.azurewebsites.net/api',
    # 게시 대상 csn — 가드의 "무엇을 올렸을 것인지" 로그(TEST-WOULD-POST) 판정용.
    # 실제로 게시하지는 않는다(-SkipPosting).
    [string]$OpsCsn = '70424',
    # 대조 게이트에 불일치 요청으로 제시할 csn(클램프 시뮬레이션용).
    [string]$ClampProbeCsn = '99999'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$libDir = Join-Path $repoRoot 'scripts/gissue/lib'
$testsLiveDir = Join-Path $repoRoot 'scripts/gissue/tests/live'
. (Join-Path $libDir 'csn-guard.ps1')
. (Join-Path $libDir 'csn-mapping.ps1')
. (Join-Path $libDir 'unmapped-csn-guard.ps1')

$probe = Join-Path $testsLiveDir 'live-api-probe.js'
$listIssues = Join-Path $repoRoot 'scripts/gissue/list-issues.js'
$mappingHelper = Join-Path $libDir 'get-csn-mapping.js'

$script:Pass = 0
$script:Fail = 0
function Assert($cond, $msg, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $msg" }
    else { $script:Fail++; Write-Output "  FAIL  $msg$(if ($detail) { " — $detail" })" }
}
function Skip($reason) {
    Write-Output "  SKIP  $reason"
    Write-Output "SKIP: $reason"
    exit 3
}
# JSON 문자열 → 행 배열. 빈 배열("[]")·빈 문자열은 **0건**으로 본다.
# (@($null) 의 Count 가 1 이 되는 PS 함정을 피한다.)
function ConvertTo-RowArray($text) {
    $t = ($text | Out-String).Trim()
    if (-not $t) { return @() }
    $parsed = $t | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

# ── 사전 조건 ───────────────────────────────────────────────────────────────
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Skip 'node 를 찾을 수 없음 — 실측 불가' }
if (-not $AccountsFile) { $AccountsFile = Join-Path $repoRoot 'slack-bot/.secrets/giip-accounts.json' }
if (-not (Test-Path -LiteralPath $AccountsFile)) { Skip "계정 파일 없음: $AccountsFile (SK 필요 — 실측 불가)" }
if (-not (Test-Path -LiteralPath $probe)) { Skip "probe 없음: $probe" }

$acc = Get-Content -LiteralPath $AccountsFile -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-SkFor($csn) {
    $all = @()
    if ($acc.default) { $all += $acc.default }
    foreach ($p in $acc.channels.PSObject.Properties) { $all += $p.Value }
    $m = $all | Where-Object { "$($_.csn)" -eq "$csn" -and $_.sk } | Select-Object -First 1
    if ($m) { return "$($m.sk)" }
    return $null
}

# 실측 대상 csn: 이 PC 의 계정 파일에 SK 가 있고, 이슈가 실제로 존재하는 csn.
# (CSN 47 = 정본 등록+활성 csn. 이 이슈의 사고 대상 csn 이자 대조 게이트 검증 재료의 출처다.)
$probeCsn = '47'
$probeSk = Get-SkFor $probeCsn
if (-not $probeSk) { Skip "csn $probeCsn 의 SK 를 계정 파일에서 찾지 못했음 — 실측 불가" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-guard-live-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {

    # ── (A) 실서버에서 실제 행 확보 ─────────────────────────────────────────
    Write-Output "== (A) 실서버 실제 응답 행 확보 (csn=$probeCsn) =="
    $rawIssues = & node $probe issues $ApiBase $probeSk $probeCsn 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Skip "실서버 조회 실패(네트워크 또는 권한): $rawIssues" }
    $liveRows = ConvertTo-RowArray $rawIssues
    if ($liveRows.Count -eq 0) { Skip "csn $probeCsn 에서 실서버 행을 하나도 못 받았다 — 실측 불가" }
    $rowCsns = @($liveRows | ForEach-Object { "$($_.cSn)" } | Sort-Object -Unique)
    Write-Output ("  실서버 행 {0}건, 응답 cSn=[{1}]" -f $liveRows.Count, ($rowCsns -join ','))
    Assert (($rowCsns | Where-Object { $_ -ne $probeCsn }).Count -eq 0) '실서버 응답 행의 cSn 이 모두 요청 csn 과 일치(현행 API 는 클램프하지 않음)'

    # (A-2) "봇 유저가 멤버가 아닌 csn 을 일부러 조회" — 실제 서버 응답이 무엇인지.
    #   현행 /api/giipIssues 는 요청 csn 을 충실 반환하고 클램프하지 않는다 →
    #   비멤버 csn 조회는 **0건**이 돌아온다(거짓 코멘트의 재료가 애초에 없다).
    #   서버가 스스로 클램프한 응답을 만들 수는 없으므로 (B) 에서 분기를 검증한다.
    Write-Output "== (A-2) 비멤버 csn 조회(실서버) =="
    $nonMember = & node $probe issues $ApiBase $probeSk $ClampProbeCsn 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Output "  (비멤버 csn 조회 실패 — 건너뛴다): $nonMember" }
    else {
        $nmRows = ConvertTo-RowArray $nonMember
        Write-Output ("  비멤버 csn {0} 조회 → {1}건" -f $ClampProbeCsn, $nmRows.Count)
        Assert ($nmRows.Count -eq 0) "비멤버 csn 조회 응답 0건 (현행 API 는 클램프하지 않음 → 거짓 코멘트 재료 없음)"
    }

    # ── (B) 실서버 행을 불일치 요청에 제시 → SKIP-CLAMP 로 0건 통과 ──────────
    Write-Output "== (B) 대조 게이트 — 실서버 행을 다른 csn 요청으로 제시 =="
    $logB = Join-Path $tmp 'clamp.log'
    $keptB = Select-GissueRowsMatchingCsn -Rows $liveRows -RequestedCsn $ClampProbeCsn -Log {
        param($m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File -FilePath $logB -Append -Encoding UTF8
    }
    Assert (@($keptB).Count -eq 0) "불일치 csn 요청($ClampProbeCsn) → 통과 행 0건"
    $logBText = Get-Content -LiteralPath $logB -Raw -Encoding UTF8
    $clampCount = ([regex]::Matches($logBText, 'SKIP-CLAMP')).Count
    Assert ($clampCount -eq $liveRows.Count) "SKIP-CLAMP 로그 $clampCount 건 (실서버 행 $((@($liveRows)).Count) 건 전부)"
    $clampExcerpt = @((Get-Content -LiteralPath $logB -Encoding UTF8) | Select-Object -First 3)
    Write-Output "  --- 로그 발췌(결과 코멘트 첨부용) ---"
    foreach ($l in $clampExcerpt) { Write-Output "  $l" }

    # ── (C) 같은 실서버 행을 일치 요청으로 제시 → 전부 통과 ──────────────────
    Write-Output "== (C) 대조 게이트 — 실서버 행을 일치 csn 요청으로 제시 =="
    $logC = Join-Path $tmp 'match.log'
    $keptC = Select-GissueRowsMatchingCsn -Rows $liveRows -RequestedCsn $probeCsn -Log {
        param($m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File -FilePath $logC -Append -Encoding UTF8
    }
    Assert (@($keptC).Count -eq $liveRows.Count) "일치 csn 요청($probeCsn) → 실서버 행 $($liveRows.Count)건 전부 통과"
    Assert (-not (Test-Path -LiteralPath $logC)) '일치 요청에서는 SKIP 로그가 남지 않음(침묵)'

    # ── (D) 가드 본체 라이브 end-to-end ─────────────────────────────────────
    Write-Output "== (D) 가드 본체 라이브 실행 (조회·판정만, 게시 없음) =="
    # 이 PC 배포의 로컬 매핑 파일이 있으면 그것을, 없으면 "자기 csn 만 있는" 임시 맵을 쓴다.
    # 사고 조건(정본에 등록된 csn 47 이 로컬 맵에 없음)을 그대로 재현하기 위한 선택이다.
    $repoMap = Join-Path $repoRoot 'scripts/gissue/csn-projects.json'
    $mapFile = Join-Path $tmp 'csn-projects.json'
    if (Test-Path -LiteralPath $repoMap) {
        Copy-Item -LiteralPath $repoMap -Destination $mapFile -Force
        Write-Output "  로컬 매핑: $repoMap 사용"
    } else {
        # 사고 조건(2026-10-22) 재현: 로컬 맵에 **후보 csn(47 등) 이 하나도 없어서**
        # "미매핑"으로 오판되던 상태. 여기서는 무관한 csn 하나만 등록해 후보 전부가 대상이 되게 한다.
        $json = [pscustomobject]@{ csn = [pscustomobject]@{ '33' = [pscustomobject]@{ project = 'giipprj'; workdir = 'C:/tmp'; enabled = $true } } } |
            ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($mapFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "  로컬 매핑: 저장소에 csn-projects.json 이 없어 임시 맵 사용(후보 csn 미등록 = 사고 조건 재현)"
    }

    $candidates = @(Get-GissueUnmappedCandidateCsns -ProjectCsnFile (Join-Path $repoRoot 'slack-bot/project-csn.json') -GiipAccountsFile $AccountsFile)
    Write-Output ("  후보 csn: {0}" -f (($candidates | ForEach-Object { "$_" }) -join ','))

    $guardLog = Join-Path $tmp 'gissue_csnguard.log'
    $env:GISSUE_CSNGUARD_OPS_CSN = $OpsCsn
    [void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns $candidates `
        -ListIssuesScript $listIssues -RegisterIssueScript (Join-Path $repoRoot 'scripts/gissue/register-issue.js') `
        -GiipAccountsFile $AccountsFile -ApiBase $ApiBase -LogFilePath $guardLog `
        -MappingHelperPath $mappingHelper -SkResolver { param($c) Get-SkFor $c } -SkipPosting)
    $guardText = if (Test-Path -LiteralPath $guardLog) { Get-Content -LiteralPath $guardLog -Raw -Encoding UTF8 } else { '' }
    foreach ($l in @((Get-Content -LiteralPath $guardLog -Encoding UTF8) | Select-Object -First 12)) { Write-Output "  $l" }

    Assert ($guardText.Contains("SKIP-MAPPED-CANONICAL: csn=$probeCsn")) "정본 등록+활성 csn($probeCsn) → SKIP-MAPPED-CANONICAL (담당 있음 → 게시 없음)"
    Assert ($guardText.Contains('SKIP-CANONICAL-UNKNOWN')) '정본 조회 불가 csn → SKIP-CANONICAL-UNKNOWN (fail-closed, 아무것도 안 씀)'
    Assert (-not $guardText.Contains('TEST-WOULD-POST')) '게시 후보 csn 없음 — TEST-WOULD-POST 로그 없음'
    Assert (-not $guardText.Contains('POSTED:')) '실제 게시 없음(POSTED 로그 없음)'

    # ── (D-2) 실행 전후 비교: 원래 이슈 코멘트 0건, 새 [OPS] 이슈 0건 ─────────
    Write-Output "== (D-2) 실행 전후 비교 — 코멘트·[OPS] 이슈 0건 =="
    $sample = @($liveRows | Select-Object -First 5)
    $opsSk = Get-SkFor $OpsCsn
    $before = @{}
    foreach ($r in $sample) {
        $before["$($r.isn)"] = [pscustomobject]@{
            total = [int](& node $probe comments $ApiBase $probeSk $r.isn)
            warn  = @((ConvertTo-RowArray (& node $probe commentlist $ApiBase $probeSk $r.isn)) |
                      Where-Object { "$($_.content)" -like '*UNMAPPED-CSN-WARN*' }).Count
        }
    }
    $opsBefore = if ($opsSk) { ConvertTo-RowArray (& node $probe issues $ApiBase $opsSk $OpsCsn 'PENDING,READY,IN_PROGRESS,REVIEW') } else { @() }
    $opsBeforeIsns = @($opsBefore | ForEach-Object { "$($_.isn)" })

    # 가드를 한 번 더(게시 스위치 켠 상태로, -SkipPosting) — 앞의 (D) 실행과 같은 조건.
    [void](Invoke-GissueUnmappedCsnGuard -MapFilePath $mapFile -CandidateCsns $candidates `
        -ListIssuesScript $listIssues -RegisterIssueScript (Join-Path $repoRoot 'scripts/gissue/register-issue.js') `
        -GiipAccountsFile $AccountsFile -ApiBase $ApiBase -LogFilePath $guardLog `
        -MappingHelperPath $mappingHelper -SkResolver { param($c) Get-SkFor $c } -SkipPosting)

    $deltaComments = 0
    $deltaWarn = 0
    foreach ($r in $sample) {
        $afterTotal = [int](& node $probe comments $ApiBase $probeSk $r.isn)
        $afterWarn = @((ConvertTo-RowArray (& node $probe commentlist $ApiBase $probeSk $r.isn)) |
                       Where-Object { "$($_.content)" -like '*UNMAPPED-CSN-WARN*' }).Count
        $b = $before["$($r.isn)"]
        $deltaComments += ($afterTotal - $b.total)
        $deltaWarn += ($afterWarn - $b.warn)
    }
    Assert ($deltaComments -eq 0) "실행 전후 원래 이슈 코멘트 변화 0건 (실제: $deltaComments)"
    Assert ($deltaWarn -eq 0) "실행 전후 [UNMAPPED-CSN-WARN] 코멘트 변화 0건 (실제: $deltaWarn)"

    $opsAfter = if ($opsSk) { ConvertTo-RowArray (& node $probe issues $ApiBase $opsSk $OpsCsn 'PENDING,READY,IN_PROGRESS,REVIEW') } else { @() }
    $opsAfterIsns = @($opsAfter | ForEach-Object { "$($_.isn)" })
    $newOps = @($opsAfterIsns | Where-Object { $opsBeforeIsns -notcontains $_ })
    Assert ($newOps.Count -eq 0) "새 [OPS] 이슈 0건 (실제: $($newOps.Count))"

    Write-Output ""
    Write-Output ("결과: PASS=$($script:Pass) FAIL=$($script:Fail)")
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Fail -gt 0) { exit 1 }
exit 0
