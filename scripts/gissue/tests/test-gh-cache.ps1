# test-gh-cache.ps1 — 머지 집합 디스크 캐시(lib/gh-cache.ps1) 회귀 테스트
#
# 왜 필요한가:
#   머지판정(Get-GissueMergedBranchSet)은 레포마다 `gh pr list --state merged --limit 1000`
#   을 부르는데, 프로세스 내 캐시만 있어 매시 러너·CSN별 잡·스윕이 같은 레포를 각자 다시
#   조회했다. GitHub GraphQL 예산(계정 공유)이 소진되면 조회가 전부 실패해 머지판정이
#   fail-closed 로 닫히고 MANUAL-REVIEW 가 폭증한다. 디스크 캐시는 **성공한 조회만**
#   프로세스 너머로 공유해 중복 호출을 줄인다.
#
# 고정하는 것:
#   A. write→read 라운드트립 — 같은 브랜치 집합이 돌아오고 파일명·형식이 사양대로다.
#   B. TTL — fetchedAt 가 TTL 보다 오래면 $null. -MaxAgeMinutes 와 env 재정의가 통한다.
#   C. 손상된 JSON — 예외 없이 $null (호출자는 gh 재조회로 떨어진다).
#   D. Clear — 파일이 사라지고 이후 read 는 $null.
#   E. 통합 — 임시 git 레포(가짜 origin)에 캐시를 미리 심으면 Get-GissueMergedBranchSet 가
#      gh 를 **부르지 않고** Ok=$true 로 그 집합을 돌려준다([GH-CACHE] HIT 로그 포함).
#      실패를 캐시하지 않는 계약상, E 의 외부 호출 래퍼(Invoke-GissueExternalCall)는
#      gh 호출 시 즉시 기록하고 예외를 던지게 스텁한다 — 캐시 히트 경로가 실제로 gh 를
#      건너뛰는지 이걸로 증명한다. 예전에는 `function gh` 를 스텁했으나, 외부 호출이
#      lib/bounded-process.ps1 경유(Start-Process)로 바뀌면서 PowerShell 함수 스텁은
#      우회되므로 래퍼를 스텁하는 방식으로 바꿨다(2026-11-25 gh-call-timeout).
#      단, 캐시 히트 경로도 owner/repo 를 알아내기 위해 `git remote get-url origin`
#      1회는 한다(로컬 호출, 타임아웃付き) — 그래서 스텁은 git 호출은 실제 헬퍼로
#      위임하고 gh 호출만 막는다. E-4 는 gh 미호출, E-5 는 외부 호출이 그 1회뿐임을 고정한다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gh-cache.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리([System.IO.Path]::GetTempPath() 아래)에만 캐시와 레포를 만든다 —
# 살아있는 체크아웃이나 호스트 로그 디렉터리를 절대 건드리지 않는다. 네트워크 불필요.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$GhCacheLib = Join-Path $PSScriptRoot '..\lib\gh-cache.ps1'
$GhCacheLib = (Resolve-Path -LiteralPath $GhCacheLib).Path
. $GhCacheLib
$SafetyLib = Join-Path $PSScriptRoot '..\worktree-safety.ps1'
$SafetyLib = (Resolve-Path -LiteralPath $SafetyLib).Path
. $SafetyLib

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Eq($actual, $expected, $name) {
    Assert-True ($actual -eq $expected) $name "expected [$expected] got [$actual]"
}
function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-gh-cache-test-$PID")
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$cacheDir = Join-Path $tempRoot 'cache'

$script:SavedCacheDir = $env:GISSUE_GH_CACHE_DIR
$script:SavedTtl = $env:GISSUE_GH_CACHE_TTL_MIN
$env:GISSUE_GH_CACHE_DIR = $cacheDir
$env:GISSUE_GH_CACHE_TTL_MIN = $null

