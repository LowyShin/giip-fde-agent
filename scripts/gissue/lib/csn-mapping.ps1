# csn-mapping.ps1 — 로컬 매핑 부족 시 GIIP 프로젝트 매핑 조회 폴백의 정본 (giip 5664)
#
# 배경: 러너는 이슈의 작업 환경을 호스트 로컬 csn-projects.json 에서만 결정해 왔다.
#   항목이 없거나 placeholder 면 GIIP 쪽 정본(tGissueCsnMapping, giip #2363)을 확인할
#   길이 없어, 낡은 로컬 매핑 그대로 진행하거나(빈 폴더에서 세션 시작 — #5524 부류)
#   조용히 건너뛰었다. DB→JSON 동기화는 별도 결함으로 막혀 있고 동기화 스크립트는
#   DB 직접 접속 전제라 이 레포(DB 직접 접근 없음)에 이식 대상이 아니다 — 그래서
#   동기화 복구가 아니라 **필요한 순간에 필요한 CSN 만 조회하는 폴백**으로 대체한다.
#
# 동작 원칙:
#   1. 로컬 항목이 충분하면(Test-GissueCsnEntryValid 통과) 조회 자체를 하지 않는다 — 현행 동작 그대로.
#   2. 부족하면 그 CSN 의 SK 로 스코프드 읽기 엔드포인트를 조회한다(계약: lib/get-csn-mapping.js 헤더).
#      조회 성공 시 항목을 결정하고 로컬 캐시(csn-projects.json)에 병합 기록한다 — 다음 실행부터는
#      로컬로 동작하는 점진적 자기 복구다. 병합은 다른 CSN 항목·최상위 키를 보존하고, 로컬에만 있는
#      선택 필드(restBranch·note 등)는 지우지 않는다.
#   3. GIIP 에도 없거나 조회가 실패하면 추측으로 진행하지 않는다 — UNMAPPED 로 남기고, 보고는 기존
#      Phase -2.5 미매핑 감시 경로가 맡는다. 엔드포인트 미배포·네트워크 실패도 전부 fail-soft
#      (로그만 남기고 현행 동작 유지)다.
#   4. -DryRun 성격의 실행에서는 캐시를 쓰지 않는다(판정과 로그만).
#
# 판정의 단일 출처(규칙 48): 항목 충분 여부는 러너의 Test-GissueCsnEntryValid 를 그대로
#   주입받아(-Validator) 쓴다. 이 파일은 그 판정을 복제하지 않는다. LOCAL/REMOTE/UNMAPPED
#   결정은 Resolve-GissueCsnMapEntry 한 곳에서만 한다.
#
# ⚠ 반환값을 돌려주는 함수 안에서 로그성 문자열을 만들 때는 Write-Host 를 쓸 것.
#   Write-Output 은 반환 스트림을 오염시켜 "조회 실패가 성공으로 보이는" 사고가 된다
#   (lib/kvs-report.ps1 과 같은 이유로 같은 규율을 적용한다).

# 원격 조회 1건. -Transport 를 주면 그 스크립트블록을 전송으로 쓴다(테스트용).
# 반환: [pscustomobject]@{ Found=[bool]; ProjectName; Workdir; Enabled; Reason; Detail }
function Get-GissueCsnMappingRemote {
    param(
        [Parameter(Mandatory = $true)][string]$Csn,
        [string]$ApiBase,
        [string]$Sk,
        [string]$NodeExe,
        [string]$HelperPath,
        [scriptblock]$Transport
    )
    if ($Transport) {
        try {
            $r = & $Transport $Csn
            if ($null -eq $r) { return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'error'; Detail = 'transport_null' } }
            return $r
        } catch {
            return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'error'; Detail = "$($_.Exception.Message)" }
        }
    }
    if (-not $Sk) {
        return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'error'; Detail = 'no_sk' }
    }
    try {
        $node = if ($NodeExe) { $NodeExe } else { 'node' }
        $raw = & $node $HelperPath $ApiBase $Sk $Csn 2>$null | Out-String
        $j = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($j.found) {
            return [pscustomobject]@{ Found = $true; ProjectName = "$($j.projectName)"; Workdir = "$($j.workdir)"; Enabled = [bool]$j.enabled; Reason = ''; Detail = '' }
        }
        return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = "$($j.reason)"; Detail = "$($j.detail)" }
    } catch {
        return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'error'; Detail = "$($_.Exception.Message)" }
    }
}

