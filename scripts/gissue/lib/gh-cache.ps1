# gh-cache.ps1 — 머지된 PR 브랜치 집합의 디스크 캐시 (dot-source 전용)
#
# 왜 필요한가:
#   머지판정(Get-GissueMergedBranchSet, worktree-safety.ps1)은 레포마다
#   `gh pr list --state merged --limit 1000` 를 부른다. 이 조회는 GitHub GraphQL
#   예산(계정 전체 공유)을 먹고, 프로세스 내 캐시(L1)만으로는 매시 러너·CSN별 잡·
#   각종 스윕이 각자 같은 레포를 다시 조회한다. 예산이 소진되면 조회가 전부 실패해
#   머지판정이 fail-closed 로 닫히고 MANUAL-REVIEW 가 폭증한다(실측).
#   이 디스크 캐시는 **성공한 조회 결과만** 프로세스 너머로 공유한다 — 실패는 절대
#   캐시하지 않으므로 fail-closed 동작은 그대로다.
#
# 파일: 레포당 1개 `<owner>__<repo>.merged.json`
#   { "ownerRepo": "owner/repo", "fetchedAt": "<ISO 8601 UTC>", "branches": [...] }
# 위치: $env:GISSUE_GH_CACHE_DIR 가 있으면 그곳, 없으면 <gissue 폴더>/logs/gh-cache
# TTL: 기본 50분. $env:GISSUE_GH_CACHE_TTL_MIN (양의 정수, 분)으로 재정의 가능.
# 무효화: PR 머지 직후 merge-standing-prs.ps1 이 Clear-GissueMergedBranchDiskCache 로 비운다.
#
# 이 파일은 함수 정의만 한다 — dot-source 시점에 부작용이 없어야 한다.

# 이 모듈 자신의 디렉터리를 dot-source 시점에 고정한다 (worktree-safety.ps1 과 같은 이유:
# 함수 본문에서 $PSScriptRoot 를 읽으면 호출자 스크립트의 디렉터리로 해석된다).
$script:GissueGhCacheLibDir = $PSScriptRoot
if (-not $script:GissueGhCacheLibDir) {
    $script:GissueGhCacheLibDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-GissueGhCacheDir {
    if ($env:GISSUE_GH_CACHE_DIR) { return $env:GISSUE_GH_CACHE_DIR }
    $gissueDir = Split-Path -Parent $script:GissueGhCacheLibDir
    return (Join-Path (Join-Path $gissueDir 'logs') 'gh-cache')
}

function Get-GissueGhCachePath {
    param([Parameter(Mandatory = $true)][string]$OwnerRepo)
    $safe = ($OwnerRepo -replace '[\\/]', '__')
    return (Join-Path (Get-GissueGhCacheDir) "$safe.merged.json")
}

function Get-GissueGhCacheTtlMinutes {
    $ttl = 50
    if ($env:GISSUE_GH_CACHE_TTL_MIN) {
        $parsed = 0
        if ([int]::TryParse($env:GISSUE_GH_CACHE_TTL_MIN, [ref]$parsed) -and $parsed -gt 0) { $ttl = $parsed }
    }
    return $ttl
}

# 캐시를 읽어 { Branches(HashSet), FetchedAt, AgeMinutes } 를 돌려준다.
# 파일 없음·TTL 만료·JSON 손상·형식 이상이면 **예외 없이 $null** — 호출자는 gh 재조회로 떨어진다.
function Read-GissueMergedBranchDiskCache {
    param(
        [Parameter(Mandatory = $true)][string]$OwnerRepo,
        [int]$MaxAgeMinutes = 0
    )
    try {
        if ($MaxAgeMinutes -le 0) { $MaxAgeMinutes = Get-GissueGhCacheTtlMinutes }
        $path = Get-GissueGhCachePath -OwnerRepo $OwnerRepo
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $raw = [System.IO.File]::ReadAllText($path)
        $obj = $raw | ConvertFrom-Json
        if (-not $obj -or -not $obj.fetchedAt) { return $null }
        # fetchedAt 의 형은 실행 환경마다 다르다: PS 7 의 ConvertFrom-Json 은 ISO 문자열을
        # [datetime] 으로 자동 변환하고, PS 5.1 은 문자열 그대로 돌려준다. 문자열로 왕복시키면
        # 문화권 형식으로 찍히면서 UTC 표식이 사라져 나이 계산이 호스트 시간대만큼 어긋난다
        # (JST 호스트에서 방금 쓴 캐시가 540분 지난 것으로 판정돼 영원히 미스한 실측 버그).
        # 그래서 형을 보고 각각 UTC 로 정규화한다.
        if ($obj.fetchedAt -is [datetime]) {
            $fetched = $obj.fetchedAt.ToUniversalTime()
        } else {
            $fetched = [datetime]::Parse("$($obj.fetchedAt)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        $age = [datetime]::UtcNow - $fetched
        if ($age.TotalMinutes -lt 0 -or $age.TotalMinutes -gt $MaxAgeMinutes) { return $null }
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($b in @($obj.branches)) { if ($b) { [void]$set.Add("$b") } }
        return [pscustomobject]@{ Branches = $set; FetchedAt = $fetched; AgeMinutes = [int][math]::Floor($age.TotalMinutes) }
    } catch {
        return $null
    }
}

# 성공한 조회 결과만 쓴다. 임시 파일에 쓰고 Move-Item -Force 로 원자적으로 교체하므로
# 읽는 쪽이 쓰는 도중의 반쪽 파일을 볼 일이 없다. 쓰기 실패는 조용히 삼킨다(캐시는 최적화일 뿐).
function Write-GissueMergedBranchDiskCache {
    param(
        [Parameter(Mandatory = $true)][string]$OwnerRepo,
        [Parameter(Mandatory = $true)]$Branches
    )
    $tmp = $null
    try {
        $dir = Get-GissueGhCacheDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $path = Get-GissueGhCachePath -OwnerRepo $OwnerRepo
        $payload = [pscustomobject]@{
            ownerRepo = $OwnerRepo
            fetchedAt = (Get-Date).ToUniversalTime().ToString('o')
            branches  = @($Branches | ForEach-Object { "$_" } | Sort-Object -Unique)
        }
        $json = $payload | ConvertTo-Json -Depth 3
        $tmp = "$path.tmp-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { try { Remove-Item -LiteralPath $tmp -Force } catch {} }
    }
}

function Clear-GissueMergedBranchDiskCache {
    param([Parameter(Mandatory = $true)][string]$OwnerRepo)
    try {
        $path = Get-GissueGhCachePath -OwnerRepo $OwnerRepo
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    } catch {}
}
