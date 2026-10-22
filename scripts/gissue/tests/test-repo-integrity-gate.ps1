# test-repo-integrity-gate.ps1 — rule 55 §3 인접 repo 무결성 게이트 회귀 테스트 (giip #2466)
#
# 왜 필요한가:
#   `Compare-GissueRepoIntegritySnapshot` 의 구현은 `$a.Head -ne $b.Head` 하나로 위반을 선언했다.
#   즉 규칙 문구("`.git` 존재 여부와 `git remote -v`/`git rev-parse HEAD` 가 **정상인지**")와 달리
#   **불변인지**를 보고 있었다. 이 PC 는 여러 세션이 같은 체크아웃을 동시에 쓰므로, 항목 하나
#   삭제에 10분씩 걸리는 대형 트리에서는 다른 세션의 정상 커밋/pull 한 번에 전체 정리가 끊겼다
#   (2026-09-14 giip #2449 실행에서 3회 — giipv3 HEAD 이동 / bcx-v2 자동커밋 / giipdb pull).
#
# 고정하는 것(양방향 — 이 테스트의 존재 이유):
#   A. 오탐 제거 — 다른 세션의 정상 커밋/머지/pull 로 HEAD 가 움직인 것은 위반이 아니라 WARN.
#   B. 탐지력 유지 — `.git` 소실 / origin 변경 / rev-parse 실패 / 새 HEAD 가 커밋이 아님 /
#      직전 HEAD 객체 소실(저장소 교체)은 **여전히 위반**. giip #2220/#2232 사고의 실제 증상이다.
#   B 가 없으면 이 수정은 그냥 안전장치를 끈 것이 된다. 게이트를 손댈 때 A 만 보고 고치지 말 것.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-repo-integrity-gate.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리(`$env:TEMP\gissue-integrity-gate-test-<pid>`)에만 레포를 만든다 —
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

# git 오브젝트 파일은 read-only 속성이라 그냥 지우면 UnauthorizedAccessException 이 난다.
# 속성을 걷어낸 뒤 지운다. **$env:TEMP 아래 이 테스트가 만든 트리에만** 쓴다.
function Remove-TestTree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {} }
    [System.IO.Directory]::Delete($Path, $true)
}

$Root = Join-Path $env:TEMP "gissue-integrity-gate-test-$PID"
Remove-TestTree $Root
New-Item -ItemType Directory -Path $Root -Force | Out-Null

function New-TestRepo([string]$Name, [string]$Origin = 'https://example.invalid/test.git') {
    $p = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    git -C $p init --quiet 2>$null | Out-Null
    git -C $p config user.email 'test@example.invalid' | Out-Null
    git -C $p config user.name  'gissue test'          | Out-Null
    git -C $p remote add origin $Origin                 | Out-Null
    Set-Content -LiteralPath (Join-Path $p 'a.txt') -Value 'one' -Encoding utf8
    git -C $p add a.txt      | Out-Null
    git -C $p commit -m one --quiet | Out-Null
    return (Resolve-Path -LiteralPath $p).Path
}

function Add-TestCommit([string]$RepoPath, [string]$Text) {
    Set-Content -LiteralPath (Join-Path $RepoPath 'a.txt') -Value $Text -Encoding utf8
    git -C $RepoPath add a.txt | Out-Null
    git -C $RepoPath commit -m $Text --quiet | Out-Null
}

try {

# ──────────────────────────────────────────────────────────────────────────────
# A. 오탐 제거 — 다른 세션의 정상 작업은 게이트를 멈추지 않는다 (giip #2466 본문)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. 다른 세션의 정상 작업 → 위반 아님(WARN)'

# A-1 정상 커밋으로 HEAD 이동 — giip #2449 에서 3회 abort 당한 바로 그 상황
$r = New-TestRepo 'normal-commit'
$pre = Get-GissueRepoIntegritySnapshot @($r)
Add-TestCommit $r 'two'
$post = Get-GissueRepoIntegritySnapshot @($r)
$res = Compare-GissueRepoIntegrity $pre $post
Assert-True ($res.Violations.Count -eq 0) 'A-1 정상 커밋으로 HEAD 이동 → 위반 0건(정리 계속)' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Warnings.Count -eq 1)   'A-1 대신 WARN 1건으로 기록' "Warnings=$($res.Warnings -join ' / ')"
Assert-True ($res.Warnings -match 'HEAD 가 이동함') 'A-1 WARN 문구에 HEAD 이동 명시' "Warnings=$($res.Warnings -join ' / ')"

