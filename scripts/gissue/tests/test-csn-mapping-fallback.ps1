# test-csn-mapping-fallback.ps1 — lib/csn-mapping.ps1 회귀 테스트 (giip 5664)
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-csn-mapping-fallback.ps1
# 네트워크·실제 스케줄러를 건드리지 않는다 — 전송은 스크립트블록으로 주입하고,
# 캐시는 임시 파일로만 검증한다.
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Assert-True([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:Pass++; Write-Host "  PASS: $Name" }
    else { $script:Fail++; Write-Host "  FAIL: $Name" }
}
function Assert-Eq($Actual, $Expected, [string]$Name) {
    Assert-True ("$Actual" -eq "$Expected") "$Name (기대=$Expected 실제=$Actual)"
}

$gissueRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $gissueRoot 'lib/csn-mapping.ps1')

# 러너의 Test-GissueCsnEntryValid 와 같은 규칙의 테스트 더블 (생산 판정은 러너 것을 주입한다).
$validator = { param($k, $e)
    if ("$k" -notmatch '^\d+$') { return $false }
    $wd = "$($e.workdir)"
    if (-not $wd) { return $false }
    if ($wd -match '[<>|*?"]') { return $false }
    return $true
}
$noSk = { param($c) $null }

function RemoteRow($csn, $wd = 'C:/proj/x', $enabled = $true, $project = 'proj-x') {
    [pscustomobject]@{ Found = $true; ProjectName = $project; Workdir = $wd; Enabled = $enabled; Reason = ''; Detail = '' }
}

Write-Host '== 판정: 로컬 충분 → LOCAL (원격 미조회) =='
$script:transportCalls = 0
$transportBoom = { param($c) $script:transportCalls++; throw '조회하면 안 된다' }
$local = [pscustomobject]@{ project = 'p'; workdir = 'C:/ok'; enabled = $true }
$v = Resolve-GissueCsnMapEntry -CsnKey '47' -LocalEntry $local -LocalValid $true -Remote $null -Validator $validator
Assert-Eq $v.Action 'LOCAL' '로컬 충분이면 LOCAL'
$remote = Get-GissueCsnMappingRemote -Csn '47' -Transport { param($c) RemoteRow $c }
Assert-True ($remote.Found) '주입 전송의 found 해석'

Write-Host '== 판정: 로컬 부족 + 원격 있음 → REMOTE (병합) =='
$stale = [pscustomobject]@{ project = 'old'; workdir = '<채울것>'; enabled = $true; note = '로컬 메모'; restBranch = 'dev' }
$v = Resolve-GissueCsnMapEntry -CsnKey '70500' -LocalEntry $stale -LocalValid $false -Remote (RemoteRow '70500' 'C:/proj-sample' $true 'proj-sample') -Validator $validator
Assert-Eq $v.Action 'REMOTE' '원격으로 결정되면 REMOTE'
Assert-Eq $v.Entry.workdir 'C:/proj-sample' 'workdir 는 원격 값'
Assert-Eq $v.Entry.project 'proj-sample' 'project 는 원격 값'
Assert-Eq $v.Entry.note '로컬 메모' '로컬 전용 필드(note) 보존'
Assert-Eq $v.Entry.restBranch 'dev' '로컬 전용 필드(restBranch) 보존'
$v2 = Resolve-GissueCsnMapEntry -CsnKey '70500' -LocalEntry $null -LocalValid $false -Remote (RemoteRow '70500' 'C:/proj-sample' $false) -Validator $validator
Assert-Eq $v2.Action 'REMOTE' '로컬 항목 자체가 없어도 REMOTE'
Assert-Eq "$($v2.Entry.enabled)" 'False' '원격 enabled=false 가 그대로 반영(Phase 1 이 건너뜀)'

