# unmapped-csn-guard.ps1 — 미매핑 CSN 가드 (giip 4116 / 4139)
#
# 왜 lib 로 뺐나: 이 가드는 2026-10-22 **거짓阳性 코멘트 사고**(CSN 47 이슈 5건에
#   "[UNMAPPED-CSN-WARN] csn-projects.json 미등록으로 자동처리 대상이 아닙니다" 가 붙은 사건)의
#   직접 원인이었던 판단 로직이다. 러너(run-gissue-claude.ps1) 안의 top-level 함수였다가
#   Phase -2.5 블록에서만 호출되어 "실제 호출 경로"를 회귀 테스트가 건드릴 수 없었다.
#   → 러너와 테스트가 **같은 함수**를 쓰도록 lib 로 분리했다(러너는 dot-source 로 그대로 사용).
#
# 계약 (giip 4116 수정 요구 1~4):
#   1) 조회 응답의 실제 cSn 만 신뢰한다.
#      - 응답 cSn != 요청 csn  → SKIP-CLAMP  (행 버림)
#      - 응답에 cSn 필드 없음  → SKIP-NOCSN (행 버림)
#      - 기본값은 침묵이다 — 거짓 코멘트 1건의 비용이 누락 1건의 비용보다 크다.
#   2) 판정 재료는 **정본** tGissueCsnMapping(gcmEnabled = 1) 이다.
#      로컬 csn-projects.json 만 믿지 않는다. 정본 조회가 실패하면(전송/권한/파싱) 로컬 파일로
#      되돌아가지 **않고 아무것도 쓰지 않는다**(fail-closed).
#   3) 게시 단위는 **csn 1건**이다. 원래 이슈들에는 코멘트를 남기지 않는다.
#   4) 실행 결과는 logs/gissue_csnguard.log 에 POSTED / SKIP-* / OK 로 남긴다.
#
# 정본 판정 상태(3값):
#   MAPPED   — 정본에 등록 + 활성. 담당 배포가 있으므로 **아무것도 하지 않는다**.
#   UNMAPPED — 정본에 행이 없음이 **확인**됨(404/빈 결과) 또는 비활성 행. → 게시 대상.
#   UNKNOWN  — 정본 조회 실패(403 스코프/전송 오류/파싱 실패/행 이상). → **아무것도 쓰지 않는다**.
#   (UNKNOWN 을 UNMAPPED 로 취급하면 "정본에 등록된 csn 을 담당 없음으로 오판" 하는 거짓 양성이
#    되돌아온다 — 2026-10-22 사고와 같은 종류다. 그래서 UNKNOWN 은 침묵이다.)
#
# 의존성 주입(러너/테스트가 각각의 환경값을 넘긴다):
#   -ListIssuesScript   : list-issues.js 경로 (응답 cSn 포함 JSON)
#   -RegisterIssueScript: register-issue.js 경로 (운영 이슈 등록)
#   -GiipAccountsFile   : CSN→SK 계정 파일
#   -ApiBase            : giipfaw API 基점
#   -MappingHelperPath  : lib/get-csn-mapping.js 경로 (정본 조회 헬퍼)
#   -SkResolver         : { param($csn) ... } → 그 csn 의 SK (없으면 $null)
#   -LogFilePath        : 로그 파일(운영: logs/gissue_csnguard.log)

if (-not (Get-Command Select-GissueRowsMatchingCsn -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'csn-guard.ps1')
}
if (-not (Get-Command Get-GissueCsnMappingRemote -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'csn-mapping.ps1')
}

# 후보 CSN 수집 — 미매핑 감시의 두 출처(프로젝트→csn 맵 + 계정 파일 채널).
# 감시 후보와 정본 판정 대상은 같은 목록이어야 한다(한쪽만 새로우면 오판이 생긴다).
# [주의] 프로젝트→csn 맵 파일의 실제 형태는 { "map": { "<프로젝트명>": <csn> } } 이지만,
#   이 함수는 러너 원본의 수집 규칙(최상위 속성에서 csn 값을 찾는다)을 그대로 유지한다 —
#   후보 집합 확대는 이 이슈(가드 정정) 범위 밖의 동작 변경이라 하지 않는다.
function Get-GissueUnmappedCandidateCsns {
    param(
        [string]$ProjectCsnFile,
        [string]$GiipAccountsFile
    )
    $candidates = @{}
    try {
        if ($ProjectCsnFile -and (Test-Path -LiteralPath $ProjectCsnFile)) {
            $pc = Get-Content -LiteralPath $ProjectCsnFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $pc.PSObject.Properties) {
                $v = $p.Value
                $c = if ($v -is [string] -or $v -is [int]) { "$v" } elseif ($v.csn) { "$($v.csn)" } else { $null }
                if ($c -and $c -match '^\d+$') { $candidates["$c"] = $true }
            }
        }
    } catch {}
    try {
        if ($GiipAccountsFile -and (Test-Path -LiteralPath $GiipAccountsFile)) {
            $acc = Get-Content -LiteralPath $GiipAccountsFile -Raw | ConvertFrom-Json
            foreach ($ch in $acc.channels.PSObject.Properties) {
                if ($ch.Value.csn) { $candidates["$($ch.Value.csn)"] = $true }
            }
        }
    } catch {}
    return @($candidates.Keys | Sort-Object)
}