# A-2 여러 커밋(머지/여러 번 pull 상당)도 마찬가지
Add-TestCommit $r 'three'; Add-TestCommit $r 'four'
$post2 = Get-GissueRepoIntegritySnapshot @($r)
$res = Compare-GissueRepoIntegrity $pre $post2
Assert-True ($res.Violations.Count -eq 0) 'A-2 여러 커밋 진행 후에도 위반 0건' "Violations=$($res.Violations -join ' / ')"

# A-3 HEAD 불변 → 위반도 WARN 도 없음(조용한 정상 경로)
$res = Compare-GissueRepoIntegrity $post2 $post2
Assert-True ($res.Violations.Count -eq 0 -and $res.Warnings.Count -eq 0) 'A-3 HEAD 불변 → 위반 0 / WARN 0'

# A-4 하위호환 래퍼도 같은 판정(기존 호출자가 그대로 동작)
$legacy = @(Compare-GissueRepoIntegritySnapshot $pre $post2)
Assert-True ($legacy.Count -eq 0) 'A-4 Compare-GissueRepoIntegritySnapshot 래퍼도 위반 0건' "legacy=$($legacy -join ' / ')"

# ──────────────────────────────────────────────────────────────────────────────
# B. 탐지력 유지 — 진짜 손상은 여전히 즉시 중단 (giip #2220/#2232 사고의 실제 증상)
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'B. 진짜 손상 → 여전히 위반(즉시 중단)'

# B-1 `.git` 소실 — giip #2232 가 정확히 이 증상이었다
$r2 = New-TestRepo 'lost-git'
$pre2 = Get-GissueRepoIntegritySnapshot @($r2)
Remove-TestTree (Join-Path $r2 '.git')
$post2b = Get-GissueRepoIntegritySnapshot @($r2)
$res = Compare-GissueRepoIntegrity $pre2 $post2b
Assert-True ($res.Violations.Count -ge 1) 'B-1 .git 소실 → 위반' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Violations -match '\.git 이 사라짐') 'B-1 위반 사유에 .git 소실 명시' "Violations=$($res.Violations -join ' / ')"

# B-2 origin remote 변경 — 디렉터리가 다른 저장소로 바뀐 신호
$r3 = New-TestRepo 'changed-origin'
$pre3 = Get-GissueRepoIntegritySnapshot @($r3)
git -C $r3 remote set-url origin 'https://example.invalid/OTHER.git' | Out-Null
$post3 = Get-GissueRepoIntegritySnapshot @($r3)
$res = Compare-GissueRepoIntegrity $pre3 $post3
Assert-True ($res.Violations.Count -ge 1) 'B-2 origin 변경 → 위반' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Violations -match 'origin remote 변경됨') 'B-2 위반 사유에 origin 변경 명시' "Violations=$($res.Violations -join ' / ')"

# B-3 rev-parse HEAD 실패 — .git 은 남았는데 읽을 수 없는 상태(저장소 손상)
$r4 = New-TestRepo 'broken-head'
$pre4 = Get-GissueRepoIntegritySnapshot @($r4)
Set-Content -LiteralPath (Join-Path $r4 '.git\HEAD') -Value 'ref: refs/heads/does-not-exist' -Encoding ascii
$post4 = Get-GissueRepoIntegritySnapshot @($r4)
Assert-True ([string]::IsNullOrWhiteSpace($post4[$r4].Head)) 'B-3 전제: 사후 스냅샷의 HEAD 가 비어 있음' "Head=$($post4[$r4].Head)"
$res = Compare-GissueRepoIntegrity $pre4 $post4
Assert-True ($res.Violations.Count -ge 1) 'B-3 rev-parse HEAD 실패 → 위반' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Violations -match 'rev-parse HEAD 가 실패') 'B-3 위반 사유에 rev-parse 실패 명시' "Violations=$($res.Violations -join ' / ')"

