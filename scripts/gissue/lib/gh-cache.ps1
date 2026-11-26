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
#   **빈 집합은 절대 쓰지 않는다** — gh 조회가 빈 stdout/빈 배열로 끝나면 그건 조회
#   실패이지 "머지 PR 0건"이 아니다. 빈 집합을 쓰면 다음 조회부터 TTL(50분) 동안
#   전부 '미머지'로 처리되는 오염이 된다(2026-11-26 실측: 0개 캐시 파일이 쓰이고
#   `[GH-CACHE] HIT ... (0 branches)` 가 그 뒤를 이었다). 이미 디스크에 있는
#   빈 집합 파일도 Read 가 $null 로 거른다.
#   조회 실패 시에는 TTL이 지났어도 비어 있지 않은 마지막 유효 캐시를 임시로 쓴다
#   (Read -AllowStale, 호출자 Get-GissueMergedBranchSet 의 STALE 폴백).
#
#   **공백이 든 항목은 절대 읽지도 쓰지도 않는다** (2026-11-25 실측 — giip #6354):
#   PowerShell 5.1 의 ConvertFrom-Json 배열 함정으로 브랜치 목록이 "공백 결합 문자열 1개"
#   로 붕괴해 저장된 파일이다(539개가 1개로). git ref 이름에는 공백이 들어갈 수 없으므로
#   공백 포함 항목이 하나라도 있으면 그 파일은 깨진 파일이다 — Read 는 $null 로 거르고
#   (이미 디스크에 있는 오염 파일은 호스트 손대지 않고 자동 무효화된다), Write 는 거부한다.
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
# 파일 없음·TTL 만료·JSON 손상·형식 이상·**빈 집합**이면 **예외 없이 $null** — 호출자는 gh 재조회로 떨어진다.
# -AllowStale: 조회 실패 시 최후 수단으로 TTL 상한을 보지 않고 읽는다(비어 있지 않은 경우만).
function Read-GissueMergedBranchDiskCache {
    param(
        [Parameter(Mandatory = $true)][string]$OwnerRepo,
        [int]$MaxAgeMinutes = 0,
        [switch]$AllowStale
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
        if ($age.TotalMinutes -lt 0) { return $null }
        if (-not $AllowStale -and $age.TotalMinutes -gt $MaxAgeMinutes) { return $null }
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($b in @($obj.branches)) {
            if (-not $b) { continue }
            $name = "$b"
            # ★ 공백이 든 항목은 깨진 파일이다(2026-11-25 실측 — giip #6354): PS 5.1 의
            #   ConvertFrom-Json 배열 함정으로 브랜치 목록이 "공백 결합 문자열 1개" 로 붕괴해
            #   저장된 파일이다. git ref 이름에는 공백이 들어갈 수 없으므로, 공백 포함 항목이
            #   하나라도 있으면 파일 전체를 오염으로 거른다 — 이미 디스크에 있는 오염 파일은
            #   호스트에서 손으로 지우지 않고 다음 조회에서 자동으로 무효화된다(#569 와 같은 precedent).
            if ($name -match '\s') { return $null }
            [void]$set.Add($name)
        }
        # 빈 집합 파일은 오염으로 취급한다 — 이미 디스크에 쓰인 빈 캐시가 있어도 히트로 쓰지 않는다.
        if ($set.Count -eq 0) { return $null }
        return [pscustomobject]@{ Branches = $set; FetchedAt = $fetched; AgeMinutes = [int][math]::Floor($age.TotalMinutes) }
    } catch {
        return $null
    }
}

# 성공한 조회 결과만 쓴다. 빈 집합은 절대 쓰지 않는다 — 빈 결과는 조회 실패이지
# "머지 PR 0건"이 아니며, 빈 파일을 쓰면 다음 조회부터 전부 '미머지'가 된다
# (2026-11-26 실측). 빈 집합이면 기존 파일을 건드리지 않고 $false 를 돌려준다.
# 임시 파일에 쓰고 Move-Item -Force 로 원자적으로 교체하므로
# 읽는 쪽이 쓰는 도중의 반쪽 파일을 볼 일이 없다. 쓰기 실패는 조용히 삼킨다(캐시는 최적화일 뿐).
# 반환: $true = 썼다, $false = 빈 집합 거부 또는 쓰기 실패.
function Write-GissueMergedBranchDiskCache {
    param(
        [Parameter(Mandatory = $true)][string]$OwnerRepo,
        [Parameter(Mandatory = $true)]$Branches
    )
    # ★ 배열 함정 방어(giip #6354): 중첩 배열이 들어오면 파이프라인이 원소 단위로 펼치지 못한 채
    #   "공백 결합 문자열 1개" 로 뭉개진다. 원소를 직접 순회해 문자열로 정규화하고, 공백이 든
    #   항목(정상 브랜치 이름이 아님)은 **쓰지 않는다**(fail-closed — 잘못된 캐시를 만들지 않는다).
    $names = @()
    foreach ($b in @($Branches)) {
        foreach ($s in @($b)) {
            if ($null -eq $s) { continue }
            $name = "$s"
            if (-not $name.Trim()) { continue }
            if ($name -match '\s') { return $false }
            $names += $name
        }
    }
    $list = @($names | Sort-Object -Unique)
    if ($list.Count -eq 0) { return $false }
    $tmp = $null
    try {
        $dir = Get-GissueGhCacheDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $path = Get-GissueGhCachePath -OwnerRepo $OwnerRepo
        $payload = [pscustomobject]@{
            ownerRepo = $OwnerRepo
            fetchedAt = (Get-Date).ToUniversalTime().ToString('o')
            branches  = $list
        }
        $json = $payload | ConvertTo-Json -Depth 3
        $tmp = "$path.tmp-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
        return $true
    } catch {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { try { Remove-Item -LiteralPath $tmp -Force } catch {} }
        return $false
    }
}

function Clear-GissueMergedBranchDiskCache {
    param([Parameter(Mandatory = $true)][string]$OwnerRepo)
    try {
        $path = Get-GissueGhCachePath -OwnerRepo $OwnerRepo
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    } catch {}
}
