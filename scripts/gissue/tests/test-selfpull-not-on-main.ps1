# [giip #2696] NOT-ON-MAIN 감지 + 조건부 자동복귀 회귀 테스트
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-selfpull-not-on-main.ps1
#   또는: powershell -NoProfile -File scripts/gissue/tests/test-selfpull-not-on-main.ps1
param([string]$ScriptUnderTest)
if (-not $ScriptUnderTest) { $ScriptUnderTest = Join-Path $PSScriptRoot '../run-gissue-claude.ps1' }
$ScriptUnderTest = (Resolve-Path -LiteralPath $ScriptUnderTest).Path

# [저장소 정비 2026-10-23] 테스트용 임시 CSN 매핑 파일.
#   러너의 preflight(Phase -3)는 매핑 파일이 없으면 치명(exit 2)으로 끝나고, 닷소싱한 스크립트의
#   `return` 이 테스트를 조용히 통과시킨다(=검사 0건인데 "ALL TESTS PASSED" 로 보고되던 문제).
#   배포용 csn-projects.json 은 로컬 전용(gitignore)이라 건드리지 않고 임시 파일을 넘긴다.
$tempMapFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue_selftest_map_" + [guid]::NewGuid().ToString('N') + ".json")
$tempMapJson = @{
    csn = @{
        '99999' = @{
            project  = 'selftest'
            workdir  = (Split-Path -Parent (Split-Path -Parent $ScriptUnderTest))   # <레포>/scripts/gissue → 레포 루트
            enabled  = $true
        }
    }
} | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $tempMapFile -Value $tempMapJson -Encoding UTF8

# 테스트 대상 함수 로드 — **-FunctionsOnly** 로 본문(스케줄러) 실행 없이 함수 정의만 가져온다.
#   닷소싱은 top-level 코드를 전부 실행하므로, 이 스위치 없으면 테스트가 스케줄러를 그대로 돌린다.
. $ScriptUnderTest -FunctionsOnly -MapFileOverride $tempMapFile

# [저장소 정비 2026-10-23] 닷소싱 **뒤에** 'Continue' 로 둬야 한다.
#   (앞에 두면 닷소싱한 러너의 $ErrorActionPreference='Stop' 이 다시 덮어쓴다.)
#   'Stop' 을 쓰면 테스트가 애초에 끝까지 돌지 않는다 — Windows PowerShell 5.1 은
#   **native 명령이 stderr 에 쓰면**(성공 여부와 무관) 그 내용을 ErrorRecord 로 올리고,
#   'Stop' 아래에서 terminating 이 된다. git checkout / push / merge 는 정상 동작이어도
#   stderr 에 "Switched to a new branch" 같은 진행 메시지를 남겨 첫 git 호출에서 죽었다.
#   판정 자체는 Check() 의 $fail 카운터가 하므로, 여기서는 'Continue' 로 두고
#   예상 못한 예외는 finally 정리(임시 디렉터리 삭제)만 책임지게 한다.
$ErrorActionPreference = 'Continue'

$fail = 0
$checks = 0
function Check($name, [bool]$ok, $detail) {
    $script:checks++
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name — $detail" }
}