# B-4 새 HEAD 가 정상 커밋 객체가 아님(존재하지 않는 sha) → 위반
$r5 = New-TestRepo 'bogus-head'
$pre5 = Get-GissueRepoIntegritySnapshot @($r5)
$fake = @{}
$fake[$r5] = @{ Exists = $true; Head = ('0' * 40); Remote = $pre5[$r5].Remote }
$res = Compare-GissueRepoIntegrity $pre5 $fake
Assert-True ($res.Violations.Count -ge 1) 'B-4 새 HEAD 가 실재하지 않는 객체 → 위반' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Violations -match '정상 커밋 객체가 아님') 'B-4 위반 사유 명시' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Warnings.Count -eq 0) 'B-4 WARN 으로 새어나가지 않음'

# B-5 저장소 교체 — .git 도 있고 origin 도 같고 새 HEAD 도 정상 커밋이지만
#     직전 HEAD 객체가 사라졌다. 정상 커밋/머지/pull 은 직전 커밋을 반드시 남기므로
#     이건 디렉터리가 통째로 다른 저장소로 바뀐 정황이다 → 위반.
$r6 = New-TestRepo 'replaced-repo'
$pre6 = Get-GissueRepoIntegritySnapshot @($r6)
Remove-TestTree (Join-Path $r6 '.git')
git -C $r6 init --quiet 2>$null | Out-Null
git -C $r6 config user.email 'test@example.invalid' | Out-Null
git -C $r6 config user.name  'gissue test'          | Out-Null
git -C $r6 remote add origin $pre6[$r6].Remote      | Out-Null
Set-Content -LiteralPath (Join-Path $r6 'b.txt') -Value 'fresh' -Encoding utf8
git -C $r6 add b.txt | Out-Null
git -C $r6 commit -m fresh --quiet | Out-Null
$post6 = Get-GissueRepoIntegritySnapshot @($r6)
Assert-True ($post6[$r6].Exists -and $post6[$r6].Head -and ($post6[$r6].Remote -eq $pre6[$r6].Remote)) `
    'B-5 전제: .git 존재 + HEAD 읽힘 + origin 동일(구 판정 3항목은 전부 통과하는 상태)'
$res = Compare-GissueRepoIntegrity $pre6 $post6
Assert-True ($res.Violations.Count -ge 1) 'B-5 저장소 교체(직전 HEAD 객체 소실) → 위반' "Violations=$($res.Violations -join ' / ')"
Assert-True ($res.Violations -match '저장소가 교체된 정황') 'B-5 위반 사유 명시' "Violations=$($res.Violations -join ' / ')"

# B-6 인접 레포가 사후 스냅샷에서 통째로 사라짐 → 위반
$r7 = New-TestRepo 'vanished'
$pre7 = Get-GissueRepoIntegritySnapshot @($r7)
$res = Compare-GissueRepoIntegrity $pre7 @{}
Assert-True ($res.Violations.Count -ge 1) 'B-6 사후 스냅샷에서 레포 소실 → 위반' "Violations=$($res.Violations -join ' / ')"

# ──────────────────────────────────────────────────────────────────────────────
# C. Test-GissueGitObjectIsCommit 단품
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'C. Test-GissueGitObjectIsCommit'
$r8 = New-TestRepo 'objcheck'
$head8 = (git -C $r8 rev-parse HEAD).Trim()
Assert-True (Test-GissueGitObjectIsCommit -RepoPath $r8 -Sha $head8) 'C-1 실제 HEAD sha → true'
Assert-True (-not (Test-GissueGitObjectIsCommit -RepoPath $r8 -Sha ('0' * 40))) 'C-2 없는 sha → false'
Assert-True (-not (Test-GissueGitObjectIsCommit -RepoPath $r8 -Sha '')) 'C-3 빈 sha → false'
$tree8 = (git -C $r8 rev-parse 'HEAD^{tree}').Trim()
Assert-True (-not (Test-GissueGitObjectIsCommit -RepoPath $r8 -Sha $tree8)) 'C-4 커밋이 아닌 객체(tree) → false'

# ──────────────────────────────────────────────────────────────────────────────
# D. 엔진 경로 — giip #2449 에서 실제로 abort 당한 그 자리 (Invoke-GissueRemnantCleanup)
#
#    순수 판정만 고쳐도 호출부 배선이 틀리면 똑같이 멈춘다(호출부가 3곳이다). 그래서 엔진을
#    실제로 돌린다. 경합은 스냅샷 함수를 테스트 스코프에서 감싸 **사전/사후 스냅샷 사이**에
#    인접 레포 커밋을 끼워 넣는 방식으로 결정론적으로 재현한다
#    (test-worktree-idle-guard.ps1 이 `gh pr list` 를 스텁하는 것과 같은 방식).
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'D. 엔진 경로(Invoke-GissueRemnantCleanup) — 삭제 도중 인접 레포 커밋'

$sibling = New-TestRepo 'sibling-live'
$scanRoot = Join-Path $Root 'scan'
$remnant  = Join-Path $scanRoot 'someproj\remnant-a'
New-Item -ItemType Directory -Path $remnant -Force | Out-Null
Set-Content -LiteralPath (Join-Path $remnant 'leftover.txt') -Value 'junk' -Encoding utf8

# 원본 보관 후 테스트 스코프에서 섀도잉.
$origSnapshot = (Get-Item function:Get-GissueRepoIntegritySnapshot).ScriptBlock
$origProjects = (Get-Item function:Get-GissueAllProjectRepoPaths).ScriptBlock
$script:SnapCalls = 0
$script:SiblingRepo = $sibling
# 살아있는 체크아웃이 §3 검증 대상으로 끌려오지 않게 한다(테스트 격리).
function Get-GissueAllProjectRepoPaths { return @($script:SiblingRepo) }
function Get-GissueRepoIntegritySnapshot($paths) {
    $script:SnapCalls++
    # 2번째 호출 = 삭제 직후의 사후 스냅샷. 그 직전에 다른 세션이 정상 커밋한 상황을 만든다.
    if ($script:SnapCalls -eq 2) {
        Set-Content -LiteralPath (Join-Path $script:SiblingRepo 'a.txt') -Value 'other session commit' -Encoding utf8
        git -C $script:SiblingRepo add a.txt | Out-Null
        git -C $script:SiblingRepo commit -m 'other session' --quiet | Out-Null
    }
    return (& $origSnapshot $paths)
}

$headBefore = (git -C $sibling rev-parse HEAD).Trim()
$engineLog = New-Object System.Collections.ArrayList
$res = $null
Invoke-GissueRemnantCleanup -ScanRoot @($scanRoot) -VerifyRepos @($sibling) `
    -ProtectRecentMinutes 0 -MinIdleMinutes 0 -ResultRef ([ref]$res) `
    -Log { param($m) [void]$engineLog.Add("$m") } | Out-Null
$headAfter = (git -C $sibling rev-parse HEAD).Trim()
$logText = ($engineLog -join "`n")

