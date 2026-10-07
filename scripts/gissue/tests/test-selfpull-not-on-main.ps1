# [giip #2696] NOT-ON-MAIN 감지 + 조건부 자동복귀 회귀 테스트
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-selfpull-not-on-main.ps1
#   또는: powershell -NoProfile -File scripts/gissue/tests/test-selfpull-not-on-main.ps1
param([string]$ScriptUnderTest)
$ErrorActionPreference = 'Stop'
if (-not $ScriptUnderTest) { $ScriptUnderTest = Join-Path $PSScriptRoot '../run-gissue-claude.ps1' }

# 테스트 대상 함수 로드 (run-gissue-claude.ps1 을 닷소싱하면 정의가 메모리에 적재된다)
. (Resolve-Path -LiteralPath $ScriptUnderTest).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name — $detail" }
}
function New-Repo($base) {
    $r = Join-Path $base 'repo.git'
    New-Item -ItemType Directory -Path $r -Force | Out-Null
    & git -C $r init --initial-branch=main 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $r 'README.md') -Value "test"
    & git -C $r add README.md; & git -C $r commit -m "init" 2>$null | Out-Null
    # origin 시뮬레이션: 같은 디렉터리를 bare 로
    $bare = Join-Path $base 'origin.git'
    & git -C $r remote add origin $bare 2>$null | Out-Null
    & git -C $r push -u origin main 2>$null | Out-Null
    return $r
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("notonmain_test_" + [guid]::NewGuid().ToString('N'))
try {
    $repo = New-Repo $base
    $null = New-Item -ItemType Directory -Path $repo -Force | Out-Null

    # ── A组: Test-GissueBranchOnMain ─────────────────────────────────────────────
    # A1: main 브랜치 위
    & git -C $repo checkout main 2>$null | Out-Null
    Check 'A1 Test-GissueBranchOnMain: main 위에서 true' (Test-GissueBranchOnMain -RepoRoot $repo) "반환: $(Test-GissueBranchOnMain -RepoRoot $repo)"

    # A2: 피처 브랜치 위
    $null = Set-Content -LiteralPath (Join-Path $repo 'x.txt') -Value "x"
    & git -C $repo checkout -b 'fix/test-branch' 2>$null | Out-Null
    & git -C $repo add x.txt; & git -C $repo commit -m "x" 2>$null | Out-Null
    Check 'A2 Test-GissueBranchOnMain: 피처 브랜치 위에서 false' (-not (Test-GissueBranchOnMain -RepoRoot $repo)) "반환: $(Test-GissueBranchOnMain -RepoRoot $repo)"

    # ── B组: Test-GissueUpstreamGone ──────────────────────────────────────────────
    # B1: upstream 있음 (main 위)
    & git -C $repo checkout main 2>$null | Out-Null
    Check 'B1 Test-GissueUpstreamGone: main 은 upstream 이 살아 있으므로 false' (-not (Test-GissueUpstreamGone -RepoRoot $repo)) "반환: $(Test-GissueUpstreamGone -RepoRoot $repo)"

    # B2: upstream 없음 (새 브랜치, upstream 미설정)
    & git -C $repo checkout -b 'orphan-branch-no-upstream' 2>$null | Out-Null
    & git -C $repo branch --unset-upstream 2>$null | Out-Null
    Check 'B2 Test-GissueUpstreamGone: upstream 없는 브랜치에서 true' (Test-GissueUpstreamGone -RepoRoot $repo) "반환: $(Test-GissueUpstreamGone -RepoRoot $repo)"

    # B3: upstream gone (원격 브랜치 삭제된 상태)
    & git -C $repo checkout -b 'fix/test-gone' 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $repo 'y.txt') -Value "y"
    & git -C $repo add y.txt; & git -C $repo commit -m "y" 2>$null | Out-Null
    & git -C $repo push -u origin fix/test-gone 2>$null | Out-Null
    & git -C $repo push origin --delete fix/test-gone 2>$null | Out-Null   # 원격 브랜치 삭제
    & git -C $repo fetch --prune 2>$null | Out-Null
    Check 'B3 Test-GissueUpstreamGone: 원격 삭제된 upstream 에서 true' (Test-GissueUpstreamGone -RepoRoot $repo) "반환: $(Test-GissueUpstreamGone -RepoRoot $repo)"

    # ── C组: Test-GissueBranchIsAncestorOfOriginMain ──────────────────────────────
    # C1: main 위 → ancestor of origin/main (자기 자신)
    & git -C $repo checkout main 2>$null | Out-Null
    Check 'C1 Test-GissueBranchIsAncestorOfOriginMain: main 은 자기 자신의 ancestor 로 true' (Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo) "반환: $(Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo)"

    # C2: origin/main 에 없는 고유 커밋 보유 → false
    & git -C $repo checkout -b 'feature-unmerged' 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $repo 'z.txt') -Value "z"
    & git -C $repo add z.txt; & git -C $repo commit -m "z" 2>$null | Out-Null
    Check 'C2 Test-GissueBranchIsAncestorOfOriginMain: 미머지 피처는 false' (-not (Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo)) "반환: $(Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo)"

    # C3: 머지된 브랜치(원격 삭제 + ancestor) → true
    & git -C $repo checkout main 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $repo 'm.txt') -Value "m"
    & git -C $repo add m.txt; & git -C $repo commit -m "m" 2>$null | Out-Null
    & git -C $repo push origin main 2>$null | Out-Null
    & git -C $repo checkout -b 'fix/merged-feature' 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $repo 'n.txt') -Value "n"
    & git -C $repo add n.txt; & git -C $repo commit -m "n" 2>$null | Out-Null
    & git -C $repo push -u origin fix/merged-feature 2>$null | Out-Null
    & git -C $repo push origin --delete fix/merged-feature 2>$null | Out-Null
    & git -C $repo fetch --prune 2>$null | Out-Null
    # main 에서 fast-forward merge 로 흡수
    & git -C $repo checkout main 2>$null | Out-Null
    & git -C $repo merge fix/merged-feature --ff-only 2>$null | Out-Null
    # merged-feature 브랜치에서 ancestor 확인
    & git -C $repo checkout fix/merged-feature 2>$null | Out-Null
    Check 'C3 Test-GissueBranchIsAncestorOfOriginMain: 머지된 브랜치는 true' (Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo) "반환: $(Test-GissueBranchIsAncestorOfOriginMain -RepoRoot $repo)"

    # ── D组: Invoke-GissueSelfPullNotOnMainCheck ──────────────────────────────────
    # D1: main 위 → 경고 없음
    & git -C $repo checkout main 2>$null | Out-Null
    $logs = @()
    Invoke-GissueSelfPullNotOnMainCheck -RepoRoot $repo -Log { param($m) $script:logs += $m }
    $hasWarn = $logs | Where-Object { $_ -match 'NOT-ON-MAIN' }
    Check 'D1 Invoke-GissueSelfPullNotOnMainCheck: main 위에서 NOT-ON-MAIN 경고 없음' (-not $hasWarn) "경고出现在了: $($hasWarn -join ', ')"

    # D2: upstream gone + ancestor + clean → 자동 복귀
    & git -C $repo checkout fix/merged-feature 2>$null | Out-Null
    $logs = @()
    Invoke-GissueSelfPullNotOnMainCheck -RepoRoot $repo -Log { param($m) $script:logs += $m }
    $hasInfo = $logs | Where-Object { $_ -match 'main 으로 자동 복귀' }
    $current = & git -C $repo branch --show-current
    Check 'D2 Invoke-GissueSelfPullNotOnMainCheck: 3조건 충족 시 main 으로 자동 복귀' ($hasInfo -and $current -eq 'main') "logs: $($logs -join ' | ') / 현재 브랜치: $current"

    # D3: 미머지 피처 위 → 경고만, 복귀 안 함
    & git -C $repo checkout feature-unmerged 2>$null | Out-Null
    $logs = @()
    Invoke-GissueSelfPullNotOnMainCheck -RepoRoot $repo -Log { param($m) $script:logs += $m }
    $hasWarn = $logs | Where-Object { $_ -match 'NOT-ON-MAIN' }
    $hasRecover = $logs | Where-Object { $_ -match '자동 복귀' }
    $current = & git -C $repo branch --show-current
    Check 'D3 Invoke-GissueSelfPullNotOnMainCheck: 미머지 피처는 경고만, 복귀 안 함' ($hasWarn -and -not $hasRecover -and $current -eq 'feature-unmerged') "logs: $($logs -join ' | ') / 현재 브랜치: $current"

    # D4: tracked 변경 있음 → 경고만, 복귀 안 함
    & git -C $repo checkout main 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $repo 'dirty.txt') -Value "dirty"
    & git -C $repo checkout -b 'fix/dirty-test' 2>$null | Out-Null
    & git -C $repo add dirty.txt
    $logs = @()
    Invoke-GissueSelfPullNotOnMainCheck -RepoRoot $repo -Log { param($m) $script:logs += $m }
    $hasWarn = $logs | Where-Object { $_ -match 'NOT-ON-MAIN' }
    $hasRecover = $logs | Where-Object { $_ -match '자동 복귀' }
    Check 'D4 Invoke-GissueSelfPullNotOnMainCheck: tracked 변경 있으면 경고만, 복귀 안 함' ($hasWarn -and -not $hasRecover) "logs: $($logs -join ' | ')"

} finally {
    # 정리
    if (Test-Path $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fail -eq 0) {
    Write-Output ""
    Write-Output "=== ALL TESTS PASSED ($fail failures) ==="
    exit 0
} else {
    Write-Output ""
    Write-Output "=== TESTS FAILED ($fail failures) ==="
    exit 1
}