# [저장소 정비 2026-10-23] 러너 함수 적재 확인 — 하나라도 없으면 **즉시 실패**한다.
#   (이 확인이 없으면 함수 미적재 상태에서 Check() 호출이 조용히 무시되고,
#    검사 0건이면서 "ALL TESTS PASSED" 로 보고되는 **거짓 통과**가 된다.)
$requiredFns = @('Test-GissueBranchOnMain', 'Test-GissueUpstreamGone', 'Test-GissueBranchIsAncestorOfOriginMain', 'Invoke-GissueSelfPullNotOnMainCheck')
$missingFns = @($requiredFns | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missingFns.Count -gt 0) {
    Write-Output "[FAIL] 러너 함수 적재 실패 — 다음 함수가 정의되지 않음: $($missingFns -join ', ')"
    Remove-Item -LiteralPath $tempMapFile -Force -ErrorAction SilentlyContinue
    Write-Output ""
    Write-Output "=== TESTS FAILED (러너 함수 미적재) ==="
    exit 1
}
function New-Repo($base) {
    $r = Join-Path $base 'repo.git'
    New-Item -ItemType Directory -Path $r -Force | Out-Null
    & git -C $r init --initial-branch=main 2>$null | Out-Null
    $null = Set-Content -LiteralPath (Join-Path $r 'README.md') -Value "test"
    & git -C $r add README.md; & git -C $r commit -m "init" 2>$null | Out-Null
    # origin 시뮬레이션: 실제 bare 저장소를 만들어 remote 로 쓴다.
    #   [저장소 정비 2026-10-23] 기존에는 디렉터리만 만들고 push 를 시도해서
    #   "origin.git does not appear to be a git repository" 로 push 가 실패했다(=B3/D2/D3 이
    #   의도한 "원격 브랜치 삭제(gone)" 시나리오가 아예 재현되지 않았다). bare 저장소를
    #   실제로 init 하면 그 시나리오가 그대로 재현된다.
    $bare = Join-Path $base 'origin.git'
    & git init --bare --initial-branch=main $bare 2>&1 | Out-Null
    & git -C $r remote add origin $bare 2>$null | Out-Null
    & git -C $r push -u origin main 2>&1 | Out-Null
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
    # [저장소 정비 2026-10-23] 흡수된 커밋을 **원격(main)에도 반영**해야
    #   "fix/merged-feature 의 HEAD 가 origin/main 의 조상" 이 성립한다.
    #   push 를 빠뜨리면 origin/main 은 병합 전 커밋에 머물러 조상 판정이 false 가 되고,
    #   C3/D2 가 "제품이 고장났다" 는 잘못된 실패를 낸다(제품이 아니라 픽스처의 문제였다).
    & git -C $repo push origin main 2>&1 | Out-Null
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
    # [저장소 정비 2026-10-23] '복귀 시도'/'복귀 + pull 성공' 로 좁혀 판정한다.
    #   예전 판정 문자열('자동 복귀')은 **복귀를 건너뛴 경고문**("…자동 복귀를 건너뜁니다")에도
    #   걸려서, "복귀 안 함" 을 검사하는 D3/D4 가 항상 실패했다(거짓 실패).
    $hasRecover = $logs | Where-Object { $_ -match '복귀 시도|복귀 \+ pull 성공' }
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
    $hasRecover = $logs | Where-Object { $_ -match '복귀 시도|복귀 \+ pull 성공' }
    Check 'D4 Invoke-GissueSelfPullNotOnMainCheck: tracked 변경 있으면 경고만, 복귀 안 함' ($hasWarn -and -not $hasRecover) "logs: $($logs -join ' | ')"

} finally {
    # 정리
    if (Test-Path $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
    # 임시 CSN 매핑 파일 정리(테스트가 만든 것만 — 배포용 파일은 건드리지 않는다)
    if ($tempMapFile -and (Test-Path -LiteralPath $tempMapFile)) { Remove-Item -LiteralPath $tempMapFile -Force -ErrorAction SilentlyContinue }
}

# [저장소 정비 2026-10-23] 거짓 통과 방지 — 검사 항목이 하나도 실행되지 않았으면 실패다.
#   (예외로 try 블록이 조용히 빠져나가면 $fail 이 0 으로 남아 "ALL TESTS PASSED" 로 보고된다.
#    실제로는 어떤 검사도 돌지 않은 상태였다 — 이 가드가 없으면 테스트가 거짓말을 한다.)
if ($checks -eq 0) {
    Write-Output "[FAIL] 검사 항목 0건 — 테스트가 실제로 실행되지 않았습니다(거짓 통과 방지 가드)"
    $fail++
}

if ($fail -eq 0) {
    Write-Output ""
    Write-Output "=== ALL TESTS PASSED ($checks checks, $fail failures) ==="
    exit 0
} else {
    Write-Output ""
    Write-Output "=== TESTS FAILED ($fail failures) ==="
    exit 1
}
