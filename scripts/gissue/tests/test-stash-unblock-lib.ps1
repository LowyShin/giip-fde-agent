# test-stash-unblock-lib.ps1 — auto-unblock stash 단계 정본 lib 회귀 테스트 (giip 4518, 원본 giip #2406)
#
# 왜 필요한가 (실측 재현, 2026-11-04):
#   untracked `nul`(Windows 장치 예약어)이 있을 때 `git stash push -u` 는:
#     Ignoring path nul
#     Saved working directory and index state On <branch>: ...   ← stash 는 실제로 만들어짐
#     warning: failed to remove nul: Permission denied            ← untracked 정리만 실패
#     EXIT=1                                                       ← 그런데 exit 코드는 1
#   = "stash 실패"가 아니라 **부분 성공(보존 성공)**. exit != 0 만 보고 포기하면 base 복귀를 못 해
#   무한 반복한다. gissue-stash-unblock-lib.ps1 이 이 시그니처를 부분 성공으로 분류하고 tracked 전용
#   stash 로 워킹트리를 리셋해 base 복귀를 계속 진행시키는지 고정한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-stash-unblock-lib.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 임시 디렉터리($env:TEMP\gissue-stash-unblock-lib-test-<pid>)에만 레포를 만든다 — 라이브 체크아웃을
# 절대 건드리지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$Lib = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\lib\gissue-stash-unblock-lib.ps1')).Path
. $Lib

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Remove-TestTree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Attributes = 'Normal' } catch {}
    }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

# ──────────────────────────────────────────────────────────────────────────────
# A. 순수 판정 (부수효과 없음)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 순수 판정 함수'

$reservedReal = @(
    'Ignoring path nul',
    'Saved working directory and index state On feature: repro auto-unblock test',
    'warning: failed to remove nul: Permission denied'
)
Assert-True (Test-GissueStashReservedNameFailure $reservedReal) 'A-1 실측 예약장치명 부분성공 출력 -> true'
Assert-True (-not (Test-GissueStashReservedNameFailure @('warning: failed to remove nul: Permission denied'))) `
    'A-2 "Saved..." 없으면 부분성공 아님 -> false(보존 증거 필수)'
# 경로길이 계열은 예약장치명 판정에서 false(= stash 자체 실패지 부분성공 아님)
Assert-True (-not (Test-GissueStashReservedNameFailure 'Cannot save the untracked files')) `
    'A-3 경로길이 계열 문자열은 예약장치명 판정에서 false'
