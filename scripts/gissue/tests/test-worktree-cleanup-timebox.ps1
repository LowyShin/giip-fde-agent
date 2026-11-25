# test-worktree-cleanup-timebox.ps1 — worktree 정리 시간 한도(타임박스) + stall 마커 회귀 테스트
#
# 왜 필요한가:
#   사후 스윕 WorktreeCleanup 이 시간 한도 없이 동기 실행돼, worktree 가 많은 레포에서
#   한 단계가 수십 분간 멈추고 러너 전체가 붙잡혔다. 사후 스윕 큐의 반복당 예산(90초)은
#   동기 단계 하나를 중간에 끊지 못하므로, 단계 자체에 시간 한도가 필요했다.
#   또 그 실행이 강제종료되면 Complete-Run 이 돌지 않아 stall 사실이 어디에도 남지 않았다.
#
# 고정하는 것:
#   A. 한도 해석(Resolve-GissueWorktreeCleanupBudgetSec) — 기본 180초·명시값·env·무효값
#   B. 엔진(Invoke-GissueWorktreeCleanupForRepo -DryRun) — 작은 한도에 걸리면 멈추고
#      "시간 한도 도달 — 나머지는 다음 실행" 을 남긴 채 정상 반환한다(throw 없음).
#      넉넉한 한도면 전부 처리한다(거짓 만료 없음).
#   C. 멈춘 단계 뒤에도 다음 레포가 진행된다(정상 반환 — 러너가 다음 단계로 간다).
#   D. stall 마커 왕복 — run N 에 쓴 마커가 run N+1 의 요약에 실리고 소비된다.
#   E. 러너 소스 배선 — 래퍼의 예산 전달·마커 쓰기·시작 시 표면화·종료 기록 반영.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-worktree-cleanup-timebox.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리([System.IO.Path]::GetTempPath() 아래)에만 레포/worktree/마커를
# 만든다 — 살아있는 체크아웃이나 호스트 로그 디렉터리를 절대 건드리지 않는다.
# 네트워크/gh 인증 불필요 — 머지판정은 스텁한다.
# 참고: 엔진의 -TimeBudgetSec 은 [double] 이라 테스트에서 0.05초 같은 작은 한도를 줄 수 있다.
#   실제 운용 한도는 초 단위 정수(env·기본값 180초)다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$SafetyLib = Join-Path $PSScriptRoot '..\worktree-safety.ps1'
$SafetyLib = (Resolve-Path -LiteralPath $SafetyLib).Path
. $SafetyLib
$StallLib = Join-Path $PSScriptRoot '..\lib\stall-marker.ps1'
$StallLib = (Resolve-Path -LiteralPath $StallLib).Path
. $StallLib
$SummaryLib = Join-Path $PSScriptRoot '..\lib\run-summary.ps1'
$SummaryLib = (Resolve-Path -LiteralPath $SummaryLib).Path
. $SummaryLib
$runnerFile = Join-Path $PSScriptRoot '..\run-gissue-claude.ps1'
$runnerFile = (Resolve-Path -LiteralPath $runnerFile).Path

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Eq($actual, $expected, $name) {
    Assert-True ($actual -eq $expected) $name "expected [$expected] got [$actual]"
}

