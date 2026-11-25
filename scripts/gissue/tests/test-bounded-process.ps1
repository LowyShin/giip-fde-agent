# test-bounded-process.ps1 — 외부 호출 타임아웃(lib/bounded-process.ps1) 회귀 테스트
#
# 왜 필요한가:
#   worktree 정리 단계는 `gh pr list --state merged --limit 1000` 와 각종 `git` 호출을
#   동기(`&`)로 실행했다. 동기 호출은 끝나야 다음 줄로 가므로, 호출 하나가 멈추면
#   2026-11-25 실측처럼 정리 단계가 31분간 침묵하다 예산 종료로 강제종료되고
#   종료 기록·슬롯 기록이 남지 않는다(17:07 회차, CQE mslsn 8257/8258).
#   lib/bounded-process.ps1 은 외부 호출 1회를 Start-Process + WaitForExit(유한 대기)로
#   실행해, 한도를 넘기면 자식을 죽이고 TimedOut=$true 로 돌려준다. 호출자는 타임아웃을
#   "실패"로 취급해 fail-closed 로 처리하고 다음 레포·항목으로 진행한다.
#
# 고정하는 것:
#   A. Invoke-GissueBoundedProcess — 빠른 성공(종료 코드·stdout), 0 아닌 종료,
#      존재하지 않는 실행 파일(Started=$false), 멈춘 명령이 한도 안에 끊김(실제 프로세스),
#      공백 포함 인자의 따옴표 처리.
#   B. Resolve-GissueBoundedCallTimeoutSec — 기본값(Gh 60초 / Git 30초), env 재정의,
#      무효값(빈 문자열·0·음수·비숫자)은 기본값으로 떨어진다.
#   C. 통합 — 멈추는 가짜 gh(PATH 우선) 상태에서 Get-GissueMergedBranchSet 가
#      타임아웃 안에 Ok=$false 로 돌아오고 '시간 초과' 로그를 남긴다.
#      바로 실패하는 gh(종료 1)도 실패 경로의 출력 결합이 throw 없이 WARN 로그를
#      남기고 Ok=$false 로 돌아온다(C-6~C-9).
#   D. 종단 — 멈추는 가짜 gh 상태에서 Invoke-GissueWorktreeCleanupForRepo 가 throw 없이
#      정상 반환하고, 해당 항목은 MANUAL-REVIEW 로 보류되며 삭제되지 않는다.
#   E. 종단(성공 경로) — 머지+idle worktree 는 실제로 삭제되고 Removed 에 기록된다.
#      `git worktree remove` 성공 직후의 출력 결합이 throw 하면 디렉터리는 지워졌는데
#      Removed 가 비는 회귀가 난다(2026-11-25 실측, test-stale-code-guard B-1b 가
#      잡아냄) — E-1~E-4 가 그 재발을 막는다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-bounded-process.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리([System.IO.Path]::GetTempPath() 아래)에만 레포·가짜 gh 를 만든다 —
# 살아있는 체크아웃이나 호스트 로그 디렉터리를 절대 건드리지 않는다. 네트워크 불필요.
# 가짜 gh 는 `sleep 30` 을 실행하는 스크립트다 — 타임아웃이 죽이는 대상이 실제 프로세스라
#   C/D 가 진짜 hang 을 재현한다. Windows(.cmd)에서는 sleep 을 맡은 powershell 자식이
#   cmd 종료 뒤 최대 30초 더 살다 스스로 끝나므로(고아, 무해) 테스트는 기다리지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$BoundedLib = Join-Path $PSScriptRoot '..\lib\bounded-process.ps1'
$BoundedLib = (Resolve-Path -LiteralPath $BoundedLib).Path
. $BoundedLib
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-bounded-test-$PID")
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$cacheDir = Join-Path $tempRoot 'cache'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

$script:SavedCacheDir = $env:GISSUE_GH_CACHE_DIR
$script:SavedGhTimeout = $env:GISSUE_GH_CALL_TIMEOUT_SEC
$script:SavedGitTimeout = $env:GISSUE_GIT_CALL_TIMEOUT_SEC
$script:SavedPath = $env:PATH
$env:GISSUE_GH_CACHE_DIR = $cacheDir
$env:GISSUE_GH_CALL_TIMEOUT_SEC = $null
$env:GISSUE_GIT_CALL_TIMEOUT_SEC = $null

