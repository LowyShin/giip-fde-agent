# setup-csn-repos.ps1 — 인스턴스 초기 설정: CSN 의 GitHub repo 일괄 clone + 위치 저장 (giip 5783)
#
# 흐름: CSN 지정 → 그 CSN 의 SK 확보(giip-accounts.json 또는 -Sk) → 콘솔 GitHub
# Actions 설정을 스코프드 API 로 조회 → 전부 clone → csn-projects.json 에 repos 와
# workdir 를 기록 → PAT 는 비밀 파일에 저장.
#
# 사용:
#   pwsh -NoProfile -File scripts/gissue/setup-csn-repos.ps1 -Csn 70424
#   pwsh -NoProfile -File scripts/gissue/setup-csn-repos.ps1 -Csn 70424 -BaseDir D:\work\repos
#   pwsh -NoProfile -File scripts/gissue/setup-csn-repos.ps1 -Csn 70424 -DryRun
#
# 종료 코드: 인자 오류만 2. 조회 실패·설정 없음은 기존 설정 절차를 막지 않도록
# [GHSETUP] 로그를 남기고 0 으로 끝낸다(fail-soft). PAT 값은 어떤 로그에도 없다.
param(
    [Parameter(Mandatory)][string]$Csn,
    [string]$Sk,
    [string]$ApiBase = 'https://giipfaw.azurewebsites.net/api',
    [string]$MapFile,
    [string]$BaseDir,
    [string]$SecretsFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'lib/github-repos.ps1')

if (-not $MapFile) { $MapFile = Join-Path $Root 'csn-projects.json' }
if (-not $SecretsFile) { $SecretsFile = Join-Path $Root '.secrets/github-pats.json' }

# 1) SK 확보: -Sk > giip-accounts.json(resolve-sk.js)
if (-not $Sk) {
    $accountsFile = Join-Path $Root '..\..\slack-bot\.secrets\giip-accounts.json'
    if (Test-Path $accountsFile) {
        $resolved = & node (Join-Path $Root 'lib/resolve-sk.js') $accountsFile $Csn 2>$null
        if ($LASTEXITCODE -eq 0 -and $resolved) { $Sk = [string]$resolved }
    }
}
if (-not $Sk) {
    Write-Host "[GHSETUP] CSN $Csn 의 SK 를 찾지 못했습니다 — giip-accounts.json 에 없거나 -Sk 미지정. repo 설정을 건너뜁니다."
    exit 0
}

# 2) 기준 폴더: -BaseDir > csn-projects.json 의 repoBaseDir > ~/giip-repos/<csn>
$mapRoot = $null
if (Test-Path $MapFile) {
    try { $mapRoot = [System.IO.File]::ReadAllText($MapFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json } catch { $mapRoot = $null }
}
if (-not $BaseDir) {
    if ($mapRoot -and $mapRoot.repoBaseDir) { $BaseDir = Join-Path ([string]$mapRoot.repoBaseDir) $Csn }
    else { $BaseDir = Join-Path $HOME "giip-repos/$Csn" }
}

# 3) 조회 (fail-soft)
$remote = Get-GissueGithubConfigsRemote -ApiBase $ApiBase -Sk $Sk -Csn $Csn
if (-not $remote.ok) {
    Write-Host "[GHSETUP] CSN $Csn GitHub 설정 조회 실패(status=$($remote.status)) — API 미배포이거나 스코프 불일치. 기존 설정 절차를 계속하세요."
    exit 0
}
if ($remote.status -eq 'not_found' -or @($remote.configs).Count -eq 0) {
    Write-Host "[GHSETUP] CSN $Csn 에 등록된 GitHub Actions 설정이 없습니다 — clone 할 repo 가 없습니다."
    exit 0
}
Write-Host "[GHSETUP] CSN $Csn GitHub 설정 $(@($remote.configs).Count)건 확인 — base=$BaseDir"

# 4) 계획 + workdir 판정
$plan = Get-GissueRepoClonePlan -Configs @($remote.configs) -BaseDir $BaseDir
$existingEntry = $null; $existingValid = $false
if ($mapRoot -and $mapRoot.csn -and $mapRoot.csn.$Csn) {
    $existingEntry = $mapRoot.csn.$Csn
    if ($existingEntry.workdir -and (Test-Path ([string]$existingEntry.workdir))) { $existingValid = $true }
}
$verdict = Get-GissueRepoWorkdirVerdict -Plan $plan -ExistingWorkdir $(if ($existingEntry) { [string]$existingEntry.workdir } else { '' }) -ExistingValid $existingValid -BaseDir $BaseDir
Write-Host "[GHSETUP] workdir 판정: $($verdict.verdict) $(if ($verdict.workdir) { "→ $($verdict.workdir)" })"

# 5) clone + 기록 (DryRun 은 계획만)
foreach ($item in $plan) {
    if ($DryRun) { Write-Host "[GHSETUP] (DryRun) clone 예정: $($item.slug) → $($item.path)"; continue }
    $r = Invoke-GissueRepoClone -PlanItem $item
    Write-Host "[GHSETUP] clone $($r.slug): $($r.result)"
}
if (-not $DryRun) {
    $saved = Save-GissueGithubPats -SecretsFilePath $SecretsFile -CsnKey $Csn -Plan $plan
    if ($saved -gt 0) { Write-Host "[GHSETUP] PAT $saved 건을 비밀 파일에 저장했습니다: $SecretsFile" }
    $recorded = Update-GissueCsnProjectsRepos -MapFilePath $MapFile -CsnKey $Csn -Plan $plan -Verdict $verdict
    if ($recorded) { Write-Host "[GHSETUP] csn-projects.json 에 repos $($plan.Count)건과 workdir 판정을 기록했습니다." }
    else { Write-Host "[GHSETUP] csn-projects.json 이 없어 기록하지 못했습니다 — 파일을 먼저 만들거나 -MapFile 로 지정하세요." }
}
exit 0
