# test-orphan-scan-idle-guard.ps1 — 고아(Orphan) 경로의 삭제 안전 가드 회귀 테스트 (giip #6603 / #6724)
#
# 왜 필요한가:
#   `cleanup-worktrees.ps1 -OrphanScan` 은 idle 가드 파라미터를 **전달하지 않았다**. 고아 경로의
#   유일한 시간 가드는 **디렉터리 mtime** 이었고, Windows 에서 디렉터리 mtime 은 안쪽 파일 편집으로
#   갱신되지 않는다. 그 결과 연결 이슈가 READY 인 상태의 worktree 도 "삭제 예정"으로 분류됐다
#   (실측: giip #6575 세션 — D:\temp\worktrees\lowyworkenv\isn6442-know103, 1시간 45분 만 생성).
#   게다가 고아 경로에는 rule 47 의 "연결 이슈 DONE" 최종 조건 검사 자체가 없었고,
#   등록정보(dangling .git)가 소실된 고아는 **미커밋 산출물 여부를 확인할 방법이 없다**.
#
# 고정하는 것(양방향 — rule 42 "검사기가 0개를 검사하고 PASS 를 반환하는 것은 통과가 아니다"):
#   A. 순수 판정(Get-GissueOrphanCleanupVerdict) — 7개 매트릭스 + isn 추출 규칙
#   B. 엔진 경로(Invoke-GissueOrphanCleanup -DryRun) — 실제 git 레포/고아 픽스처로
#      "오래된 고아 + 이슈 DONE" → 삭제 대상 / "오래된 고아 + 이슈 OPEN" → 수동확인 /
#      "방금 고친 고아" → 보호 / "등록정보 소실 고아" → 수동확인 을 **실제로** 확인한다.
#   C. 삭제 안전성 — DryRun 이면 픽스처가 그대로 있고, 보호/수동확인 항목은 Removed 에 들어가지 않는다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-orphan-scan-idle-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 임시 디렉터리($env:TEMP\gissue-orphan-scan-test-<pid>)만 쓴다 — 살아있는 체크아웃이나
# D:\temp\worktrees 를 절대 건드리지 않는다. 네트워크는 쓰지 않는다(이슈 상태 조회는 스텁한다).

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
Write-Output 'A. 고아 삭제 판정 순수함수(Get-GissueOrphanCleanupVerdict)'

$now = [datetime]::UtcNow

function New-TestActivity($determined, $newestUtc, $source = 'tree') {
    [pscustomobject]@{ Determined = $determined; NewestUtc = $newestUtc; Source = $source; Detail = '(test)' }
}
function New-TestLinkScan([int]$linkCount = 0, [bool]$scanFailed = $false) {
    $links = @()
    for ($i = 0; $i -lt $linkCount; $i++) { $links += "C:\test\link$i" }
    [pscustomobject]@{ Links = $links; ScanFailed = $scanFailed; Truncated = $false; NewestWriteUtc = $null }
}
function New-TestIssueVerdict($verdict, $status) {
    [pscustomobject]@{ Isn = 0; Found = $true; Status = $status; Verdict = $verdict; Detail = '(test)' }
}
function New-TestOrphan($status = 'OrphanUnlisted', $path = 'C:\test\isn9001-x') {
    [pscustomobject]@{ Path = $path; Status = $status; Reason = '(test)' }
}

$actOld   = New-TestActivity $true $now.AddHours(-5)
$actNew   = New-TestActivity $true $now.AddMinutes(-5)
$actNone  = New-TestActivity $false $null
$linkNone = New-TestLinkScan 0 $false
$done     = New-TestIssueVerdict 'Done'   'DONE'
$open     = New-TestIssueVerdict 'Open'   'READY'
$unknown  = New-TestIssueVerdict 'Unknown' $null

# A-1 최근 활동(5분 전) → Protected (삭제 금지)
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $done -NowUtc $now -Activity $actNew
Assert-True ($v.Decision -eq 'Protected') 'A-1 최근 활동 → Protected' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-2 오래된 활동 + 연결 이슈 DONE → Delete
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $done -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'Delete') 'A-2 오래됨 + 이슈 DONE → Delete' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-3 오래된 활동 + 연결 이슈 OPEN → ManualReview (rule 47 최종 조건)
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $open -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'ManualReview') 'A-3 오래됨 + 이슈 OPEN → ManualReview' "Decision=$($v.Decision) Reason=$($v.Reason)"
Assert-True ("$($v.Reason)" -match 'READY') 'A-3b 사유에 연결 이슈 상태 표기' "Reason=$($v.Reason)"

