# github-repos.ps1 — 초기 설정 시 CSN 의 GitHub repo 일괄 clone 계획·위치 저장 라이브러리 (giip 5783)
#
# 배경: 인스턴스 초기 설정에서 CSN+SK 를 받을 때, 콘솔 GitHub Actions 에 그 CSN 으로
# 등록된 repo 를 전부 내려받고 위치를 저장해, 그 CSN 의 gissue 작업이 내려받은
# repo 에서 이뤄지게 한다. 조회 API(스코프드 byAK)는 giip 5782가 정본이고,
# 이 파일은 그 결과를 받아 clone 계획과 csn-projects.json 기록을 판정하는 쪽이다.
#
# 설계 결정:
#  - 위치 저장은 csn-projects.json 의 해당 CSN 항목에 repos 배열 [{name, slug, path}].
#    workdir 자동 결정: 기존 workdir 가 유효하면 유지(운영자 설정 우선 — giip 5664 의
#    로컬 우선 원칙). 없을 때 repo 1개면 그 repo 경로, 여러 개면 워크스페이스 폴더.
#  - PAT 는 clone 시 1회만 주입한다(http.extraHeader, 그 호출에만 적용되고 저장되지
#    않음). 원격 URL 에는 남기지 않고, 로그에도 PAT 를 출력하지 않는다.
#
# 판정 정본(규칙 48): clone 계획 Get-GissueRepoClonePlan, workdir 판정
# Get-GissueRepoWorkdirVerdict 는 이 파일에만 둔다. Write-Host 규율: 값을 반환하는
# 함수의 로그는 Write-Host 로만 낸다(반환 스트림 오염 방지).
#
# 사용: run-gissue-claude.ps1 이 아니라 setup-csn-repos.ps1 이 dot-source 한다.

$script:GithubConfigsScript = Join-Path $PSScriptRoot 'get-github-configs.js'

# 원격 조회. -Transport 를 주면 그 스크립트블록이 (apiBase, sk, csn) 을 받아
# parseGithubConfigsResponse 와 같은 모양의 객체를 돌려준다(테스트용).
# 반환: @{ ok; status; configs } — 실패해도 던지지 않는다(fail-soft).
function Get-GissueGithubConfigsRemote {
    param(
        [Parameter(Mandatory)][string]$ApiBase,
        [Parameter(Mandatory)][string]$Sk,
        [Parameter(Mandatory)][string]$Csn,
        [scriptblock]$Transport
    )
    if ($Transport) {
        try { return (& $Transport $ApiBase $Sk $Csn) }
        catch { return [pscustomobject]@{ ok = $false; status = 'transport_error'; configs = @() } }
    }
    try {
        $out = & node $script:GithubConfigsScript $ApiBase $Sk $Csn 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return [pscustomobject]@{ ok = $false; status = 'lookup_error'; configs = @() } }
        return ($out | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{ ok = $false; status = 'lookup_error'; configs = @() }
    }
}

# clone 계획(순수 판정): 설정 목록 → 대상 경로. slug 중복은 1건만 남긴다.
# BaseDir 가 그 CSN 의 워크스페이스 폴더이고, 각 repo 는 BaseDir/<repo명> 에 둔다.
function Get-GissueRepoClonePlan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Configs,
        [Parameter(Mandatory)][string]$BaseDir
    )
    $seen = @{}
    $plan = @()
    foreach ($cfg in $Configs) {
        $slug = [string]$cfg.slug
        if (-not $slug -or $seen.ContainsKey($slug)) { continue }
        $seen[$slug] = $true
        $plan += [pscustomobject]@{
            name = [string]$cfg.name
            slug = $slug
            path = Join-Path $BaseDir ([string]$cfg.repo)
            pat  = [string]$cfg.pat
        }
    }
    return ,$plan
}

# workdir 판정(순수 판정): 기존 workdir 가 유효하면 KEEP, repo 1개면 SINGLE,
# 여러 개면 WORKSPACE(BaseDir), 없으면 NONE.
function Get-GissueRepoWorkdirVerdict {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Plan,
        [string]$ExistingWorkdir,
        [bool]$ExistingValid,
        [Parameter(Mandatory)][string]$BaseDir
    )
    if ($ExistingValid) { return [pscustomobject]@{ verdict = 'KEEP'; workdir = $ExistingWorkdir } }
    if ($Plan.Count -eq 1) { return [pscustomobject]@{ verdict = 'SINGLE'; workdir = [string]$Plan[0].path } }
    if ($Plan.Count -gt 1) { return [pscustomobject]@{ verdict = 'WORKSPACE'; workdir = $BaseDir } }
    return [pscustomobject]@{ verdict = 'NONE'; workdir = '' }
}