Write-Host '== 판정: 양쪽 다 없음/실패 → UNMAPPED (fail-soft) =='
$nf = [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'not_found'; Detail = '' }
$v = Resolve-GissueCsnMapEntry -CsnKey '99999' -LocalEntry $null -LocalValid $false -Remote $nf -Validator $validator
Assert-Eq $v.Action 'UNMAPPED' 'GIIP 에도 없으면 UNMAPPED'
Assert-Eq $v.Reason 'not_found' '사유 not_found (보고는 Phase -2.5 경로)'
$errRemote = Get-GissueCsnMappingRemote -Csn '47' -Transport { param($c) throw 'network down' }
Assert-True (-not $errRemote.Found) '전송 예외는 throw 가 아니라 Found=false 로 돌아온다'
Assert-Eq $errRemote.Reason 'error' '전송 예외 사유 error'
$v = Resolve-GissueCsnMapEntry -CsnKey '47' -LocalEntry $null -LocalValid $false -Remote $errRemote -Validator $validator
Assert-Eq $v.Action 'UNMAPPED' '조회 실패도 UNMAPPED 로 fail-soft'
$noSkRemote = Get-GissueCsnMappingRemote -Csn '47' -ApiBase 'https://example.invalid' -Sk $null -NodeExe 'node' -HelperPath 'x.js'
Assert-Eq $noSkRemote.Detail 'no_sk' 'SK 가 없으면 조회 시도 없이 error/no_sk'

Write-Host '== 판정: 원격 행 자체가 placeholder → UNMAPPED/remote_invalid =='
$v = Resolve-GissueCsnMapEntry -CsnKey '47' -LocalEntry $null -LocalValid $false -Remote (RemoteRow '47' '<미기입>') -Validator $validator
Assert-Eq $v.Action 'UNMAPPED' '원격 workdir 가 placeholder 면 채택하지 않는다'
Assert-Eq $v.Reason 'remote_invalid' '사유 remote_invalid'

Write-Host '== 캐시 병합 기록 =='
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("csnmap-test-$PID")
[void](New-Item -ItemType Directory -Path $tmpDir -Force)
$mapFile = Join-Path $tmpDir 'csn-projects.json'
$seed = [ordered]@{
    heartbeat = @{ lssn = '1' }
    csn = [ordered]@{
        '47' = @{ project = 'giipprj'; workdir = 'C:/giipprj'; enabled = $true }
        '33' = @{ project = 'lowy'; workdir = 'C:/lowy'; enabled = $true; note = '유지' }
    }
}
[System.IO.File]::WriteAllText($mapFile, ($seed | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$entry = Merge-GissueCsnEntryFromRemote -LocalEntry $null -Remote (RemoteRow '70500' 'C:/proj-sample' $true 'proj-sample')
Assert-True (Update-GissueCsnProjectsCache -MapFilePath $mapFile -CsnKey '70500' -Entry $entry) '신규 CSN 캐시 기록 성공'
$after = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Eq $after.csn.'70500'.workdir 'C:/proj-sample' '신규 항목이 캐시에 들어감'
Assert-Eq $after.csn.'33'.note '유지' '다른 CSN 항목 보존'
Assert-Eq $after.csn.'47'.workdir 'C:/giipprj' '기존 항목 보존'
Assert-True ($null -ne $after.heartbeat) '최상위 키(heartbeat) 보존'
$entry2 = Merge-GissueCsnEntryFromRemote -LocalEntry $after.csn.'33' -Remote (RemoteRow '33' 'C:/lowy2' $true 'lowy')
Assert-True (Update-GissueCsnProjectsCache -MapFilePath $mapFile -CsnKey '33' -Entry $entry2) '기존 CSN 갱신 성공'
$after2 = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Eq $after2.csn.'33'.workdir 'C:/lowy2' '기존 항목 workdir 갱신'
Assert-Eq $after2.csn.'33'.note '유지' '갱신 시에도 로컬 전용 필드 보존'
Assert-True (-not (Update-GissueCsnProjectsCache -MapFilePath (Join-Path $tmpDir 'nope.json') -CsnKey '1' -Entry $entry)) '파일이 없으면 만들지 않고 false'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmpDir 'nope.json'))) '없는 파일이 생기지 않음'