# A-4 오래된 활동 + 연결 이슈 Unknown(조회 실패) → ManualReview
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $unknown -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'ManualReview') 'A-4 오래됨 + 이슈 Unknown → ManualReview' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-5 오래된 활동 + 연결 이슈 DONE + 등록정보 소실(OrphanNoAdmin) → ManualReview
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan 'OrphanNoAdmin') -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $done -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'ManualReview') 'A-5 등록정보 소실 → ManualReview' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-6 링크/정션 포함 → ManualReview
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan (New-TestLinkScan 2 $false) `
    -IssueVerdict $done -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'ManualReview') 'A-6 링크 포함 → ManualReview' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-7 활동 시각 판정 불가 → Protected (fail-closed)
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan) -MinIdleMinutes 120 -LinkScan $linkNone `
    -IssueVerdict $done -NowUtc $now -Activity $actNone
Assert-True ($v.Decision -eq 'Protected') 'A-7 활동 판정 불가 → Protected(fail-closed)' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-8 연결 이슈 식별 불가(이름에 isn 없음) → ManualReview (fail-closed)
$v = Get-GissueOrphanCleanupVerdict -Orphan (New-TestOrphan 'OrphanUnlisted' 'C:\test\no-issue-here') `
    -MinIdleMinutes 120 -LinkScan $linkNone -IssueVerdict $null -NowUtc $now -Activity $actOld
Assert-True ($v.Decision -eq 'ManualReview') 'A-8 연결 이슈 식별 불가 → ManualReview' "Decision=$($v.Decision) Reason=$($v.Reason)"

# A-9 isn 추출 규칙
Assert-True ((Get-GissueOrphanIssueNumber 'D:\temp\worktrees\lowyworkenv\isn6442-know103') -eq 6442) 'A-9 isn6442-know103 → 6442' ''
Assert-True ((Get-GissueOrphanIssueNumber 'D:\temp\worktrees\giip-6558-mergegate-logtype') -eq 6558) 'A-9b giip-6558-... → 6558' ''
Assert-True ((Get-GissueOrphanIssueNumber 'D:\temp\worktrees\task-giip-1545') -eq 1545) 'A-9c task-giip-1545 → 1545' ''
Assert-True ($null -eq (Get-GissueOrphanIssueNumber 'D:\temp\worktrees\some-random-dir')) 'A-9d isn 없음 → $null' ''

# A-10 이슈 상태 1줄 JSON 파서(순수) — 멤버 접근 보간 누락 회귀.
#     PowerShell 큰따옴표 문자열 안의 "$j.status" 는 $j 를 보간한 뒤 ".status" 를 리터럴로
#     붙인다 → 판정값이 "<전체 객체>.status" 가 되고 Verdict 가 전부 Unknown 으로 붕괴한다.
#     이 부류의 결함은 "파일을 읽고 실행해야만" 드러나므로 순수 함수로 떼어내 직접 검증한다.
$doneLine = '{"isn":1545,"found":true,"status":"DONE","verdict":"Done","detail":"이슈 상태=DONE"}'
$pv = ConvertTo-GissueIssueCleanupVerdict -Line $doneLine -Isn 1545
Assert-True ($pv.Verdict -eq 'Done') 'A-10 DONE 줄 → Verdict=Done' "Verdict=$($pv.Verdict)"
Assert-True ($pv.Status -eq 'DONE') 'A-10b DONE 줄 → Status=DONE' "Status=$($pv.Status)"
Assert-True ($pv.Detail -eq '이슈 상태=DONE') 'A-10c DONE 줄 → Detail 이 통째로' "Detail=$($pv.Detail)"
Assert-True ($pv.Found -eq $true) 'A-10d DONE 줄 → Found=true' ''

$openLine = '{"isn":6442,"found":true,"status":"READY","verdict":"Open","detail":"이슈 상태=READY"}'
$pv = ConvertTo-GissueIssueCleanupVerdict -Line $openLine -Isn 6442
Assert-True ($pv.Verdict -eq 'Open') 'A-11 READY 줄 → Verdict=Open' "Verdict=$($pv.Verdict)"
Assert-True ($pv.Status -eq 'READY') 'A-11b READY 줄 → Status=READY' "Status=$($pv.Status)"

$absentLine = '{"isn":999999,"found":false,"status":null,"verdict":"Unknown","detail":"이슈 상태 미확인(error_code=ISSUE_NOT_FOUND_OR_NO_PERMISSION, HTTP 404)"}'
$pv = ConvertTo-GissueIssueCleanupVerdict -Line $absentLine -Isn 999999
Assert-True ($pv.Verdict -eq 'Unknown') 'A-12 부재(404) 줄 → Verdict=Unknown(삭제 허용 근거 아님)' "Verdict=$($pv.Verdict)"
Assert-True ($pv.Found -eq $false) 'A-12b 부재 줄 → Found=false' ''
Assert-True ($null -eq $pv.Status) 'A-12c 부재 줄 → Status=null' "Status=$($pv.Status)"

$pv = ConvertTo-GissueIssueCleanupVerdict -Line 'not-json-at-all' -Isn 1
Assert-True ($pv.Verdict -eq 'Unknown') 'A-13 파싱 불가 줄 → Verdict=Unknown' "Verdict=$($pv.Verdict)"

# ──────────────────────────────────────────────────────────────────────────────
# B. 엔진 경로 회귀 — 실제 git 레포 + 실제 고아 픽스처
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. 엔진(Invoke-GissueOrphanCleanup -DryRun) 양방향'

# [CI 결선] 임시 루트를 전체 경로(long form) 로 고정한다 — 8.3 단축 경로면 엔진이 해석한 경로와
# 이 테스트가 비교하는 문자열이 어긋난다(giip #2463 회귀 테스트와 동일).
$tempRootLong = (Get-Item -LiteralPath $env:TEMP).FullName
$root = Join-Path $tempRootLong ("gissue-orphan-scan-test-$PID")
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$repo = Join-Path $root 'repo'
$scanRoot = Join-Path $root 'scan'
New-Item -ItemType Directory -Path $repo -Force | Out-Null
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

function Invoke-Git { param([string[]]$GitArgs) $out = & git @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 실패: $out" }; return $out }

Invoke-Git @('-C', $repo, 'init', '-q', '-b', 'main')
Invoke-Git @('-C', $repo, 'config', 'user.email', 'test@example.invalid')
Invoke-Git @('-C', $repo, 'config', 'user.name', 'orphan-guard-test')
Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', 'https://example.invalid/test/orphan-guard.git')
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'orphan guard test' -Encoding UTF8
Invoke-Git @('-C', $repo, 'add', '-A')
Invoke-Git @('-C', $repo, 'commit', '-q', '-m', 'init')

# 픽스처: 디렉터리 mtime 과 git 관리 디렉터리 mtime 을 함께 오래된 시각으로 되돌린다.
#   주의: [System.IO.File]::SetLastWriteTimeUtc 는 **디렉터리에는 통하지 않는다**(File API).
#   디렉터리까지 함께 되돌려야 트리 최신 시각 판정이 '지금'으로 남아 테스트가 무의미해지지 않는다.
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
function Set-DirAge([string]$Path, [datetime]$Utc) {
    try { [System.IO.Directory]::SetLastWriteTimeUtc($Path, $Utc) } catch {}
}

# 고아 픽스처를 만든다 — `git worktree` 로 만들되 **관리 디렉터리의 `gitdir` 파일을 지워**
# `git worktree list` 에 등재되지 않게 한다 → Status=OrphanUnlisted.
# (이 방식이 실제로 등재되지 않는다는 것은 이 테스트가 관측해 확인한다 — 아래 B-0.)
function New-OrphanFixture([string]$Name, [string]$Branch) {
    $wt = Join-Path $scanRoot $Name
    Invoke-Git @('-C', $repo, 'worktree', 'add', '-q', '-b', $Branch, $wt, 'main')
    $admin = Join-Path (Join-Path $repo '.git\worktrees') (Split-Path -Leaf $wt)
    Remove-Item -LiteralPath (Join-Path $admin 'gitdir') -Force -ErrorAction SilentlyContinue
    return @{ Path = $wt; Admin = $admin }
}

$oldUtc = [datetime]::UtcNow.AddHours(-5)

# (1) 오래된 고아 + 연결 이슈 DONE → 삭제 대상이어야 한다
$fxDone = New-OrphanFixture 'isn9001-done' 'feat/orphan-done'
Set-TreeAge $fxDone.Path $oldUtc
Set-TreeAge $fxDone.Admin $oldUtc

# (2) 오래된 고아 + 연결 이슈 OPEN → 수동확인이어야 한다
$fxOpen = New-OrphanFixture 'isn9002-open' 'feat/orphan-open'
Set-TreeAge $fxOpen.Path $oldUtc
Set-TreeAge $fxOpen.Admin $oldUtc

# (3) 디렉터리 mtime 은 오래됐지만 **방금 파일을 고친** 고아 → 보호되어야 한다
#     (이것이 이번 결함의 정면 — 디렉터리 mtime 만 보던 판정이 여기서 "삭제 예정"으로 내려갔다)
$fxRecent = New-OrphanFixture 'isn9003-recent' 'feat/orphan-recent'
Set-TreeAge $fxRecent.Path $oldUtc
Set-TreeAge $fxRecent.Admin $oldUtc
Set-Content -LiteralPath (Join-Path $fxRecent.Path 'just-now.txt') -Value 'edited now' -Encoding UTF8
Set-DirAge $fxRecent.Path $oldUtc

# (4) 등록정보 소실(dangling .git) 고아 → 수동확인이어야 한다
$fxDangling = Join-Path $scanRoot 'isn9004-dangling'
New-Item -ItemType Directory -Path $fxDangling -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fxDangling '.git') `
    -Value ("gitdir: " + (Join-Path $repo '.git\worktrees\isn9004-missing') + "`n") -Encoding ASCII