# 원복
Set-Item function:Get-GissueRepoIntegritySnapshot $origSnapshot
Set-Item function:Get-GissueAllProjectRepoPaths  $origProjects

Assert-True ($headBefore -ne $headAfter) 'D-0 전제: 삭제 도중 인접 레포의 HEAD 가 실제로 움직였다' "$headBefore -> $headAfter"
Assert-True ($res -and (-not $res.Aborted)) 'D-1 엔진이 abort 하지 않음(giip #2449 재현 시나리오)' "AbortReason=$($res.AbortReason)"
Assert-True (@($res.Removed).Count -eq 1) 'D-2 잔해 1건이 실제로 회수됨' "Removed=$(@($res.Removed).Count) / Manual=$(@($res.ManualReview).Count)"
Assert-True (-not (Test-Path -LiteralPath $remnant)) 'D-3 잔해 디렉터리가 실제로 사라짐'
Assert-True ($logText -match 'giip #2466') 'D-4 HEAD 이동이 WARN 으로 로그에 남음' "log=$logText"
Assert-True ($logText -notmatch 'CRITICAL') 'D-5 CRITICAL 중단 로그가 없음' "log=$logText"

} finally {
    Write-Output ''
    if (Test-Path -LiteralPath $Root) {
        try { Remove-TestTree $Root } catch { Write-Output "  (정리 실패, 수동 확인: $Root)" }
    }
}

Write-Output ''
Write-Output "=== 결과: PASS $script:Pass / FAIL $script:Fail ==="
if ($script:Fail -gt 0) { exit 1 }
exit 0