# ──────────────────────────────────────────────────────────────────────────────
# A. 한도 해석
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 한도 해석(Resolve-GissueWorktreeCleanupBudgetSec)'
$script:SavedBudgetEnv = $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC
try {
    $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = $null
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null) 180 'A-1 값·env 없음 → 기본 180초'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null 600) 600 'A-2 기본값 인자(스윕 600초)가 통한다'
    $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = '300'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null) 300 'A-3 env 300 → 300초'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec 60) 60 'A-4 명시값 60이 env 300보다 우선'
    $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = 'abc'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null) 180 'A-5 env 비숫자 → 기본 180초'
    $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = '0'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null) 180 'A-6 env 0 → 기본 180초(양의 정수만 유효)'
    $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = '-5'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec $null) 180 'A-7 env 음수 → 기본 180초'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec 0) 180 'A-8 명시값 0 → 기본 180초(0은 "미지정")'
    Assert-Eq (Resolve-GissueWorktreeCleanupBudgetSec ' 120 ') 120 'A-9 앞뒤 공백이 있는 명시값도 해석된다'
} finally {
    if ($null -eq $script:SavedBudgetEnv) { Remove-Item Env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC -ErrorAction SilentlyContinue }
    else { $env:GISSUE_WORKTREE_CLEANUP_BUDGET_SEC = $script:SavedBudgetEnv }
}

# ──────────────────────────────────────────────────────────────────────────────
# B/C. 엔진 경로 — 실제 git 레포 + 실제 worktree (DryRun, 머지판정만 스텁)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B/C. 엔진 시간 한도(실제 git 레포 + worktree, DryRun)'

$tempRootLong = (Get-Item -LiteralPath ([System.IO.Path]::GetTempPath())).FullName
$root = Join-Path $tempRootLong ("gissue-cleanup-timebox-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$repo = Join-Path $root 'repo'
New-Item -ItemType Directory -Path $repo -Force | Out-Null

function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

Invoke-Git @('-C', $repo, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo, 'config', 'user.name', 'timebox-test')
Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', 'https://example.invalid/test/timebox.git')
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'timebox test' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'init')

# 오래된(5시간 전) clean+머지됨 worktree 16건 — 전부 삭제 대상이어야 한다(한도가 없을 때).
$wtCount = 16
$wtPaths = @()
$branchNames = @()
for ($i = 1; $i -le $wtCount; $i++) {
    $name = ('wt-old-{0:D2}' -f $i)
    $branch = ('feat/old-{0:D2}' -f $i)
    $wt = Join-Path $root $name
    Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', $branch, $wt, 'main')
    $wtPaths += $wt
    $branchNames += $branch
}

function Set-TreeAge([string]$Path, [datetime]$Utc) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    $all = New-Object System.Collections.ArrayList
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        [void]$all.Add($d)
        try {
            foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($d)) {
                [void]$all.Add($e)
                if ([System.IO.File]::GetAttributes($e) -band [System.IO.FileAttributes]::Directory) { $stack.Push($e) }
            }
        } catch {}
    }
    foreach ($p in $all) {
        try {
            if ([System.IO.Directory]::Exists($p)) { [System.IO.Directory]::SetLastWriteTimeUtc($p, $Utc) }
            else { [System.IO.File]::SetLastWriteTimeUtc($p, $Utc) }
        } catch {}
    }
}

$oldUtc = [datetime]::UtcNow.AddHours(-5)
foreach ($wt in $wtPaths) {
    Set-TreeAge $wt $oldUtc
    $adminDir = Join-Path (Join-Path (Join-Path $repo '.git') 'worktrees') (Split-Path -Leaf $wt)
    Set-TreeAge $adminDir $oldUtc
}

# 머지판정만 스텁한다 — 네트워크/gh 인증 없이 "16건 전부 머지된 PR 있음" 상태를 만든다.
# dot-source 로 같은 스코프에 들어온 엔진은 호출 시점에 이 정의를 찾는다.
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($b in $script:StubMergedBranches) { [void]$set.Add($b) }
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/timebox'; Branches = $set }
}
$script:StubMergedBranches = $branchNames

