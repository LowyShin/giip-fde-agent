# test-worktree-ancestry-general-guard.ps1 — 일반 worktree 조상(ancestry) 정리 경로 회귀 테스트 (giip 6401/6423)
#
# 왜 필요한가:
#   `worktree-safety.ps1` 의 `Invoke-GissueWorktreeCleanupForRepo` 는 머지판정을
#   `gh pr list --state merged --json headRefName` 로 한다 — 즉 **PR 헤드 브랜치 이름**만 준다.
#   PR 이 없는 로컬 전용 검증 브랜치나 PR 헤드 이름과 로컬 브랜치 이름이 다른 경우, 그 worktree 는
#   PR 게이트만으로는 **영영** '미머지' 로 남는다 → 정리 대상 0건 → 무한 누적의 잔류 경로.
#   실측(giip 6401, 2026-11-26): 이 레포 잔여 worktree 5건 **전부** HEAD 가 origin/main 의 조상
#   (= 커밋된 내용이 이미 main 에 있음)인데도 5건 전부 MANUAL-REVIEW 였다.
#
#   그래서 "고유 커밋 없음"(조상) 판정을 **모든 worktree** 에 병행하고(giip 5175 의 확장),
#   ★ **하한선**을 함께 박는다: 조상 판정은 *커밋된 내용*만 증명한다 — **미커밋 산출물은 증명에
#   포함되지 않는다**. 그래서 이 경로는 dirty 판정을 엄격하게 태워야 한다(미커밋 1건이라도 보류).
#   이 테스트는 그 하한선을 기계로 고정한다.
#
# 고정하는 것(양방향):
#   A. 일반 worktree 3종으로 엔진 경로 검증
#      - wt-anc-clean : HEAD 가 origin/main 의 조상 + clean + 오래됨 → **정리 대상**이어야 한다
#      - wt-anc-dirty : HEAD 가 origin/main 의 조상 + **미커밋 산출물 있음** → **보류**되어야 한다
#      - wt-anc-unmerged : 고유 커밋이 main 에 없음 → **보류**되어야 한다
#      - wt-pr-dirty  : PR 머지 게이트 통과 + dirty → 기존 동작 유지(진행) — surgical 확인
#   B. 격리 계열(`.claude/worktrees`)의 기존 동작이 깨지지 않았는지 확인(회귀)
#
# 재현 조건:
#   머지판정은 스텁한다 — 이 시리즈가 검증하는 것은 PR 게이트가 아니라 **조상 판정 + dirty 하한선**이라
#   PR 목록에는 아무것도 없는(= 미머지) 상태로 만든다. 그래야 조상 판정이 실제로 발동한다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-worktree-ancestry-general-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-ancestry-wt-test-<pid>`)에만 레포/worktree 를 만든다 —
# 살아있는 체크아웃이나 D:\temp\worktrees 를 절대 건드리지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$SafetyLib = Join-Path $PSScriptRoot '..\worktree-safety.ps1'
$SafetyLib = (Resolve-Path -LiteralPath $SafetyLib).Path
. $SafetyLib

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

Write-Output 'A. 일반 worktree 조상(ancestry) 경로 + dirty 하한선'

# ── 테스트 저장소 준비 ──
$tempRootLong = (Get-Item -LiteralPath $env:TEMP).FullName
$root = Join-Path $tempRootLong ("gissue-ancestry-wt-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$repo = Join-Path $root 'repo'
$origin = Join-Path $root 'origin.git'
New-Item -ItemType Directory -Path $repo -Force | Out-Null

function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

Invoke-Git @('init', '-q', '--bare', $origin)
Invoke-Git @('-C', $repo, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo, 'config', 'user.name', 'ancestry-wt-test')
Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', $origin)
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'ancestry general guard test' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'init')
Invoke-Git @('-C', $repo, 'push', '-q', 'origin', 'main')

# ── worktree 4종 ──
#   wt-anc-clean    : 조상 + clean + 오래됨                     → 정리 대상이어야 한다
#   wt-anc-dirty    : 조상 + 미커밋 산출물                        → 보류되어야 한다(★하한선)
#   wt-anc-unmerged : 고유 커밋이 main 에 없음                   → 보류되어야 한다
#   wt-pr-dirty     : PR 머지 게이트 통과 + dirty                → 기존 동작 유지(진행)
$wtClean = Join-Path $root 'wt-anc-clean'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'local/only-clean', $wtClean, 'main')

