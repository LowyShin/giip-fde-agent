# test-stale-code-guard.ps1 — "구 코드가 도는 프로세스의 파괴적 작업 차단" 회귀 테스트 (giip #2471)
#
# 왜 필요한가 (실측 사고, 2026-09-14):
#   12:07:00  :07 스케줄러 기동 → self-pull → 구 worktree-safety.ps1 을 메모리에 적재
#   12:54:53  PR #744(giip #2438/#2440) 머지 — 위험한 `clean+pushed` 삭제판정 제거
#   13:03:59  그 구 판정으로 giip #2445 세션의 **작업 중 worktree 를 삭제**
#   잡 예산은 105분이라, 안전수정을 아무리 빨리 머지해도 최대 두 시간 가까이 닿지 않는다.
#
# 고정하는 것(양방향 — 보호 부족도 결함이지만 보호 과잉도 결함이다):
#   A. 순수 판정(Test-GissueCodeStale)
#      A-1 미초기화(= 단명 프로세스) → 낡지 않음(fail-open)
#      A-2 변화 없음 → 낡지 않음                        ← 정상 상황에서 막히지 않는지(반대 방향)
#      A-3 디스크의 감시 파일이 기동 이후 바뀜 → 낡음     ← 이번 사고의 재현(다른 세션이 pull)
#      A-4 latch — 파일을 원복해도 그 프로세스 내내 낡음
#      A-5 아무도 pull 하지 않았지만 origin/main 에만 새 코드 → 낡음 (Layer B)
#      A-6 감시 파일에 로컬 미커밋 변경이 있는 체크아웃 → 낡지 않음 (Layer B 오탐 방지)
#   B. 엔진 경로(Invoke-GissueWorktreeCleanupForRepo, **DryRun 아님 = 실제 삭제**)
#      B-1 코드가 최신이면 머지+idle 조건을 만족한 worktree 는 실제로 삭제된다(정리가 멈추지 않음)
#      B-2 구 코드가 도는 상태면 **같은 입력인데 삭제가 차단**되고 worktree 가 그대로 남는다
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-stale-code-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-stale-code-test-<pid>`) 안에 자기만의 git 레포와
# worktree 를 만들어 거기서만 삭제를 수행한다 — 살아있는 체크아웃이나 D:\temp\worktrees 는
# 절대 건드리지 않는다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$SafetyLib = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\worktree-safety.ps1')).Path
. $SafetyLib   # worktree-safety.ps1 이 code-freshness.ps1 을 함께 닷소싱한다

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

# 주의: 파라미터 이름을 `$Args` 로 쓰면 PowerShell 자동변수와 충돌해 인자가 통째로 비어버린다.
function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

$WatchRel = @('scripts/gissue/worktree-safety.ps1', 'scripts/gissue/run-gissue-claude.ps1')

# 감시 대상 파일 2개를 가진 "가짜 lowyworkenv" 레포를 만든다(내용은 무관 — 가드는 해시만 본다).
function New-FakeRepo($path, $originPath) {
    New-Item -ItemType Directory -Path (Join-Path $path 'scripts/gissue') -Force | Out-Null
    Invoke-Git @('-C', $path, 'init', '-q', '-b', 'main')
    Invoke-Git @('-C', $path, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git @('-C', $path, 'config', 'user.name', 'stale-code-test')
    foreach ($rel in $WatchRel) {
        Set-Content -LiteralPath (Join-Path $path $rel) -Value "# v1 $rel" -Encoding UTF8
    }
    Invoke-Git @('-C', $path, 'add', '-A')
    Invoke-Git @('-C', $path, 'commit', '-q', '-m', 'init')
    if ($originPath) {
        Invoke-Git @('-C', $path, 'remote', 'add', 'origin', $originPath)
        Invoke-Git @('-C', $path, 'push', '-q', '-u', 'origin', 'main')
    }
}

$root = Join-Path $env:TEMP ("gissue-stale-code-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null

# 로컬 bare 레포를 origin 으로 쓴다 — 네트워크 없이 Layer B(origin/main 비교)를 진짜로 검증한다.
$origin = Join-Path $root 'origin.git'
Invoke-Git @('init', '-q', '--bare', '-b', 'main', $origin)

$repo = Join-Path $root 'repo'
New-FakeRepo $repo $origin

# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 순수 판정 (Test-GissueCodeStale)'
# ──────────────────────────────────────────────────────────────────────────────

# A-1 미초기화 = 단명 프로세스(cleanup-worktrees.ps1 등) → 이 갭이 없으므로 막지 않는다
$script:GissueCodeFreshness = $null
Assert-True (-not (Test-GissueCodeStale)) 'A-1 미초기화 → 낡지 않음(fail-open)' ''

# A-2 정상 상황: 기동 직후, 로컬도 origin 도 그대로 → 막히면 안 된다
Initialize-GissueCodeFreshness -RepoRoot $repo -WatchPaths $WatchRel -RemoteCheckIntervalMin 0
Assert-True ($null -ne $script:GissueCodeFreshness) 'A-2a 스냅샷 초기화됨' ''
Assert-True (-not (Test-GissueCodeStale)) 'A-2 변화 없음 → 낡지 않음(정상 정리 진행)' "Reason=$(Get-GissueCodeStaleReason)"
# 원격 확인을 여러 번 반복해도 여전히 통과해야 한다(fetch 반복으로 판정이 흔들리지 않는지)
Assert-True (-not (Test-GissueCodeStale)) 'A-2b 재확인해도 낡지 않음' "Reason=$(Get-GissueCodeStaleReason)"

# A-3 사고 재현: 다른 세션이 공유 체크아웃을 pull 해서 디스크의 판정 파일이 바뀐 상태
Set-Content -LiteralPath (Join-Path $repo $WatchRel[0]) -Value '# v2 (안전수정 머지본)' -Encoding UTF8
Assert-True (Test-GissueCodeStale) 'A-3 디스크의 감시 파일이 기동 이후 바뀜 → 낡음' ''
Assert-True ((Get-GissueCodeStaleReason) -match 'worktree-safety\.ps1') 'A-3b 사유에 바뀐 파일명 표기' "Reason=$(Get-GissueCodeStaleReason)"

# A-4 latch — 파일을 원복해도 이 프로세스의 메모리는 이미 낡았으므로 계속 낡음이어야 한다
Set-Content -LiteralPath (Join-Path $repo $WatchRel[0]) -Value "# v1 $($WatchRel[0])" -Encoding UTF8
Assert-True (Test-GissueCodeStale) 'A-4 원복해도 latch 유지(플래핑 금지)' ''

# A-5 Layer B: 아무도 pull 하지 않았지만 origin/main 에만 새 코드가 머지된 상황
$repo2 = Join-Path $root 'repo2'
Invoke-Git @('clone', '-q', $origin, $repo2)
Invoke-Git @('-C', $repo2, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo2, 'config', 'user.name', 'stale-code-test')
$script:GissueCodeFreshness = $null
Initialize-GissueCodeFreshness -RepoRoot $repo2 -WatchPaths $WatchRel -RemoteCheckIntervalMin 0
Assert-True (-not (Test-GissueCodeStale)) 'A-5a 클론 직후에는 낡지 않음' "Reason=$(Get-GissueCodeStaleReason)"
# 제3의 체크아웃에서 안전수정을 머지(push)한다 — repo2 의 워킹트리는 전혀 건드리지 않는다.
Set-Content -LiteralPath (Join-Path $repo $WatchRel[0]) -Value '# v3 (긴급 안전수정)' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'urgent safety fix')
Invoke-Git @('-C', $repo, 'push', '-q', 'origin', 'main')
Assert-True (Test-GissueCodeStale) 'A-5 로컬은 그대로지만 origin/main 에 새 코드 → 낡음(Layer B)' ''
Assert-True ((Get-GissueCodeStaleReason) -match 'origin/main') 'A-5b 사유가 origin/main 출처임을 표기' "Reason=$(Get-GissueCodeStaleReason)"

# A-6 Layer B 오탐 방지: 감시 파일에 로컬 미커밋 변경이 있는 체크아웃(= 개발 중)은 막지 않는다.
#     이 예외가 없으면 그런 체크아웃에서는 정리가 영구히 멈춘다.
$repo3 = Join-Path $root 'repo3'
Invoke-Git @('clone', '-q', $origin, $repo3)
Set-Content -LiteralPath (Join-Path $repo3 $WatchRel[0]) -Value '# 로컬 작업 중(미커밋)' -Encoding UTF8
$script:GissueCodeFreshness = $null
Initialize-GissueCodeFreshness -RepoRoot $repo3 -WatchPaths $WatchRel -RemoteCheckIntervalMin 0
Assert-True (-not (Test-GissueCodeStale)) 'A-6 로컬 미커밋 변경분은 origin 과 달라도 낡음 아님' "Reason=$(Get-GissueCodeStaleReason)"

# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. 엔진 경로 — 실제 삭제가 차단되는가 (DryRun 아님)'
# ──────────────────────────────────────────────────────────────────────────────

# 머지판정만 스텁한다(네트워크/gh 인증 불필요). dot-source 로 같은 스코프에 있는 엔진이 이 정의를 쓴다.
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$set.Add('feat/merged-and-idle')
    return [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/stale-code'; Branches = $set }
}

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

# 매 케이스마다 "머지됨 + 충분히 오래된(idle) worktree" 를 새로 만든다 — 두 케이스의 입력이 동일해야
# 차이의 원인이 가드 하나임이 증명된다.
function New-DeletableWorktree($engineRepo, $wtPath) {
    Invoke-Git @('-C', $engineRepo, 'worktree', 'add', '-q', '-b', 'feat/merged-and-idle', $wtPath, 'main')
    $oldUtc = [datetime]::UtcNow.AddHours(-5)
    Set-TreeAge $wtPath $oldUtc
    Set-TreeAge (Join-Path $engineRepo ('.git\worktrees\' + (Split-Path -Leaf $wtPath))) $oldUtc
}

# 주의: 이 함수 안에서 로그를 Write-Output 으로 찍으면 그 로그가 함수의 성공 스트림에 섞여
# 호출자의 `$b = Invoke-EngineOnce ...` 가 **배열**이 된다(worktree-safety.ps1 헤더가 경고하는 바로
# 그 함정 — 실측으로 여기서도 재현됐다). 로그는 호출부에서 찍는다.
function Invoke-EngineOnce($engineRepo) {
    $lines = New-Object System.Collections.ArrayList
    $logger = { param($m) [void]$lines.Add([string]$m) }
    $r = $null
    Invoke-GissueWorktreeCleanupForRepo -RepoPath $engineRepo -Log $logger `
        -DeleteRemoteBranch $false -ResultRef ([ref]$r)
    return [pscustomobject]@{ Result = $r; Log = ($lines -join "`n") }
}
function Write-EngineLog($outcome) {
    foreach ($l in ($outcome.Log -split "`n")) { Write-Output "  | $l" }
}

