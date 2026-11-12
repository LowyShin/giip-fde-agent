# test-worktree-merge-gate-failclosed.ps1 — 머지판정 게이트 fail-closed 회귀 테스트 (106차, 2026-11-13)
#
# 왜 필요한가:
#   `scripts/gissue/worktree-safety.ps1` 의 `Invoke-GissueWorktreeCleanupForRepo` 는 머지된 PR 목록을
#   조회해("머지판정") 그 브랜치의 worktree 만 **자동 삭제**한다. 그런데 게이트가 **통째로 무너지는**
#   경로가 있었다 — 실측: 2026-11-13 02:26:46 DryRun 에서 아래 예외가 실제로 떴다.
#
#     You cannot call a method on a null-valued expression.
#     At ...\worktree-safety.ps1:1170 char:13
#     +         if (-not $merged.Branches.Contains($e.Branch)) {
#     + FullyQualifiedErrorId : InvokeMethodOnNull
#
#   근본 원인(106차에 확정):
#     ① `Get-GissueMergedBranchSet` 는 머지판정 로그를 `& $Log "..."` 로 남기는데, 로그 콜백
#        (`Write-CleanupLog` → `Write-Output`) 은 **성공 스트림**에 쓴다. 그래서 호출부의
#        `$merged = Get-GissueMergedBranchSet ...` 대입이 **로그 문자열까지 함께 빨아들인다**
#        → `$merged` = @(String, PSCustomObject) 혼합 배열.
#     ② PowerShell 의 멤버 열거는 반환된 컬렉션을 **펼쳐서** 준다. 그래서 `$merged.Branches` 는
#        HashSet 이 아니라 **그 안의 분기명 문자열 배열**이 되고, **머지된 PR 이 0건이면**(즐
#        `gh pr list --state merged` 가 실패했으면) 아예 아무 값이 없어서 **$null** 이 된다.
#     ③ `$null.Contains(...)` 는 런타임 예외이며 **'if' 문장 하나만 버리고** 흐름이 다음 문장으로
#        넘어간다 → 링크스캔 → idle 게이트 → 삭제 보고 → **`git worktree remove`**.
#        즉 **머지 확인을 한 번도 하지 않은 채 삭제**까지 간다 — fail-open.
#
#   왜 위험한가: `gh pr list` 실패(레이트리밋·인증 만료·일시적 네트워크)는 일상적인 실패다.
#   그 순간 머지판정은 "약한 판정" 이 아니라 **"모든 worktree 를 삭제"** 로 뒤집힌다.
#   파일 자체가 "giip #2463: 판정 불가일 때 삭제로 흘러가던 fail-open 을 fail-closed 로 뒤집었다"
#   라고 명시해 둔 것과 정면으로 어긋난다.
#
# 고정하는 것(양방향):
#   A. `Get-GissueMergedBranchSet` 반환값이 **정확히 1개 객체**인가(로그 오염 회귀)
#   B. 머지판정 결과가 못 쓰면 **삭제 금지(fail-closed)** 로 닫히는가 — 세 가지 모양:
#      B-1 오염된 반환(로그 문자열 + 빈 Branches) — ①+② 재현, 예전엔 삭제로 흘렀다
#      B-2 조회 실패(Ok=$false + 빈 Branches)   — 사유를 '조회 실패' 로 구분해 기록한다
#      B-3 머지 확인됨(Ok=$true + 브랜치 포함)  — **통과 통제**: 게이트를 고칠 때 정상 경로가
#                                                  막히지 않았음을 함께 증명한다
#   C. `Remove-GissueDirectoryTreeSafely` 반환값이 폴백 경로에서도 1개 객체인가(같은 오염 계열)
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-worktree-merge-gate-failclosed.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-merge-gate-test-<pid>`)에만 레포/worktree 를 만든다 —
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

# 주의: 파라미터 이름을 `$Args` 로 쓰면 PowerShell 자동변수와 충돌해 인자가 통째로 비어버린다(실측).
function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

# `$env:TEMP` 가 8.3 단축 경로면 엔진이 계산한 자식 경로와 이 테스트가 비교하는 문자열이 어긋난다.
$tempRootLong = (Get-Item -LiteralPath $env:TEMP).FullName
$root = Join-Path $tempRootLong ("gissue-merge-gate-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null

# ──────────────────────────────────────────────────────────────────────────────
# A. Get-GissueMergedBranchSet 반환값 오염 회귀
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. Get-GissueMergedBranchSet — 로그 콜백이 성공 스트림에 써도 반환값은 1개'

$repoA = Join-Path $root 'repo-no-origin'
New-Item -ItemType Directory -Path $repoA -Force | Out-Null
Invoke-Git @('-C', $repoA, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repoA, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repoA, 'config', 'user.name', 'merge-gate-test')
# origin 을 **만들지 않는다** → "머지판정 불가(origin remote 없음)" 로그 경로로 간다.
# (네트워크·gh 인증 없이 오염 재현 지점 하나를 정확히 찍는다)
Set-Content -LiteralPath (Join-Path $repoA 'README.md') -Value 'merge gate test' -Encoding UTF8
Invoke-Git @('-C', $repoA, 'add', '-A')
Invoke-Git @('-C', $repoA, 'commit', '-q', '-m', 'init')

# `Write-CleanupLog` 와 **같은 형태**의 로거 — 성공 스트림에 쓴다(오염의 진짜 원인).
$logA = New-Object System.Collections.ArrayList
$loggerA = { param($m) [void]$logA.Add([string]$m); Write-Output $m }

$m = Get-GissueMergedBranchSet -RepoPath $repoA -Log $loggerA
$mCount = @($m).Count
Assert-True ($mCount -eq 1) 'A-1 로그 콜백이 성공 스트림에 써도 반환값은 정확히 1개' "count=$mCount types=$((@($m) | ForEach-Object { $_.GetType().Name }) -join ',')"
Assert-True ($null -ne $m.Branches) 'A-2 반환값에서 Branches 를 읽을 수 있다(오염 시 $null 이 된다)' "Branches=$($null -eq $m.Branches)"
Assert-True ($m.Branches -is [System.Collections.Generic.HashSet[string]]) 'A-3 Branches 는 HashSet 그대로(펼쳐지지 않음)' "type=$(if ($null -ne $m.Branches) { $m.Branches.GetType().Name } else { 'NULL' })"
Assert-True ($logA.Count -ge 1) 'A-4 실제로 로그 경로를 탔는지(무의미한 통과 방지)' "logCount=$($logA.Count)"

# 캐시 히트 경로도 같은 계약(1개 객체)을 지켜야 한다.
$m2 = Get-GissueMergedBranchSet -RepoPath $repoA -Log $loggerA
Assert-True (@($m2).Count -eq 1) 'A-5 캐시 히트 경로에서도 반환값은 1개' "count=$(@($m2).Count)"

# ──────────────────────────────────────────────────────────────────────────────
# B. 머지판정 게이트 fail-closed — 엔진 경로
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. Invoke-GissueWorktreeCleanupForRepo — 머지판정 불가 시 삭제 금지'

$repoB = Join-Path $root 'repo'
New-Item -ItemType Directory -Path $repoB -Force | Out-Null
Invoke-Git @('-C', $repoB, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repoB, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repoB, 'config', 'user.name', 'merge-gate-test')
# 머지판정 조회 경로가 실제로 돌도록 origin 은 있게 두되, 조회는 스텁한다(네트워크 불필요).
Invoke-Git @('-C', $repoB, 'remote', 'add', 'origin', 'https://example.invalid/test/merge-gate.git')
Set-Content -LiteralPath (Join-Path $repoB 'README.md') -Value 'merge gate test' -Encoding UTF8
Invoke-Git @('-C', $repoB, 'add', '-A')
Invoke-Git @('-C', $repoB, 'commit', '-q', '-m', 'init')

$wtB = Join-Path $root 'wt-candidate'
Invoke-Git @('-C', $repoB, 'worktree', 'add', '-q', '-b', 'feat/merged-candidate', $wtB, 'main')

$logB = New-Object System.Collections.ArrayList
$loggerB = { param($m) [void]$logB.Add([string]$m); Write-Output $m }

# 머지판정 함수를 통째로 스텁한다 — dot-source 로 같은 스코프에 들어온 엔진은 호출 시점에 이 정의를 찾는다.
# 스텁이 어떤 모양을 돌려주는지로 "머지판정 결과가 언제나 쓰일 수 있는가" 를 갈라본다.
$script:StubMerged = $null
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    return $script:StubMerged
}

function Invoke-CleanupDryRun {
    # **try/catch 로 감싸지 않는다** — 실제 호출부(cleanup-worktrees.ps1 / run-gissue-claude.ps1)도
    # try/catch 없이 호출한다. 그래서 예전 구현의 런타임 예외(InvokeMethodOnNull)는 'if' 문장 하나만
    # 버리고 **삭제 경로로 흘러간다**(실측: 삭제 예정 로그 + Removed 에 들어감). 여기서 감싸면
    # 오히려 함수가 중단돼 "삭제 안 함" 으로 보일 뿐이고, 진짜 결함(fail-open)이 가려진다.
    # `$ErrorActionPreference` 만 'Continue' 로 낮춰 테스트 스크립트 전체가 예외로 죽지 않게 한다
    # (cleanup-worktrees.ps1 도 전역으로 'Continue' 를 쓴다 — 같은 조건).
    $ErrorActionPreference = 'Continue'
    $r = $null
    Invoke-GissueWorktreeCleanupForRepo -RepoPath $repoB -DryRun -Log $loggerB `
        -DeleteRemoteBranch $false -MinIdleMinutes 0 -ResultRef ([ref]$r)
    return $r
}