# clone 실행. 이미 .git 이 있으면 건너뛴다. PAT 는 extraHeader 로 이 호출에만 주입한다.
# -CloneRunner 를 주면 (planItem) 을 받아 성공 여부를 돌려주는 블록으로 대체한다(테스트용).
# 반환: @{ slug; result = CLONED | EXISTS | FAILED }
function Invoke-GissueRepoClone {
    param(
        [Parameter(Mandatory)]$PlanItem,
        [scriptblock]$CloneRunner
    )
    if (Test-Path (Join-Path $PlanItem.path '.git')) {
        return [pscustomobject]@{ slug = $PlanItem.slug; result = 'EXISTS' }
    }
    if ($CloneRunner) {
        $okFlag = & $CloneRunner $PlanItem
        return [pscustomobject]@{ slug = $PlanItem.slug; result = $(if ($okFlag) { 'CLONED' } else { 'FAILED' }) }
    }
    try {
        $parent = Split-Path $PlanItem.path -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $url = "https://github.com/$($PlanItem.slug).git"
        if ($PlanItem.pat) {
            $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$($PlanItem.pat)"))
            & git -c "http.https://github.com/.extraHeader=AUTHORIZATION: basic $basic" clone --quiet $url $PlanItem.path 2>$null
        } else {
            & git clone --quiet $url $PlanItem.path 2>$null
        }
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $PlanItem.path '.git'))) {
            return [pscustomobject]@{ slug = $PlanItem.slug; result = 'CLONED' }
        }
        return [pscustomobject]@{ slug = $PlanItem.slug; result = 'FAILED' }
    } catch {
        return [pscustomobject]@{ slug = $PlanItem.slug; result = 'FAILED' }
    }
}

# csn-projects.json 에 repos(+판정된 workdir)를 병합 기록한다. 다른 CSN 항목·최상위
# 키·로컬 전용 필드는 보존한다(giip 5664 의 캐시 병합과 같은 규칙, 원자적 교체).
# workdir 는 Verdict 가 KEEP/NONE 이면 건드리지 않는다. 파일이 없으면 만들지 않고 $false.
function Update-GissueCsnProjectsRepos {
    param(
        [Parameter(Mandatory)][string]$MapFilePath,
        [Parameter(Mandatory)][string]$CsnKey,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Plan,
        [Parameter(Mandatory)]$Verdict
    )
    if (-not (Test-Path $MapFilePath)) { return $false }
    try {
        $raw = [System.IO.File]::ReadAllText($MapFilePath, [System.Text.UTF8Encoding]::new($false))
        $root = $raw | ConvertFrom-Json
        if (-not $root.csn) { $root | Add-Member -NotePropertyName csn -NotePropertyValue ([pscustomobject]@{}) }
        $entry = $root.csn.$CsnKey
        if (-not $entry) {
            $entry = [pscustomobject]@{ project = ''; workdir = ''; enabled = $true }
            $root.csn | Add-Member -NotePropertyName $CsnKey -NotePropertyValue $entry
        }
        $repos = @($Plan | ForEach-Object { [pscustomobject]@{ name = $_.name; slug = $_.slug; path = $_.path } })
        if ($entry.PSObject.Properties.Name -contains 'repos') { $entry.repos = $repos }
        else { $entry | Add-Member -NotePropertyName repos -NotePropertyValue $repos }
        if ($Verdict.verdict -eq 'SINGLE' -or $Verdict.verdict -eq 'WORKSPACE') { $entry.workdir = [string]$Verdict.workdir }
        $json = $root | ConvertTo-Json -Depth 8
        $tmpPath = "$MapFilePath.tmp"
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -Force $tmpPath $MapFilePath
        return $true
    } catch {
        Write-Host "[GHSETUP] csn-projects.json 기록 실패: $($_.Exception.Message)"
        return $false
    }
}

# PAT 저장: 비밀 파일(지정 경로)에 { "<csn>": { "<slug>": "<pat>" } } 로 병합한다.
# 값이 없는 항목은 저장하지 않는다. 반환: 저장한 건수.
function Save-GissueGithubPats {
    param(
        [Parameter(Mandatory)][string]$SecretsFilePath,
        [Parameter(Mandatory)][string]$CsnKey,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Plan
    )
    $withPat = @($Plan | Where-Object { $_.pat })
    if ($withPat.Count -eq 0) { return 0 }
    try {
        $store = [pscustomobject]@{}
        if (Test-Path $SecretsFilePath) {
            $existing = [System.IO.File]::ReadAllText($SecretsFilePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            if ($existing) { $store = $existing }
        }
        $perCsn = [pscustomobject]@{}
        foreach ($item in $withPat) { $perCsn | Add-Member -NotePropertyName $item.slug -NotePropertyValue $item.pat }
        if ($store.PSObject.Properties.Name -contains $CsnKey) { $store.$CsnKey = $perCsn }
        else { $store | Add-Member -NotePropertyName $CsnKey -NotePropertyValue $perCsn }
        $dir = Split-Path $SecretsFilePath -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($SecretsFilePath, ($store | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
        return $withPat.Count
    } catch {
        Write-Host "[GHSETUP] PAT 저장 실패: $($_.Exception.Message)"
        return 0
    }
}