# ── B-1 코드가 최신인 경우 → 실제로 삭제되어야 한다(보호 과잉 방지) ──
Write-Output '  [B-1] 코드 최신 — 삭제가 정상 수행되어야 함'
# 엔진 레포와 worktree 는 **서로 다른 부모 폴더**에 둔다. 엔진은 "레포의 부모 폴더에 있는 .git 보유
# 디렉터리"를 인접 nested repo 로 보고 삭제 직후 무결성을 재검증하는데(rule 55 §3), worktree 를 레포
# 바로 옆에 두면 방금 지운 worktree 자신이 그 검증 대상에 잡혀 CRITICAL 오탐이 난다(실측).
# 운영 배치(레포는 projects\, worktree 는 D:\temp\worktrees\)와 같은 구조로 맞춘다.
New-Item -ItemType Directory -Path (Join-Path $root 'engines') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'wts') -Force | Out-Null
$engine1 = Join-Path $root 'engines\engine-fresh'
# origin 을 그대로 클론한다 — 즉 "감시 파일이 origin/main 과 완전히 동일한, 막 self-pull 을 마친
# 스케줄러 프로세스" 상태다. 가드는 여기서 절대 개입하면 안 된다.
Invoke-Git @('clone', '-q', $origin, $engine1)
Invoke-Git @('-C', $engine1, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $engine1, 'config', 'user.name', 'stale-code-test')
$wt1 = Join-Path $root 'wts\wt-fresh'
New-DeletableWorktree $engine1 $wt1
$script:GissueCodeFreshness = $null
Initialize-GissueCodeFreshness -RepoRoot $engine1 -WatchPaths $WatchRel -RemoteCheckIntervalMin 0
# (engine1 은 방금 origin 을 따라잡은 상태 — origin/main 의 감시 파일과 동일하다)
$b1 = Invoke-EngineOnce $engine1
Write-EngineLog $b1
Assert-True (-not $b1.Result.SkippedStaleCode) 'B-1a 최신 코드에서는 가드가 개입하지 않음' "Reason=$($b1.Result.StaleCodeReason)"
Assert-True (@($b1.Result.Removed).Count -ge 1) 'B-1b 머지+idle worktree 가 실제 삭제됨' "Removed=$(@($b1.Result.Removed | ForEach-Object { $_.Path }) -join ', ')"
Assert-True (-not (Test-Path -LiteralPath $wt1)) 'B-1c worktree 디렉터리가 실제로 사라짐' ''

