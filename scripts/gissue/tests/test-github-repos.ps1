# test-github-repos.ps1 — lib/github-repos.ps1 의 계획·판정·기록 회귀 테스트
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-github-repos.ps1
# 실제 clone·네트워크는 하지 않는다 — CloneRunner 주입으로 대체한다.
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Assert-True([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:Pass++; Write-Host "  PASS: $Name" }
    else { $script:Fail++; Write-Host "  FAIL: $Name" }
}
function Assert-Eq($Actual, $Expected, [string]$Name) {
    if ([string]$Actual -eq [string]$Expected) { $script:Pass++; Write-Host "  PASS: $Name" }
    else { $script:Fail++; Write-Host "  FAIL: $Name (기대=$Expected 실제=$Actual)" }
}

$gissueRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $gissueRoot 'lib/github-repos.ps1')

$base = Join-Path ([System.IO.Path]::GetTempPath()) 'ghsetup-test-base'
function Cfg($name, $owner, $repo, $pat) { [pscustomobject]@{ name = $name; owner = $owner; repo = $repo; slug = "$owner/$repo"; pat = $pat } }

Write-Host '== clone 계획 =='
$plan = Get-GissueRepoClonePlan -Configs @((Cfg 'a' 'LowyShin' 'giipfaw' 'P1'), (Cfg 'b' 'SHINSEMA' 'giipv3' 'P2'), (Cfg 'dup' 'LowyShin' 'giipfaw' 'P1')) -BaseDir $base
Assert-Eq $plan.Count 2 'slug 중복은 1건으로'
Assert-Eq $plan[0].path (Join-Path $base 'giipfaw') '경로는 BaseDir/<repo명>'

Write-Host '== workdir 판정 =='
$v = Get-GissueRepoWorkdirVerdict -Plan $plan -ExistingWorkdir 'C:/already' -ExistingValid $true -BaseDir $base
Assert-Eq $v.verdict 'KEEP' '기존 workdir 가 유효하면 유지'
$v = Get-GissueRepoWorkdirVerdict -Plan @($plan[0]) -ExistingWorkdir '' -ExistingValid $false -BaseDir $base
Assert-Eq $v.verdict 'SINGLE' 'repo 1개면 SINGLE'
Assert-Eq $v.workdir $plan[0].path 'SINGLE 의 workdir 는 그 repo'
$v = Get-GissueRepoWorkdirVerdict -Plan $plan -ExistingWorkdir '' -ExistingValid $false -BaseDir $base
Assert-Eq $v.verdict 'WORKSPACE' 'repo 여러 개면 WORKSPACE'
Assert-Eq $v.workdir $base 'WORKSPACE 의 workdir 는 기준 폴더'
$v = Get-GissueRepoWorkdirVerdict -Plan @() -ExistingWorkdir '' -ExistingValid $false -BaseDir $base
Assert-Eq $v.verdict 'NONE' 'repo 없으면 NONE'

Write-Host '== clone 실행(주입) =='
$r = Invoke-GissueRepoClone -PlanItem $plan[0] -CloneRunner { param($i) $true }
Assert-Eq $r.result 'CLONED' '러너 성공이면 CLONED'
$r = Invoke-GissueRepoClone -PlanItem $plan[0] -CloneRunner { param($i) $false }
Assert-Eq $r.result 'FAILED' '러너 실패면 FAILED'

Write-Host '== csn-projects.json 병합 기록 =='
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ghsetup-map-' + [guid]::NewGuid().ToString('N') + '.json')
$seed = [pscustomobject]@{
    repoBaseDir = 'D:/repos'
    csn = [pscustomobject]@{
        '47' = [pscustomobject]@{ project = 'lw-giip'; workdir = ''; enabled = $true; note = 'keep-me' }
        '33' = [pscustomobject]@{ project = 'other'; workdir = 'C:/other'; enabled = $true }
    }
}
[System.IO.File]::WriteAllText($tmp, ($seed | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
$v = Get-GissueRepoWorkdirVerdict -Plan $plan -ExistingWorkdir '' -ExistingValid $false -BaseDir $base
Assert-True (Update-GissueCsnProjectsRepos -MapFilePath $tmp -CsnKey '47' -Plan $plan -Verdict $v) '기록 성공'
$after = [System.IO.File]::ReadAllText($tmp, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
Assert-Eq $after.csn.'47'.repos.Count 2 'repos 2건 기록'
Assert-Eq $after.csn.'47'.workdir $base 'WORKSPACE workdir 기록'
Assert-Eq $after.csn.'47'.note 'keep-me' '로컬 전용 필드(note) 보존'
Assert-Eq $after.csn.'33'.workdir 'C:/other' '다른 CSN 항목 보존'
Assert-Eq $after.repoBaseDir 'D:/repos' '최상위 키 보존'
Assert-True (-not (Update-GissueCsnProjectsRepos -MapFilePath ($tmp + '.missing') -CsnKey '47' -Plan $plan -Verdict $v)) '파일이 없으면 만들지 않고 false'
Remove-Item $tmp -Force

Write-Host '== PAT 저장 =='
$secFile = Join-Path ([System.IO.Path]::GetTempPath()) ('ghsetup-sec-' + [guid]::NewGuid().ToString('N') + '.json')
$saved = Save-GissueGithubPats -SecretsFilePath $secFile -CsnKey '47' -Plan $plan
Assert-Eq $saved 2 'PAT 있는 항목 2건 저장'
$store = [System.IO.File]::ReadAllText($secFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
Assert-Eq $store.'47'.'LowyShin/giipfaw' 'P1' 'slug 키로 저장'
$saved0 = Save-GissueGithubPats -SecretsFilePath $secFile -CsnKey '99' -Plan @([pscustomobject]@{ name = 'x'; slug = 'a/b'; path = 'p'; pat = '' })
Assert-Eq $saved0 0 'PAT 없는 항목은 저장하지 않음'
Remove-Item $secFile -Force

Write-Host '== 소스 커플링 =='
$libSrc = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/github-repos.ps1')
Assert-True ($libSrc -match 'extraHeader') 'PAT 는 extraHeader 로 1회 주입(원격 URL에 남기지 않음)'
$setupSrc = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'setup-csn-repos.ps1')
Assert-True ($setupSrc -match 'Get-GissueGithubConfigsRemote') '설정 진입점이 조회를 경유한다'
Assert-True ($setupSrc -notmatch 'Write-Host.*\$(item|cfg)\.pat(?![a-zA-Z])') '설정 진입점이 PAT 를 로그에 쓰지 않는다'

Write-Host ''
Write-Host "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