$wtBNorm = (Resolve-Path -LiteralPath $wtB).Path.TrimEnd('\', '/')
function Get-RemovedPaths($res) { return @($res.Removed | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') }) }
function Get-ManualPaths($res) { return @($res.ManualReview | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') }) }

# B-1 [핵심 회귀] gh 실패 재현: 로그 문자열이 반환값에 섞였고 머지된 PR 집합이 비어 있다.
#     예전 구현은 여기서 $merged.Branches 가 $null 이 되어 예외가 났고, 그 예외는 'if' 만 버리고
#     **삭제 경로로 흘렀다**(Removed 에 들어갔다). 지금은 삭제 금지로 닫혀야 한다.
$emptySet = New-Object 'System.Collections.Generic.HashSet[string]'
$script:StubMerged = @('WARN: gh pr list --state merged 실패(테스트 재현)', [pscustomobject]@{ Ok = $false; OwnerRepo = 'test/merge-gate'; Branches = $emptySet })
$r = Invoke-CleanupDryRun
$removedB1 = if ($null -ne $r) { Get-RemovedPaths $r } else { @() }
$manualB1 = if ($null -ne $r) { Get-ManualPaths $r } else { @() }
Assert-True ($removedB1 -notcontains $wtBNorm) 'B-1 오염+빈 집합 → 삭제 대상이 아니다(fail-closed)' "removed=$($removedB1 -join ',') "
Assert-True ($manualB1 -contains $wtBNorm) 'B-1b 대신 수동확인 목록에 들어간다' "manual=$($manualB1 -join ',')"
$reasonB1 = (@($r.ManualReview | Where-Object { ([string]$_.Path).TrimEnd('\', '/') -eq $wtBNorm })[0]).Reason
Assert-True ("$reasonB1" -match '머지판정') 'B-1c 사유에 "머지판정" 이 명시된다' "reason=$reasonB1"
Assert-True (Test-Path -LiteralPath $wtB) 'B-1d worktree 가 디스크에 그대로 남아 있다' ''

# B-2 머지 목록 조회가 실패한 경우(Ok=$false + 빈 집합) — '미머지' 와 사유를 구분해 기록한다.
$script:StubMerged = [pscustomobject]@{ Ok = $false; OwnerRepo = 'test/merge-gate'; Branches = $emptySet }
$r = Invoke-CleanupDryRun
$removedB2 = if ($null -ne $r) { Get-RemovedPaths $r } else { @() }
$manualB2 = if ($null -ne $r) { Get-ManualPaths $r } else { @() }
Assert-True ($removedB2 -notcontains $wtBNorm) 'B-2 조회 실패 → 삭제 대상이 아니다' "removed=$($removedB2 -join ',') "
Assert-True ($manualB2 -contains $wtBNorm) 'B-2b 수동확인 목록에 들어간다' "manual=$($manualB2 -join ',')"
$reasonB2 = (@($r.ManualReview | Where-Object { ([string]$_.Path).TrimEnd('\', '/') -eq $wtBNorm })[0]).Reason
Assert-True ("$reasonB2" -match '조회 실패') 'B-2c 사유가 "조회 실패" 로 구분된다' "reason=$reasonB2"

# B-3 [통제] 머지 확인이 된 정상 경로는 **그대로 통과**해야 한다(게이트를 고쳐 정상 삭제를 막지 않았는지).
$okSet = New-Object 'System.Collections.Generic.HashSet[string]'
[void]$okSet.Add('feat/merged-candidate')
$script:StubMerged = [pscustomobject]@{ Ok = $true; OwnerRepo = 'test/merge-gate'; Branches = $okSet }
$r = Invoke-CleanupDryRun
$removedB3 = if ($null -ne $r) { Get-RemovedPaths $r } else { @() }
Assert-True ($removedB3 -contains $wtBNorm) 'B-3 머지 확인된 worktree 는 삭제 대상(정상 경로 유지)' "removed=$($removedB3 -join ',') "

# ──────────────────────────────────────────────────────────────────────────────
# C. Remove-GissueDirectoryTreeSafely 반환값 오염 회귀(같은 계열)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'C. Remove-GissueDirectoryTreeSafely — 폴백 경로에서도 반환값은 1개'

# 존재하지 않는 경로 → 1차 Remove-Item 이 실패 → 폴백(확장경로) 경로로 들어간다.
# 이 경로에서만 로그가 먼저 나가므로 반환값이 오염된다.
$missing = Join-Path $root 'no-such-dir-xyz'
$logC = New-Object System.Collections.ArrayList
$loggerC = { param($m) [void]$logC.Add([string]$m); Write-Output $m }
$del = Remove-GissueDirectoryTreeSafely -Path $missing -Log $loggerC
Assert-True (@($del).Count -eq 1) 'C-1 폴백 경로에서 반환값은 정확히 1개' "count=$(@($del).Count) types=$((@($del) | ForEach-Object { $_.GetType().Name }) -join ',')"
Assert-True ($null -ne $del.Ok) 'C-2 Ok 값이 단일 값으로 전달된다' "ok=$($null -eq $del.Ok)"
Assert-True ($del.Ok -eq $false) 'C-3 삭제 실패를 Ok=false 로 알린다' "ok=$($del.Ok)"
Assert-True ($del.Detail -is [string]) 'C-4 Detail 이 문자열이다(배열로 뭉개지지 않음)' "type=$(if ($null -ne $del.Detail) { $del.Detail.GetType().Name } else { 'NULL' })"
Assert-True ($logC.Count -ge 1) 'C-5 실제로 로그를 남겼다(무의미한 통과 방지)' "logCount=$($logC.Count)"

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
