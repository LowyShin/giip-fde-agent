# test-worktree-claude-session-guard.ps1 — `.claude/worktrees` 격리 worktree 정리 게이트 회귀 테스트 (giip 5175)
#
# 왜 필요한가:
#   Claude Code 의 `isolation: worktree` 가 만드는 `<repo>/.claude/worktrees/agent-*` 는
#   `worktree-safety.ps1` 에서 **무조건 skip** 됐다("Claude Code 자체 세션 격리 메커니즘이라
#   완전히 별개 — 항상 제외"). 그 결과 어떤 자동 정리 경로에도 잡히지 않아 레포당 수십 개가
#   누적됐다(2026-11-13 실측: lowyworkenv `.claude/worktrees` 27건 + D:/temp/worktrees 60여 건).
#   "클릭 한 번으로 정리된다"를 목표로 하면 위험하므로, **같은 안전 요건을 적용한 뒤에도
#   살아 있는 것만 정리되는지**를 기계로 고정한다.
#
# 고정하는 것(양방향):
#   A. 순수 판정 2종
#      - Test-GissueWorktreeContentInMain : HEAD 가 origin/main 의 조상인가(fail-closed 3종)
#      - Get-GissueWorktreeDirtyPaths      : 격리 메커니즘 부산물만 제외되는가 / 실 산출물은 남는가
#   B. 엔진 경로(Invoke-GissueWorktreeCleanupForRepo -DryRun) — 실제 git 레포 + 실제 worktree 로
#      정리 대상(누적 잔해) 과 보호 대상(진행 중·미반영·미커밋 산출물) 을 함께 검증한다.
#
# 재현 조건(중요):
#   격리 worktree 의 미커밋 변경이 현실에서 어떻게 보이는지 그대로 재현한다 —
#   `.claude/settings.local.json` 이 **추적 파일**인 상태에서 수정된 형태(실측 lowyworkenv 와 동일).
#   (이 PC 는 `~/.config/git/ignore` 에 `**/.claude/settings.local.json` 가 있어, 추적되지 않은
#   같은 이름 파일은 애초에 status 에 나타나지 않는다 — 그래서 "추적 파일" 로 만들어 재현한다.)
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-worktree-claude-session-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-claude-wt-test-<pid>`)에만 레포/worktree 를 만든다 —
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

# ──────────────────────────────────────────────────────────────────────────────
# A. 순수 판정 회귀
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 순수 판정'

# ── 테스트 저장소 준비 (A-1 에서도 쓰므로 먼저 만든다) ──
$tempRootLong = (Get-Item -LiteralPath $env:TEMP).FullName
$root = Join-Path $tempRootLong ("gissue-claude-wt-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$repo = Join-Path $root 'repo'
$origin = Join-Path $root 'origin.git'
New-Item -ItemType Directory -Path $repo -Force | Out-Null

function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

Invoke-Git @('init', '-q', '--bare', $origin)
Invoke-Git @('-C', $repo, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo, 'config', 'user.name', 'claude-wt-test')
Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', $origin)
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'claude worktree guard test' -Encoding UTF8
# 격리 산출물은 **추적 파일**로 둔다 — 현실(lowyworkenv)에서 "미커밋 변경"으로 보이는形态을 재현한다.
New-Item -ItemType Directory -Path (Join-Path $repo '.claude') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $repo '.claude\settings.local.json') -Value '{"permissions":{"allow":[]}}' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
# 이 PC 의 전역 ignore(`~/.config/git/ignore`)에 `**/.claude/settings.local.json` 가 있어
# `add -A` 는 이 파일을 건너뛴다. 현실(lowyworkenv)처럼 **추적 파일**로 만들어 재현해야 하므로 강제 추가.
Invoke-Git @('-C', $repo, 'add', '-f', '.claude/settings.local.json')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'init')
Invoke-Git @('-C', $repo, 'push', '-q', 'origin', 'main')
# 격리 worktree 디렉터리 자체가 주 worktree 에 untracked 로 잡히지 않게 한다(저장소 관례).
Add-Content -LiteralPath (Join-Path $repo '.git\info\exclude') -Value "`n**/.claude/worktrees/`n" -Encoding UTF8

# A-1 HEAD 가 origin/main 의 조상(고유 커밋 없음) → InMain=true
$wtClean = Join-Path $repo '.claude\worktrees\agent-aaaaaaaaaaaaaaaa'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'worktree-agent-aaaaaaaaaaaaaaaa', $wtClean, 'main')
$v = Test-GissueWorktreeContentInMain -RepoPath $repo -WorktreePath $wtClean
Assert-True ($v.Determined -and $v.InMain) 'A-1 HEAD 가 origin/main 의 조상 → InMain=true' "Detail=$($v.Detail)"

# A-2 HEAD 가 origin/main 에 없음(고유 커밋 있음) → Determined=true, InMain=false
$wtUnmerged = Join-Path $repo '.claude\worktrees\agent-bbbbbbbbbbbbbbbb'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'worktree-agent-bbbbbbbbbbbbbbbb', $wtUnmerged, 'main')
Set-Content -LiteralPath (Join-Path $wtUnmerged 'UNIQUE.txt') -Value 'unique work' -Encoding UTF8
Invoke-Git @('-C', $wtUnmerged, 'add', '-A')
Invoke-Git @('-C', $wtUnmerged, 'commit', '-q', '-m', 'subagent work not merged yet')
$v = Test-GissueWorktreeContentInMain -RepoPath $repo -WorktreePath $wtUnmerged
Assert-True ($v.Determined -and (-not $v.InMain)) 'A-2 고유 커밋이 main 에 없음 → InMain=false' "Detail=$($v.Detail)"

# A-3 판정 불가(HEAD 를 못 읽음) → Determined=false (fail-closed)
$v = Test-GissueWorktreeContentInMain -RepoPath $repo -WorktreePath (Join-Path $root 'no-such-worktree')
Assert-True ((-not $v.Determined) -and (-not $v.InMain)) 'A-3 HEAD 판정 불가 → Determined=false(fail-closed)' "Detail=$($v.Detail)"

# A-4 MainRef 가 없으면(미 fetch 등) 판정 불가 → Determined=false (fail-closed)
$v = Test-GissueWorktreeContentInMain -RepoPath $repo -WorktreePath $wtClean -MainRef 'origin/does-not-exist'
Assert-True ((-not $v.Determined) -and (-not $v.InMain)) 'A-4 MainRef 없음 → Determined=false(fail-closed)' "Detail=$($v.Detail)"

# A-5 dirty 판정 — 격리 메커니즘 산출물(`.claude/settings.local.json`)만 있으면 제외된다
Set-Content -LiteralPath (Join-Path $wtClean '.claude\settings.local.json') -Value '{"permissions":{"allow":["Bash(gh *)"]}}' -Encoding UTF8
$dirty = Get-GissueWorktreeDirtyPaths -WorktreePath $wtClean -IgnorePaths $script:GissueClaudeWorktreeInfrastructurePaths
Assert-True (@($dirty.Dirty).Count -eq 0) 'A-5 격리 산출물만 있으면 산출물 dirty 0건' "Dirty=$($dirty.Dirty -join ',')"
Assert-True (@($dirty.Ignored).Count -ge 1) 'A-5b 제외된 경로는 Ignored 로 보고된다(숨기지 않음)' "Ignored=$($dirty.Ignored -join ',')"

# A-6 실 산출물(다른 파일)이 남아 있으면 dirty 로 잡힌다
Set-Content -LiteralPath (Join-Path $wtClean 'REAL-OUTPUT.md') -Value 'real work' -Encoding UTF8
$dirty = Get-GissueWorktreeDirtyPaths -WorktreePath $wtClean -IgnorePaths $script:GissueClaudeWorktreeInfrastructurePaths
Assert-True (@($dirty.Dirty).Count -ge 1) 'A-6 격리 산출물 외 실 산출물은 dirty 로 남는다' "Dirty=$($dirty.Dirty -join ',')"
Remove-Item -LiteralPath (Join-Path $wtClean 'REAL-OUTPUT.md') -Force

# A-7 미추적 **디렉터리**가 통째로(`?? .claude/`) 잡히면 개별 파일로 펼쳐야 경로 매칭이 통한다
#     (접으면 격리 산출물 1개가 "디렉터리 1개"로 뭉개져 이 계열이 영영 정리 대상 0건이 된다)
New-Item -ItemType Directory -Path (Join-Path $wtClean '.claude\state') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $wtClean '.claude\state\other.json') -Value '{}' -Encoding UTF8
$dirty = Get-GissueWorktreeDirtyPaths -WorktreePath $wtClean -IgnorePaths $script:GissueClaudeWorktreeInfrastructurePaths
Assert-True ((@($dirty.Dirty) -join ',') -match 'other\.json') 'A-7 미추적 디렉터리가 개별 파일로 펼쳐진다' "Dirty=$($dirty.Dirty -join ',')"
Remove-Item -LiteralPath (Join-Path $wtClean '.claude\state') -Recurse -Force

# ──────────────────────────────────────────────────────────────────────────────
# B. 엔진 경로 회귀 — 실제 git 레포 + 실제 worktree
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. 엔진(Invoke-GissueWorktreeCleanupForRepo -DryRun) 양방향'

# 격리 worktree 4종을 만든다.
#   wt-clean    : 커밋 0건 + 격리 산출물만 미커밋 + 오래됨        → 정리 대상이어야 한다
#   wt-unmerged : 고유 커밋 있음(미반영)                          → 보호되어야 한다
#   wt-dirty    : 격리 산출물 외에 실 산출물 미커밋               → 보호되어야 한다
#   wt-recent   : 정리 대상 조건은 갖췄으나 최근 활동              → 보호되어야 한다
$wtDirty = Join-Path $repo '.claude\worktrees\agent-cccccccccccccccc'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'worktree-agent-cccccccccccccccc', $wtDirty, 'main')
Set-Content -LiteralPath (Join-Path $wtDirty '.claude\settings.local.json') -Value '{"permissions":{"allow":["Bash(gh *)"]}}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $wtDirty 'REAL-OUTPUT.md') -Value 'real uncommitted work' -Encoding UTF8

$wtRecent = Join-Path $repo '.claude\worktrees\agent-dddddddddddddddd'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'worktree-agent-dddddddddddddddd', $wtRecent, 'main')
Set-Content -LiteralPath (Join-Path $wtRecent '.claude\settings.local.json') -Value '{"permissions":{"allow":["Bash(gh *)"]}}' -Encoding UTF8

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
foreach ($n in @('agent-aaaaaaaaaaaaaaaa', 'agent-bbbbbbbbbbbbbbbb', 'agent-cccccccccccccccc')) {
    Set-TreeAge (Join-Path $repo ".claude\worktrees\$n") $oldUtc
    Set-TreeAge (Join-Path $repo ".git\worktrees\$n") $oldUtc
}
# wt-recent 는 최근 활동 그대로 둔다(관리 디렉터리 mtime 이 '지금').

# 머지판정은 스텁한다 — 이 시리즈에서 검증하는 것은 PR 게이트가 아니라 **고유 커밋 없음** 판정이라
# PR 목록에는 아무것도 없는(= 미머지) 상태로 만든다. 그래야 조상 판정이 실제로 발동한다.
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/claude-wt-guard'; Branches = $set }
}

$logLines = New-Object System.Collections.ArrayList
$logger = { param($m) [void]$logLines.Add([string]$m) }
$r = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger `
    -DeleteRemoteBranch $false -ResultRef ([ref]$r)