# 원격 행 + 기존 로컬 항목 → 최종 csn-projects 항목(순수 함수).
# 원격이 채우는 필드: project·workdir·enabled. 로컬에만 있는 선택 필드는 보존한다.
function Merge-GissueCsnEntryFromRemote {
    param(
        $LocalEntry,
        [Parameter(Mandatory = $true)]$Remote
    )
    $merged = [ordered]@{}
    if ($LocalEntry) {
        foreach ($p in $LocalEntry.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    }
    if ($Remote.ProjectName) { $merged['project'] = "$($Remote.ProjectName)" }
    $merged['workdir'] = "$($Remote.Workdir)"
    $merged['enabled'] = [bool]$Remote.Enabled
    return [pscustomobject]$merged
}

# LOCAL/REMOTE/UNMAPPED 판정의 단일 출처(순수 함수).
#   -LocalValid : 러너의 Test-GissueCsnEntryValid 결과(로컬 항목 기준)
#   -Remote     : Get-GissueCsnMappingRemote 결과 (로컬이 충분하면 $null 로 와도 된다)
#   -Validator  : 병합 항목의 충분 여부를 다시 판정하는 스크립트블록 { param($csnKey, $entry) ... }
# 반환: @{ Action = 'LOCAL'|'REMOTE'|'UNMAPPED'; Entry = <최종 항목 또는 $null>; Reason = <코드> }
function Resolve-GissueCsnMapEntry {
    param(
        [Parameter(Mandatory = $true)][string]$CsnKey,
        $LocalEntry,
        [bool]$LocalValid,
        $Remote,
        [scriptblock]$Validator
    )
    if ($LocalValid) {
        return @{ Action = 'LOCAL'; Entry = $LocalEntry; Reason = '' }
    }
    if ($Remote -and $Remote.Found) {
        $merged = Merge-GissueCsnEntryFromRemote -LocalEntry $LocalEntry -Remote $Remote
        if ($Validator) {
            $ok = & $Validator $CsnKey $merged
            if (-not $ok) {
                return @{ Action = 'UNMAPPED'; Entry = $null; Reason = 'remote_invalid' }
            }
        }
        return @{ Action = 'REMOTE'; Entry = $merged; Reason = '' }
    }
    $reason = if ($Remote) { "$($Remote.Reason)" } else { 'not_looked_up' }
    if (-not $reason) { $reason = 'not_found' }
    return @{ Action = 'UNMAPPED'; Entry = $null; Reason = $reason }
}

# 캐시(csn-projects.json)에 항목 1건을 병합 기록한다. 다른 항목·최상위 키 보존,
# 임시 파일에 써서 교체(이동)하므로 중간에 죽어도 원본이 깨지지 않는다.
# 파일 자체가 없으면 만들지 않고 $false (신규 클론의 파일 부재는 Phase -3 의 별도 안내 경로다).
function Update-GissueCsnProjectsCache {
    param(
        [Parameter(Mandatory = $true)][string]$MapFilePath,
        [Parameter(Mandatory = $true)][string]$CsnKey,
        [Parameter(Mandatory = $true)]$Entry
    )
    try {
        if (-not (Test-Path -LiteralPath $MapFilePath)) { return $false }
        $root = Get-Content -LiteralPath $MapFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $root.csn) { $root | Add-Member -NotePropertyName 'csn' -NotePropertyValue ([pscustomobject]@{}) }
        if ($root.csn.PSObject.Properties.Name -contains $CsnKey) {
            $root.csn.$CsnKey = $Entry
        } else {
            $root.csn | Add-Member -NotePropertyName $CsnKey -NotePropertyValue $Entry
        }
        $tmp = "$MapFilePath.tmp-$PID"
        $json = $root | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $MapFilePath -Force
        return $true
    } catch {
        Write-Host "[CSN-MAP] 캐시 기록 실패 csn=${CsnKey}: $($_.Exception.Message)"
        return $false
    }
}