$ownerRepo = 'someowner/somerepo'
try {
    # ──────────────────────────────────────────────────────────────────────────
    Write-Output 'A. write→read 라운드트립'
    Write-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo -Branches @('feat/a', 'feat/b', 'fix/c')
    $cacheFile = Join-Path $cacheDir 'someowner__somerepo.merged.json'
    Assert-True (Test-Path -LiteralPath $cacheFile) 'A-1 파일명이 <owner>__<repo>.merged.json 이다' $cacheFile
    $rawObj = ([System.IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json)
    Assert-Eq $rawObj.ownerRepo $ownerRepo 'A-2 JSON ownerRepo 필드'
    Assert-True ([bool]$rawObj.fetchedAt) 'A-3 JSON fetchedAt 필드가 있다'
    $read1 = Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo
    Assert-True ($null -ne $read1) 'A-4 방금 쓴 캐시가 읽힌다'
    Assert-Eq $read1.Branches.Count 3 'A-5 브랜치 3개가 돌아온다'
    Assert-True ($read1.Branches.Contains('feat/a') -and $read1.Branches.Contains('feat/b') -and $read1.Branches.Contains('fix/c')) 'A-6 집합 내용이 일치한다'
    $readMissing = Read-GissueMergedBranchDiskCache -OwnerRepo 'no/suchrepo'
    Assert-True ($null -eq $readMissing) 'A-7 없는 레포는 $null'

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'B. TTL 만료'
    $staleObj = [pscustomobject]@{
        ownerRepo = $ownerRepo
        fetchedAt = (Get-Date).ToUniversalTime().AddHours(-3).ToString('o')
        branches  = @('feat/old')
    }
    [System.IO.File]::WriteAllText($cacheFile, ($staleObj | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    $readStale = Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo
    Assert-True ($null -eq $readStale) 'B-1 3시간 전 캐시는 기본 TTL(50분)에서 $null'
    $readStaleWide = Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo -MaxAgeMinutes 10000
    Assert-True ($null -ne $readStaleWide -and $readStaleWide.Branches.Contains('feat/old')) 'B-2 -MaxAgeMinutes 를 넓히면 읽힌다'
    $env:GISSUE_GH_CACHE_TTL_MIN = '200'
    $readStaleEnv = Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo
    Assert-True ($null -ne $readStaleEnv) 'B-3 env TTL 200분 재정의가 통한다(180분 경과분 히트)'
    $env:GISSUE_GH_CACHE_TTL_MIN = $null

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'C. 손상된 JSON'
    [System.IO.File]::WriteAllText($cacheFile, '{ this is not json', (New-Object System.Text.UTF8Encoding($false)))
    $threw = $false; $readCorrupt = $null
    try { $readCorrupt = Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo } catch { $threw = $true }
    Assert-True (-not $threw) 'C-1 손상 JSON 에서 예외가 나지 않는다'
    Assert-True ($null -eq $readCorrupt) 'C-2 손상 JSON 은 $null 이다'

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'D. Clear'
    Write-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo -Branches @('feat/a')
    Assert-True (Test-Path -LiteralPath $cacheFile) 'D-1 Clear 전 파일이 있다'
    Clear-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo
    Assert-True (-not (Test-Path -LiteralPath $cacheFile)) 'D-2 Clear 후 파일이 없다'
    Assert-True ($null -eq (Read-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo)) 'D-3 Clear 후 read 는 $null'

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'E. Get-GissueMergedBranchSet — 캐시 히트 시 gh 미호출'
    $repoE = Join-Path $tempRoot 'repo-fake-origin'
    New-Item -ItemType Directory -Path $repoE -Force | Out-Null
    Invoke-Git @('-C', $repoE, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $repoE, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $repoE, 'config', 'user.name', 'gh-cache-test')
    Invoke-Git @('-C', $repoE, 'remote', 'add', 'origin', 'https://example.invalid/someowner/somerepo.git')
    Set-Content -LiteralPath (Join-Path $repoE 'README.md') -Value 'gh cache test' -Encoding UTF8
    Invoke-Git @('-C', $repoE, 'add', '-A')
    Invoke-Git @('-C', $repoE, 'commit', '-q', '-m', 'init')

    Write-GissueMergedBranchDiskCache -OwnerRepo $ownerRepo -Branches @('feat/merged-x', 'feat/other')

    # 외부 호출 래퍼 스텁: gh 호출이면 기록하고 예외를 던진다 — 캐시가 히트하면 gh 는 절대 불리면 안 된다.
    # (Start-Process 경유라 `function gh` 스텁은 우회되므로 래퍼를 스텁한다.)
    # git 호출은 실제 헬퍼로 위임한다 — 캐시 히트 경로도 origin URL 조회(git) 1회는 하기 때문이다.
    # 원본 정의를 저장해 두었다가 finally 에서 복원한다(제거하면 이후 구간이 래퍼를 못 쓴다).
    $origExternalCall = (Get-Command Invoke-GissueExternalCall -ErrorAction Stop).ScriptBlock
    $script:GhCalls = 0
    $script:ExternalCalls = 0
    function Invoke-GissueExternalCall {
        param([string]$FilePath, [string[]]$ArgumentList = @(), [int]$TimeoutSec = 0, [string]$Kind = 'Git')
        $script:ExternalCalls++
        if ($FilePath -eq 'gh') {
            $script:GhCalls++
            throw 'gh stub — 캐시 히트 경로에서는 호출 금지'
        }
        return (Invoke-GissueBoundedProcess -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSec $TimeoutSec)
    }
    $logE = New-Object System.Collections.ArrayList
    $loggerE = { param($m) [void]$logE.Add([string]$m); Write-Output $m }
    try {
        $setE = Get-GissueMergedBranchSet -RepoPath $repoE -Log $loggerE
    } finally {
        Set-Item -Path 'Function:\Invoke-GissueExternalCall' -Value $origExternalCall -ErrorAction SilentlyContinue
    }
    Assert-True (@($setE).Count -eq 1) 'E-1 반환값은 정확히 1개 객체' "count=$(@($setE).Count)"
    Assert-True ($setE.Ok -eq $true) 'E-2 Ok=$true (캐시 히트)'
    Assert-True ($setE.Branches.Contains('feat/merged-x') -and $setE.Branches.Contains('feat/other')) 'E-3 심어둔 집합이 그대로 돌아온다'
    Assert-Eq $script:GhCalls 0 'E-4 gh 가 한 번도 불리지 않았다'
    Assert-Eq $script:ExternalCalls 1 'E-5 외부 호출은 git remote get-url origin 1회뿐이다' "ExternalCalls=$($script:ExternalCalls)"
    Assert-True (@($logE | Where-Object { $_ -match '\[GH-CACHE\] HIT someowner/somerepo' }).Count -ge 1) 'E-6 [GH-CACHE] HIT 로그가 남는다' ($logE -join ' | ')
} finally {
    $env:GISSUE_GH_CACHE_DIR = $script:SavedCacheDir
    $env:GISSUE_GH_CACHE_TTL_MIN = $script:SavedTtl
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false }
}

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
Write-Output "ALL PASS ($($script:Pass) 건)"
exit 0