$wtDirty = Join-Path $root 'wt-anc-dirty'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'local/only-dirty', $wtDirty, 'main')
Set-Content -LiteralPath (Join-Path $wtDirty 'UNCOMMITTED-OUTPUT.md') -Value 'other session output' -Encoding UTF8

$wtUnmerged = Join-Path $root 'wt-anc-unmerged'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'local/only-unmerged', $wtUnmerged, 'main')
Set-Content -LiteralPath (Join-Path $wtUnmerged 'UNIQUE.txt') -Value 'unique work' -Encoding UTF8
Invoke-Git @('-C', $wtUnmerged, 'add', '-A')
Invoke-Git @('-C', $wtUnmerged, 'commit', '-q', '-m', 'work not merged yet')

function Set-TreeAge([string]$Path, [datetime]$Utc) {
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    $all = New-Object System.Collections.ArrayList
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        [void]$all.Add($d)
        foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($d)) {
            [void]$all.Add($e)
            if ([System.IO.File]::GetAttributes($e) -band [System.IO.FileAttributes]::Directory) { $stack.Push($e) }
        }
    }
    foreach ($p in $all) {
        try {
            if ([System.IO.Directory]::Exists($p)) { [System.IO.Directory]::SetLastWriteTimeUtc($p, $Utc) }
            else { [System.IO.File]::SetLastWriteTimeUtc($p, $Utc) }
        } catch {}
    }
}

$oldUtc = [datetime]::UtcNow.AddHours(-8)
foreach ($n in @('wt-anc-clean', 'wt-anc-dirty', 'wt-anc-unmerged')) {
    Set-TreeAge (Join-Path $root $n) $oldUtc
    Set-TreeAge (Join-Path $repo ".git\worktrees\$n") $oldUtc
}

# 머지판정 스텁 — PR 목록 비어있음(= 미머지). 조상 판정이 실제로 발동해야 한다.
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/ancestry-wt-guard'; Branches = $set }
}

# ── 1차 실행: PR 목록이 비어 있음(= 조상 판정 경로) ──
$logLines = New-Object System.Collections.ArrayList
$logger = { param($m) [void]$logLines.Add([string]$m) }
$r = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger `
    -DeleteRemoteBranch $false -ResultRef ([ref]$r)

$log = ($logLines -join "`n")
Write-Output '  --- 엔진 로그(1차: 조상 경로) ---'
foreach ($l in $logLines) { Write-Output "  | $l" }
Write-Output '  ---------------------------------'