# ── B-2 구 코드가 도는 경우 → 같은 입력인데 삭제가 차단되어야 한다 ──
Write-Output '  [B-2] 구 코드 — 삭제가 차단되어야 함'
$engine2 = Join-Path $root 'engines\engine-stale'
New-FakeRepo $engine2 $null
$wt2 = Join-Path $root 'wts\wt-stale'
New-DeletableWorktree $engine2 $wt2
$script:GissueCodeFreshness = $null
Initialize-GissueCodeFreshness -RepoRoot $engine2 -WatchPaths $WatchRel -RemoteCheckIntervalMin 0
# 기동 이후 판정 파일이 갱신된 상황(= 안전수정이 머지되고 누군가 pull 한 상태)을 재현한다.
Set-Content -LiteralPath (Join-Path $engine2 $WatchRel[0]) -Value '# 안전수정 머지본(구 판정 제거)' -Encoding UTF8
$b2 = Invoke-EngineOnce $engine2
Write-EngineLog $b2
Assert-True ($b2.Result.SkippedStaleCode) 'B-2a 구 코드에서 가드가 발동(SkippedStaleCode)' "Reason=$($b2.Result.StaleCodeReason)"
Assert-True (@($b2.Result.Removed).Count -eq 0) 'B-2b 아무것도 삭제되지 않음' "Removed=$(@($b2.Result.Removed | ForEach-Object { $_.Path }) -join ', ')"
Assert-True (Test-Path -LiteralPath $wt2) 'B-2c worktree 디렉터리가 그대로 남아 있음' ''
Assert-True ($b2.Log -match 'giip #2471') 'B-2d 차단 사유가 로그에 남음' ''

# ── 정리: 이 테스트가 만든 임시 레포만 제거한다(rule 55 — 링크 선검사 후 삭제) ──
$script:GissueCodeFreshness = $null
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