$log = ($logLines -join "`n")
Write-Output '  --- 엔진 로그 ---'
foreach ($l in $logLines) { Write-Output "  | $l" }
Write-Output '  -----------------'

$removedPaths = @($r.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$manualPaths = @($r.ManualReview | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$cleanNorm    = (Resolve-Path -LiteralPath $wtClean).Path.TrimEnd('\', '/')
$unmergedNorm = (Resolve-Path -LiteralPath $wtUnmerged).Path.TrimEnd('\', '/')
$dirtyNorm    = (Resolve-Path -LiteralPath $wtDirty).Path.TrimEnd('\', '/')
$recentNorm   = (Resolve-Path -LiteralPath $wtRecent).Path.TrimEnd('\', '/')

# B-1 누적 잔해(커밋 0건 + 격리 산출물만 미커밋 + 오래됨) → 정리 대상이 되어야 한다
Assert-True ($removedPaths -contains $cleanNorm) 'B-1 격리 잔해(고유 커밋 없음+오래됨) 는 정리 대상' "Removed=$($removedPaths -join ', ')"
Assert-True ($log -match 'MERGED-BY-ANCESTRY') 'B-1b 조상 판정 로그가 남는다' ''

# B-2 고유 커밋이 미반영 → 보호(정리 대상 아님)
Assert-True ($removedPaths -notcontains $unmergedNorm) 'B-2 미반영 고유 커밋 worktree 는 보호' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $unmergedNorm) 'B-2b 대신 수동확인 목록에 든다' "Manual=$($manualPaths -join ', ')"

# B-3 실 산출물이 미커밋 → 보호(정리 대상 아님)
Assert-True ($removedPaths -notcontains $dirtyNorm) 'B-3 실 산출물 미커밋 worktree 는 보호' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $dirtyNorm) 'B-3b 대신 수동확인 목록에 든다' "Manual=$($manualPaths -join ', ')"

# B-4 최근 활동 → 보호(idle 가드가 실행 중 에이전트 보호를 겸한다)
Assert-True ($removedPaths -notcontains $recentNorm) 'B-4 최근 활동 worktree 는 보호' "Removed=$($removedPaths -join ', ')"

# B-5 격리 계열이 아닌 일반 worktree 는 기존과 동일하게 "머지 없으면 미머지" 로 남는다
$wtPlain = Join-Path $root 'wt-plain'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'feat/plain', $wtPlain, 'main')
Set-TreeAge $wtPlain $oldUtc
Set-TreeAge (Join-Path $repo '.git\worktrees\wt-plain') $oldUtc
$logLines2 = New-Object System.Collections.ArrayList
$logger2 = { param($m) [void]$logLines2.Add([string]$m) }
$r2 = $null
Invoke-GissueWorktreeCleanupForRepo -RepoPath $repo -DryRun -Log $logger2 `
    -DeleteRemoteBranch $false -ResultRef ([ref]$r2)
$removedPaths2 = @($r2.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$plainNorm = (Resolve-Path -LiteralPath $wtPlain).Path.TrimEnd('\', '/')
Assert-True ($removedPaths2 -notcontains $plainNorm) 'B-5 일반 worktree 는 조상 판정을 받지 않는다(기존 동작 유지)' "Removed=$($removedPaths2 -join ', ')"

# B-6 DryRun 이므로 실제로는 아무것도 사라지지 않아야 한다
Assert-True (Test-Path -LiteralPath $wtClean) 'B-6 DryRun 은 실제 삭제하지 않음(격리 잔해)' ''
Assert-True (Test-Path -LiteralPath $wtDirty) 'B-6b DryRun 은 실제 삭제하지 않음(실 산출물)' ''

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