Set-TreeAge $fxDangling $oldUtc

# B-0 픽스처 관측 — 관리 디렉터리는 실재하고 worktree list 에는 등재되지 않아야 OrphanUnlisted 다.
$listed = @(Invoke-Git @('-C', $repo, 'worktree', 'list', '--porcelain') | Where-Object { $_ -like 'worktree *' })
$listedPaths = @($listed | ForEach-Object { ("$_" -replace '^worktree\s+', '') })
Assert-True (-not ($listedPaths -contains $fxDone.Path)) 'B-0 픽스처가 worktree list 에 등재되지 않음' "listed=$($listedPaths -join ' | ')"
Assert-True (Test-Path -LiteralPath $fxDone.Admin) 'B-0b 픽스처 관리 디렉터리는 실재' ''

# 이슈 상태 조회는 스텁한다 — 네트워크 없이 "DONE / OPEN / Unknown" 을 만든다.
# dot-source 로 같은 스코프에 들어온 엔진은 호출 시점에 이 정의를 찾는다.
function Get-GissueIssueCleanupVerdict {
    param([Parameter(Mandatory = $true)][int]$Isn, [int]$Csn = 0)
    switch ($Isn) {
        9001 { return [pscustomobject]@{ Isn = $Isn; Found = $true; Status = 'DONE'; Verdict = 'Done'; Detail = '(stub)' } }
        9002 { return [pscustomobject]@{ Isn = $Isn; Found = $true; Status = 'READY'; Verdict = 'Open'; Detail = '(stub)' } }
        9004 { return [pscustomobject]@{ Isn = $Isn; Found = $true; Status = 'DONE'; Verdict = 'Done'; Detail = '(stub)' } }
        default { return [pscustomobject]@{ Isn = $Isn; Found = $false; Status = $null; Verdict = 'Unknown'; Detail = '(stub)' } }
    }
}

