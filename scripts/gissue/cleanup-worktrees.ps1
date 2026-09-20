# cleanup-worktrees.ps1 — 1회성 worktree 정리 (giip #2220)
#
# 배경: 2026-09-08/09 이틀 연속 C드라이브 고갈 인시던트 — run-gissue-claude.ps1(giip 이슈 자동처리
#   스케줄러)이 nested repo(giipprj/giipv3 등)마다 이슈별로 `git worktree add` 를 만들면서도, 처리
#   종료 후 그 worktree 를 지우는 로직이 전혀 없어 무한 누적됐다(giipv3 만 25개 → 76개+로 폭증).
#   상시 방지 로직은 run-gissue-claude.ps1 의 Invoke-GissueWorktreeCleanup(Complete-Run 에서 CSN 잡
#   종료마다 자동 호출)로 별도 추가했다 — 이 스크립트는 "이미 쌓인 기존 76개+"를 1회성으로 치우는
#   용도다.
#
# 이 저장소들은 squash-merge 컨벤션을 쓴다 — 즉 PR 이 머지돼도 그 브랜치는 `origin/main` 의 조상이
#   되지 않는다(squash 커밋은 별도 새 커밋이라 `git merge-base --is-ancestor`/`rev-list --count
#   origin/main..<branch>` 로는 "머지 안 됨(ahead>0)"으로 오판된다 — 실제로 오늘 세션에서 이 방법으로
#   giip #2207/#2208 이 이미 머지됐는데도 미머지로 오판될 뻔한 사례를 발견했다). 그래서 이 스크립트는
#   ahead-count 를 쓰지 않고, `gh pr list --state merged --json headRefName` 로 그 브랜치명이 실제로
#   머지된 PR 목록에 있는지 직접 확인한다.
#
# 안전 원칙(무인 삭제 금지 — 사람 미완료 작업일 수 있음):
#   - 머지 확인된 것만 자동 삭제(worktree remove + 로컬/원격 브랜치 삭제). 확인 없이 바로 삭제하되,
#     아래 세이프가드(주 worktree 제외/locked 제외/.claude\worktrees 제외)는 항상 적용한다.
#   - 머지 안 된 것은 절대 삭제하지 않는다 — 목록만 만들어 사람에게 제안(REPORT 섹션에 출력).
#   - locked worktree 는 이유 불문 절대 건드리지 않는다.
#   - `.claude\worktrees\` 경로는 Claude Code 자체 세션 격리 메커니즘이라 완전히 별개 — 항상 제외.
#
# 사용법:
#   [실행 셸] 이 배포 대상에는 PowerShell 7(pwsh)이 없을 수 있다 — 항상 Windows PowerShell 5.1 로
#   호출한다(giip #2559: pwsh 로 부르면 command not found 로 아무 일도 하지 않고 끝난다).
#   powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-worktrees.ps1 -RepoPath "<프로젝트 컨테이너>" [-DryRun]
#   powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-worktrees.ps1 -RepoPath "<프로젝트 컨테이너>\<nested repo>" [-DryRun]
#   powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-worktrees.ps1 -AllRepos [-DryRun]
#
# 2026-09-14 (giip #2438 / #2440): 판정·삭제 엔진을 공용 모듈 `worktree-safety.ps1` 의
#   `Invoke-GissueWorktreeCleanupForRepo` 한 곳으로 옮겼다. 이전엔 이 파일과 `run-gissue-claude.ps1` 에
#   판정이 복붙 중복돼 있어 한쪽(이 파일)에만 squash-merge 대응 머지판정이 들어가는 격차가 생겼고,
#   그 결과 상시 로직이 사실상 아무것도 못 지욬다. 이제 두 호출자는 **동일한 정책**을 쓴다.
#   rule 55 §2-예외(node_modules 정션 한정, giip #2438 오너 결정 2026-09-14)도 그 엔진에 있다.
#
# -AllRepos: csn-projects.json 에 등록된 전 프로젝트 workdir + 그 직계 자식 git 레포를 전부 훑는다
#   (giip #2440 원인 3 — CSN workdir 직계자식 스코프 밖 레포가 영구 방치되던 문제. 실측: uamath 6건 22일 방치).
# -OnlyPath: 그 경로의 worktree 1건만 처리한다(핀포인트 정리/절차 검증용).
# -MinIdleMinutes: 트리 안 파일이 최근 N분 이내에 바뀜 worktree 는 "사람/다른 세션이 작업 중"으로
#   보고 건너뛴다(기본 120분, 0 이면 비활성).
#
# -DryRun: 실제 삭제 없이 무엇을 지울지/보류할지만 출력.
# -DeleteRemoteBranch: 머지 확인된 브랜치의 원격 브랜치도 삭제 시도(기본 $true — 이미 머지된 브랜치의
#   원격 잔가지 청소). GitHub 가 PR 머지 시 자동으로 원격 브랜치를 지웠으면(auto-delete 설정) 그냥
#   "이미 없음"으로 조용히 넘어간다.