# 후보 CSN 수집 — Phase -2.5 미매핑 감시와 같은 두 출처(slack-bot/project-csn.json +
# giip-accounts.json 채널)를 본다. 감시 쪽 수집과 출처가 갈라지면 한쪽만 새 CSN 을
# 보게 되므로, 출처를 바꾸면 양쪽을 같이 고칠 것.
function Get-GissueCandidateCsnList {
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
            if ($acc.default -and $acc.default.csn) { $candidates["$($acc.default.csn)"] = $true }
        }
    } catch {}
    return @($candidates.Keys | Sort-Object)
}

# 오케스트레이션: 대상 CSN 목록 각각에 대해 (로컬 판정 → 필요 시 원격 조회 → 판정)을 돌리고,
# REMOTE 인 항목은 MapRoot 에 반영하고(-ApplyTo 에 맵 객체를 주면) 캐시에 기록한다(-WriteCache 시).
# 반환: 결과 객체 배열 @{ Csn; Action; Reason } — 호출부(러너)가 로그·집계에 쓴다.
function Resolve-GissueCsnMappings {
    param(
        [Parameter(Mandatory = $true)][string[]]$CsnKeys,
        [Parameter(Mandatory = $true)]$MapRoot,
        [Parameter(Mandatory = $true)][scriptblock]$Validator,
        [Parameter(Mandatory = $true)][scriptblock]$SkResolver,
        [string]$ApiBase,
        [string]$NodeExe,
        [string]$HelperPath,
        [scriptblock]$Transport,
        [string]$MapFilePath,
        [switch]$WriteCache
    )
    $results = @()
    foreach ($csnKey in $CsnKeys) {
        $local = $null
        if ($MapRoot.csn -and ($MapRoot.csn.PSObject.Properties.Name -contains $csnKey)) {
            $local = $MapRoot.csn.$csnKey
        }
        $localValid = [bool](& $Validator $csnKey $local)
        if ($localValid) {
            $results += @{ Csn = $csnKey; Action = 'LOCAL'; Reason = '' }
            continue
        }
        $sk = & $SkResolver $csnKey
        $remote = Get-GissueCsnMappingRemote -Csn $csnKey -ApiBase $ApiBase -Sk $sk `
            -NodeExe $NodeExe -HelperPath $HelperPath -Transport $Transport
        $verdict = Resolve-GissueCsnMapEntry -CsnKey $csnKey -LocalEntry $local `
            -LocalValid $false -Remote $remote -Validator $Validator
        if ($verdict.Action -eq 'REMOTE') {
            if ($MapRoot.csn -and ($MapRoot.csn.PSObject.Properties.Name -contains $csnKey)) {
                $MapRoot.csn.$csnKey = $verdict.Entry
            } elseif ($MapRoot.csn) {
                $MapRoot.csn | Add-Member -NotePropertyName $csnKey -NotePropertyValue $verdict.Entry
            }
            if ($WriteCache -and $MapFilePath) {
                [void](Update-GissueCsnProjectsCache -MapFilePath $MapFilePath -CsnKey $csnKey -Entry $verdict.Entry)
            }
            Write-Host "[CSN-MAP] csn=$csnKey 로컬 항목 부족 → GIIP 매핑으로 결정 (project=$($verdict.Entry.project), workdir=$($verdict.Entry.workdir), enabled=$($verdict.Entry.enabled))"
        } else {
            $detail = if ($remote) { "$($remote.Detail)" } else { '' }
            Write-Host "[CSN-MAP] csn=$csnKey GIIP 매핑으로도 결정 불가 (reason=$($verdict.Reason) $detail) — 미매핑 경로로 남긴다"
        }
        $results += @{ Csn = $csnKey; Action = $verdict.Action; Reason = $verdict.Reason }
    }
    return ,$results
}