try {
    # ──────────────────────────────────────────────────────────────────────────
    Write-Output 'A. Invoke-GissueBoundedProcess'
    $fast = Invoke-GissueBoundedProcess -FilePath 'git' -ArgumentList @('--version') -TimeoutSec 30
    Assert-True ($fast.Started) 'A-1 빠른 호출은 Started=$true'
    Assert-True (-not $fast.TimedOut) 'A-2 빠른 호출은 TimedOut=$false'
    Assert-Eq $fast.ExitCode 0 'A-3 빠른 호출은 ExitCode=0'
    Assert-True ("$($fast.StdOut)" -match 'git version') 'A-4 빠른 호출의 stdout 이 돌아온다' "$($fast.StdOut)".Trim()

    $repoA = Join-Path $tempRoot 'repo-a'
    New-Item -ItemType Directory -Path $repoA -Force | Out-Null
    Invoke-Git @('-C', $repoA, 'init', '-q', '-b', 'main')
    $nonZero = Invoke-GissueBoundedProcess -FilePath 'git' -ArgumentList @('-C', $repoA, 'rev-parse', '--verify', '--quiet', 'refs/heads/definitely-not-a-branch') -TimeoutSec 30
    Assert-True ($nonZero.Started -and -not $nonZero.TimedOut) 'A-5 0 아닌 종료도 TimedOut=$false 로 돌아온다'
    Assert-True ($nonZero.ExitCode -ne 0) 'A-6 0 아닌 종료 코드가 그대로 돌아온다' "ExitCode=$($nonZero.ExitCode)"

    $missing = Invoke-GissueBoundedProcess -FilePath 'gissue-definitely-not-a-real-exe-xyz' -ArgumentList @('--version') -TimeoutSec 5
    Assert-True (-not $missing.Started) 'A-7 없는 실행 파일은 Started=$false'
    Assert-True (-not $missing.TimedOut) 'A-8 없는 실행 파일은 TimedOut=$false'
    Assert-Eq $missing.ExitCode -1 'A-9 없는 실행 파일은 ExitCode=-1'

    # 멈춘 명령 — 같은 엔진으로 30초 sleep 을 띄우고 2초 한도로 끊는다.
    $engine = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh' } else { Join-Path $PSHOME 'powershell.exe' }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hung = Invoke-GissueBoundedProcess -FilePath $engine -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') -TimeoutSec 2
    $sw.Stop()
    Assert-True ($hung.TimedOut) 'A-10 멈춘 명령은 TimedOut=$true'
    Assert-Eq $hung.ExitCode -1 'A-11 멈춘 명령은 ExitCode=-1'
    Assert-True ($sw.Elapsed.TotalSeconds -lt 15) 'A-12 멈춘 명령이 15초 안에 끊긴다(한도 2초 + 여유)' "elapsed=$([int]$sw.Elapsed.TotalSeconds)초"

    # 공백 포함 인자 — 경로에 공백이 있어도 1개 인자로 전달돼야 한다.
    $repoSpace = Join-Path $tempRoot 'repo with space'
    New-Item -ItemType Directory -Path $repoSpace -Force | Out-Null
    Invoke-Git @('-C', $repoSpace, 'init', '-q', '-b', 'main')
    $spaced = Invoke-GissueBoundedProcess -FilePath 'git' -ArgumentList @('-C', $repoSpace, 'rev-parse', '--show-toplevel') -TimeoutSec 30
    Assert-True ($spaced.ExitCode -eq 0) 'A-13 공백 포함 경로 인자도 정상 실행된다' "$($spaced.StdErr)".Trim()
    Assert-True ("$($spaced.StdOut)".Trim() -eq $repoSpace) 'A-14 공백 포함 경로가 1개 인자로 전달된다' "$($spaced.StdOut)".Trim()

    # 출력 배수(drain) 회귀 — WaitForExit(타임아웃)만으로는 리다이렉트 출력이
    # 파일에 다 쓰이기 전에 반환될 수 있어(특히 Unix 파이프+펌프) stdout 이
    # 비어 읽히는 경우가 있다. 20회 반복 호출이 매번 온전한 stdout 을 돌려줘야 한다.
    Invoke-Git @('-C', $repoSpace, 'remote', 'add', 'origin', 'https://example.invalid/someowner/repo-space.git')
    $drainFails = 0
    for ($d = 1; $d -le 20; $d++) {
        $drainCall = Invoke-GissueBoundedProcess -FilePath 'git' -ArgumentList @('-C', $repoSpace, 'remote', 'get-url', 'origin') -TimeoutSec 30
        if ($drainCall.ExitCode -ne 0 -or "$($drainCall.StdOut)".Trim() -ne 'https://example.invalid/someowner/repo-space.git') { $drainFails++ }
    }
    Assert-Eq $drainFails 0 'A-15 반복 git 호출 20회 모두 온전한 stdout 을 돌려준다' "실패 $drainFails/20회"

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'B. Resolve-GissueBoundedCallTimeoutSec'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = $null
    $env:GISSUE_GIT_CALL_TIMEOUT_SEC = $null
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Gh) 60 'B-1 Gh 기본값 60초'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Git) 30 'B-2 Git 기본값 30초'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = '7'
    $env:GISSUE_GIT_CALL_TIMEOUT_SEC = '9'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Gh) 7 'B-3 env 가 Gh 한도를 재정의한다'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Git) 9 'B-4 env 가 Git 한도를 재정의한다'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = 'abc'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Gh) 60 'B-5 비숫자 env 는 기본값으로 떨어진다'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = '0'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Gh) 60 'B-6 0 env 는 기본값으로 떨어진다'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = '-5'
    Assert-Eq (Resolve-GissueBoundedCallTimeoutSec -Kind Gh) 60 'B-7 음수 env 는 기본값으로 떨어진다'
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = $null
    $env:GISSUE_GIT_CALL_TIMEOUT_SEC = $null

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'C. Get-GissueMergedBranchSet — 멈추는 gh 가 타임아웃 안에 끊긴다'
    # 가짜 gh: PATH 맨 앞에 두고 30초 잔다. 실제 gh 가 아니라 이 스크립트가 불려야 한다.
    $fakeBin = Join-Path $tempRoot 'fakebin'
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        $fakeGh = Join-Path $fakeBin 'gh.cmd'
        Set-Content -LiteralPath $fakeGh -Value "@echo off`r`npowershell -NoProfile -Command `"Start-Sleep -Seconds 30`"`r`n" -Encoding ASCII
    } else {
        $fakeGh = Join-Path $fakeBin 'gh'
        Set-Content -LiteralPath $fakeGh -Value "#!/bin/sh`nexec sleep 30`n" -Encoding ASCII
        & chmod +x $fakeGh
    }
    $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $env:PATH
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = '2'

    $repoC = Join-Path $tempRoot 'repo-fake-origin'
    New-Item -ItemType Directory -Path $repoC -Force | Out-Null
    Invoke-Git @('-C', $repoC, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $repoC, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $repoC, 'config', 'user.name', 'bounded-test')
    Invoke-Git @('-C', $repoC, 'remote', 'add', 'origin', 'https://example.invalid/someowner/somerepo.git')
    Set-Content -LiteralPath (Join-Path $repoC 'README.md') -Value 'bounded test' -Encoding UTF8
    Invoke-Git @('-C', $repoC, 'add', '-A')
    Invoke-Git @('-C', $repoC, 'commit', '-q', '-m', 'init')

    $logC = New-Object System.Collections.ArrayList
    $loggerC = { param($m) [void]$logC.Add([string]$m); Write-Output $m }
    $swC = [System.Diagnostics.Stopwatch]::StartNew()
    $setC = Get-GissueMergedBranchSet -RepoPath $repoC -Log $loggerC
    $swC.Stop()
    Assert-True (@($setC).Count -eq 1) 'C-1 반환값은 정확히 1개 객체' "count=$(@($setC).Count)"
    Assert-True ($setC.Ok -eq $false) 'C-2 멈추는 gh 면 Ok=$false (fail-closed)'
    Assert-Eq $setC.Branches.Count 0 'C-3 멈추는 gh 면 브랜치 집합은 비어 있다'
    Assert-True ($swC.Elapsed.TotalSeconds -lt 20) 'C-4 멈추는 gh 조회가 20초 안에 돌아온다(한도 2초 + 여유)' "elapsed=$([int]$swC.Elapsed.TotalSeconds)초"
    Assert-True (@($logC | Where-Object { $_ -match '시간 초과' }).Count -ge 1) 'C-5 시간 초과 로그가 남는다' ($logC -join ' | ')

    # C-6~C-9 — 바로 실패하는 gh(종료 1): 실패 경로의 출력 결합($ghOut)도 throw 없이
    # WARN 로그를 남기고 Ok=$false 로 돌아와야 한다. `@(...) | Where-Object { $_ }
    # -join` 에 괄호가 없으면 -join 이 Where-Object 의 인자로 해석돼 throw 한다
    # (2026-11-25 실측 회귀) — 이 케이스가 그 재발을 막는다.
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        Set-Content -LiteralPath $fakeGh -Value "@echo off`r`nexit /b 1`r`n" -Encoding ASCII
    } else {
        Set-Content -LiteralPath $fakeGh -Value "#!/bin/sh`nexit 1`n" -Encoding ASCII
    }
    # C 와 다른 레포를 쓴다 — 프로세스 내 캐시가 C 의 실패 결과를 돌려주면 gh 가
    # 다시 불리지 않아 실패 경로를 타지 않기 때문이다.
    $repoC2 = Join-Path $tempRoot 'repo-fake-origin-c2'
    New-Item -ItemType Directory -Path $repoC2 -Force | Out-Null
    Invoke-Git @('-C', $repoC2, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $repoC2, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $repoC2, 'config', 'user.name', 'bounded-test')
    Invoke-Git @('-C', $repoC2, 'remote', 'add', 'origin', 'https://example.invalid/someowner/somerepo-c2.git')
    Set-Content -LiteralPath (Join-Path $repoC2 'README.md') -Value 'bounded test c2' -Encoding UTF8
    Invoke-Git @('-C', $repoC2, 'add', '-A')
    Invoke-Git @('-C', $repoC2, 'commit', '-q', '-m', 'init')
    $logC2 = New-Object System.Collections.ArrayList
    $loggerC2 = { param($m) [void]$logC2.Add([string]$m) }
    $setC2 = Get-GissueMergedBranchSet -RepoPath $repoC2 -Log $loggerC2
    Assert-True (@($setC2).Count -eq 1) 'C-6 반환값은 정확히 1개 객체' "count=$(@($setC2).Count)"
    Assert-True ($setC2.Ok -eq $false) 'C-7 바로 실패하는 gh 면 Ok=$false (fail-closed)'
    Assert-Eq $setC2.Branches.Count 0 'C-8 바로 실패하는 gh 면 브랜치 집합은 비어 있다'
    Assert-True (@($logC2 | Where-Object { $_ -match 'gh pr list --state merged 실패' }).Count -ge 1) 'C-9 gh 실패 WARN 로그가 남는다' ($logC2 -join ' | ')
    # D 를 위해 멈추는 가짜 gh 로 되돌린다.
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        Set-Content -LiteralPath $fakeGh -Value "@echo off`r`npowershell -NoProfile -Command `"Start-Sleep -Seconds 30`"`r`n" -Encoding ASCII
    } else {
        Set-Content -LiteralPath $fakeGh -Value "#!/bin/sh`nexec sleep 30`n" -Encoding ASCII
        & chmod +x $fakeGh
    }

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'D. Invoke-GissueWorktreeCleanupForRepo — 멈추는 gh 에도 정상 반환하고 삭제하지 않는다'
    # C 와 다른 레포를 쓴다 — 머지판정의 프로세스 내 캐시가 C 의 실패 결과를 그대로
    # 돌려주면 D 에서 gh 가 다시 불리지 않아 '시간 초과' 로그가 남지 않기 때문이다.
    $repoD = Join-Path $tempRoot 'repo-d'
    New-Item -ItemType Directory -Path $repoD -Force | Out-Null
    Invoke-Git @('-C', $repoD, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $repoD, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $repoD, 'config', 'user.name', 'bounded-test')
    Invoke-Git @('-C', $repoD, 'remote', 'add', 'origin', 'https://example.invalid/someowner/somerepo-d.git')
    Set-Content -LiteralPath (Join-Path $repoD 'README.md') -Value 'bounded test d' -Encoding UTF8
    Invoke-Git @('-C', $repoD, 'add', '-A')
    Invoke-Git @('-C', $repoD, 'commit', '-q', '-m', 'init')
    # 5시간 전 clean worktree 1건 — 머지판정이 실패하면 MANUAL-REVIEW 로 보류돼야 한다.
    $wtD = Join-Path $tempRoot 'wt-d-old-01'
    Invoke-Git @('-C', $repoD, 'worktree', 'add', '-q', '-b', 'feat/d-old-01', $wtD, 'main')
    $oldUtc = [datetime]::UtcNow.AddHours(-5)
    foreach ($p in @($wtD, (Join-Path (Join-Path (Join-Path $repoD '.git') 'worktrees') 'wt-d-old-01'))) {
        $stack = New-Object System.Collections.Stack
        $stack.Push($p)
        while ($stack.Count -gt 0) {
            $d = $stack.Pop()
            try { [System.IO.Directory]::SetLastWriteTimeUtc($d, $oldUtc) } catch {}
            try {
                foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($d)) {
                    try { [System.IO.Directory]::SetLastWriteTimeUtc($e, $oldUtc) } catch {}
                    try { [System.IO.File]::SetLastWriteTimeUtc($e, $oldUtc) } catch {}
                    if ([System.IO.File]::GetAttributes($e) -band [System.IO.FileAttributes]::Directory) { $stack.Push($e) }
                }
            } catch {}
        }
    }
    $logD = New-Object System.Collections.ArrayList
    $loggerD = { param($m) [void]$logD.Add([string]$m) }
    $rD = $null
    $threwD = $false
    $swD = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-GissueWorktreeCleanupForRepo -RepoPath $repoD -Log $loggerD `
            -DeleteRemoteBranch $false -TimeBudgetSec 300 -ResultRef ([ref]$rD)
    } catch { $threwD = $true }
    $swD.Stop()
    Assert-True (-not $threwD) 'D-1 멈추는 gh 에도 throw 하지 않는다(정상 반환)'
    Assert-True ($null -ne $rD) 'D-2 결과가 [ref] 로 돌아온다'
    Assert-True ($swD.Elapsed.TotalSeconds -lt 25) 'D-3 정리 단계가 25초 안에 끝난다(한도 2초 + 여유)' "elapsed=$([int]$swD.Elapsed.TotalSeconds)초"
    Assert-Eq (@($rD.Removed).Count) 0 'D-4 멈추는 gh 면 삭제 0건'
    Assert-True (@($rD.ManualReview).Count -ge 1) 'D-5 해당 항목이 MANUAL-REVIEW 로 보류된다' "ManualReview=$(@($rD.ManualReview).Count)"
    Assert-True (@($rD.ManualReview | Where-Object { $_.Reason -match '머지된 PR 목록 조회 실패' }).Count -ge 1) 'D-6 보류 사유가 머지판정 조회 실패이다' ((@($rD.ManualReview) | ForEach-Object { $_.Reason }) -join ' | ')
    Assert-True (Test-Path -LiteralPath $wtD) 'D-7 보류된 worktree 가 디스크에 그대로 있다'
    Assert-True (-not $rD.Aborted) 'D-8 타임아웃은 Aborted(CRITICAL 중단)가 아니다'
    Assert-True (@($logD | Where-Object { $_ -match '시간 초과' }).Count -ge 1) 'D-9 시간 초과 로그가 남는다' ($logD -join ' | ')

    # ──────────────────────────────────────────────────────────────────────────
    Write-Output ''
    Write-Output 'E. Invoke-GissueWorktreeCleanupForRepo — 머지+idle worktree 는 실제로 삭제된다(성공 경로)'
    # 가짜 gh 를 PATH 에서 빼고 머지판정을 스텁한다 — 실제 `git worktree remove`
    # 성공 경로($rmOut 결합 포함)가 throw 없이 Removed 를 기록하는지 확인한다.
    # (2026-11-25 실측: 같은 괄호 누락이 remove 성공 직후 throw 해, 디렉터리는
    #  지워졌는데 Removed 가 비는 회귀가 있었다 — test-stale-code-guard B-1b 가
    #  잡아냈고 이 케이스가 고정한다.)
    $env:PATH = $script:SavedPath
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = $null
    function Get-GissueMergedBranchSet {
        param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        [void]$set.Add('feat/e-old-01')
        return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/bounded'; Branches = $set }
    }
    # 엔진 레포와 worktree 는 서로 다른 부모 폴더에 둔다 — 삭제 직후 인접 nested repo
    # 무결성 재검증에서 방금 지운 worktree 자신이 잡혀 CRITICAL 오탐이 나는 것을
    # 피하기 위해서다(test-stale-code-guard B-1 과 같은 구조).
    $engineE = Join-Path (Join-Path $tempRoot 'engines') 'engine-e'
    $wtE = Join-Path (Join-Path $tempRoot 'wts') 'wt-e-old-01'
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'engines') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'wts') -Force | Out-Null
    New-Item -ItemType Directory -Path $engineE -Force | Out-Null
    Invoke-Git @('-C', $engineE, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $engineE, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $engineE, 'config', 'user.name', 'bounded-test')
    Invoke-Git @('-C', $engineE, 'remote', 'add', 'origin', 'https://example.invalid/test/bounded-e.git')
    Set-Content -LiteralPath (Join-Path $engineE 'README.md') -Value 'bounded test e' -Encoding UTF8
    Invoke-Git @('-C', $engineE, 'add', '-A')
    Invoke-Git @('-C', $engineE, 'commit', '-q', '-m', 'init')
    Invoke-Git @('-C', $engineE, 'worktree', 'add', '-q', '-b', 'feat/e-old-01', $wtE, 'main')
    $oldUtcE = [datetime]::UtcNow.AddHours(-5)
    foreach ($p in @($wtE, (Join-Path (Join-Path (Join-Path $engineE '.git') 'worktrees') 'wt-e-old-01'))) {
        $stack = New-Object System.Collections.Stack
        $stack.Push($p)
        while ($stack.Count -gt 0) {
            $d = $stack.Pop()
            try { [System.IO.Directory]::SetLastWriteTimeUtc($d, $oldUtcE) } catch {}
            try {
                foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($d)) {
                    try { [System.IO.Directory]::SetLastWriteTimeUtc($e, $oldUtcE) } catch {}
                    try { [System.IO.File]::SetLastWriteTimeUtc($e, $oldUtcE) } catch {}
                    if ([System.IO.File]::GetAttributes($e) -band [System.IO.FileAttributes]::Directory) { $stack.Push($e) }
                }
            } catch {}
        }
    }
    $logE = New-Object System.Collections.ArrayList
    $loggerE = { param($m) [void]$logE.Add([string]$m) }
    $rE = $null
    $threwE = $false
    try {
        Invoke-GissueWorktreeCleanupForRepo -RepoPath $engineE -Log $loggerE `
            -DeleteRemoteBranch $false -TimeBudgetSec 300 -ResultRef ([ref]$rE)
    } catch { $threwE = $true }
    Assert-True (-not $threwE) 'E-1 실제 삭제 경로에서 throw 하지 않는다'
    Assert-True (@($rE.Removed).Count -ge 1) 'E-2 머지+idle worktree 가 Removed 에 기록된다' "Removed=$(@($rE.Removed | ForEach-Object { $_.Path }) -join ', ')"
    Assert-True (-not (Test-Path -LiteralPath $wtE)) 'E-3 worktree 디렉터리가 실제로 사라진다'
    Assert-True (@($logE | Where-Object { $_ -match '삭제 중 예외' }).Count -eq 0) 'E-4 삭제 중 예외 로그가 없다' ($logE -join ' | ')
} finally {
    $env:GISSUE_GH_CACHE_DIR = $script:SavedCacheDir
    $env:GISSUE_GH_CALL_TIMEOUT_SEC = $script:SavedGhTimeout
    $env:GISSUE_GIT_CALL_TIMEOUT_SEC = $script:SavedGitTimeout
    $env:PATH = $script:SavedPath
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false }
}

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
Write-Output "ALL PASS ($($script:Pass) 건)"
exit 0