$logLines = New-Object System.Collections.ArrayList
$logger = { param($m) [void]$logLines.Add([string]$m) }
$r = $null
Invoke-GissueOrphanCleanup -ScanRoot $scanRoot -Csn 70424 -MinIdleMinutes 120 -ProtectRecentMinutes 60 `
    -DryRun -Log $logger -ResultRef ([ref]$r)

$log = ($logLines -join "`n")
Write-Output '  --- 엔진 로그 ---'
foreach ($l in $logLines) { Write-Output "  | $l" }
Write-Output '  -----------------'

Assert-True ($null -ne $r) 'B-1 엔진이 결과를 돌려주었음' ''
$removedPaths = @(@($r.Removed) | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$manualPaths = @(@($r.ManualReview) | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })
$protectedPaths = @(@($r.Protected) | ForEach-Object { ([string]$_.Path).TrimEnd('\', '/') })

$doneNorm = (Resolve-Path -LiteralPath $fxDone.Path).Path.TrimEnd('\', '/')
$openNorm = (Resolve-Path -LiteralPath $fxOpen.Path).Path.TrimEnd('\', '/')
$recentNorm = (Resolve-Path -LiteralPath $fxRecent.Path).Path.TrimEnd('\', '/')
$danglingNorm = (Resolve-Path -LiteralPath $fxDangling).Path.TrimEnd('\', '/')

Assert-True ($removedPaths -contains $doneNorm) 'B-2 오래된 고아 + 이슈 DONE → 삭제 대상' "Removed=$($removedPaths -join ', ')"
Assert-True ($removedPaths -notcontains $openNorm) 'B-3 오래된 고아 + 이슈 OPEN → 삭제 대상 아님' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $openNorm) 'B-3b 이슈 OPEN 고아 → 수동확인 목록' "Manual=$($manualPaths -join ', ')"
Assert-True ($removedPaths -notcontains $recentNorm) 'B-4 방금 고친 고아 → 삭제 대상 아님' "Removed=$($removedPaths -join ', ')"
Assert-True ($protectedPaths -contains $recentNorm) 'B-4b 방금 고친 고아 → 보호 목록' "Protected=$($protectedPaths -join ', ')"
Assert-True ($removedPaths -notcontains $danglingNorm) 'B-5 등록정보 소실 고아 → 삭제 대상 아님' "Removed=$($removedPaths -join ', ')"
Assert-True ($manualPaths -contains $danglingNorm) 'B-5b 등록정보 소실 고아 → 수동확인 목록' "Manual=$($manualPaths -join ', ')"
$deleteLogPat = '\[DRY-RUN\] 삭제 예정\(고아, 링크 없음 확인됨\): ' + [regex]::Escape($openNorm)
Assert-True ($log -notmatch $deleteLogPat) 'B-6 이슈 OPEN 고아 는 삭제 예정 로그가 없다' ''
Assert-True ($log -match 'PROTECTED\(idle 가드\)') 'B-6b 보호 사유 로그에 idle 가드 표기(rule 47 §5)' ''

# B-7 판정 수단 없이 삭제 경로를 열지 않는다(-Csn <= 0 → 중단)
$r2 = $null
Invoke-GissueOrphanCleanup -ScanRoot $scanRoot -Csn 0 -MinIdleMinutes 120 -DryRun -Log $logger -ResultRef ([ref]$r2)
Assert-True ($r2.Aborted -eq $true) 'B-7 -Csn 없으면 삭제 경로를 열지 않음(중단)' "Aborted=$($r2.Aborted) Reason=$($r2.AbortReason)"
Assert-True (@($r2.Removed).Count -eq 0) 'B-7b -Csn 없으면 삭제 0건' "Removed=$(@($r2.Removed).Count)"

# ──────────────────────────────────────────────────────────────────────────────
# C. 삭제 안전성 — DryRun 은 실제로 아무것도 지우지 않는다
# ──────────────────────────────────────────────────────────────────────────────
Assert-True (Test-Path -LiteralPath $fxDone.Path)    'C-1 DryRun 은 실제 삭제하지 않음(done)' ''
Assert-True (Test-Path -LiteralPath $fxOpen.Path)    'C-1b DryRun 은 실제 삭제하지 않음(open)' ''
Assert-True (Test-Path -LiteralPath $fxRecent.Path)  'C-1c DryRun 은 실제 삭제하지 않음(recent)' ''
Assert-True (Test-Path -LiteralPath $fxDangling)     'C-1d DryRun 은 실제 삭제하지 않음(dangling)' ''
Assert-True ($removedPaths.Count -eq 1) 'C-2 삭제 대상은 "이슈 DONE + 오래됨" 1건뿐이다' "Removed=$($removedPaths -join ', ')"

# ── 정리: 이 테스트가 만든 임시 레포만 제거한다(rule 55 — 링크 선검사 후 삭제) ──
try {
    if (Test-GissueWorktreeHasLink $root) {
        Write-Output "  NOTE: 임시 루트에 링크가 감지되어 자동 삭제하지 않음 — 수동 확인: $root"
    } else {
        Remove-Item -LiteralPath $root -Recurse -Force -Confirm:$false
    }
} catch {
    Write-Output "  NOTE: 임시 루트 정리 실패(무해) — $($_.Exception.Message) / 경로: $root"
}

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