# B-1~B-6: 아주 작은 한도(0.05초) — 항목 1건당 git status 1회만으로도 한도를 넘으므로
#   만료는 사실상 확정적이다. 멈추고, skip 줄을 남기고, throw 없이 정상 반환해야 한다.
$logLines = New-Object System.Collections.ArrayList
$logger = { param($m) [void]$logLines.Add([string]$m) }
$rTiny = $null
$threw = $false
try {
    Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger `
        -DeleteRemoteBranch $false -TimeBudgetSec 0.05 -ResultRef ([ref]$rTiny)
} catch { $threw = $true }
$tinyLog = ($logLines -join "`n")
Assert-True (-not $threw) 'B-1 작은 한도에 걸려도 throw 하지 않는다(정상 반환)' ''
Assert-True ($null -ne $rTiny) 'B-2 결과가 [ref] 로 돌아온다' ''
Assert-True ($rTiny.TimeBudgetExpired) 'B-3 TimeBudgetExpired=true' "Processed=$($rTiny.ProcessedCount) Total=$($rTiny.TotalEntries)"
Assert-True ($rTiny.TotalEntries -eq ($wtCount + 1)) 'B-4 전체 항목 수(16건 worktree + 주 worktree 1건)가 기록된다' "Total=$($rTiny.TotalEntries)"
Assert-True ($rTiny.ProcessedCount -lt $rTiny.TotalEntries) 'B-5 처리 건수가 전체보다 적다(중간에 멈춤)' "Processed=$($rTiny.ProcessedCount)"
Assert-True ($rTiny.RemainingCount -gt 0) 'B-6 남은 건수가 0보다 크다' "Remaining=$($rTiny.RemainingCount)"
Assert-True (($rTiny.ProcessedCount + $rTiny.RemainingCount) -eq $rTiny.TotalEntries) 'B-7 처리+남음=전체' "Processed=$($rTiny.ProcessedCount) Remaining=$($rTiny.RemainingCount)"
Assert-True ($tinyLog -match '시간 한도 도달 — 나머지는 다음 실행') 'B-8 skip-and-log 줄("시간 한도 도달 — 나머지는 다음 실행")이 남는다' ''
Assert-True ($tinyLog -match '처리 \d+건, 남음 \d+건') 'B-9 skip 줄에 처리/남음 건수가 들어간다' ''
Assert-True (@($rTiny.Removed).Count -lt $wtCount) 'B-10 작은 한도에서는 16건 전부를 처리하지 않는다' "Removed=$(@($rTiny.Removed).Count)"
Assert-True (-not $rTiny.Aborted) 'B-11 시간 한도 만료는 Aborted(CRITICAL 중단)가 아니다' ''

# B-12~B-15: 넉넉한 한도(300초) — 전부 처리하고 거짓 만료가 없어야 한다.
$logLines2 = New-Object System.Collections.ArrayList
$logger2 = { param($m) [void]$logLines2.Add([string]$m) }
$rBig = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger2 `
    -DeleteRemoteBranch $false -TimeBudgetSec 300 -ResultRef ([ref]$rBig)
$bigLog = ($logLines2 -join "`n")
Assert-True (-not $rBig.TimeBudgetExpired) 'B-12 넉넉한 한도면 만료되지 않는다' ''
Assert-Eq (@($rBig.Removed).Count) $wtCount 'B-13 넉넉한 한도면 16건 전부 처리 대상이다'
Assert-Eq $rBig.RemainingCount 0 'B-14 넉넉한 한도면 남은 건수 0'
Assert-True ($bigLog -notmatch '시간 한도 도달') 'B-15 넉넉한 한도면 skip 줄이 없다' ''
Assert-True ($rBig.TimeBudgetSec -eq 300) 'B-16 결과에 적용된 한도(300초)가 기록된다' "TimeBudgetSec=$($rBig.TimeBudgetSec)"

# B-17: DryRun 은 실제로 아무것도 삭제하지 않는다.
$stillThere = @($wtPaths | Where-Object { Test-Path -LiteralPath $_ }).Count
Assert-Eq $stillThere $wtCount 'B-17 DryRun 은 실제 삭제하지 않는다'

# C. 멈춘 단계 뒤에도 다음 레포가 진행된다 — 두 번째 레포는 넉넉한 한도로 끝까지 돈다.
$repo2 = Join-Path $root 'repo2'
New-Item -ItemType Directory -Path $repo2 -Force | Out-Null
Invoke-Git @('-C', $repo2, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo2, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo2, 'config', 'user.name', 'timebox-test')
Invoke-Git @('-C', $repo2, 'remote', 'add', 'origin', 'https://example.invalid/test/timebox2.git')
Set-Content -LiteralPath (Join-Path $repo2 'README.md') -Value 'timebox test 2' -Encoding UTF8
Invoke-Git @('-C', $repo2, 'add', '-A')
Invoke-Git @('-C', $repo2, 'commit', '-q', '-m', 'init')
$wt2 = Join-Path $root 'wt2-old-01'
Invoke-Git @('-C', $repo2, 'worktree', 'add', '-q', '-b', 'feat/r2-old-01', $wt2, 'main')
Set-TreeAge $wt2 $oldUtc
Set-TreeAge (Join-Path (Join-Path (Join-Path $repo2 '.git') 'worktrees') 'wt2-old-01') $oldUtc
$script:StubMergedBranches = $branchNames + @('feat/r2-old-01')
$logLines3 = New-Object System.Collections.ArrayList
$logger3 = { param($m) [void]$logLines3.Add([string]$m) }
$rSecond = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo2 -DryRun -Log $logger3 `
    -DeleteRemoteBranch $false -TimeBudgetSec 300 -ResultRef ([ref]$rSecond)
Assert-True ($null -ne $rSecond -and -not $rSecond.TimeBudgetExpired) 'C-1 멈춘 단계 뒤의 다음 레포는 정상 완료된다' ''
Assert-Eq (@($rSecond.Removed).Count) 1 'C-2 다음 레포의 삭제 대상 1건이 처리된다'

# ── 정리: 이 테스트가 만든 임시 레포만 제거한다 ──
try {
    if (Test-GissueWorktreeHasLink $root) {
        Write-Output "  NOTE: 임시 레포에 링크가 감지되어 자동 삭제하지 않음 — 수동 확인: $root"
    } else {
        Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false
    }
} catch {
    Write-Output "  NOTE: 임시 레포 정리 실패(무해) — $($_.Exception.Message) / 경로: $root"
}

# ──────────────────────────────────────────────────────────────────────────────
# D. stall 마커 왕복 (run N → run N+1)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'D. stall 마커 왕복(run N → run N+1)'
$markerLogDir = Join-Path $tempRootLong ("gissue-stall-marker-test-$PID")
if (Test-Path -LiteralPath $markerLogDir) { Remove-Item -LiteralPath $markerLogDir -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $markerLogDir -Force | Out-Null
try {
    # D-1~D-3: run N 이 마커를 쓴다.
    $markerPath = Write-GissueStallMarker -LogDir $markerLogDir -Csn '70424' -Phase 'WorktreeCleanup' `
        -ElapsedSec 181 -Processed 3 -Remaining 13 -BudgetSec 180 -RunId 'run-20261125-070700-1234' -Detail '레포=D:\work\example (worktree 항목 단위)'
    Assert-True ($null -ne $markerPath -and (Test-Path -LiteralPath $markerPath)) 'D-1 마커 쓰기가 경로를 돌려주고 파일이 생긴다' "path=$markerPath"
    $parsed = (Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    Assert-Eq $parsed.Phase 'WorktreeCleanup' 'D-2 마커 JSON에 단계가 그대로 실린다'
    Assert-Eq $parsed.Processed 3 'D-2b 마커 JSON에 처리 건수가 실린다'
    Assert-Eq $parsed.Remaining 13 'D-2c 마커 JSON에 남은 건수가 실린다'
    Assert-Eq $parsed.BudgetSec 180 'D-2d 마커 JSON에 예산이 실린다'
    Assert-Eq $parsed.RunId 'run-20261125-070700-1234' 'D-2e 마커 JSON에 실행 ID가 실린다'

    # D-4~D-5: run N+1 이 마커를 읽어 요약으로 만든다.
    $notes = @(Get-GissuePrevStallNotes -LogDir $markerLogDir -Csn '70424')
    Assert-Eq @($notes).Count 1 'D-3 이전 실행 마커 1건이 요약 1건이 된다'
    Assert-True ($notes[0] -match '시간 한도 도달') 'D-4 요약에 "시간 한도 도달"이 들어간다' "note=$($notes[0])"
    Assert-True ($notes[0] -match '처리 3건, 남음 13건') 'D-4b 요약에 처리/남음 건수가 들어간다' "note=$($notes[0])"
    Assert-True ($notes[0] -match 'WorktreeCleanup') 'D-4c 요약에 단계가 들어간다' "note=$($notes[0])"

    # D-6~D-7: 종료 기록 summary 에 실린다(없으면 stall 문구가 없다 — 하위 호환).
    $summaryWith = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' `
        -EnginePath '엔진경로 기록없음' -SyncInfo '없음' -StallNotes $notes
    Assert-True ($summaryWith -match '이전실행 stall 1건') 'D-5 summary에 "이전실행 stall 1건"이 실린다' "summary=$summaryWith"
    Assert-True ($summaryWith -match 'WorktreeCleanup') 'D-5b summary에 stall 단계가 실린다' "summary=$summaryWith"
    $summaryWithout = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' `
        -EnginePath '엔진경로 기록없음' -SyncInfo '없음'
    Assert-True ($summaryWithout -notmatch 'stall') 'D-6 stall 메모가 없으면 summary에 stall 문구가 없다' "summary=$summaryWithout"

    # D-8: 깨진 JSON 마커는 건너뛴다(쓰기 도중 강제종료로 반만 남은 파일).
    $badPath = Get-GissueStallMarkerPath -LogDir $markerLogDir -Csn '70424' -Phase 'WorktreeDailySweep'
    Set-Content -LiteralPath $badPath -Value '{"Phase": "WorktreeDailySweep", "Processed": ' -Encoding UTF8
    $notes2 = @(Get-GissuePrevStallNotes -LogDir $markerLogDir -Csn '70424')
    Assert-Eq @($notes2).Count 1 'D-7 깨진 마커는 건너뛰고 멀쩡한 1건만 요약된다'
    Remove-Item -LiteralPath $badPath -Force -ErrorAction SilentlyContinue

    # D-9~D-10: 종료 기록 뒤 소비(삭제)하면 다음 실행에는 다시 나오지 않는다.
    $cleared = Clear-GissueStallMarkers -LogDir $markerLogDir -Csn '70424'
    Assert-Eq $cleared 1 'D-8 소비(삭제)는 마커 1건을 지운다'
    $notes3 = @(Get-GissuePrevStallNotes -LogDir $markerLogDir -Csn '70424')
    Assert-Eq @($notes3).Count 0 'D-9 소비 뒤에는 이전 실행 stall 요약이 0건이다'

    # D-11: 단계 이름의 경로 주입을 막는다.
    $weirdPath = Get-GissueStallMarkerPath -LogDir $markerLogDir -Csn '70424' -Phase 'a/b\c'
    Assert-True ($weirdPath -match 'a_b_c') 'D-10 단계 이름의 /·\는 _로 치환된다' "path=$weirdPath"
    Assert-True ($weirdPath -notmatch '[\\/]a[\\/]') 'D-10b 치환된 경로에 하위 디렉터리가 생기지 않는다' "path=$weirdPath"

    # D-12: 로그 디렉터리가 없어도 던지지 않는다(fail-open).
    $noThrow = $true
    try {
        $p = Write-GissueStallMarker -LogDir (Join-Path $markerLogDir 'no-such-dir') -Csn '70424' -Phase 'WorktreeCleanup'
        if ($null -ne $p) { $noThrow = $false }
        $n = @(Get-GissuePrevStallNotes -LogDir (Join-Path $markerLogDir 'no-such-dir') -Csn '70424')
        if (@($n).Count -ne 0) { $noThrow = $false }
        $c = Clear-GissueStallMarkers -LogDir (Join-Path $markerLogDir 'no-such-dir') -Csn '70424'
        if ($c -ne 0) { $noThrow = $false }
    } catch { $noThrow = $false }
    Assert-True $noThrow 'D-11 없는 로그 디렉터리에서도 던지지 않는다(쓰기 $null·읽기 0건·삭제 0건)'
} finally {
    try { Remove-Item -LiteralPath $markerLogDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

# ──────────────────────────────────────────────────────────────────────────────
# E. 러너 소스 배선
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'E. 러너 소스 배선'
$src = Get-Content -LiteralPath $runnerFile -Raw -Encoding UTF8
$engineSrc = Get-Content -LiteralPath $SafetyLib -Raw -Encoding UTF8
$summarySrc = Get-Content -LiteralPath $SummaryLib -Raw -Encoding UTF8
Assert-True ($src -match "lib/stall-marker\.ps1") 'E-1 러너가 stall-marker 라이브러리를 적재한다' ''
Assert-True ($src -match 'Invoke-GissueWorktreeCleanupForRepo -RepoPath \$repo -Log \$logger -DryRun:\$DryRunSwitch @idleArgs[\s\S]{0,200}?-TimeBudgetSec \$remainingSec') 'E-2 WorktreeCleanup 래퍼가 엔진에 -TimeBudgetSec 을 넘긴다' ''
Assert-True ($src -match 'Invoke-GissueWorktreeCleanupForRepo -RepoPath \$repo -Log \$logger -DryRun:\$DryRunSwitch @idleArgs[\s\S]{0,200}?-TimeBudgetSec \$sweepRemainingSec') 'E-3 DailySweep 래퍼가 엔진에 -TimeBudgetSec 을 넘긴다' ''
Assert-True ($src -match 'Write-GissueWorktreeCleanupStallMarker \$csn ''WorktreeCleanup''') 'E-4 WorktreeCleanup 만료 시 stall 마커를 쓴다' ''
Assert-True ($src -match 'Write-GissueWorktreeCleanupStallMarker \$csn ''WorktreeDailySweep''') 'E-5 DailySweep 만료 시 stall 마커를 쓴다' ''
Assert-True ($src -match 'Get-GissuePrevStallNotes -LogDir \$LogDir -Csn') 'E-6 실행 시작 시 이전 실행 stall 마커를 읽는다' ''
Assert-True ($src -match '\[STALL-PREV\]') 'E-7 이전 실행 stall 을 [STALL-PREV] 로그로 남긴다' ''
Assert-True ($src -match 'Format-GissueRunEndSummary -Status \$status[\s\S]{0,300}?-StallNotes') 'E-8 종료 기록 조립에 -StallNotes 를 넘긴다' ''
Assert-True ($src -match 'Clear-GissueStallMarkers -LogDir \$LogDir -Csn') 'E-9 종료 기록 뒤 stall 마커를 소비(삭제)한다' ''
Assert-True ($summarySrc -match '\[string\[\]\]\$StallNotes') 'E-10 run-summary 가 StallNotes 파라미터를 받는다' ''
Assert-True ($engineSrc -match '\[double\]\$TimeBudgetSec') 'E-11 엔진이 TimeBudgetSec 파라미터를 받는다' ''
Assert-True ($engineSrc -match '시간 한도 도달 — 나머지는 다음 실행') 'E-12 엔진에 skip-and-log 줄이 있다' ''
Assert-True ($engineSrc -match 'Resolve-GissueWorktreeCleanupBudgetSec') 'E-13 엔진이 한도 해석 함수를 쓴다' ''

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
Write-Output "ALL PASS ($($script:Pass) 건)"
exit 0