$removedPaths = @($r.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$manualPaths = @($r.ManualReview | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$cleanNorm    = (Resolve-Path -LiteralPath $wtClean).Path.TrimEnd('\', '/')
$dirtyNorm    = (Resolve-Path -LiteralPath $wtDirty).Path.TrimEnd('\', '/')
$unmergedNorm = (Resolve-Path -LiteralPath $wtUnmerged).Path.TrimEnd('\', '/')

# A-1 조상 + clean + 오래됨 → 정리 대상
Assert-True ($removedPaths -contains $cleanNorm) 'A-1 일반 worktree(조상+clean) 는 정리 대상' "Removed=$($removedPaths -join ', ')"
Assert-True ($log -match 'MERGED-BY-ANCESTRY') 'A-1b 조상 판정 로그가 남는다' ''
# A-1c clean 경로가 "dirty 였다" 플래그를 켜지 않는다 — 그 플래그는 `git worktree remove` 실패 시
#      `--force` 재시도 분기의 조건이고, rule 57 은 `--force` 를 금지한다(조상 경로는 clean 이므로
#      remove 실패는 그 자체로 수동 확인 대상이다).
Assert-True ($log -match '조상 판정 경로: 미커밋 산출물 없음\(clean\) 확인됨') 'A-1c clean 확인 사실이 로그로 남는다' ''
Assert-True ($log -notmatch 'dirty 상태였음') 'A-1d 조상 clean 경로가 dirty 플래그를 켜지 않는다(--force 재시도 방지)' ''

# A-2 ★하한선★ 조상이지만 미커밋 산출물이 있으면 **보류**(삭제 금지)
Assert-True ($removedPaths -notcontains $dirtyNorm) 'A-2 일반 worktree(조상+미커밋 산출물) 는 보류' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $dirtyNorm) 'A-2b 대신 수동확인 목록에 든다' "Manual=$($manualPaths -join ', ')"
$dirtyReasons = @($r.ManualReview | Where-Object { ([string]$_.Path).TrimEnd('\','/') -eq $dirtyNorm } | ForEach-Object { [string]$_.Reason }) -join ' | '
Assert-True ($dirtyReasons -match '미커밋') 'A-2c 보류 사유가 "미커밋" 임을 명시한다' "Reason=$dirtyReasons"

# A-3 고유 커밋 미반영 → 보류
Assert-True ($removedPaths -notcontains $unmergedNorm) 'A-3 일반 worktree(고유 커밋 미반영) 는 보류' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $unmergedNorm) 'A-3b 대신 수동확인 목록에 든다' "Manual=$($manualPaths -join ', ')"

# ── 2차 실행: PR 머지 게이트를 통과한 경로 — 기존 동작 유지(surgical) ──
#   wt-pr-dirty 는 PR 목록에 브랜치 이름이 들어 있는 상태 → 머지 게이트 통과 → 기존과 같이 진행.
#   (조상 판정 경로가 아니므로 dirty 여도 진행 — 이 "기존 동작 유지"를 고정한다)
$wtPrDirty = Join-Path $root 'wt-pr-dirty'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'feat/pr-merged-dirty', $wtPrDirty, 'main')
Set-Content -LiteralPath (Join-Path $wtPrDirty 'UNCOMMITTED-OUTPUT.md') -Value 'scratch' -Encoding UTF8
Set-TreeAge $wtPrDirty $oldUtc
Set-TreeAge (Join-Path $repo '.git\worktrees\wt-pr-dirty') $oldUtc

function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$set.Add('feat/pr-merged-dirty')
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/ancestry-wt-guard'; Branches = $set }
}

$logLines2 = New-Object System.Collections.ArrayList
$logger2 = { param($m) [void]$logLines2.Add([string]$m) }
$r2 = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger2 `
    -DeleteRemoteBranch $false -ResultRef ([ref]$r2)
$removedPaths2 = @($r2.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$prDirtyNorm = (Resolve-Path -LiteralPath $wtPrDirty).Path.TrimEnd('\', '/')
Assert-True ($removedPaths2 -contains $prDirtyNorm) 'A-4 PR 머지 게이트 통과 경로의 기존 동작 유지(dirty 여도 진행)' "Removed=$($removedPaths2 -join ', ')"

# ── 3. 격리 계열 회귀: `.claude/worktrees` 가 계속 조상 판정을 받는가 ──
Write-Output ''
Write-Output 'B. 격리 계열 회귀(기존 동작 유지)'
$wtClaude = Join-Path $repo '.claude\worktrees\agent-eeeeeeeeeeeeeeee'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'worktree-agent-eeeeeeeeeeeeeeee', $wtClaude, 'main')
Set-TreeAge $wtClaude $oldUtc
Set-TreeAge (Join-Path $repo '.git\worktrees\agent-eeeeeeeeeeeeeeee') $oldUtc
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/ancestry-wt-guard'; Branches = $set }
}
$logLines3 = New-Object System.Collections.ArrayList
$logger3 = { param($m) [void]$logLines3.Add([string]$m) }
$r3 = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger3 `
    -DeleteRemoteBranch $false -ResultRef ([ref]$r3)
$removedPaths3 = @($r3.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$claudeNorm = (Resolve-Path -LiteralPath $wtClaude).Path.TrimEnd('\', '/')
Assert-True ($removedPaths3 -contains $claudeNorm) 'B-1 격리 계열 조상 판정 경로가 유지된다' "Removed=$($removedPaths3 -join ', ')"

# ── 4. DryRun 은 실제로 아무것도 지우지 않는다 ──
Assert-True (Test-Path -LiteralPath $wtClean) 'B-2 DryRun 은 실제 삭제하지 않음(조상 clean)' ''
Assert-True (Test-Path -LiteralPath $wtDirty) 'B-3 DryRun 은 실제 삭제하지 않음(미커밋 산출물)' ''

# ── 정리: 이 테스트가 만든 임시 레포만 제거한다(rule 55 — 링크 선검사 후 삭제) ──
try {
    if (Test-GissueWorktreeHasLink $root) {
        Write-Output "  NOTE: 임시 레포에 링크가 감지되어 자동 삭제하지 않음 — 수동 확인: $root"
    } else {
        Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false
    }
} catch {
    Write-Output "  NOTE: 임시 레포 정리 실패(무해) — $($_.Exception.Message) / 경로: $root"
}

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