# 정본(tGissueCsnMapping) 조회 결과를 3값 상태로 접는다 — 순수 판정(조회는 lib/csn-mapping.ps1 이 한다).
function Get-GissueCanonicalMappingStatus {
    param(
        [Parameter(Mandatory = $true)]$Remote
    )
    if (-not $Remote) { return [pscustomobject]@{ Status = 'UNKNOWN'; Detail = 'no_result' } }
    if ($Remote.Found) {
        if ($Remote.Enabled) {
            return [pscustomobject]@{ Status = 'MAPPED'; Detail = "project=$($Remote.ProjectName)" }
        }
        return [pscustomobject]@{ Status = 'UNMAPPED'; Detail = 'canonical_row_disabled' }
    }
    $reason = "$($Remote.Reason)"
    if ($reason -eq 'not_found') {
        return [pscustomobject]@{ Status = 'UNMAPPED'; Detail = 'not_in_canonical_mapping' }
    }
    # scope_mismatch(403) · error(전송/파싱) · invalid_row 등 = 확인 못 함 → 침묵
    return [pscustomobject]@{ Status = 'UNKNOWN'; Detail = "$reason" }
}

# 후보 csn 의 열린 이슈를 조회하고, **응답 cSn 이 요청 csn 과 같은 행만** 돌려준다.
function Get-GissueOpenIssuesAllCsn {
    param(
        [string[]]$CandidateCsns = @(),
        [string[]]$MappedCsns = @(),
        [Parameter(Mandatory = $true)][string]$ListIssuesScript,
        [Parameter(Mandatory = $true)][string]$GiipAccountsFile,
        [Parameter(Mandatory = $true)][string]$ApiBase,
        [Parameter(Mandatory = $true)][string]$LogFilePath
    )
    $result = @()
    foreach ($c in $CandidateCsns) {
        if ($MappedCsns -contains "$c") { continue }
        try {
            $raw = & node $ListIssuesScript --csn $c --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED' `
                --accounts-file $GiipAccountsFile --api-base $ApiBase --json 2>&1
            if ($LASTEXITCODE -ne 0) { continue }
            $parsed = ($raw | Out-String) | ConvertFrom-Json
            # giip 4116/4139: 응답 행의 실제 cSn 이 요청 csn 과 같은 행만 신뢰한다(서버 클램프 방어).
            $trusted = Select-GissueRowsMatchingCsn -Rows $parsed -RequestedCsn "$c" -Log {
                param($m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
            }
            foreach ($r in @($trusted)) {
                $result += [pscustomobject]@{ Csn = "$c"; Isn = "$($r.isn)"; Status = "$($r.status)" }
            }
        } catch {}
    }
    return ,$result
}

# 메인 오케스트레이터. -SkipPosting 은 실제 등록 대신 "무엇을 올렸을 것인지"만 로그로 남긴다
# (구현 검증용 호출 전용 — 운영 실행은 이 스위치를 절대 쓰지 않는다).
function Invoke-GissueUnmappedCsnGuard {
    param(
        [Parameter(Mandatory = $true)][string]$MapFilePath,
        [string[]]$CandidateCsns = @(),
        [string]$ListIssuesScript,
        [string]$RegisterIssueScript,
        [string]$GiipAccountsFile,
        [string]$ApiBase,
        [Parameter(Mandatory = $true)][string]$LogFilePath,
        [string]$MappingHelperPath,
        [scriptblock]$SkResolver,
        [string]$NodeExe = 'node',
        [switch]$SkipPosting
    )
    $Tag = '[UNMAPPED-CSN-WARN]'
    $found = @()
    function Write-GuardLine($msg) {
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
        $line | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
        Write-Output $line
    }
    try {
        $mappedCsns = @()
        if (Test-Path -LiteralPath $MapFilePath) {
            $mapJson = Get-Content -LiteralPath $MapFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($mapJson.csn) { $mappedCsns = @($mapJson.csn.PSObject.Properties.Name) }
        } else {
            Write-GuardLine "$Tag SKIP-NOMAPFILE: 매핑 파일을 찾을 수 없음: $MapFilePath — 아무것도 하지 않는다"
            return ,$found
        }

        $targets = @($CandidateCsns | Where-Object { $mappedCsns -notcontains "$_" })
        if ($targets.Count -eq 0) {
            Write-GuardLine "$Tag OK: 후보 csn 중 로컬 매핑에 없는 csn 이 없음"
            return ,$found
        }

        # ── 정본 기준 1차 판정 (수정 요구 2) ───────────────────────────────
        # 정본에 등록+활성인 csn 은 "담배 배포 없음"이 아니다 → 아무것도 하지 않는다.
        # 정본 조회 실패(UNKNOWN)는 침묵이다(로컬 파일로 되돌아가지 않는다).
        $unmappedTargets = @()
        foreach ($csnVal in $targets) {
            $sk = if ($SkResolver) { & $SkResolver $csnVal } else { $null }
            $remote = Get-GissueCsnMappingRemote -Csn $csnVal -ApiBase $ApiBase -Sk $sk `
                -NodeExe $NodeExe -HelperPath $MappingHelperPath
            $verdict = Get-GissueCanonicalMappingStatus -Remote $remote
            if ($verdict.Status -eq 'MAPPED') {
                Write-GuardLine "$Tag SKIP-MAPPED-CANONICAL: csn=$csnVal 정본(tGissueCsnMapping)에 등록+활성($($verdict.Detail)) — 담당 있음, 게시 없음"
                continue
            }
            if ($verdict.Status -eq 'UNKNOWN') {
                Write-GuardLine "$Tag SKIP-CANONICAL-UNKNOWN: csn=$csnVal 정본 조회 불가($($verdict.Detail)) — 아무것도 쓰지 않는다(수정 요구 2: 정본 실패 시 로컬로 되돌아가지 않음)"
                continue
            }
            $unmappedTargets += $csnVal
        }
        if ($unmappedTargets.Count -eq 0) {
            Write-GuardLine "$Tag OK: 정본 기준 미매핑 csn 없음"
            return ,$found
        }

        # ── 2차: 미매핑으로 확인된 csn 의 열린 이슈 조회 + 응답 cSn 대조 ──
        $openIssues = Get-GissueOpenIssuesAllCsn -CandidateCsns $unmappedTargets -MappedCsns @() `
            -ListIssuesScript $ListIssuesScript -GiipAccountsFile $GiipAccountsFile `
            -ApiBase $ApiBase -LogFilePath $LogFilePath
        if (-not $openIssues -or $openIssues.Count -eq 0) {
            Write-GuardLine "$Tag OK: 미매핑 csn 에서 발견된 오픈이슈 없음(또는 응답 cSn 대조로 전부 버림)"
            return ,$found
        }

        $byCsn = @($openIssues) | Group-Object -Property Csn
        foreach ($grp in $byCsn) {
            $csnVal = $grp.Name
            $isnList = @($grp.Group | ForEach-Object { $_.Isn })
            Write-GuardLine "$Tag csn=$csnVal, 미처리 이슈 isn=[$($isnList -join ',')]"
            $found += [pscustomobject]@{ Csn = $csnVal; Isns = $isnList }

            # giip 4116/4139: 원래 이슈들에는 코멘트를 남기지 않는다(거짓 양성 코멘트 사고).
            # 게시 단위는 csn 1건이며, 운영 이슈 등록은 GISSUE_CSNGUARD_OPS_CSN 이 지정된 때만 한다.
            $opsCsn = "$($env:GISSUE_CSNGUARD_OPS_CSN)".Trim()
            $opsTitle = "[OPS] csn $csnVal 담당 배포 없음 — 이슈 $($isnList.Count)건 방치"
            if (-not $opsCsn -or $opsCsn -notmatch '^\d+$') {
                Write-GuardLine "$Tag SKIP-NOOPSCSN: csn=$csnVal 이슈 $($isnList.Count)건 — GISSUE_CSNGUARD_OPS_CSN 미지정이라 게시 없음(로그만)"
                continue
            }
            if ($SkipPosting) {
                Write-GuardLine "$Tag TEST-WOULD-POST: ops csn=$opsCsn title=$opsTitle"
                continue
            }
            try {
                $existing = & node $ListIssuesScript --csn $opsCsn --status 'PENDING,READY,IN_PROGRESS,REVIEW' `
                    --accounts-file $GiipAccountsFile --api-base $ApiBase --json 2>&1 | Out-String | ConvertFrom-Json
                $dup = @($existing | Where-Object { $_.cSn -and "$($_.cSn)" -eq $opsCsn -and $_.title -like "[[]OPS] csn $csnVal 담당 배포 없음*" })
                if ($dup.Count -gt 0) {
                    Write-GuardLine "$Tag SKIP-DUP: 운영 이슈 이미 있음(isn=$($dup[0].isn)) csn=$csnVal"
                    continue
                }
                $body = "csn $csnVal 에 열린 이슈 $($isnList.Count)건(isn=$($isnList -join ','))이 있으나 이 배포의 csn-projects.json 에 담당 매핑이 없습니다. (auto-detected: gissue_csnguard, giip 4116)"
                $regOut = & node $RegisterIssueScript --title $opsTitle --content $body --csn $opsCsn 2>&1 | Out-String
                Write-GuardLine "$Tag POSTED: ops csn=$opsCsn 운영 이슈 1건 등록. 출력: $($regOut.Trim())"
            } catch {
                Write-GuardLine "$Tag POST-FAIL: ops csn=$opsCsn 등록 실패: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-GuardLine "$Tag ERROR: $($_.Exception.Message)"
    }
    return ,$found
}
