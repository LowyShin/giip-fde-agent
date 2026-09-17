# test-worktree-idle-guard.ps1 — worktree 정리의 "작업 중 세션 보호" 회귀 테스트 (giip #2463)
#
# 왜 필요한가:
#   giip #2445 담당 세션의 worktree 가 작업 도중 삭제됐다. 판정 사유는 `clean+pushed` — 세션이
#   방금 push 해서 워킹트리가 깨끗했을 뿐, CI 대기·머지·이슈 코멘트·사양서 갱신이 남아 있었다.
#   giip #2440 이 idle 가드를 넣었지만 **worktree 트리 안 파일 mtime** 만 봤기 때문에,
#   "파일 편집은 2시간 전, 커밋·push 는 5분 전" 인 세션은 여전히 idle 로 오판돼 삭제된다
#   (커밋/push 는 worktree 안 파일을 건드리지 않는다 — 바뀌는 곳은 `.git/worktrees/<name>/`).
#   그리고 활동시각을 못 구하면 가드를 통째로 건너뛰는 fail-open 이었다.
#
# 고정하는 것(양방향):
#   A. 순수 판정(Test-GissueWorktreeIdleEnough) — 최근/오래됨/판정불가/커밋만 최근인 경우
#   B. 엔진 경로(Invoke-GissueWorktreeCleanupForRepo -DryRun) — 실제 git 레포 + 실제 worktree 로
#      "최근 활동 clean+pushed+머지됨 → 삭제 안 됨" / "오래된 clean+pushed+머지됨 → 삭제 대상" 둘 다.
#      머지판정(`gh pr list`)만 테스트 스코프에서 스텁한다(네트워크 불필요).
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-worktree-idle-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-idle-guard-test-<pid>`)에만 레포/worktree 를 만든다 —
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
# A. 순수 판정 회귀 (Test-GissueWorktreeIdleEnough)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. idle 판정 순수함수'
$now = [datetime]::UtcNow

function New-Activity($determined, $newestUtc, $source = 'tree', $detail = '(test)') {
    [pscustomobject]@{ Determined = $determined; NewestUtc = $newestUtc; Source = $source; Detail = $detail }
}

# A-1 최근(10분 전) → 삭제 금지
$v = Test-GissueWorktreeIdleEnough -Activity (New-Activity $true $now.AddMinutes(-10)) -MinIdleMinutes 120 -NowUtc $now
Assert-True (-not $v.Idle) 'A-1 10분 전 활동 → Idle=false(보호)' "Reason=$($v.Reason)"
Assert-True ($v.Reason -match 'MinIdleMinutes=120') 'A-1 사유에 MinIdleMinutes 표기' "Reason=$($v.Reason)"

# A-2 오래됨(3시간 전) → 삭제 허용
$v = Test-GissueWorktreeIdleEnough -Activity (New-Activity $true $now.AddHours(-3)) -MinIdleMinutes 120 -NowUtc $now
Assert-True ($v.Idle) 'A-2 3시간 전 활동 → Idle=true(정리 진행)' "Reason=$($v.Reason)"

# A-3 판정 불가 → fail-closed(삭제 금지). #2440 구현은 여기서 가드를 건너뛰고 삭제로 갔다.
$v = Test-GissueWorktreeIdleEnough -Activity (New-Activity $false $null) -MinIdleMinutes 120 -NowUtc $now
Assert-True (-not $v.Idle) 'A-3 활동시각 판정불가 → Idle=false(fail-closed)' "Reason=$($v.Reason)"
$v = Test-GissueWorktreeIdleEnough -Activity $null -MinIdleMinutes 120 -NowUtc $now
Assert-True (-not $v.Idle) 'A-3b Activity=$null → Idle=false(fail-closed)' "Reason=$($v.Reason)"

# A-4 giip #2445 시나리오 — 파일은 3시간 전, 커밋/push 는 5분 전(gitadmin 출처)
$v = Test-GissueWorktreeIdleEnough -Activity (New-Activity $true $now.AddMinutes(-5) 'gitadmin') -MinIdleMinutes 120 -NowUtc $now
Assert-True (-not $v.Idle) 'A-4 파일은 오래됐지만 커밋/push 가 5분 전 → 보호' "Reason=$($v.Reason)"
Assert-True ($v.Reason -match 'gitadmin') 'A-4 사유에 출처(gitadmin) 표기' "Reason=$($v.Reason)"

# A-5 가드 비활성(0) → 판정 통과(기존 동작 보존)
$v = Test-GissueWorktreeIdleEnough -Activity (New-Activity $true $now.AddMinutes(-1)) -MinIdleMinutes 0 -NowUtc $now
Assert-True ($v.Idle) 'A-5 MinIdleMinutes=0 이면 가드 비활성' "Reason=$($v.Reason)"

# ──────────────────────────────────────────────────────────────────────────────
# B. 엔진 경로 회귀 — 실제 git 레포 + 실제 worktree
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. 엔진(Invoke-GissueWorktreeCleanupForRepo -DryRun) 양방향'

$root = Join-Path $env:TEMP ("gissue-idle-guard-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$repo = Join-Path $root 'repo'
New-Item -ItemType Directory -Path $repo -Force | Out-Null

# 주의: 파라미터 이름을 `$Args` 로 쓰면 PowerShell 자동변수와 충돌해 인자가 통째로 비어버린다(실측).
function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

Invoke-Git @('-C', $repo, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo, 'config', 'user.name', 'idle-guard-test')
# origin 이 없으면 Get-GissueMergedBranchSet 이 조기 반환한다. 아래에서 그 함수를 통째로 스텁하지만,
# 스텁이 사라져도 테스트가 조용히 무의미해지지 않도록 더미 origin 을 박아둔다.
Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', 'https://example.invalid/test/idle-guard.git')
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'idle guard test' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'init')

$wtRecent = Join-Path $root 'wt-recent'
$wtOld    = Join-Path $root 'wt-old'
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'feat/recent-merged', $wtRecent, 'main')
Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', 'feat/old-merged',    $wtOld,    'main')

# 두 worktree 모두 clean + (가상으로) push 완료 + PR 머지됨 — 즉 구 판정의 `clean+pushed` 다.
# 차이는 오직 "마지막 활동 시각" 하나뿐이다.
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
    # 주의: [System.IO.File]::SetLastWriteTimeUtc 는 **디렉터리에는 통하지 않는다**(File API).
    # 스캐너는 디렉터리 엔트리의 mtime 도 읽으므로 디렉터리까지 반드시 함께 되돌려야 한다
    # (안 그러면 `logs`/`refs` 디렉터리 mtime 이 '지금'으로 남아 테스트가 조용히 무의미해진다 — 실측).
    foreach ($p in $all) {
        try {
            if ([System.IO.Directory]::Exists($p)) { [System.IO.Directory]::SetLastWriteTimeUtc($p, $Utc) }
            else { [System.IO.File]::SetLastWriteTimeUtc($p, $Utc) }
        } catch {}
    }
}

$oldUtc = [datetime]::UtcNow.AddHours(-5)
Set-TreeAge $wtOld $oldUtc
Set-TreeAge (Join-Path $repo '.git\worktrees\wt-old') $oldUtc
# wt-recent 는 "파일은 5시간 전, 커밋/push 는 방금" 인 giip #2445 상태를 재현한다.
Set-TreeAge $wtRecent $oldUtc
# (관리 디렉터리는 방금 만들어졌으므로 현재 시각 그대로 둔다)

# 머지판정만 스텁한다 — 네트워크/gh 인증 없이 "둘 다 머지된 PR 있음" 상태를 만든다.
# dot-source 로 같은 스코프에 들어온 엔진은 호출 시점에 이 정의를 찾는다.
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$set.Add('feat/recent-merged')
    [void]$set.Add('feat/old-merged')
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/idle-guard'; Branches = $set }
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
$recentNorm = (Resolve-Path -LiteralPath $wtRecent).Path.TrimEnd('\', '/')
$oldNorm    = (Resolve-Path -LiteralPath $wtOld).Path.TrimEnd('\', '/')

# B-1 최근 활동(커밋/push 방금) clean+pushed+머지됨 → 삭제 대상이 되면 안 된다
Assert-True ($removedPaths -notcontains $recentNorm) 'B-1 최근 활동 worktree 는 삭제 대상 아님' "Removed=$($removedPaths -join ', ')"
Assert-True ($log -match [regex]::Escape($recentNorm) ) 'B-1b 최근 worktree 가 로그에 등장' ''
$recentSkipLine = @($logLines | Where-Object { $_ -like "*$recentNorm*" -and $_ -like 'SKIP(*' })
Assert-True ($recentSkipLine.Count -ge 1) 'B-1c 최근 worktree 가 SKIP 으로 기록됨' "lines=$($logLines -join ' || ')"
Assert-True (($recentSkipLine -join ' ') -match 'MinIdleMinutes') 'B-1d SKIP 사유에 MinIdleMinutes 표기' "$($recentSkipLine -join ' ')"

# B-2 오래된 clean+pushed+머지됨 → 여전히 삭제 대상으로 잡혀야 한다(보호 과잉 방지)
Assert-True ($removedPaths -contains $oldNorm) 'B-2 오래된 머지완료 worktree 는 삭제 대상' "Removed=$($removedPaths -join ', ')"
Assert-True ($log -match '\[DRY-RUN\] 삭제 예정') 'B-2b DryRun 삭제 예정 로그 존재' ''

# B-3 DryRun 이므로 실제로는 아무것도 사라지지 않아야 한다
Assert-True (Test-Path -LiteralPath $wtOld) 'B-3 DryRun 은 실제 삭제하지 않음(old)' ''
Assert-True (Test-Path -LiteralPath $wtRecent) 'B-3b DryRun 은 실제 삭제하지 않음(recent)' ''

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