# 예약장치명이 아닌 파일의 removal 실패는 부분성공으로 분류하지 않는다(원인·대응이 다름)
Assert-True (-not (Test-GissueStashReservedNameFailure @('Saved working directory and index state On x: y','warning: failed to remove locked.bin: Permission denied'))) `
    'A-4 예약장치명 아닌 파일 removal 실패는 부분성공 아님'
Assert-True (-not (Test-GissueStashReservedNameFailure $null)) 'A-5 $null -> false'

Assert-True (Test-GissueStashUntrackedFailure 'Cannot save the untracked files') 'A-6 경로길이 계열 -> true'
Assert-True (Test-GissueStashUntrackedFailure 'error: ...: Filename too long') 'A-7 Filename too long -> true'
Assert-True (-not (Test-GissueStashUntrackedFailure $reservedReal)) 'A-8 예약장치명 출력은 경로길이 판정에서 false(분기 혼선 없음)'
Assert-True (-not (Test-GissueStashUntrackedFailure "error: pathspec 'x' did not match")) 'A-9 무관한 실패 -> false'

Assert-True (Test-GissueWindowsReservedDeviceName 'nul') 'A-10 nul -> 예약장치명'
Assert-True (Test-GissueWindowsReservedDeviceName 'NUL.txt') 'A-11 NUL.txt(확장자 포함) -> 예약장치명'
Assert-True (Test-GissueWindowsReservedDeviceName 'sub/com1') 'A-12 경로의 마지막 요소(com1) -> 예약장치명'
Assert-True (-not (Test-GissueWindowsReservedDeviceName 'normal.txt')) 'A-13 normal.txt -> 아님'
Assert-True (-not (Test-GissueWindowsReservedDeviceName '')) 'A-14 빈 문자열 -> 아님'

$rp = Get-GissueStashReservedNamePaths $reservedReal
Assert-True ((@($rp) -contains 'nul') -and (@($rp).Count -eq 1)) 'A-15 남은 예약장치명 경로 추출=nul(중복 제거)' "rp=$(@($rp) -join '|')"

# ──────────────────────────────────────────────────────────────────────────────
# B. 통합 — 실제 git 레포에서 예약장치명 nul 부분성공을 재현하고 폴백이 base 복귀를 뚫는지
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'B. Invoke-GissueAutoUnblockStash (예약장치명 통합)'

# nul 은 Windows 일반 수단으로 못 만들고 MSYS(git-bash)로만 literal 파일이 된다 — bash 없거나
# 생성 실패면 WARN 로 건너뛴다(환경 의존이라 flaky 하지 않게).
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd) {
    Write-Output '  WARN  B 건너뜀 — bash 없음(예약장치명 literal 파일 생성 불가 환경)'
} else {
    $testRoot = Join-Path $env:TEMP "gissue-stash-unblock-lib-test-$PID"
    Remove-TestTree $testRoot
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $repo = Join-Path $testRoot 'repo'
    try {
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        $repoUnix = $repo.Replace('\', '/')
        git -C $repo init -q --initial-branch=main 2>&1 | Out-Null
        git -C $repo config user.email 'test@example.com' 2>&1 | Out-Null
        git -C $repo config user.name 'gissue test' 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'v1' -Encoding UTF8
        git -C $repo add -A 2>&1 | Out-Null
        git -C $repo commit -q -m init 2>&1 | Out-Null
        # base/feature 가 tracked.txt 에서 갈라지게 — 워킹트리를 리셋하지 않으면 checkout 이 막히는 조건.
        git -C $repo checkout -q -b feature 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'feature-v2' -Encoding UTF8
        git -C $repo commit -aqm 'feature' 2>&1 | Out-Null
        git -C $repo checkout -q main 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'main-v2' -Encoding UTF8
        git -C $repo commit -aqm 'main' 2>&1 | Out-Null
        git -C $repo checkout -q feature 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tracked.txt') -Value 'dirty-local' -Encoding UTF8
        & bash -c "cd '$repoUnix'; printf 'x' > nul; printf 'o' > other.txt" 2>&1 | Out-Null
        $hasNul = (git -C $repo status --porcelain 2>&1 | Out-String) -match '\?\? nul(\s|$)'
        if (-not $hasNul) {
            Write-Output '  WARN  B 건너뜀 — 이 환경에서 literal nul 파일 생성 실패'
        } else {
            $res = Invoke-GissueAutoUnblockStash $repo 'auto-unblock reserved-name test'
            Assert-True ($res.Ok) 'B-1 예약장치명 부분성공 -> Ok=true(포기하지 않고 base 복귀 계속)' "err=$($res.ErrDetail)"
            Assert-True ($res.ExitCode -eq 0) 'B-2 Ok=true 는 ExitCode=0 을 함의'
            Assert-True (@($res.ReservedNames) -contains 'nul') 'B-3 ReservedNames 에 잔여 nul' "rn=$(@($res.ReservedNames) -join '|')"
            Assert-True ((@($res.LogLines) -join "`n") -match 'nul') 'B-4 LogLines 에 남은 예약장치명(nul) 명시(조용한 동작 변경 금지)'
            $st = (git -C $repo status --porcelain 2>&1 | Out-String)
            Assert-True (-not ($st -match '(?m)^ M ')) 'B-5 tracked 변경이 워킹트리에서 리셋됨(= checkout 가능)' "status=$st"
            $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $co = git -C $repo checkout main 2>&1; $coe = $LASTEXITCODE
            $ErrorActionPreference = $eap
            Assert-True ($coe -eq 0) 'B-6 잔여 예약장치명과 함께 base checkout 성공(= 큐가 다시 흐른다)' "exit=$coe"
            Assert-True ((git -C $repo rev-parse --abbrev-ref HEAD 2>&1 | Out-String).Trim() -eq 'main') 'B-7 HEAD 가 base 로 복귀'
        }
    } finally {
        & cmd /c "del /f /q \\.\$($repo.Replace('/','\'))\nul" 2>&1 | Out-Null
        Remove-TestTree $testRoot
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# C. 통합 — 정상 경로(예약장치명 없음)는 기존대로 -u stash 로 동작(폴백이 정상 경로를 깨뜨리지 않음)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'C. Invoke-GissueAutoUnblockStash (정상 경로)'
$testRootC = Join-Path $env:TEMP "gissue-stash-unblock-lib-normal-$PID"
Remove-TestTree $testRootC
New-Item -ItemType Directory -Force -Path $testRootC | Out-Null
try {
    $repoC = Join-Path $testRootC 'repo'
    New-Item -ItemType Directory -Force -Path $repoC | Out-Null
    git -C $repoC init -q --initial-branch=main 2>&1 | Out-Null
    git -C $repoC config user.email 'test@example.com' 2>&1 | Out-Null
    git -C $repoC config user.name 'gissue test' 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $repoC 'tracked.txt') -Value 'v1' -Encoding UTF8
    git -C $repoC add -A 2>&1 | Out-Null
    git -C $repoC commit -q -m init 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $repoC 'tracked.txt') -Value 'v2' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $repoC 'untracked.txt') -Value 'u1' -Encoding UTF8
    $resC = Invoke-GissueAutoUnblockStash $repoC 'auto-unblock normal test'
    Assert-True ($resC.Ok) 'C-1 정상 경로 Ok=true' "err=$($resC.ErrDetail)"
    Assert-True ($resC.UsedUntracked) 'C-2 정상 경로는 -u 를 쓴다(UsedUntracked=true)'
    Assert-True (@($resC.LogLines).Count -eq 0) 'C-3 정상 경로는 폴백 로그를 남기지 않는다(조용한 정상동작)'
    $afterC = (git -C $repoC status --porcelain 2>&1 | Out-String).Trim()
    Assert-True ($afterC -eq '') 'C-4 stash 후 워킹트리 clean(= checkout 가능)' "status=$afterC"
    # 존재하지 않는 레포 = 분류에 안 걸리는 실패 -> 폴백 없이 Ok=false
    $resBad = Invoke-GissueAutoUnblockStash (Join-Path $testRootC 'nosuch') 'x'
    Assert-True (-not $resBad.Ok) 'C-5 무관한 실패 -> Ok=false(폴백 남용 안 함)'
} finally {
    Remove-TestTree $testRootC
}

Write-Output ''
Write-Output "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