# -OrphanScan (giip #2439): 위 모드와 달리 `git worktree list` 가 아니라 **파일시스템**에서 출발한다.
#   `-ScanRoot`(기본 D:\temp\worktrees) 아래에서 `.git` 을 가진 디렉터리를 전부 모은 뒤 각 `.git` 의
#   `gitdir:` 포인터를 직접 열어 소속 레포를 알아내고, 그 레포의 worktree list 에 없으면 "고아"로
#   분류한다. 등록정보(`<repo>/.git/worktrees/<name>`)가 사라진 worktree 는 `git worktree list` 에
#   아예 나타나지 않아 기존 정리 도구 2종이 **구조적으로 도달 불가**였다(giip #2439 에서 50건 실측).
#   `git worktree prune` 도 방향이 반대다 — 디렉터리가 사라진 등록정보를 지우는 것이지, 등록정보가
#   사라진 디렉터리를 지우지 않는다.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-worktrees.ps1 -OrphanScan [-DryRun] [-Protect <경로>,...] [-ScanRoot <경로>]
#
#   고아는 등록정보가 없어 `git worktree remove` 가 통하지 않는다. 그래서 디렉터리 삭제로 회수하되
#   rule 55 절차(링크 선검사 → 항목별 삭제 → 인접 repo 재검증)를 그대로, 오히려 더 엄격하게 적용한다:
#     - 정션/심볼릭 링크를 가진 고아는 **삭제하지 않는다**. giip #2438 §2-예외는 2026-09-14 에
#       확정됐지만, 그 예외는 `git worktree remove` 를 쓰는 정상 경로 전용이다 — 고아는 등록정보가
#       없어 디렉터리 삭제로 회수해야 하므로 예외를 **의도적으로 확장하지 않았다**(사람 확인 경로 유지).
#     - `-Protect` 로 지정된 경로와 최근 `-ProtectRecentMinutes` 분 내 수정된 경로는 판정 결과와
#       무관하게 무조건 보호한다(다른 세션이 작업 중일 수 있음).
#     - 삭제 직전에 링크 검사를 **한 번 더** 수행한다(선검사와 삭제 사이의 경합 차단).