Write-Host '== 오케스트레이션: 맵 전체 패스 =='
$mapRoot = [pscustomobject]@{ csn = [pscustomobject]@{
    '47' = [pscustomobject]@{ project = 'giipprj'; workdir = 'C:/giipprj'; enabled = $true }
    '70500' = [pscustomobject]@{ project = 'x'; workdir = ''; enabled = $true }
} }
$transport = { param($c)
    if ($c -eq '70500') { return (RemoteRow $c 'C:/proj-sample' $true 'proj-sample') }
    if ($c -eq '99999') { return [pscustomobject]@{ Found = $false; ProjectName = ''; Workdir = ''; Enabled = $false; Reason = 'not_found'; Detail = '' } }
    throw "예상 밖 csn $c"
}
$results = Resolve-GissueCsnMappings -CsnKeys @('47', '70500', '99999') -MapRoot $mapRoot `
    -Validator $validator -SkResolver $noSk -Transport $transport -MapFilePath $mapFile -WriteCache
$byCsn = @{}; foreach ($r in $results) { $byCsn[$r.Csn] = $r.Action }
Assert-Eq $byCsn['47'] 'LOCAL' '충분한 CSN 은 LOCAL (조회 안 함)'
Assert-Eq $byCsn['70500'] 'REMOTE' '부족한 CSN 은 REMOTE'
Assert-Eq $byCsn['99999'] 'UNMAPPED' '없는 CSN 은 UNMAPPED'
Assert-Eq $mapRoot.csn.'70500'.workdir 'C:/proj-sample' 'MapRoot 에 원격 항목 반영'
$cached = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Eq $cached.csn.'70500'.workdir 'C:/proj-sample' '캐시 파일에도 반영'
$resultsDry = Resolve-GissueCsnMappings -CsnKeys @('88888') -MapRoot $mapRoot `
    -Validator $validator -SkResolver $noSk -Transport { param($c) RemoteRow $c 'C:/dry' } -MapFilePath $mapFile
$cached2 = Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($null -eq $cached2.csn.'88888') 'WriteCache 없으면(DryRun) 파일에 쓰지 않음'

Write-Host '== 후보 CSN 수집 (Phase -2.5 와 같은 두 출처) =='
$pcFile = Join-Path $tmpDir 'project-csn.json'
[System.IO.File]::WriteAllText($pcFile, '{"projA": {"csn": 70500}, "projB": "33", "bad": {"x": 1}}', (New-Object System.Text.UTF8Encoding($false)))
$accFile = Join-Path $tmpDir 'giip-accounts.json'
[System.IO.File]::WriteAllText($accFile, '{"channels": {"ch1": {"csn": 47, "sk": "x"}}, "default": {"csn": 70424, "sk": "y"}}', (New-Object System.Text.UTF8Encoding($false)))
$cands = Get-GissueCandidateCsnList -ProjectCsnFile $pcFile -GiipAccountsFile $accFile
Assert-True (($cands -contains '70500') -and ($cands -contains '33') -and ($cands -contains '47') -and ($cands -contains '70424')) '두 출처의 합집합 + default 채널 포함'
Assert-True ($cands.Count -eq 4) '숫자 아닌 후보는 제외'

Write-Host '== 소스 커플링 =='
$libText = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'lib/csn-mapping.ps1')
Assert-True ($libText -notmatch 'function Test-GissueCsnEntryValid') 'lib 는 충분 여부 판정을 복제하지 않는다(러너 판정을 주입)'
$runner = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'run-gissue-claude.ps1')
Assert-True ($runner -match [regex]::Escape("lib/csn-mapping.ps1")) '러너가 lib 를 dot-source 한다'
Assert-True (([regex]::Matches($runner, 'Resolve-GissueCsnMappings')).Count -eq 1) '러너 배선 1곳(Phase -3 폴백 패스만)'
# [giip 4116, 2026-11-23] Phase -2.5 사전 패스는 **의도적으로 제거**했다.
#   그 패스는 로컬 맵에 **아예 없는** 후보 csn 을 정본으로 결정해 로컬 맵에 병합(채택)했다.
#   정본 배열 응답을 읽도록 고치면(giip 4116) 그 채택이 **처음으로 실제로 동작**하게 되고,
#   그 결과 이 배포(CSN 70424)가 csn 47/70335/70428 같은 **타 CSN 을 통째로 떠안게** 된다
#   = CSN 경계 위반. 정본 판정은 이제 읽기 전용 가드(lib/unmapped-csn-guard.ps1)가 하므로,
#   채택은 Phase -3(1-b2)의 "이미 이 배포가 주장한 csn" 채우기만 남긴다.
Assert-True ($runner -notmatch 'unmappedCandidates') '사전 패스(로컬 맵에 없는 csn 을 정본으로 채택) 코드는 제거됨 — CSN 경계 유지'
Assert-True ($runner -match [regex]::Escape('lib/unmapped-csn-guard.ps1')) '러너가 미매핑 가드 lib 를 dot-source 한다'
Assert-True ($runner -match [regex]::Escape('Invoke-GissueUnmappedCsnGuard')) '러너가 lib 가드 오케스트레이터를 호출한다'

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