# -RemnantScan (giip #2449): `-OrphanScan` 은 `.git` 을 **가진** 디렉터리에서 출발하므로 `.git` 이
#   아예 없는 잔해는 정의상 잡지 못한다. 실측(2026-09-14) `D:\temp\worktrees` 아래 13건이 그랬고,
#   그중 `giipprj\isn1169-protocol-doc` 은 giip #2220 사고를 일으킨 정션(`giipv3` -> 라이브 레포
#   루트)을 아직 품고 있었다. 이 모드는 그 구멍을 메운다.
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-worktrees.ps1 -RemnantScan [-DryRun] [-Protect <경로>,...] [-ScanRoot <경로>]
#
#   `.git` 이 없으므로 `git worktree remove` 가 물리적으로 불가능하다 — 고아와 같은 이유로 디렉터리
#   삭제로 회수하되 rule 55 §1~3 을 더 엄격히 적용한다(링크 선검사 → §2-예외 3조건 판정 → 삭제 직전
#   2차 링크 재검사 → 항목별 삭제 → 인접 repo 즉시 재검증). 판정 엔진 정본은 worktree-safety.ps1 의
#   `Invoke-GissueRemnantCleanup` 이다.
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Repo')][string]$RepoPath,
    # giip #2440 원인 3(스코프 갭): csn-projects.json 등록 전 레포를 한 번에 훑는다.
    [Parameter(Mandatory = $true, ParameterSetName = 'AllRepos')][switch]$AllRepos,
    [Parameter(Mandatory = $true, ParameterSetName = 'Orphan')][switch]$OrphanScan,
    # giip #2449: `.git` 이 아예 없는 잔해 회수.
    [Parameter(Mandatory = $true, ParameterSetName = 'Remnant')][switch]$RemnantScan,
    # -OnlyPath: 그 경로의 worktree 1건만 처리(핀포인트 정리/절차 검증용).
    [string]$OnlyPath,
    # -MinIdleMinutes: 트리 안 파일이 최근 N분 이내에 바뀜 worktree 는 "작업 중"으로 보고
    #   건너뛴다(기본 120분, 0 이면 비활성). giip #2440 후속 안전장치.
    [int]$MinIdleMinutes = 120,
    [Parameter(ParameterSetName = 'Orphan')]
    [Parameter(ParameterSetName = 'Remnant')][string[]]$ScanRoot = @('D:\temp\worktrees'),
    [string[]]$Protect = @(),
    # -ProtectFile (giip #2449): 보호 경로를 **파일에서** 읽는다(한 줄에 하나, `#` 주석/빈 줄 무시).
    #   왜 필요한가: `powershell.exe -File script.ps1 -Protect "a","b"` 형태는 셸(bash/cmd)이 따옴표를
    #   먼저 먹어 한 덩어리 문자열로 전달되고, `-File` 바인딩이 그걸 배열로 쪼개주지 않아 **보호가
    #   조용히 무력화된다**(2026-09-14 실측: 지정한 경로가 그대로 삭제 후보로 잡힘). giip #2432 에서
    #   "제외 지정 경로가 삭제된" 사고와 같은 실패 계열이라 셸 인용에 의존하지 않는 경로를 만든다.
    [string]$ProtectFile,
    [Parameter(ParameterSetName = 'Orphan')]
    [Parameter(ParameterSetName = 'Remnant')][int]$ProtectRecentMinutes = 60,
    # 콘솔 코드페이지(CP949)가 한글 로그를 '?' 로 뭉개서 rule 55 §5 의 과정 검증 로그를 남길 수 없다.
    # -LogFile 을 주면 같은 내용을 UTF-8 로 따로 적는다.
    [string]$LogFile,
    [switch]$DryRun,
    [bool]$DeleteRemoteBranch = $true
)

# 주의(giip #2220): $ErrorActionPreference='Stop' 상태에서 native 명령을 `2>&1` 로 캡처하면 그 stderr
# 출력이 PowerShell ErrorRecord 로 감싸져 종료(terminating) 오류로 던져진다 — 이 스크립트 전체가
# git 호출 뒤 $LASTEXITCODE 를 직접 검사해 분기하는 구조라 여기서 Stop 을 켜면 그 분기 로직이 예외
# catch 블록으로 건너뛰어 무력화된다(실측: worktree remove 실패 시의 --force 재시도 분기가 전혀
# 발동하지 않음). 그래서 기본값(Continue)을 유지하고, 대신 각 git 호출 뒤 명시적으로 $LASTEXITCODE 를
# 검사한다.
$ErrorActionPreference = 'Continue'

function Write-CleanupLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $msg"
    Write-Output $line
    if ($LogFile) {
        try { [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false)) } catch {}
    }
}

# 안전게이트(giip #2232 인시던트 후속, .agent/rules/55_destructive_cleanup_incident_gate.md 반영).
# 2026-09-09 이 스크립트를 giipprj 대상으로 실제 실행하던 중, worktree 디렉토리 내부에 있던 심볼릭
# 링크(다른 살아있는 nested repo — 실제로는 giipv3 — 를 가리킴)를 `git worktree remove` 의 재귀삭제가
# 따라 들어가 giipprj/giipdb 폴더 전체와 giipv3 의 .git(이력 전체)을 삭제하는 사고가 실제로 발생했다
# (giip #2232). 그래서 이 스크립트는 이제 각 항목을 지우기 **직전**에 그 디렉토리 안에 심볼릭
# 링크/정션이 있는지 검사해 하나라도 있으면 절대 지우지 않고 사람 확인 목록(ManualReview)으로 돌리며,
# 지운 **직후**에는 이 레포와 같은 부모 폴더를 공유하는 인접 nested repo(giipdb/giipv3/giipfaw 등)의
# `.git` 존재 여부/HEAD/origin remote 를 재검증해 하나라도 달라졌으면 즉시 전체 정리를 중단한다(남은
# 항목은 절대 처리하지 않음).
#
# giip #2439/#2440: 이 안전게이트 함수들(Test-GissueWorktreeHasLink / Get-GissueRepoIntegritySnapshot)은
# 원래 이 파일과 run-gissue-claude.ps1 에 **복붙**돼 있어 한쪽만 고쳐지는 사고가 났다. 이제 정본은
# worktree-safety.ps1 한 곳이고 여기서 dot-source 한다. 아래 함수 정의를 다시 이 파일에 복사하지 말 것.
$GissueWorktreeSafety = Join-Path $PSScriptRoot 'worktree-safety.ps1'
if (-not (Test-Path -LiteralPath $GissueWorktreeSafety)) {
    Write-Output "[FATAL] 공용 안전 모듈이 없습니다: $GissueWorktreeSafety — rule 55 선검사를 수행할 수 없으므로 중단합니다."
    exit 1
}
. $GissueWorktreeSafety

# ---------------------------------------------------------------------------
# 보호 경로 확정 (giip #2449).
# `-Protect` 는 셸 인용에 따라 "a,b,c" 한 덩어리로 들어올 수 있어 그대로 쓰면 보호가 조용히
# 깨진다. 여기서 콤마/개행으로 한 번 더 쪼개고, `-ProtectFile` 내용을 합친 뒤 **실제로 적용되는
# 목록을 로그에 찍는다** — 보호가 먹었는지 사람이 눈으로 확인할 수 있어야 한다(rule 55 §5).
# ---------------------------------------------------------------------------
$ProtectEffective = @()
foreach ($p in @($Protect)) {
    if (-not $p) { continue }
    $ProtectEffective += @($p -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($ProtectFile) {
    if (-not (Test-Path -LiteralPath $ProtectFile)) {
        Write-CleanupLog "[FATAL] -ProtectFile 경로가 없습니다: $ProtectFile — 보호 목록을 못 읽은 채 삭제하지 않습니다."
        exit 1
    }
    foreach ($line in (Get-Content -LiteralPath $ProtectFile -Encoding UTF8)) {
        $t = "$line".Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $ProtectEffective += $t
    }
}
$ProtectEffective = @($ProtectEffective | Select-Object -Unique)
$Protect = $ProtectEffective
if ($ProtectEffective.Count -gt 0) {
    Write-CleanupLog "보호 경로 $($ProtectEffective.Count)건 적용:"
    foreach ($p in $ProtectEffective) {
        $exists = if (Test-Path -LiteralPath $p) { '존재' } else { 'WARN: 경로 없음(오타 의심)' }
        Write-CleanupLog "  - $p [$exists]"
    }
}

# ===========================================================================
# -RemnantScan 모드 (giip #2449) — `.git` 이 아예 없는 잔해 회수.
# 판정·삭제 절차는 전부 worktree-safety.ps1 의 Invoke-GissueRemnantCleanup 이 구현한다
# (rule 55 §140 "공용 함수는 한 벌만" — 여기에 복붙하지 말 것).
# ===========================================================================
if ($RemnantScan) {
    Write-CleanupLog "=== .git 없는 잔해 스캔 시작 (ScanRoot=$($ScanRoot -join ', '), DryRun=$($DryRun.IsPresent)) ==="
    $rr = $null
    Invoke-GissueRemnantCleanup -ScanRoot $ScanRoot -DryRun:$DryRun -Log { param($m) Write-CleanupLog $m } `
        -ProtectedPaths $Protect -ProtectRecentMinutes $ProtectRecentMinutes `
        -MinIdleMinutes $MinIdleMinutes -ResultRef ([ref]$rr)
    if ($null -eq $rr) {
        Write-CleanupLog 'ERROR: 잔해 정리 엔진이 결과를 돌려주지 않았습니다.'
        exit 1
    }
    if ($rr.Aborted) { Write-CleanupLog "=== 중단됨(rule 55 게이트 발동): $($rr.AbortReason) ===" }
    Write-CleanupLog "=== 잔해 정리 요약: 삭제 $($rr.Removed.Count)건 / 보호 $($rr.Protected.Count)건 / 수동확인 $($rr.ManualReview.Count)건 (전체 $($rr.Scanned)건) ==="
    if ($rr.Protected.Count -gt 0) {
        Write-CleanupLog '--- 보호(남김) 목록 ---'
        foreach ($m in $rr.Protected) { Write-CleanupLog "  - $($m.Path) :: $($m.Reason)" }
    }
    if ($rr.ManualReview.Count -gt 0) {
        Write-CleanupLog '--- 수동확인 필요(남김) 목록 ---'
        foreach ($m in $rr.ManualReview) { Write-CleanupLog "  - $($m.Path) :: $($m.Reason)" }
    }
    [pscustomobject]@{
        Mode         = 'RemnantScan'
        DryRun       = [bool]$DryRun.IsPresent
        ScannedTotal = $rr.Scanned
        Removed      = $rr.Removed
        Protected    = $rr.Protected
        ManualReview = $rr.ManualReview
        Aborted      = $rr.Aborted
        AbortReason  = $rr.AbortReason
    }
    exit 0
}

# ===========================================================================
# -OrphanScan 모드 (giip #2439) — 파일시스템 출발 고아 회수.
# ===========================================================================
if ($OrphanScan) {
    Write-CleanupLog "=== 고아 worktree 스캔 시작 (ScanRoot=$($ScanRoot -join ', '), DryRun=$($DryRun.IsPresent)) ==="

    $all = Get-GissueOrphanWorktree -ScanRoot $ScanRoot
    Write-CleanupLog "디스크상 .git 보유 디렉터리 $($all.Count)건 발견"

    # 상태별 집계
    foreach ($grp in ($all | Group-Object Status | Sort-Object Name)) {
        Write-CleanupLog "  상태 $($grp.Name): $($grp.Count)건"
    }

    # giip #2449: `.git` 이 아예 없는 잔해는 이 스캐너의 정의 밖이다(출발점이 `.git` 보유 디렉터리).
    # 여기서는 **보고만** 하고 손대지 않는다 — 회수는 `-RemnantScan` 모드가 담당한다.
    $noGit = @(Get-GissueNoGitRemnant -ScanRoot $ScanRoot)
    if ($noGit.Count -gt 0) {
        Write-CleanupLog "  상태 NoGit: $($noGit.Count)건 (이 모드의 정의 밖 — 회수는 -RemnantScan 으로, giip #2449)"
        foreach ($n in $noGit) {
            $linkNote = if ($n.ScanFailed) { '링크스캔실패' } elseif ($n.LinkCount -gt 0) { "링크 $($n.LinkCount)건" } else { '링크없음' }
            Write-CleanupLog "    - $($n.Path) [$linkNote, 최상위 $($n.TopEntries)개]"
        }
    }

    $orphans = @($all | Where-Object { $_.Status -like 'Orphan*' })
    Write-CleanupLog "--- 고아 $($orphans.Count)건 (레포별 내역) ---"
    foreach ($grp in ($orphans | Group-Object RepoLabel | Sort-Object Name)) {
        Write-CleanupLog "  [$($grp.Name)] $($grp.Count)건: $((@($grp.Group | ForEach-Object { Split-Path -Leaf $_.Path })) -join ', ')"
    }

    # 경로 구분자 소실 탐지(등록된 것/디스크 양쪽) — 자동삭제하지 않고 보고만 한다.
    $malformed = @()
    foreach ($repo in @($all | Where-Object { $_.OwnerRepo } | Select-Object -ExpandProperty OwnerRepo -Unique)) {
        foreach ($p in (Get-GissueRegisteredWorktreePath $repo)) {
            if (Test-GissueMalformedWorktreePath $p) { $malformed += "[$repo] $p" }
        }
    }
    if ($malformed.Count -gt 0) {
        Write-CleanupLog "--- WARN: 경로 구분자가 소실된 worktree 등록 $($malformed.Count)건(자동삭제 안 함, giip #2439) ---"
        foreach ($m in $malformed) { Write-CleanupLog "  - $m" }
    }

    $protectNorm = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in $Protect) { [void]$protectNorm.Add((ConvertTo-GissueComparablePath $p)) }
    $cutoff = (Get-Date).AddMinutes(-1 * $ProtectRecentMinutes)

    $oRemoved = @(); $oManual = @(); $oProtected = @()
    $oAbort = $false; $oAbortReason = $null

    # rule 55 §3 재검증 대상: 고아들이 속한 모든 레포 + 그 레포들의 형제 레포.
    $verifyRepos = @($all | Where-Object { $_.OwnerRepo } | Select-Object -ExpandProperty OwnerRepo -Unique)
    $verifyRepos += @($verifyRepos | ForEach-Object {
        $par = Split-Path -Parent $_
        if ($par -and (Test-Path -LiteralPath $par)) {
            Get-ChildItem -LiteralPath $par -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
                ForEach-Object { $_.FullName }
        }
    })
    # ScanRoot 하위 경로는 재검증 대상에서 제외한다 — 그 안의 항목은 **우리가 지우는 대상** 자체라,
    # 정상 삭제만으로도 "인접 레포의 .git 이 사라짐" 위반이 떠 첫 항목에서 무조건 중단된다(2026-09-14
    # 실측: giipAgentLinux 축소 실행에서 1건 삭제 직후 자기 자신을 인접 레포로 보고 오탐 abort).
    # 재검증 대상은 ScanRoot 밖의 진짜 레포여야 한다.
    $verifyRepos = @($verifyRepos | Where-Object { $_ } | Where-Object {
        $c = ConvertTo-GissueComparablePath $_
        $inScan = $false
        foreach ($r in $ScanRoot) {
            $rc = ConvertTo-GissueComparablePath $r
            if ($c -eq $rc -or $c.StartsWith($rc + '\')) { $inScan = $true }
        }
        -not $inScan
    } | Select-Object -Unique)
    if ($verifyRepos.Count -eq 0) {
        Write-CleanupLog "ERROR: 인접 nested repo 재검증 대상이 0개입니다 — rule 55 §3 검증을 할 수 없으므로 삭제를 수행하지 않습니다."
        exit 1
    }
    Write-CleanupLog "인접 nested repo 재검증 대상($($verifyRepos.Count)개): $($verifyRepos -join ', ')"

    foreach ($o in $orphans) {
        if ($oAbort) { break }
        $leaf = Split-Path -Leaf $o.Path

        # (a) 명시 보호 — 판정 결과와 무관하게 무조건 제외.
        if ($protectNorm.Contains((ConvertTo-GissueComparablePath $o.Path))) {
            Write-CleanupLog "PROTECTED(명시 지정 — 다른 세션 작업 중): $($o.Path)"
            $oProtected += [pscustomobject]@{ Path = $o.Path; Reason = '-Protect 로 명시 지정됨(다른 세션 작업 중)' }
            continue
        }
        # (b) 최근 수정 — 작업 중일 수 있으므로 남긴다("애매하면 남긴다").
        if ($o.LastWriteTime -and ($o.LastWriteTime -gt $cutoff)) {
            Write-CleanupLog "PROTECTED(최근 $ProtectRecentMinutes 분 내 수정 $($o.LastWriteTime)): $($o.Path)"
            $oProtected += [pscustomobject]@{ Path = $o.Path; Reason = "최근 $ProtectRecentMinutes 분 내 수정됨($($o.LastWriteTime)) — 작업 중일 수 있음" }
            continue
        }
        # (c) rule 55 §1-2 링크 선검사 — 링크가 있으면 절대 지우지 않는다(giip #2438 판단 대기).
        if (Test-GissueWorktreeHasLink $o.Path) {
            $detail = @(Get-GissueWorktreeLinkDetail $o.Path 5)
            Write-CleanupLog "MANUAL-REVIEW(심볼릭 링크/정션 발견 — rule 55 §1-2, 자동삭제 금지): $($o.Path)"
            foreach ($d in $detail) { Write-CleanupLog "      link: $d" }
            $oManual += [pscustomobject]@{ Path = $o.Path; Reason = "심볼릭 링크/정션 포함(표본: $($detail -join ' | ')) — rule 55 §1-2 로 자동삭제 제외" }
            continue
        }
        # (d) 경로 형태 가드 — ScanRoot 밖이거나 reparse point 자체면 손대지 않는다.
        $underRoot = $false
        foreach ($r in $ScanRoot) {
            if ((ConvertTo-GissueComparablePath $o.Path).StartsWith((ConvertTo-GissueComparablePath $r) + '\')) { $underRoot = $true }
        }
        if (-not $underRoot) {
            Write-CleanupLog "MANUAL-REVIEW(ScanRoot 밖 경로 — 삭제 거부): $($o.Path)"
            $oManual += [pscustomobject]@{ Path = $o.Path; Reason = 'ScanRoot 밖 경로' }
            continue
        }
        $selfItem = Get-Item -LiteralPath $o.Path -Force -ErrorAction SilentlyContinue
        if ($selfItem -and $selfItem.LinkType) {
            Write-CleanupLog "MANUAL-REVIEW(대상 자체가 링크/정션 — 삭제 거부): $($o.Path)"
            $oManual += [pscustomobject]@{ Path = $o.Path; Reason = '대상 디렉터리 자체가 심볼릭 링크/정션' }
            continue
        }

        if ($DryRun) {
            Write-CleanupLog "[DRY-RUN] 삭제 예정(고아, 링크 없음 확인됨): $($o.Path) — $($o.Reason)"
            $oRemoved += [pscustomobject]@{ Path = $o.Path; Reason = $o.Reason }
            continue
        }

        # rule 55 §3 — 삭제 직전 스냅샷.
        $preSnap = Get-GissueRepoIntegritySnapshot $verifyRepos
        # 선검사와 삭제 사이의 경합 차단용 2차 링크 검사(직전).
        if (Test-GissueWorktreeHasLink $o.Path) {
            Write-CleanupLog "MANUAL-REVIEW(삭제 직전 2차 검사에서 링크 발견 — 중단): $($o.Path)"
            $oManual += [pscustomobject]@{ Path = $o.Path; Reason = '삭제 직전 2차 링크 검사에서 링크 발견' }
            continue
        }
        # 고아는 등록정보가 없어 `git worktree remove` 가 통하지 않는다(rule 55 §4 의 "우선 사용"
        # 대상이 물리적으로 불가). 대신 직전 2차 링크 검사로 재귀삭제가 링크를 따라갈 여지를
        # 없앤 뒤에만 디렉터리 삭제를 수행한다.
        # giip #2449: `Remove-Item -Recurse` 는 260자 초과 경로에서 실패해 트리를 반쯤 지운 채
        # 남긴다(pnpm 스토어에서 실측). 공용 헬퍼가 \\?\ 확장 경로로 폴백한다.
        $oDel = Remove-GissueDirectoryTreeSafely -Path $o.Path -Log { param($m) Write-CleanupLog $m }
        $delOk = $oDel.Ok
        if (-not $delOk) {
            Write-CleanupLog "WARN: 고아 삭제 실패($($o.Path)) — $($oDel.Detail)"
            $oManual += [pscustomobject]@{ Path = $o.Path; Reason = "삭제 실패: $($oDel.Detail)" }
        }
        # rule 55 §3 — 삭제 직후 즉시 재검증(성공/실패 무관).
        $postSnap = Get-GissueRepoIntegritySnapshot $verifyRepos
        $oIntegrity = Compare-GissueRepoIntegrity $preSnap $postSnap
        # giip #2466 — 다른 세션의 정상 커밋으로 HEAD 가 움직인 것은 손상이 아니다. 기록만 남기고 진행.
        foreach ($w in $oIntegrity.Warnings) { Write-CleanupLog "WARN(rule 55 §3, giip #2466): $w" }
        $violations = @($oIntegrity.Violations)
        if ($violations.Count -gt 0) {
            foreach ($v in $violations) { Write-CleanupLog "CRITICAL: '$($o.Path)' 삭제 직후 — $v (giip #2232 재발 의심)" }
            Write-CleanupLog "CRITICAL: 즉시 중단합니다. 남은 항목은 처리하지 않습니다."
            $oAbort = $true; $oAbortReason = ($violations -join ' / ')
            break
        }
        if ($delOk) {
            Write-CleanupLog "삭제됨(고아, 인접 레포 무결성 재검증 통과 — 검증 $($verifyRepos.Count)개 전부 정상): $($o.Path)"
            $oRemoved += [pscustomobject]@{ Path = $o.Path; Reason = $o.Reason }
        }
    }

    if ($oAbort) {
        Write-CleanupLog "=== 중단됨(rule 55 §3 게이트 발동): $oAbortReason ==="
    }
    Write-CleanupLog "=== 고아 정리 요약: 삭제 $($oRemoved.Count)건 / 보호 $($oProtected.Count)건 / 수동확인 $($oManual.Count)건 (고아 총 $($orphans.Count)건) ==="
    if ($oProtected.Count -gt 0) {
        Write-CleanupLog "--- 보호(남김) 목록 ---"
        foreach ($m in $oProtected) { Write-CleanupLog "  - $($m.Path) :: $($m.Reason)" }
    }
    if ($oManual.Count -gt 0) {
        Write-CleanupLog "--- 수동확인 필요(남김) 목록 ---"
        foreach ($m in $oManual) { Write-CleanupLog "  - $($m.Path) :: $($m.Reason)" }
    }

    [pscustomobject]@{
        Mode         = 'OrphanScan'
        DryRun       = [bool]$DryRun.IsPresent
        ScannedTotal = $all.Count
        OrphanTotal  = $orphans.Count
        Removed      = $oRemoved
        Protected    = $oProtected
        ManualReview = $oManual
        Malformed    = $malformed
        Aborted      = $oAbort
        AbortReason  = $oAbortReason
    }
    exit 0
}

if (-not $AllRepos -and -not $RepoPath) {
    Write-CleanupLog 'ERROR: -RepoPath 또는 -AllRepos 중 하나가 필요합니다.'
    exit 1
}

# 대상 레포 목록 산출.
$targets = @()
if ($AllRepos) {
    $targets = @(Get-GissueAllProjectRepoPaths)
    if ($targets.Count -eq 0) {
        Write-CleanupLog 'ERROR: csn-projects.json 에서 대상 레포를 하나도 찾지 못했습니다.'
        exit 1
    }
    Write-CleanupLog "=== 전체 스윈 대상 $($targets.Count)개 레포: $($targets -join ', ') ==="
} else {
    if (-not (Test-Path -LiteralPath $RepoPath)) {
        Write-CleanupLog "ERROR: RepoPath 없음: $RepoPath"
        exit 1
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        Write-CleanupLog "ERROR: git 레포 아님(.git 없음): $RepoPath"
        exit 1
    }
    $targets = @((Resolve-Path -LiteralPath $RepoPath).Path)
}

$allRemoved = @()
$allManual = @()
$allLocked = @()
$aborted = $false
$abortReason = $null
$logger = { param($m) Write-CleanupLog $m }

foreach ($t in $targets) {
    if ($aborted) { break }
    Write-CleanupLog "=== $t worktree 정리 시작 (DryRun=$($DryRun.IsPresent)) ==="
    # 결과는 [ref] 로 받는다 — `$r = Invoke-...` 로 받으면 로그 콜백이 성공 스트림에 찍은 진행
    # 로그가 통째로 $r 안으로 빨려들어가 화면/리다이렉트에서 사라진다(rule 55 §5 위반).
    # 상세는 worktree-safety.ps1 의 Invoke-GissueWorktreeCleanupForRepo 헤더 주석 참조.
    $r = $null
    Invoke-GissueWorktreeCleanupForRepo -RepoPath $t -DryRun:$DryRun `
        -DeleteRemoteBranch $DeleteRemoteBranch -Log $logger -OnlyPath $OnlyPath `
        -MinIdleMinutes $MinIdleMinutes -ProtectedPaths $Protect -ResultRef ([ref]$r)
    if ($null -eq $r) { continue }
    $allRemoved += @($r.Removed)
    $allManual += @($r.ManualReview)
    $allLocked += @($r.SkippedLocked)
    if ($r.Aborted) {
        $aborted = $true
        $abortReason = $r.AbortReason
    }
}

if ($aborted) {
    Write-CleanupLog "=== 중단됨(rule 55 재발방지 게이트 발동): $abortReason — 이후 항목은 처리하지 않았습니다. 사람 확인 필요. ==="
}
Write-CleanupLog "=== 요약: 삭제 $($allRemoved.Count)건 / locked 제외 $($allLocked.Count)건 / 수동확인 필요 $($allManual.Count)건 ==="
if ($allManual.Count -gt 0) {
    Write-CleanupLog '--- 수동확인 필요 목록(자동삭제 안 함) ---'
    foreach ($m in $allManual) { Write-CleanupLog "  - $($m.Path) [branch=$($m.Branch)] $($m.Reason)" }
}

[pscustomobject]@{
    RepoPath      = ($targets -join ';')
    DryRun        = [bool]$DryRun.IsPresent
    Removed       = $allRemoved
    SkippedLocked = $allLocked
    ManualReview  = $allManual
    Aborted       = $aborted
    AbortReason   = $abortReason
}
