# worktree-safety.ps1 — worktree 안전 정리 공용 함수 모듈 (dot-source 전용, giip #2439)
#
# 왜 별도 파일인가 (giip #2440):
#   `Test-GissueWorktreeHasLink` / `Get-GissueRepoIntegritySnapshot` 이 `cleanup-worktrees.ps1` 과
#   `run-gissue-claude.ps1` 두 곳에 **복붙**돼 있어, 한쪽만 고쳐지는 사고가 이미 났다. 이 파일이
#   그 로직의 정본이고, 두 호출자는 여기를 dot-source 한다.
#
#     . (Join-Path $PSScriptRoot 'worktree-safety.ps1')
#
# 이 파일은 함수 정의만 한다 — 실행 시 부작용(파일 삭제·git 호출 등)이 전혀 없어야 한다.
# `.agent/rules/55_destructive_cleanup_incident_gate.md` 가 이 파일의 헌법이다.

# 이 모듈 자신의 디렉터리를 dot-source 시점에 고정한다.
# 주의: dot-source 된 파일 안의 **함수 본문**에서 `$PSScriptRoot` 를 읽으면 호출 시점의
# 스크립트(= 호출자 파일)의 디렉터리로 해석된다 — 모듈 자신의 위치가 아니다. 실제로 이
# 함정 때문에 `csn-projects.json` 을 호출자 폴더에서 찾아 "알려진 라이브 체크아웃 목록"이
# 통째로 비는 버그가 났다(2026-09-14 실측 검출). 그래서 dot-source 시점의 값을 변수에 박아둔다.
$script:GissueWorktreeSafetyDir = $PSScriptRoot
if (-not $script:GissueWorktreeSafetyDir) {
    $script:GissueWorktreeSafetyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# 낡은 코드 가드(giip #2471). 이 모듈은 장수 프로세스(run-gissue-claude.ps1)에 닷소싱되므로,
# 여기 담긴 삭제 판정은 그 프로세스가 죽을 때까지 갱신되지 않는다. Test-GissueCodeStale 은
# Initialize-GissueCodeFreshness 를 부른 프로세스에서만 참이 될 수 있고(= 단명 프로세스인
# cleanup-worktrees.ps1 에는 아무 영향이 없다), 그 외 모든 경우 fail-open 이다.
. (Join-Path $script:GissueWorktreeSafetyDir 'code-freshness.ps1')

# ---------------------------------------------------------------------------
# rule 55 §1-2 — 재귀삭제 전 심볼릭 링크/정션 선검사.
# 2026-09-09 사고(giip #2232): worktree 안의 `giipv3` 정션을 재귀삭제가 따라 들어가 진짜
# `giipprj/giipv3` 의 `.git` 과 `giipprj/giipdb` 전체를 삭제했다. 스캔 자체가 실패하면 **링크가
# 있다고 보수적으로 판정**해 자동삭제를 막는다("모르면 지우지 않는다").
#
# giip #2438(2026-09-14): 구현을 `Get-ChildItem -Recurse` 에서 **스택 기반 수동 순회**로 교체했다.
#   (a) reparse point 는 발견 즉시 결과로 기록하고 **그 안으로는 절대 들어가지 않는다** —
#       정션을 따라 들어가면 검사 자체가 라이브 `node_modules` 전체를 훑는다.
#   (b) `MaxLinks` 개를 찾는 즉시 순회를 중단한다(조기중단).
#   (c) 순회하는 김에 트리 안 **최신 수정시각**도 모은다(사용 중 worktree 보호용, 추가 순회 비용 없음).
#   실측(giipv3 DryRun, warm): 306.6초 -> 10.8초. 구현 근거는 rule 55 §1 참조.
# ---------------------------------------------------------------------------
# MAX_PATH(260자) 우회용 확장 경로 접두사 (giip #2449).
#
# 왜 필요한가: .NET Framework 기반 Windows PowerShell 5.1 의 `[System.IO.File]::GetAttributes` 는
# 260자를 넘는 경로에서 "Could not find a part of the path" 로 던진다. pnpm 스토어는 이 한계를
# 일상적으로 넘는다 — 실측(giip #2449): `giipv3\giip2173-tpartner` 의
# `node_modules\.pnpm\@fluentui+react-virtualizer_...\...\useVirtualizerScrollViewDynamicStyles.styles.js`
# 가 264~272자였다. 그 결과 아래 스캐너가 `ScanFailed=$true` 를 돌려주고, 그건 보수적으로
# "링크 있음"으로 판정되어 **그 worktree 는 영구히 자동정리 대상에서 빠진다**. giip #2438 이 고친
# "정션 때문에 영원히 안 지워짐"과 같은 계열의 구조적 교착이며, 이쪽은 원인이 경로 길이다.
#
# `\\?\` 접두사는 Win32 파서를 우회해 32767자까지 허용한다. 로컬 절대경로(`X:\...`)에만 붙이고,
# UNC/이미 접두사가 붙은 경로/상대경로는 그대로 둔다. 접두사는 조회에만 쓰고 **결과 문자열에는
# 남기지 않는다** — 호출자(정션 판정·삭제 경로)가 보는 경로 표기가 달라지면 안 되기 때문이다.
function ConvertTo-GissueExtendedPath([string]$p) {
    if (-not $p) { return $p }
    if ($p.StartsWith('\\?\') -or $p.StartsWith('\\.\')) { return $p }
    if ($p -match '^[A-Za-z]:\\') { return '\\?\' + $p }
    if ($p.StartsWith('\\')) { return '\\?\UNC\' + $p.Substring(2) }
    return $p
}

function Get-GissueWorktreeLinkScan {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxLinks = 1
    )
    $links = New-Object System.Collections.ArrayList
    $scanFailed = $false
    $newest = [datetime]::MinValue
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Links = @(); ScanFailed = $true; Truncated = $false; NewestWriteUtc = $null }
    }
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        if ($links.Count -ge $MaxLinks) { break }
        $dir = $stack.Pop()
        $entries = $null
        try {
            $entries = [System.IO.Directory]::EnumerateFileSystemEntries($dir)
        } catch {
            # 1차 실패 원인이 경로 길이일 수 있다 — 확장 경로로 한 번만 재시도한다(giip #2449).
            try {
                $entries = [System.IO.Directory]::EnumerateFileSystemEntries((ConvertTo-GissueExtendedPath $dir))
            } catch {
                # 접근 거부 등 — 안전 쪽으로(링크가 있다고 볼 수 있게) 실패를 표시한다.
                $scanFailed = $true
                continue
            }
        }
        foreach ($entry in $entries) {
            # 확장 경로로 열거하면 항목 경로에도 `\\?\` 가 붙어 나온다 — 판정·기록은 항상 원래
            # 표기로 하고, 접두사는 파일시스템 조회 순간에만 쓴다.
            $entryPlain = if ($entry.StartsWith('\\?\UNC\')) { '\\' + $entry.Substring(8) }
                          elseif ($entry.StartsWith('\\?\')) { $entry.Substring(4) }
                          else { $entry }
            $attr = $null
            try { $attr = [System.IO.File]::GetAttributes($entryPlain) } catch {
                try { $attr = [System.IO.File]::GetAttributes((ConvertTo-GissueExtendedPath $entryPlain)) } catch { $scanFailed = $true; continue }
            }
            if ($attr -band [System.IO.FileAttributes]::ReparsePoint) {
                [void]$links.Add($entryPlain)
                if ($links.Count -ge $MaxLinks) { break }
                continue   # ★ 절대 안으로 들어가지 않는다(giip #2232 사고의 핵심 방어선이자 성능 개선점)
            }
            try {
                $wt = [System.IO.File]::GetLastWriteTimeUtc((ConvertTo-GissueExtendedPath $entryPlain))
                if ($wt -gt $newest) { $newest = $wt }
            } catch {}
            if ($attr -band [System.IO.FileAttributes]::Directory) { $stack.Push($entryPlain) }
        }
    }
    $newestOut = $null
    if ($newest -gt [datetime]::MinValue) { $newestOut = $newest }
    return [pscustomobject]@{
        Links          = @($links.ToArray())
        ScanFailed     = $scanFailed
        Truncated      = ($links.Count -ge $MaxLinks)
        NewestWriteUtc = $newestOut
    }
}

# rule 55 §1 의 불리언 게이트(기존 시그니처 호환). 스캔 자체가 실패하면 보수적으로 "링크 있음".
function Test-GissueWorktreeHasLink($path) {
    $scan = Get-GissueWorktreeLinkScan -Path $path -MaxLinks 1
    if ($scan.ScanFailed -and $scan.Links.Count -eq 0) { return $true }
    return ($scan.Links.Count -gt 0)
}

# 링크가 발견됐을 때 "무엇이 어디를 가리키는지"를 사람이 읽을 수 있게 돌려준다(보고용).
function Get-GissueWorktreeLinkDetail($path, [int]$Max = 10) {
    try {
        # 보고용이므로 최대 $Max 건만 — 전수 열거는 대형 worktree 에서 몇 분씩 걸린다.
        return @(Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LinkType } | Select-Object -First $Max |
            ForEach-Object { "$($_.FullName) -> $($_.Target -join ',') [$($_.LinkType)]" })
    } catch {
        return @("(링크 스캔 실패: $($_.Exception.Message))")
    }
}

# ---------------------------------------------------------------------------
# rule 55 §3 — 인접 nested repo 무결성 스냅샷(.git 존재 / HEAD / origin remote).
# ---------------------------------------------------------------------------
function Get-GissueRepoIntegritySnapshot($paths) {
    $snap = @{}
    foreach ($p in $paths) {
        $pFull = try { (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { $p }
        $gitPath = Join-Path $pFull '.git'
        $exists = Test-Path -LiteralPath $gitPath
        $head = $null; $remote = $null
        if ($exists) {
            try { $head = git -C $pFull rev-parse HEAD 2>$null } catch {}
            try { $remote = (git -C $pFull remote get-url origin 2>$null) } catch {}
        }
        $snap[$pFull] = @{ Exists = $exists; Head = "$head"; Remote = "$remote" }
    }
    return $snap
}

# 주어진 sha 가 그 레포 안의 **정상 커밋 객체**인지 확인한다.
# `git cat-file -t` 는 객체가 없거나 깨졌으면 실패하므로, "HEAD 가 가리키는 값이 실재하는
# 커밋인가"를 판별하는 가장 값싼 수단이다.
function Test-GissueGitObjectIsCommit([string]$RepoPath, [string]$Sha) {
    if ([string]::IsNullOrWhiteSpace($Sha)) { return $false }
    try {
        $t = git -C $RepoPath cat-file -t $Sha 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        return ("$t".Trim() -eq 'commit')
    } catch { return $false }
}

# ---------------------------------------------------------------------------
# 스냅샷 2개를 비교한다. 결과는 `Violations`(즉시 중단) 와 `Warnings`(기록만 하고 계속) 다.
#
# giip #2466 — 판정 의미를 "불변인가"에서 "손상됐는가"로 좁힌다:
#   구현은 `$a.Head -ne $b.Head` 하나로 위반을 선언했다. 즉 규칙 문구("`.git` 존재 여부와
#   `git remote -v`/`git rev-parse HEAD` 가 **정상인지**")와 달리 **불변인지**를 보고 있었다.
#   이 PC 는 여러 세션이 같은 체크아웃을 동시에 쓰므로(메모리
#   `feedback_concurrent_subagents_shared_giipv3_checkout`), 항목 하나 삭제에 10분씩 걸리는
#   대형 트리에서는 **다른 세션의 정상 커밋/pull 한 번에 전체 정리가 중단**됐다.
#   2026-09-14 giip #2449 실행에서 3회 발생(giipv3 HEAD 이동 / bcx-v2 45분 주기 자동커밋 /
#   giipdb `pull --ff-only`). 매번 reflog 로 사고 아님이 확인됐지만 그때마다 정리가 끊겨
#   13건 중 5건만 처리하고 4패스로 쪼개야 했다.
#
#   ⚠️ 완화가 아니다 — 아래는 **그대로 즉시 중단**이다(giip #2220/#2232 사고의 실제 증상):
#     - 인접 레포가 사후 스냅샷에서 사라짐
#     - `.git` 소실
#     - `origin` remote 변경
#     - `git rev-parse HEAD` 실패(직전에는 성공했는데 지금 못 읽음) — 저장소가 깨진 것이다
#     - HEAD 가 바뀌었는데 **새 HEAD 가 정상 커밋 객체가 아님**
#     - HEAD 가 바뀌었는데 **직전 HEAD 객체가 저장소에서 사라짐** — 같은 저장소가 아니라
#       디렉터리가 통째로 교체된 정황이다(정상 커밋/머지/pull 은 직전 커밋을 항상 남긴다)
#
#   WARN 으로 강등되는 것은 **단 하나** — 새 HEAD 도 직전 HEAD 도 정상 커밋 객체로 실재하는
#   경우다. 그건 다른 세션이 정상적으로 커밋/머지/pull 했다는 뜻이고, 저장소는 멀쩡하다.
# ---------------------------------------------------------------------------
function Compare-GissueRepoIntegrity($pre, $post) {
    $violations = @()
    $warnings = @()
    foreach ($k in $pre.Keys) {
        $a = $pre[$k]; $b = $post[$k]
        if ($null -eq $b) { $violations += "인접 레포 '$k' 가 사후 스냅샷에서 사라짐"; continue }
        if ($a.Exists -and (-not $b.Exists)) { $violations += "인접 레포 '$k' 의 .git 이 사라짐"; continue }
        if (-not ($a.Exists -and $b.Exists)) { continue }

        if ($a.Remote -and ($a.Remote -ne $b.Remote)) {
            $violations += "인접 레포 '$k' 의 origin remote 변경됨($($a.Remote) -> $($b.Remote))"
        }

        if (-not $a.Head) { continue }   # 직전에도 HEAD 를 못 읽었으면 비교할 기준이 없다
        if (-not $b.Head) {
            $violations += "인접 레포 '$k' 의 git rev-parse HEAD 가 실패함(직전에는 $($a.Head) 였음) — 저장소 손상"
            continue
        }
        if ($a.Head -eq $b.Head) { continue }

        $newIsCommit = Test-GissueGitObjectIsCommit -RepoPath $k -Sha $b.Head
        $oldSurvives = Test-GissueGitObjectIsCommit -RepoPath $k -Sha $a.Head
        if (-not $newIsCommit) {
            $violations += "인접 레포 '$k' 의 HEAD 가 $($a.Head) -> $($b.Head) 로 바뀌었는데 새 HEAD 가 정상 커밋 객체가 아님 — 저장소 손상"
        } elseif (-not $oldSurvives) {
            $violations += "인접 레포 '$k' 의 HEAD 가 $($a.Head) -> $($b.Head) 로 바뀌었고 직전 HEAD 객체가 저장소에서 사라짐 — 저장소가 교체된 정황"
        } else {
            $warnings += "인접 레포 '$k' 의 HEAD 가 이동함($($a.Head) -> $($b.Head)). 새 HEAD 와 직전 HEAD 모두 정상 커밋 객체로 실재함 = 다른 세션의 정상 커밋/머지/pull. 손상 아니므로 계속 진행한다(giip #2466)."
        }
    }
    return [pscustomobject]@{ Violations = @($violations); Warnings = @($warnings) }
}

# 하위호환 래퍼 — 위반 사유 문자열 배열만 돌려준다(빈 배열이면 정상).
# 호출자는 하나라도 나오면 **즉시 중단**해야 한다(rule 55 §3).
# 경고까지 보고 싶으면 `Compare-GissueRepoIntegrity` 를 직접 쓸 것.
function Compare-GissueRepoIntegritySnapshot($pre, $post) {
    return @((Compare-GissueRepoIntegrity $pre $post).Violations)
}

# ---------------------------------------------------------------------------
# worktree 의 `.git` 포인터 해석.
#
# `git worktree add` 로 만든 worktree 의 `.git` 은 **파일**이고 내용은 한 줄이다:
#     gitdir: <프로젝트 컨테이너>/<nested repo>/.git/worktrees/<name>
# (2026-09-14 실제 파일을 직접 열어 확인함 — 추측 아님.)
# `.git` 이 **디렉터리**면 그건 worktree 가 아니라 독립 클론이다.
# ---------------------------------------------------------------------------
function Get-GissueWorktreePointer([string]$WorktreePath) {
    $dotGit = Join-Path $WorktreePath '.git'
    if (-not (Test-Path -LiteralPath $dotGit)) { return $null }
    $item = Get-Item -LiteralPath $dotGit -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }

    if ($item -is [System.IO.DirectoryInfo]) {
        # 독립 클론 — worktree 등록정보라는 개념 자체가 없다. 고아 판정 대상이 아니다.
        return [pscustomobject]@{
            WorktreePath = $WorktreePath
            Kind         = 'StandaloneClone'
            GitDir       = $item.FullName
            AdminExists  = $true
            OwnerRepo    = $WorktreePath
            Name         = Split-Path -Leaf $WorktreePath
        }
    }

    $first = $null
    try { $first = (Get-Content -LiteralPath $dotGit -TotalCount 1 -Encoding UTF8 -ErrorAction Stop) } catch {}
    $line = "$first".Trim()
    if ($line -notmatch '^gitdir:\s*(.+)$') {
        return [pscustomobject]@{
            WorktreePath = $WorktreePath
            Kind         = 'Unparsable'
            GitDir       = $null
            AdminExists  = $false
            OwnerRepo    = $null
            Name         = Split-Path -Leaf $WorktreePath
            Raw          = $line
        }
    }

    $gitDir = $Matches[1].Trim()
    # gitDir = <ownerRepo>/.git/worktrees/<name> → ownerRepo 는 3단계 위.
    $name      = Split-Path -Leaf $gitDir
    $wtRoot    = Split-Path -Parent $gitDir     # <ownerRepo>/.git/worktrees
    $ownerGit  = if ($wtRoot) { Split-Path -Parent $wtRoot } else { $null }   # <ownerRepo>/.git
    $ownerRepo = if ($ownerGit) { Split-Path -Parent $ownerGit } else { $null }

    return [pscustomobject]@{
        WorktreePath = $WorktreePath
        Kind         = 'Worktree'
        GitDir       = $gitDir
        AdminExists  = [bool](Test-Path -LiteralPath $gitDir)
        OwnerRepo    = $ownerRepo
        Name         = $name
    }
}

# 한 레포에 등록된 worktree 경로 집합(정규화된 소문자 전체경로).
function Get-GissueRegisteredWorktreePath([string]$RepoPath) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not $RepoPath -or -not (Test-Path -LiteralPath $RepoPath)) { return $set }
    $out = @(git -C $RepoPath worktree list --porcelain 2>$null)
    foreach ($line in $out) {
        if ("$line" -match '^worktree\s+(.+)$') {
            [void]$set.Add((ConvertTo-GissueComparablePath $Matches[1].Trim()))
        }
    }
    return $set
}

# 경로 비교용 정규화 — 구분자 통일 + 후행 구분자 제거 + 소문자.
function ConvertTo-GissueComparablePath([string]$p) {
    if (-not $p) { return '' }
    return ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# 고아 worktree 탐지 — **파일시스템에서 출발**하는 경로 (giip #2439).
#
# 기존 정리 도구 2종은 전부 `git worktree list` 를 순회한다. 등록정보(`.git/worktrees/<name>`)가
# 사라진 디렉터리는 그 목록에 **아예 나타나지 않으므로**, 몇 번을 돌려도 영원히 회수되지 않는다
# (`git worktree prune` 도 방향이 반대다 — 디렉터리가 사라진 등록정보를 지우는 것).
# 그래서 여기서는 디스크를 먼저 훑고, 각 `.git` 의 `gitdir:` 포인터를 직접 열어 소속 레포를 알아낸
# 뒤, 그 레포의 `git worktree list` 에 없으면 고아로 분류한다.
#
# 반환 객체의 Status:
#   Registered       — 정상(등록정보 실재 + worktree list 에 있음). 기존 도구가 처리한다.
#   OrphanNoAdmin    — `.git/worktrees/<name>` 관리 디렉터리가 없음(등록정보 소실). 전형적 고아.
#   OrphanUnlisted   — 관리 디렉터리는 있으나 그 레포의 worktree list 에 없음.
#   StandaloneClone  — `.git` 이 디렉터리(독립 클론). 고아가 아니므로 자동삭제 대상 아님.
#   Unparsable       — `.git` 파일을 읽었으나 `gitdir:` 형식이 아님. 사람 확인.
# ---------------------------------------------------------------------------
function Get-GissueOrphanWorktree {
    param(
        [string[]]$ScanRoot = @('D:\temp\worktrees'),
        [int]$Depth = 3
    )

    $found = @()
    foreach ($root in $ScanRoot) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $gitEntries = @(Get-ChildItem -LiteralPath $root -Recurse -Force -Depth $Depth -Filter '.git' -ErrorAction SilentlyContinue)
        foreach ($g in $gitEntries) {
            $parent = if ($g -is [System.IO.DirectoryInfo]) { $g.Parent.FullName } else { $g.Directory.FullName }
            $found += $parent
        }
    }
    $found = @($found | Select-Object -Unique)

    # 소속 레포별 worktree list 는 레포당 한 번만 조회해 캐시한다(레포 수보다 worktree 수가 훨씬 많다).
    $regCache = @{}

    $results = @()
    foreach ($wt in $found) {
        $ptr = Get-GissueWorktreePointer $wt
        if ($null -eq $ptr) { continue }

        $status = 'Registered'
        $reason = ''
        if ($ptr.Kind -eq 'StandaloneClone') {
            $status = 'StandaloneClone'
            $reason = '.git 이 디렉터리 — worktree 가 아니라 독립 클론'
        } elseif ($ptr.Kind -eq 'Unparsable') {
            $status = 'Unparsable'
            $reason = ".git 파일이 'gitdir:' 형식이 아님: $($ptr.Raw)"
        } elseif (-not $ptr.AdminExists) {
            $status = 'OrphanNoAdmin'
            $reason = "등록정보 없음 — $($ptr.GitDir) 가 실재하지 않음"
        } else {
            $owner = $ptr.OwnerRepo
            if (-not $regCache.ContainsKey($owner)) { $regCache[$owner] = Get-GissueRegisteredWorktreePath $owner }
            if (-not $regCache[$owner].Contains((ConvertTo-GissueComparablePath $wt))) {
                $status = 'OrphanUnlisted'
                $reason = "등록정보는 있으나 '$owner' 의 worktree list 에 없음"
            }
        }

        $lw = $null
        try { $lw = (Get-Item -LiteralPath $wt -Force -ErrorAction Stop).LastWriteTime } catch {}

        $results += [pscustomobject]@{
            Path          = $wt
            Status        = $status
            Reason        = $reason
            OwnerRepo     = $ptr.OwnerRepo
            RepoLabel     = if ($ptr.OwnerRepo) { Split-Path -Leaf $ptr.OwnerRepo } else { '(unknown)' }
            GitDir        = $ptr.GitDir
            LastWriteTime = $lw
        }
    }
    return @($results | Sort-Object RepoLabel, Path)
}

# ---------------------------------------------------------------------------
# `.git` 이 **아예 없는** 잔해 탐지 (giip #2449).
#
# `Get-GissueOrphanWorktree`(giip #2439)는 디스크에서 `.git` 을 가진 디렉터리를 모아 출발한다 —
# 즉 `.git` 자체가 사라진 디렉터리는 **정의상** 그 스캐너에 잡히지 않는다. 실측(2026-09-14):
# `D:\temp\worktrees` 아래에 그런 디렉터리가 13건 있었고, 그중 하나
# (`giipprj\isn1169-protocol-doc`)는 giip #2220 사고를 일으킨 바로 그 정션
# (`giipv3` -> 라이브 `giipprj\giipv3` 레포 루트)을 아직 품고 있었다.
#
# 판정 구조(ScanRoot 아래 2단계까지):
#   - 1단계 디렉터리가 `.git` 을 가지면 레포 체크아웃/worktree 다 → 여기서는 대상 아님(OrphanScan 담당).
#   - 1단계에 하위 디렉터리가 하나도 없으면(빈 폴더이거나 파일만 있음) 그 1단계 자체가 잔해다.
#   - 그렇지 않으면 2단계 자식 중 `.git` 없는 것들이 잔해다(1단계는 레포별 컨테이너 폴더).
# 삭제는 절대 하지 않는다 — 이 함수는 **분류만** 한다.
# ---------------------------------------------------------------------------
function Get-GissueNoGitRemnant {
    param(
        [string[]]$ScanRoot = @('D:\temp\worktrees'),
        [int]$MaxLinksPerItem = 10
    )
    $cands = New-Object System.Collections.ArrayList
    foreach ($root in $ScanRoot) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($d1 in (Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $d1.FullName '.git')) { continue }
            $kids = @(Get-ChildItem -LiteralPath $d1.FullName -Directory -Force -ErrorAction SilentlyContinue)
            if ($kids.Count -eq 0) { [void]$cands.Add($d1.FullName); continue }
            foreach ($k in $kids) {
                if (-not (Test-Path -LiteralPath (Join-Path $k.FullName '.git'))) { [void]$cands.Add($k.FullName) }
            }
        }
    }

    $results = @()
    foreach ($c in @($cands | Sort-Object -Unique)) {
        $lw = $null
        try { $lw = (Get-Item -LiteralPath $c -Force -ErrorAction Stop).LastWriteTime } catch {}
        $scan = Get-GissueWorktreeLinkScan -Path $c -MaxLinks $MaxLinksPerItem
        $linkDetail = @()
        foreach ($l in $scan.Links) {
            $t = $null; $lt = $null
            try {
                $it = Get-Item -LiteralPath $l -Force -ErrorAction Stop
                $t = (@($it.Target)[0]); $lt = "$($it.LinkType)"
            } catch { $t = "(대상 해석 실패: $($_.Exception.Message))" }
            $linkDetail += "$l -> $t [$lt]"
        }
        $topEntries = -1
        try { $topEntries = @(Get-ChildItem -LiteralPath $c -Force -ErrorAction SilentlyContinue).Count } catch {}
        $results += [pscustomobject]@{
            Path           = $c
            Status         = 'NoGit'
            LastWriteTime  = $lw
            NewestWriteUtc = $scan.NewestWriteUtc
            TopEntries     = $topEntries
            LinkCount      = $scan.Links.Count
            ScanFailed     = $scan.ScanFailed
            Links          = $scan.Links
            LinkDetail     = $linkDetail
            Scan           = $scan
        }
    }
    return @($results | Sort-Object Path)
}

# ---------------------------------------------------------------------------
# 경로 구분자 소실 탐지 (giip #2439 부수 버그).
#
# 실측: giipv3 에 `D:/tempworktreesgiipv3-kb-i18n-labels` 가 worktree 로 등록돼 있고 D: 루트에
# 실제 디렉터리까지 만들어져 있었다. 원인은 bash 에서 `D:\temp\worktrees\...` 를 **따옴표 없이**
# 넘겨 백슬래시가 이스케이프로 먹힌 것(`D:\t` → `D:t`). 그 증거로 giipv3 의 등록정보 이름 중
# `D-tempworktreesgiipv3-kb-i18n-aigiip-fde-local` 이 남아 있다 — git 이 구분자 없는 경로의
# basename 을 그대로 이름으로 삼고 `:` 만 `-` 로 치환한 형태다.
#
# 판정: 드라이브 문자(`X:`) 바로 뒤에 구분자가 없는 경로.  예) `D:tempworktrees...`, `D:/tempworktrees...`
# 후자는 `D:` + `tempworktrees`(구분자가 통째로 사라짐)라 basename 이 `temp`/`worktrees` 를 품는다.
# ---------------------------------------------------------------------------
function Test-GissueMalformedWorktreePath([string]$Path) {
    if (-not $Path) { return $false }
    $norm = $Path -replace '/', '\'
    # X:foo (드라이브 상대경로) — 정상적인 worktree 경로에서는 나올 수 없다.
    if ($norm -match '^[A-Za-z]:[^\\]') { return $true }
    # 구분자가 먹혀 'temp' 와 'worktrees' 가 한 세그먼트로 붙어버린 형태.
    $leaf = Split-Path -Leaf $norm
    if ($leaf -match '(?i)tempworktrees') { return $true }
    return $false
}

# ──────────────────────────────────────────────────────────────────────────────
# 3. 알려진 "라이브 체크아웃" 목록 (rule 55 §2-예외 조건 3)
# ──────────────────────────────────────────────────────────────────────────────
# 정션 대상이 "알려진 라이브 체크아웃의 node_modules" 인지 확인하기 위한 화이트리스트.
# 출처: `csn-projects.json` 의 workdir + 그 직계 자식 중 git 레포인 것(= 이 PC 가 실제로 다루는
# 프로젝트 체크아웃 전부). 호출자가 추가 루트를 넘길 수 있다(-ExtraLiveRoots).
$script:GissueLiveRootsCache = $null
function Get-GissueKnownLiveCheckoutRoots {
    param([string[]]$ExtraRoots = @())
    if ($null -eq $script:GissueLiveRootsCache) {
        $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $cfgPath = Join-Path $script:GissueWorktreeSafetyDir 'csn-projects.json'
        $workdirs = @()
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($prop in $cfg.csn.PSObject.Properties) {
                    if ($prop.Value.workdir) { $workdirs += [string]$prop.Value.workdir }
                }
            } catch {}
        }
        foreach ($wd in $workdirs) {
            if (-not (Test-Path -LiteralPath $wd)) { continue }
            $wdFull = try { (Resolve-Path -LiteralPath $wd -ErrorAction Stop).Path } catch { $wd }
            [void]$roots.Add($wdFull.TrimEnd('\', '/'))
            try {
                foreach ($child in (Get-ChildItem -LiteralPath $wdFull -Directory -Force -ErrorAction SilentlyContinue)) {
                    if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) {
                        [void]$roots.Add($child.FullName.TrimEnd('\', '/'))
                    }
                }
            } catch {}
        }
        $script:GissueLiveRootsCache = $roots
    }
    $result = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $script:GissueLiveRootsCache) { [void]$result.Add($r) }
    foreach ($e in @($ExtraRoots)) {
        if (-not $e) { continue }
        if (-not (Test-Path -LiteralPath $e)) { continue }
        $eFull = try { (Resolve-Path -LiteralPath $e -ErrorAction Stop).Path } catch { $e }
        [void]$result.Add($eFull.TrimEnd('\', '/'))
        # 형제 레포(같은 부모 폴더를 공유하는 다른 nested repo)도 라이브 체크아웃이다.
        $parent = Split-Path -Path $eFull -Parent
        if ($parent -and (Test-Path -LiteralPath $parent)) {
            try {
                foreach ($sib in (Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue)) {
                    if (Test-Path -LiteralPath (Join-Path $sib.FullName '.git')) {
                        [void]$result.Add($sib.FullName.TrimEnd('\', '/'))
                    }
                }
            } catch {}
        }
    }
    # HashSet 을 그냥 return 하면 PowerShell 파이프라인이 컬렉션을 **언롤**해 Object[] 로 바꿔
    # 버린다. 그러면 .Contains 가 배열의 대소문자 구분 비교가 되어 "...\projects\..." 와
    # "...\Projects\..." 를 다른 경로로 오판한다(2026-09-14 테스트에서 실측 검출).
    # 단항 콤마로 언롤을 막는다.
    return ,$result
}

# ──────────────────────────────────────────────────────────────────────────────
# 4. rule 55 §2-예외: node_modules 정션 한정 예외 (giip #2438, 오너 결정 2026-09-14)
# ──────────────────────────────────────────────────────────────────────────────
# 아래 3조건을 **전부** 만족할 때만 Eligible=$true. 하나라도 어긋나면 기존 rule 55 §2 그대로
# "제외하고 사람에게 보고"다. 이 경계를 코드에서 임의로 넓히지 말 것.
#   1) worktree 최상위의 `node_modules` 정션 1건만 존재하고,
#   2) 그 worktree 안 다른 어떤 경로에도 심볼릭 링크/정션이 없으며,
#   3) 그 정션의 대상이 알려진 라이브 체크아웃의 `node_modules` 일 것(대상 경로를 실제 해석해 확인).
function Get-GissueJunctionExemption {
    param(
        [Parameter(Mandatory = $true)][string]$WorktreePath,
        [string[]]$ExtraLiveRoots = @(),
        $Scan = $null   # 이미 MaxLinks>=2 로 스캔한 결과가 있으면 재스캔을 피한다(성능)
    )
    $fail = {
        param($reason)
        [pscustomobject]@{ Eligible = $false; Reason = $reason; JunctionPath = $null; TargetPath = $null; TargetRepoRoot = $null }
    }
    # 조건 1+2: 트리 전체에서 링크가 정확히 1건인지 확인한다(2건째를 찾는 즉시 중단).
    $scan = $Scan
    if ($null -eq $scan) { $scan = Get-GissueWorktreeLinkScan -Path $WorktreePath -MaxLinks 2 }
    if ($scan.ScanFailed) { return (& $fail '링크 스캔 실패(접근거부/경로길이 등) — 보수적으로 예외 미적용') }
    if ($scan.Links.Count -ne 1) {
        return (& $fail "링크가 1건이 아님(발견 $($scan.Links.Count)건$(if($scan.Truncated){'+'}else{''})) — rule 55 §2-예외 조건 1/2 불충족")
    }
    $link = $scan.Links[0]
    $linkParent = (Split-Path -Path $link -Parent).TrimEnd('\', '/')
    $wtFull = try { (Resolve-Path -LiteralPath $WorktreePath -ErrorAction Stop).Path } catch { $WorktreePath }
    if ($linkParent -ne $wtFull.TrimEnd('\', '/')) {
        return (& $fail "링크가 worktree 최상위가 아님($link) — 조건 1 불충족")
    }
    if ((Split-Path -Path $link -Leaf) -ine 'node_modules') {
        return (& $fail "최상위 링크 이름이 node_modules 가 아님($link) — 조건 1 불충족")
    }
    $item = $null
    try { $item = Get-Item -LiteralPath $link -Force -ErrorAction Stop } catch {
        return (& $fail "링크 조회 실패($link): $($_.Exception.Message)")
    }
    if ("$($item.LinkType)" -ine 'Junction') {
        return (& $fail "정션이 아님(LinkType=$($item.LinkType)) — 이 예외는 정션 한정이다")
    }
    # 조건 3: 대상 경로를 실제 해석해 확인한다.
    $target = @($item.Target)[0]
    if (-not $target) { return (& $fail '정션 대상 경로를 해석할 수 없음 — 조건 3 불충족') }
    $target = ([string]$target).TrimEnd('\', '/')
    if ((Split-Path -Path $target -Leaf) -ine 'node_modules') {
        return (& $fail "정션 대상이 node_modules 가 아님($target) — 조건 3 불충족")
    }
    $targetRepoRoot = (Split-Path -Path $target -Parent)
    if (-not $targetRepoRoot) { return (& $fail "정션 대상의 상위 레포 경로를 얻을 수 없음($target)") }
    $targetRepoRoot = $targetRepoRoot.TrimEnd('\', '/')
    $known = Get-GissueKnownLiveCheckoutRoots -ExtraRoots $ExtraLiveRoots
    if (-not $known.Contains($targetRepoRoot)) {
        return (& $fail "정션 대상의 상위($targetRepoRoot)가 알려진 라이브 체크아웃 목록에 없음 — 조건 3 불충족")
    }
    # 라이브 체크아웃은 `.git` 이 **디렉터리**다(worktree 는 `.git` 이 파일). 이 구분으로
    # "대상이 또 다른 worktree" 인 케이스를 배제한다.
    $targetGit = Join-Path $targetRepoRoot '.git'
    if (-not (Test-Path -LiteralPath $targetGit -PathType Container)) {
        return (& $fail "정션 대상의 상위($targetRepoRoot)가 주 체크아웃이 아님(.git 이 디렉터리가 아님) — 조건 3 불충족")
    }
    return [pscustomobject]@{
        Eligible       = $true
        Reason         = "rule 55 §2-예외 3조건 충족(최상위 node_modules 정션 1건, 다른 링크 없음, 대상=라이브 체크아웃 $targetRepoRoot)"
        JunctionPath   = $link
        TargetPath     = $target
        TargetRepoRoot = $targetRepoRoot
    }
}

# 정션 대상(라이브 체크아웃의 node_modules)이 건전한지 검증. 오너 결정의 "대상 경로 건전성 검증".
function Test-GissueJunctionTargetHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$TargetRepoRoot
    )
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        return [pscustomobject]@{ Ok = $false; Detail = "대상 디렉터리 없음: $TargetPath" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $TargetRepoRoot '.git'))) {
        return [pscustomobject]@{ Ok = $false; Detail = "대상 레포의 .git 없음: $TargetRepoRoot" }
    }
    $head = $null
    try { $head = git -C $TargetRepoRoot rev-parse HEAD 2>$null } catch {}
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$head")) {
        return [pscustomobject]@{ Ok = $false; Detail = "대상 레포 rev-parse HEAD 실패: $TargetRepoRoot" }
    }
    $remote = $null
    try { $remote = git -C $TargetRepoRoot remote get-url origin 2>$null } catch {}
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$remote")) {
        return [pscustomobject]@{ Ok = $false; Detail = "대상 레포 remote get-url origin 실패: $TargetRepoRoot" }
    }
    $childCount = -1
    try { $childCount = @([System.IO.Directory]::EnumerateFileSystemEntries($TargetPath) | Select-Object -First 1).Count } catch {}
    return [pscustomobject]@{
        Ok     = $true
        Detail = "대상 살아있음: $TargetPath (비어있지않음=$($childCount -gt 0)) / repo=$TargetRepoRoot HEAD=$("$head".Trim()) origin=$("$remote".Trim())"
    }
}

# 정션 **자체만** 제거한다 — 대상을 절대 따라가지 않는다.
# Windows 에서 정션 자체만 지우는 정확한 수단은 `rmdir <junction>`(/s 없이) 또는
# `[System.IO.Directory]::Delete($path, $false)` 다. 둘 다 reparse point 만 제거하고 대상은 건드리지
# 않는다. 반대로 `Remove-Item -Recurse` / `rm -rf` 계열은 대상을 따라 들어갈 수 있어 **금지**다
# (giip #2220/#2232 사고의 실제 원인). 여기서는 .NET API 를 쓴다 — 셸 파싱을 거치지 않아 경로에
# 공백/특수문자가 있어도 안전하고, 재귀 플래그를 $false 로 명시하므로 의도가 코드에 고정된다.
function Remove-GissueJunctionOnly {
    param([Parameter(Mandatory = $true)][string]$JunctionPath)
    $attr = $null
    try { $attr = [System.IO.File]::GetAttributes($JunctionPath) } catch {
        return [pscustomobject]@{ Ok = $false; Detail = "속성 조회 실패: $($_.Exception.Message)" }
    }
    if (-not ($attr -band [System.IO.FileAttributes]::ReparsePoint)) {
        return [pscustomobject]@{ Ok = $false; Detail = "reparse point 가 아님 — 제거 거부(안전): $JunctionPath" }
    }
    if (-not ($attr -band [System.IO.FileAttributes]::Directory)) {
        return [pscustomobject]@{ Ok = $false; Detail = "디렉터리 정션이 아님 — 제거 거부(안전): $JunctionPath" }
    }
    try {
        [System.IO.Directory]::Delete($JunctionPath, $false)   # recursive=$false — 대상 미추적
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = "정션 제거 실패: $($_.Exception.Message)" }
    }
    if (Test-Path -LiteralPath $JunctionPath) {
        return [pscustomobject]@{ Ok = $false; Detail = "정션 제거 후에도 경로가 남아있음: $JunctionPath" }
    }
    return [pscustomobject]@{ Ok = $true; Detail = "정션만 제거됨(대상 미추적): $JunctionPath" }
}

# ──────────────────────────────────────────────────────────────────────────────
# 5. 머지판정 (giip #2440 원인 1) — squash-merge 컨벤션이라 ahead-count 를 쓰지 않는다
# ──────────────────────────────────────────────────────────────────────────────
$script:GissueMergedBranchCache = @{}
function Get-GissueMergedBranchSet {
    param([Parameter(Mandatory = $true)][string]$RepoPath, [scriptblock]$Log)
    $repoFull = try { (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path } catch { $RepoPath }
    $key = $repoFull.ToLowerInvariant()
    if ($script:GissueMergedBranchCache.ContainsKey($key)) { return $script:GissueMergedBranchCache[$key] }
    $result = [pscustomobject]@{ Ok = $false; OwnerRepo = $null; Branches = (New-Object 'System.Collections.Generic.HashSet[string]') }
    $originUrl = $null
    try { $originUrl = git -C $repoFull remote get-url origin 2>$null } catch {}
    if (-not $originUrl) {
        if ($Log) { & $Log "머지판정 불가(origin remote 없음): $repoFull" }
        $script:GissueMergedBranchCache[$key] = $result
        return $result
    }
    $ghOwnerRepo = $null
    if ("$originUrl" -match '[:/]([^/:]+)/([^/]+?)(\.git)?\s*$') { $ghOwnerRepo = "$($Matches[1])/$($Matches[2])" }
    if (-not $ghOwnerRepo) {
        if ($Log) { & $Log "머지판정 불가(origin URL 파싱 실패): $originUrl" }
        $script:GissueMergedBranchCache[$key] = $result
        return $result
    }
    # giip #2220: gh 는 cwd 기준으로 owner/repo 를 추론한다 — 반드시 --repo 를 명시한다.
    try {
        $ghOut = & gh pr list --repo $ghOwnerRepo --state merged --json headRefName --limit 1000 2>&1
        if ($LASTEXITCODE -eq 0) {
            $parsed = $ghOut | ConvertFrom-Json
            foreach ($p in @($parsed)) { if ($p.headRefName) { [void]$result.Branches.Add($p.headRefName) } }
            $result.Ok = $true
            $result.OwnerRepo = $ghOwnerRepo
            if ($Log) { & $Log "머지된 PR 브랜치 $($result.Branches.Count)개 조회 완료($ghOwnerRepo)" }
        } else {
            if ($Log) { & $Log "WARN: gh pr list --state merged 실패($ghOwnerRepo) — $ghOut (이 레포는 전부 '미머지'로 보수적 처리)" }
        }
    } catch {
        if ($Log) { & $Log "WARN: gh pr list 예외($ghOwnerRepo) — $($_.Exception.Message)" }
    }
    $script:GissueMergedBranchCache[$key] = $result
    return $result
}

# ──────────────────────────────────────────────────────────────────────────────
# 6. worktree 목록 파싱
# ──────────────────────────────────────────────────────────────────────────────
function Get-GissueWorktreeEntries {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $wtOut = @(git -C $RepoPath worktree list --porcelain 2>$null)
    $entries = @()
    $cur = $null
    foreach ($line in $wtOut) {
        if ("$line" -match '^worktree\s+(.+)$') {
            if ($cur) { $entries += [pscustomobject]$cur }
            $cur = @{ Path = $Matches[1].Trim(); Branch = $null; Locked = $false; Detached = $false }
        } elseif ($cur -and "$line" -match '^branch\s+refs/heads/(.+)$') {
            $cur.Branch = $Matches[1].Trim()
        } elseif ($cur -and "$line" -match '^locked') {
            $cur.Locked = $true
        } elseif ($cur -and "$line" -match '^detached') {
            $cur.Detached = $true
        }
    }
    if ($cur) { $entries += [pscustomobject]$cur }
    return $entries
}

# ──────────────────────────────────────────────────────────────────────────────
# 6.5 "작업 중 세션" 활동 판정 (giip #2463)
# ──────────────────────────────────────────────────────────────────────────────
# giip #2440 이 넣은 idle 가드는 **worktree 트리 안 파일 mtime** 하나만 봤다. 그런데 세션이
# `git commit` / `git push` 를 하면 worktree 안의 **작업파일은 전혀 안 바뀐다** — 바뀌는 것은
# 주 저장소의 `.git/worktrees/<name>/` (index, HEAD, ORIG_HEAD, logs/HEAD, refs/) 쪽이다.
# 그래서 "12:00 에 파일 편집 → 13:00 에 커밋·push → CI/머지/이슈 코멘트 대기" 인 세션은
# 14:05 의 정리에서 트리 mtime 기준 125분 idle 로 계산되어 **작업 중인데도 삭제된다**.
# 이것이 giip #2445 세션이 당한 시나리오이고, #2440 수정 후에도 그대로 남아 있었다.
#
# 또 하나의 구멍(fail-open): 활동 시각을 못 구했을 때(`NewestWriteUtc=$null`, 스캔 실패,
# MaxLinks 로 조기중단되어 트리를 다 못 본 경우) 구현이 idle 가드를 **통째로 건너뛰어**
# 그대로 삭제로 진행했다. "모르면 지우지 않는다"(rule 55) 원칙과 정반대다.
#
# 이 함수는 두 출처를 합쳐 "마지막 활동 시각"을 구하고, 신뢰할 수 없으면 Determined=$false 를
# 돌려준다. 호출자는 Determined=$false 를 **삭제 금지**로 다뤄야 한다.
#   Sources: 'tree'(worktree 안 파일)  /  'gitadmin'(.git/worktrees/<name> 관리 디렉터리)
function Get-GissueWorktreeActivity {
    param(
        [Parameter(Mandatory = $true)][string]$WorktreePath,
        $Scan = $null   # Get-GissueWorktreeLinkScan 결과가 있으면 재사용(추가 순회 비용 0)
    )
    $treeUtc = $null; $treeReliable = $false
    $scan = $Scan
    if ($null -eq $scan) { $scan = Get-GissueWorktreeLinkScan -Path $WorktreePath -MaxLinks 2 }
    if ($scan) {
        $treeUtc = $scan.NewestWriteUtc
        # 스캔이 실패했거나 링크 상한으로 조기중단됐으면 트리 전체를 본 게 아니다 → 트리 시각은
        # "하한"일 뿐이므로 단독으로는 신뢰하지 않는다.
        $treeReliable = ($treeUtc -and (-not $scan.ScanFailed) -and (-not $scan.Truncated))
    }

    # ── git 관리 디렉터리(.git/worktrees/<name>) 최신 변경시각 ──
    # 여기 파일들은 커밋/체크아웃/스테이징/브랜치 이동 때마다 갱신된다. 디렉터리가 작아서
    # (수~수십 파일) 전수 순회해도 비용이 무시할 수준이다.
    $adminUtc = $null; $adminDir = $null
    $ptr = $null
    try { $ptr = Get-GissueWorktreePointer $WorktreePath } catch {}
    if ($ptr -and $ptr.Kind -eq 'Worktree' -and $ptr.AdminExists) {
        $adminDir = $ptr.GitDir
        $newest = [datetime]::MinValue
        $stack = New-Object System.Collections.Stack
        $stack.Push($adminDir)
        while ($stack.Count -gt 0) {
            $d = $stack.Pop()
            $entries = $null
            try { $entries = [System.IO.Directory]::EnumerateFileSystemEntries($d) } catch { continue }
            foreach ($entry in $entries) {
                $attr = $null
                try { $attr = [System.IO.File]::GetAttributes($entry) } catch { continue }
                if ($attr -band [System.IO.FileAttributes]::ReparsePoint) { continue }   # 링크는 따라가지 않는다
                # `*.lock` 은 git 명령이 잠깐 만들었다 지우는 파일이라 활동 근거가 아니다.
                if ([System.IO.Path]::GetExtension($entry) -ieq '.lock') { continue }
                try {
                    $wt = [System.IO.File]::GetLastWriteTimeUtc($entry)
                    if ($wt -gt $newest) { $newest = $wt }
                } catch {}
                if ($attr -band [System.IO.FileAttributes]::Directory) { $stack.Push($entry) }
            }
        }
        if ($newest -gt [datetime]::MinValue) { $adminUtc = $newest }
    }

    # 둘 중 **더 최근** 쪽을 채택한다(활동이 한쪽에만 남는 경우가 정상이다).
    $newestUtc = $null; $source = ''
    if ($treeUtc -and $adminUtc) {
        if ($treeUtc -ge $adminUtc) { $newestUtc = $treeUtc; $source = 'tree' } else { $newestUtc = $adminUtc; $source = 'gitadmin' }
    } elseif ($treeUtc) { $newestUtc = $treeUtc; $source = 'tree' }
    elseif ($adminUtc) { $newestUtc = $adminUtc; $source = 'gitadmin' }

    # 신뢰성: (a) 트리 스캔이 온전했거나 (b) git 관리 디렉터리 시각을 얻었으면 판정 가능.
    # 둘 다 아니면 "모름" → 호출자가 보수적으로 보류해야 한다.
    $determined = [bool]($treeReliable -or $adminUtc)
    $detail = "tree=$(if ($treeUtc) { $treeUtc.ToString('yyyy-MM-dd HH:mm:ss') } else { '(없음)' })" +
              "$(if ($scan -and $scan.ScanFailed) { '(스캔실패)' } elseif ($scan -and $scan.Truncated) { '(조기중단)' } else { '' })" +
              " / gitadmin=$(if ($adminUtc) { $adminUtc.ToString('yyyy-MM-dd HH:mm:ss') } else { '(없음)' })"

    return [pscustomobject]@{
        Determined = $determined
        NewestUtc  = $newestUtc
        Source     = $source
        TreeUtc    = $treeUtc
        GitAdminUtc = $adminUtc
        AdminDir   = $adminDir
        Detail     = $detail
    }
}

# idle 판정 — 순수 함수(부작용 없음). 회귀 테스트가 시각을 주입해 고정할 수 있게 분리한다.
# 반환: Idle=$true 여야만 삭제 후보로 넘어간다. 판정 불가는 **항상 Idle=$false**(fail-closed).
function Test-GissueWorktreeIdleEnough {
    param(
        # Mandatory 로 두지 않는다 — $null 이 들어오면 **에러가 아니라 보수적 보류**여야 한다.
        # Mandatory 면 $null 바인딩이 예외가 되고, 호출자의 try/catch 에 따라 가드 자체가
        # 건너뛰어질 수 있다(= fail-open 재현). 판정 불가는 항상 "지우지 않는다"로 수렴시킨다.
        $Activity = $null,
        [int]$MinIdleMinutes = 120,
        [datetime]$NowUtc = [datetime]::UtcNow
    )
    if ($MinIdleMinutes -le 0) {
        return [pscustomobject]@{ Idle = $true; IdleMinutes = $null; Reason = "idle 가드 비활성(MinIdleMinutes=$MinIdleMinutes)" }
    }
    if ($null -eq $Activity -or -not $Activity.Determined -or -not $Activity.NewestUtc) {
        $d = if ($Activity) { $Activity.Detail } else { '(활동정보 없음)' }
        return [pscustomobject]@{
            Idle = $false; IdleMinutes = $null
            Reason = "최근 활동 시각을 판정할 수 없음 — 보수적으로 보류(MinIdleMinutes=$MinIdleMinutes): $d"
        }
    }
    $idleMin = ($NowUtc - $Activity.NewestUtc).TotalMinutes
    if ($idleMin -lt $MinIdleMinutes) {
        return [pscustomobject]@{
            Idle = $false; IdleMinutes = $idleMin
            Reason = ("최근 {0:N0}분 전 활동({1}) — 사람/다른 세션이 작업 중일 수 있음, MinIdleMinutes={2} [{3}]" -f $idleMin, $Activity.Source, $MinIdleMinutes, $Activity.Detail)
        }
    }
    return [pscustomobject]@{
        Idle = $true; IdleMinutes = $idleMin
        Reason = ("마지막 활동 {0:N0}분 전({1}) — MinIdleMinutes={2} 초과" -f $idleMin, $Activity.Source, $MinIdleMinutes)
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# 7. 단일 레포 정리 엔진 — 두 호출자가 **동일 정책**을 쓰게 하는 지점
# ──────────────────────────────────────────────────────────────────────────────
# 정책(= rule 55 + giip #2438 예외 + giip #2440 판정 수정):
#   - 주 worktree / `.claude\worktrees\` / locked / detached → 건드리지 않음
#   - 머지판정은 `gh pr list --state merged` 로만 한다(ahead-count 금지 — squash-merge 오판).
#     "워킹트리가 clean 하고 push 됐다"는 것만으로는 절대 삭제하지 않는다 — 세션은 push 이후에도
#     CI 대기·머지·이슈 코멘트·사양서 갱신을 계속한다(giip #2463). 머지된 PR + idle 가드 둘 다 통과해야 한다.
#   - dirty 는 **머지 확인된 경우에만** `--force` 로 진행(미머지 dirty 는 사람 작업이므로 절대 제외)
#   - idle 가드(giip #2440 신설 / #2463 강화): 트리 mtime **과** `.git/worktrees/<name>` mtime 중
#     더 최근 쪽으로 마지막 활동을 판정하고, 판정 불가면 삭제하지 않는다(fail-closed)
#   - 삭제 직전 링크 선검사 → 링크 있으면 rule 55 §2-예외 3조건 판정 → 불충족이면 ManualReview
#   - 예외 충족 시: 대상 사전 건전성 확인 → 정션만 제거 → 대상 사후 건전성 재확인 → worktree 제거
#   - 항목별 삭제 직후 인접 nested repo 무결성 재검증, 이상 시 즉시 전체 중단
#
# ★ 결과는 **`-ResultRef ([ref]$var)` 로만** 돌려준다 — 이 함수 자체는 반환값을 파이프라인에 내보내지
#   않는다. 이유: 로그 콜백(`-Log`)이 `Write-Output` 으로 찍는 구현(이 레포의 Write-Log/
#   Write-CleanupLog 가 그렇다)이면 그 로그가 함수의 성공 스트림에 섞여, 호출자가
#   `$r = Invoke-...` 로 받는 순간 **로그가 통째로 사라지고 $r 이 배열이 된다**(2026-09-14 실측).
#   결과를 [ref] 로 빼면 로그는 호출자 스트림으로 그대로 흘러가고 rule 55 §5(과정 로그)가 지켜진다.
function Invoke-GissueWorktreeCleanupForRepo {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [switch]$DryRun,
        [bool]$DeleteRemoteBranch = $false,
        [scriptblock]$Log = $null,
        [string[]]$ProtectedPaths = @(),
        [string[]]$SiblingRepos = @(),
        [string]$OnlyPath = $null,
        [int]$MinIdleMinutes = 120,
        [ref]$ResultRef = $null
    )
    $say = {
        param($m)
        if ($Log) { & $Log $m } else { Write-Output $m }
    }
    $result = [pscustomobject]@{
        RepoPath = $RepoPath; Removed = @(); ManualReview = @(); SkippedLocked = @()
        Aborted = $false; AbortReason = $null
        SkippedStaleCode = $false; StaleCodeReason = $null
    }
    $publish = { if ($ResultRef) { $ResultRef.Value = $result } }

    # ── 낡은 코드 가드(giip #2471) ──
    # 이 함수 전체가 호출자 프로세스의 메모리에 고정된 판정이다. 그 프로세스가 기동한 뒤 이 판정
    # 로직이 바뀌었다면(= 안전수정이 머지됐다면) 지금 여기서 내리는 삭제 결정은 **이미 폐기된
    # 기준**으로 내리는 것이다. 2026-09-14 실측 사고가 정확히 그것이었다 — 12:54:53 에 머지로
    # 제거된 `clean+pushed` 판정이 13:03:59 에 남의 작업 중 worktree 를 지웠다.
    # DryRun 은 아무것도 지우지 않으므로 막지 않는다(검증·관측 목적까지 멈출 이유가 없다).
    if (-not $DryRun) {
        if (Test-GissueCodeStale -Log $Log) {
            $result.SkippedStaleCode = $true
            $result.StaleCodeReason = (Get-GissueCodeStaleReason)
            & $say "SKIP(낡은 코드 — giip #2471): '$RepoPath' 정리를 건너뛴다(다음 :07 의 새 프로세스가 최신 판정으로 처리한다). 사유: $($result.StaleCodeReason)"
            & $publish
            return
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) { & $publish; return }
    $repoFull = try { (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path } catch { $RepoPath }
    $result.RepoPath = $repoFull

    # 인접 nested repo(rule 55 §3 재검증 대상) — 호출자가 준 목록 + 부모 폴더 공유 레포
    $siblings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$siblings.Add($repoFull)
    foreach ($s in @($SiblingRepos)) { if ($s) { [void]$siblings.Add($s) } }
    $parent = Split-Path -Path $repoFull -Parent
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        try {
            foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue)) {
                if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { [void]$siblings.Add($d.FullName) }
            }
        } catch {}
    }
    $siblingList = @($siblings)

    # 자기 자신(이 스크립트가 실행 중인 위치)은 절대 지우지 않는다 — 자기발밑 삭제 방지.
    $selfPaths = @()
    foreach ($c in @($PSScriptRoot, (Get-Location).Path)) {
        if ($c) { $selfPaths += ([string]$c).TrimEnd('\', '/') }
    }
    $protectedAll = @($ProtectedPaths) + $selfPaths | Where-Object { $_ }

    try { git -C $repoFull worktree prune 2>&1 | Out-Null } catch {}
    $merged = Get-GissueMergedBranchSet -RepoPath $repoFull -Log $Log
    $entries = Get-GissueWorktreeEntries -RepoPath $repoFull

    foreach ($e in $entries) {
        if ($result.Aborted) { break }
        $ePath = try { (Resolve-Path -LiteralPath $e.Path -ErrorAction Stop).Path } catch { $e.Path }
        if ($ePath -ieq $repoFull) { continue }                                   # 주 worktree
        if ($ePath -match '\.claude[\\/]worktrees[\\/]') { continue }             # Claude Code 세션 격리
        # -OnlyPath 지정 시 그 항목 하나만 처리한다(핀포인트 정리/검증용).
        if ($OnlyPath -and (([string]$ePath).TrimEnd('\', '/') -ine ([string]$OnlyPath).TrimEnd('\', '/'))) { continue }
        $ePathNorm = ([string]$ePath).TrimEnd('\', '/')
        $isProtected = $false
        foreach ($pp in $protectedAll) {
            if ($ePathNorm -ieq $pp -or $pp.StartsWith($ePathNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $isProtected = $true; break
            }
        }
        if ($isProtected) { & $say "SKIP(보호 경로 — 현재 작업 중이거나 호출자가 지정): $ePath"; continue }
        if ($e.Locked) { & $say "SKIP(locked): $ePath"; $result.SkippedLocked += $ePath; continue }
        if ($e.Detached -or (-not $e.Branch)) {
            & $say "MANUAL-REVIEW(detached HEAD, 브랜치 없음): $ePath"
            $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = '(detached)'; Reason = 'detached HEAD' }
            continue
        }
        if (-not (Test-Path -LiteralPath $ePath)) { continue }   # 물리적으로 이미 없음 — 위 prune 이 회수

        # ── 머지판정(giip #2440 원인 1): ahead-count 금지, 머지된 PR 목록만 신뢰 ──
        if (-not $merged.Branches.Contains($e.Branch)) {
            & $say "MANUAL-REVIEW(미머지 — 자동삭제 대상 아님): $ePath (branch=$($e.Branch))"
            $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = '머지 PR 없음(사람 확인 필요 — 미완료 작업일 수 있음)' }
            continue
        }

        # ── rule 55 §1: 링크 선검사(DryRun 포함 항상) ──
        # MaxLinks=2 로 한 번만 스캔한다 — 0건이면 게이트 통과, 1건이면 예외 판정에 그대로 재사용,
        # 2건째를 찾는 순간 순회를 중단한다(예외 조건 2가 이미 깨졌으므로 더 볼 필요가 없다).
        $linkScan = Get-GissueWorktreeLinkScan -Path $ePath -MaxLinks 2
        $exemption = $null
        if ($linkScan.ScanFailed -or $linkScan.Links.Count -gt 0) {
            $exemption = Get-GissueJunctionExemption -WorktreePath $ePath -ExtraLiveRoots $siblingList -Scan $linkScan
            if (-not $exemption.Eligible) {
                & $say "MANUAL-REVIEW(심볼릭 링크/정션 발견 — rule 55 §2, 자동삭제 대상에서 제외): $ePath — $($exemption.Reason)"
                $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = "심볼릭 링크/정션 포함 — 자동삭제 금지(rule 55 §2): $($exemption.Reason)" }
                continue
            }
            & $say "LINK-EXEMPT(rule 55 §2-예외, giip #2438): $ePath — $($exemption.Reason)"
        }

        # ── 사용 중 worktree 보호(giip #2440 신설 → giip #2463 강화) ──
        # 구 판정의 dirty/ahead>0 SKIP 은 결과적으로 "지금 사람/다른 세션이 쓰고 있는 worktree"를
        # 보호하고 있었다. 그 둘을 가이드대로 거두자, 브랜치가 머지되기만 하면 **작업 중인 worktree 까지**
        # 스케줄러가 지우게 된다 — 2026-09-14 실측으로 동시 진행 중이던 다른 세션의 worktree
        # (`lowyworkenv\orphan-wt-2439`, `lowyworkenv\parse-gate-fix-2436`)가 삭제 후보로 잡혔다.
        #
        # giip #2463: 판정 출처를 트리 mtime **하나**에서 "트리 mtime + git 관리 디렉터리 mtime"
        # 둘로 넓히고, 판정 불가일 때 삭제로 흘러가던 fail-open 을 fail-closed 로 뒤집었다.
        # 커밋/push 는 worktree 안 파일을 갱신하지 않으므로(변경되는 곳은 `.git/worktrees/<name>/`)
        # 트리 mtime 만 보면 "push 하고 CI 를 기다리는 세션"이 idle 로 오판된다 — giip #2445 실측.
        # 상세는 Get-GissueWorktreeActivity / Test-GissueWorktreeIdleEnough 헤더 주석 참조.
        #
        # ★ 순서 주의(giip #2463 실측): 이 판정은 **이 worktree 에 대한 어떤 git 명령보다 먼저** 해야 한다.
        #   `git status` 는 stat 정보가 달라졌으면 `.git/worktrees/<name>/index` 를 다시 쓴다. 즉
        #   정리 도구 자신의 dirty 검사가 관리 디렉터리 mtime 을 '지금'으로 갱신해버려, 그 값을 나중에
        #   읽으면 무엇이든 "방금 활동함"으로 보이고 정리가 영영 멈춘다(테스트에서 실제로 재현됐다).
        #   그래서 dirty 검사는 아래 idle 통과 이후로 내렸다.
        $activity = Get-GissueWorktreeActivity -WorktreePath $ePath -Scan $linkScan
        $idleVerdict = Test-GissueWorktreeIdleEnough -Activity $activity -MinIdleMinutes $MinIdleMinutes
        if (-not $idleVerdict.Idle) {
            & $say "SKIP($($idleVerdict.Reason)): $ePath"
            $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = $idleVerdict.Reason }
            continue
        }

        # ── dirty 판정(giip #2440 원인 2): 머지 확인된 경우에만 --force 로 진행 ──
        # (giip #2463: 위 idle 판정 뒤로 내렸다 — 이 `git status` 자체가 관리 디렉터리를 갱신하기 때문)
        $dirtyNote = ''
        try {
            $dirtyStatus = git -C $ePath status --porcelain 2>&1
            if ("$dirtyStatus".Trim()) { $dirtyNote = ' [dirty 상태였음 — 머지 PR 확인되어 진행]' }
        } catch {}

        if ($DryRun) {
            if ($exemption) {
                & $say "[DRY-RUN] 삭제 예정(머지 확인 + $($idleVerdict.Reason) + rule 55 §2-예외 적용): $ePath (branch=$($e.Branch)) / 제거할 정션=$($exemption.JunctionPath) -> 대상(보존)=$($exemption.TargetPath)"
            } else {
                & $say "[DRY-RUN] 삭제 예정(머지 확인, $($idleVerdict.Reason), 링크 없음 확인됨): $ePath (branch=$($e.Branch))$dirtyNote"
            }
            $result.Removed += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Exempt = [bool]$exemption }
            continue
        }

        $preSnap = Get-GissueRepoIntegritySnapshot $siblingList

        # ── rule 55 §2-예외 절차: 대상 사전확인 → 정션만 제거 → 대상 사후확인 ──
        if ($exemption) {
            $preHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $preHealth.Ok) {
                & $say "MANUAL-REVIEW(정션 대상이 이미 비정상 — 예외 미적용): $ePath — $($preHealth.Detail)"
                $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = "정션 대상 사전검증 실패: $($preHealth.Detail)" }
                continue
            }
            & $say "  정션 대상 사전검증 OK — $($preHealth.Detail)"
            $rmJunction = Remove-GissueJunctionOnly -JunctionPath $exemption.JunctionPath
            if (-not $rmJunction.Ok) {
                & $say "MANUAL-REVIEW(정션 제거 실패 — worktree 는 건드리지 않음): $ePath — $($rmJunction.Detail)"
                $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = "정션 제거 실패: $($rmJunction.Detail)" }
                continue
            }
            & $say "  $($rmJunction.Detail)"
            $postHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $postHealth.Ok) {
                & $say "CRITICAL: 정션 제거 직후 대상이 비정상이 됨 — 즉시 중단, 남은 항목은 처리하지 않음. $($postHealth.Detail)"
                $result.Aborted = $true
                $result.AbortReason = "정션 제거 후 대상 검증 실패: $($postHealth.Detail)"
                break
            }
            & $say "  정션 대상 사후검증 OK(대상 생존 확인) — $($postHealth.Detail)"
        }

        # ── rule 55 §4: git worktree remove 우선 ──
        $removedOk = $false
        try {
            $rmOut = git -C $repoFull worktree remove $ePath 2>&1
            if ($LASTEXITCODE -ne 0) {
                if (-not $dirtyNote) {
                    & $say "WARN: worktree remove 실패(clean 인데도, 원인 불명 — 수동 확인 필요): $ePath — $rmOut"
                    $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = "머지 확인됨, clean 인데도 remove 실패: $rmOut" }
                } else {
                    $rmOut2 = git -C $repoFull worktree remove --force $ePath 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        & $say "WARN: worktree remove --force 도 실패(머지 확인됐는데도): $ePath — $rmOut2"
                        $result.ManualReview += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Reason = "머지 확인됨, --force 도 remove 실패: $rmOut2" }
                    } else { $removedOk = $true }
                }
            } else { $removedOk = $true }
        } catch {
            & $say "WARN: 삭제 중 예외($ePath) — $($_.Exception.Message)"
        }

        # ── rule 55 §3: 삭제 시도 직후(성공/실패 무관) 인접 nested repo 즉시 재검증 ──
        $postSnap = Get-GissueRepoIntegritySnapshot $siblingList
        $integrity = Compare-GissueRepoIntegrity $preSnap $postSnap
        # giip #2466 — 다른 세션의 정상 커밋으로 HEAD 가 움직인 것은 손상이 아니다. 기록만 남기고 진행.
        foreach ($w in $integrity.Warnings) { & $say "WARN(rule 55 §3, giip #2466): $w" }
        $regress = @($integrity.Violations) -join ' / '
        if ($regress) {
            & $say "CRITICAL: '$ePath' 삭제 직후 $regress — giip #2232 재발 의심. 즉시 중단, 남은 항목은 처리하지 않음."
            $result.Aborted = $true; $result.AbortReason = $regress
            break
        }
        if ($exemption) {
            $finalHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $finalHealth.Ok) {
                & $say "CRITICAL: '$ePath' 삭제 직후 정션 대상이 비정상 — 즉시 중단. $($finalHealth.Detail)"
                $result.Aborted = $true; $result.AbortReason = "worktree 제거 후 정션 대상 검증 실패: $($finalHealth.Detail)"
                break
            }
            & $say "  worktree 제거 후 정션 대상 재검증 OK — $($finalHealth.Detail)"
        }
        if (-not $removedOk) { continue }
        & $say "삭제됨(머지 확인, $($idleVerdict.Reason), 인접 레포 무결성 재검증 통과)$dirtyNote : $ePath (branch=$($e.Branch))"
        try { git -C $repoFull branch -D $e.Branch 2>&1 | Out-Null } catch {}
        if ($DeleteRemoteBranch) {
            try {
                $remoteExists = git -C $repoFull ls-remote --heads origin $e.Branch 2>&1
                if ("$remoteExists".Trim()) {
                    git -C $repoFull push origin --delete $e.Branch 2>&1 | Out-Null
                    & $say "원격 브랜치 삭제: $($e.Branch)"
                }
            } catch {
                & $say "WARN: 원격 브랜치 삭제 실패($($e.Branch)) — $($_.Exception.Message)"
            }
        }
        $result.Removed += [pscustomobject]@{ Path = $ePath; Branch = $e.Branch; Exempt = [bool]$exemption }
    }
    & $publish
}

# ──────────────────────────────────────────────────────────────────────────────
# 8. 스코프 (giip #2440 원인 3) — csn-projects.json 전 레포 목록
# ──────────────────────────────────────────────────────────────────────────────
# 상시 로직이 CSN 의 workdir + 직계자식으로만 한정돼 있어, 어느 CSN 의 workdir 에도 직계로 들어있지
# 않은 레포(실측: uamath)의 worktree 가 22일간 방치됐다. 이 함수는 csn-projects.json 에 등록된
# 전 workdir 과 그 직계 자식 git 레포를 전부 돌려준다(하루 1회 스윕용).
function Get-GissueAllProjectRepoPaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cfgPath = Join-Path $script:GissueWorktreeSafetyDir 'csn-projects.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return @() }
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return @() }
    foreach ($prop in $cfg.csn.PSObject.Properties) {
        $wd = [string]$prop.Value.workdir
        if (-not $wd -or -not (Test-Path -LiteralPath $wd)) { continue }
        $wdFull = try { (Resolve-Path -LiteralPath $wd -ErrorAction Stop).Path } catch { $wd }
        if (Test-Path -LiteralPath (Join-Path $wdFull '.git')) { [void]$paths.Add($wdFull) }
        try {
            foreach ($child in (Get-ChildItem -LiteralPath $wdFull -Directory -Force -ErrorAction SilentlyContinue)) {
                if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) { [void]$paths.Add($child.FullName) }
            }
        } catch {}
    }
    return @($paths)
}

# ──────────────────────────────────────────────────────────────────────────────
# 8-b. MAX_PATH 안전 디렉터리 트리 삭제 (giip #2449)
# ──────────────────────────────────────────────────────────────────────────────
# `Remove-Item -Recurse` 도 260자 한계에 걸린다 — 실측(2026-09-14): `giipv3\giip2173-tpartner`
# 삭제가 `Could not find a part of the path 'useOverlayDrawerSurfaceStyles.styles.js.map'` 로
# 실패해 트리가 **반쯤 지워진 채** 남았다(링크 스캐너만 고쳐서는 부족했다).
#
# 폴백은 `[System.IO.Directory]::Delete($extended, $true)` 다. **호출자는 이 함수를 부르기 직전에
# 그 트리에 reparse point 가 0건임을 재검사해 두어야 한다**(rule 55 §1-2 / 고아·잔해 경로의 2차
# 링크 재검사). 그 전제가 성립할 때만 재귀삭제가 링크를 따라갈 여지가 원천적으로 없다.
# 이 함수는 스스로 그 전제를 만들지 않으므로, 링크 검사 없이 호출하지 말 것.
function Remove-GissueDirectoryTreeSafely {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [scriptblock]$Log = $null
    )
    $say = { param($m) if ($Log) { & $Log $m } }
    $firstErr = $null
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]@{ Ok = $true; Detail = 'Remove-Item -Recurse 로 삭제 완료'; UsedFallback = $false }
        }
        $firstErr = '삭제 후에도 경로가 남아있음'
    } catch {
        $firstErr = $_.Exception.Message
    }
    & $say "  1차 삭제 실패($Path) — $firstErr / MAX_PATH 가능성 → \\?\ 확장 경로로 재시도"
    try {
        [System.IO.Directory]::Delete((ConvertTo-GissueExtendedPath $Path), $true)
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = "1차: $firstErr / 확장경로 재시도: $($_.Exception.Message)"; UsedFallback = $true }
    }
    if (Test-Path -LiteralPath $Path) {
        return [pscustomobject]@{ Ok = $false; Detail = "1차: $firstErr / 확장경로 재시도 후에도 경로가 남아있음"; UsedFallback = $true }
    }
    return [pscustomobject]@{ Ok = $true; Detail = "확장 경로(\\?\) 폴백으로 삭제 완료 (1차 실패: $firstErr)"; UsedFallback = $true }
}

# ──────────────────────────────────────────────────────────────────────────────
# 9. `.git` 없는 잔해 회수 엔진 (giip #2449)
# ──────────────────────────────────────────────────────────────────────────────
# `Invoke-GissueWorktreeCleanupForRepo`(정식 등록 worktree)와 `-OrphanScan`(등록정보 소실 고아)
# 어느 쪽도 `.git` 이 아예 없는 디렉터리에는 도달하지 못한다. 이 엔진이 그 구멍을 메운다.
#
# 고아와 마찬가지로 `git worktree remove` 가 물리적으로 불가능하므로(등록정보는커녕 `.git` 자체가
# 없다) 디렉터리 삭제로 회수하고, 그 대가로 rule 55 §1~3 을 더 엄격하게 적용한다:
#   - `-Protect` 명시 경로와 최근 `-ProtectRecentMinutes` 분 내 수정된 것은 **판정과 무관하게** 보호
#     (giip #2432: DryRun 시점 판정이 실행 시점에 달라져 제외 지정 경로가 삭제된 사고).
#   - 링크 선검사 → 링크가 있으면 rule 55 §2-예외 3조건 판정 → 불충족이면 ManualReview(삭제 금지).
#   - 예외 충족 시에만: 대상 사전 건전성 → 정션만 제거 → 대상 사후 건전성 → **2차 링크 재검사(0건)**
#     → 디렉터리 삭제. 예외의 근거는 giip #2438 오너 결정이며 경계를 넓히지 않는다.
#   - 항목별 삭제 직후 인접 nested repo 무결성 재검증, 하나라도 어긋나면 즉시 전체 중단.
#   - ScanRoot 밖 경로, 대상 자체가 링크/정션인 경우는 삭제를 거부한다.
#
# ★ 결과는 `Invoke-GissueWorktreeCleanupForRepo` 와 같은 이유로 `-ResultRef ([ref]$var)` 로만 준다.
function Invoke-GissueRemnantCleanup {
    param(
        [string[]]$ScanRoot = @('D:\temp\worktrees'),
        [switch]$DryRun,
        [scriptblock]$Log = $null,
        [string[]]$ProtectedPaths = @(),
        [int]$ProtectRecentMinutes = 60,
        [int]$MinIdleMinutes = 120,
        [string[]]$VerifyRepos = @(),
        [ref]$ResultRef = $null
    )
    $say = { param($m) if ($Log) { & $Log $m } else { Write-Output $m } }
    $result = [pscustomobject]@{
        Scanned = 0; Removed = @(); Protected = @(); ManualReview = @()
        Aborted = $false; AbortReason = $null
    }
    $publish = { if ($ResultRef) { $ResultRef.Value = $result } }

    # rule 55 §3 재검증 대상 — csn-projects.json 등록 레포 전체(ScanRoot 밖만).
    # ScanRoot 안의 것을 넣으면 정상 삭제만으로도 "인접 레포가 사라짐" 위반이 떠서 첫 항목에서
    # 무조건 중단된다(giip #2439 에서 실측된 오탐).
    $verify = @(@($VerifyRepos) + @(Get-GissueAllProjectRepoPaths) | Where-Object { $_ } | Where-Object {
        $c = ConvertTo-GissueComparablePath $_
        $inScan = $false
        foreach ($r in $ScanRoot) {
            $rc = ConvertTo-GissueComparablePath $r
            if ($c -eq $rc -or $c.StartsWith($rc + '\')) { $inScan = $true }
        }
        -not $inScan
    } | Select-Object -Unique)
    if ($verify.Count -eq 0) {
        & $say 'ERROR: 인접 nested repo 재검증 대상이 0개입니다 — rule 55 §3 검증 불가로 삭제를 수행하지 않습니다.'
        $result.Aborted = $true; $result.AbortReason = '재검증 대상 0개'
        & $publish; return
    }
    & $say "인접 nested repo 재검증 대상($($verify.Count)개): $($verify -join ', ')"

    $items = Get-GissueNoGitRemnant -ScanRoot $ScanRoot
    $result.Scanned = $items.Count
    & $say "=== .git 없는 잔해 $($items.Count)건 발견 (ScanRoot=$($ScanRoot -join ', '), DryRun=$($DryRun.IsPresent)) ==="

    $protectNorm = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in @($ProtectedPaths)) { if ($p) { [void]$protectNorm.Add((ConvertTo-GissueComparablePath $p)) } }
    $cutoff = (Get-Date).AddMinutes(-1 * $ProtectRecentMinutes)

    foreach ($o in $items) {
        if ($result.Aborted) { break }

        # (a) 명시 보호 — 판정 결과보다 우선(giip #2432).
        $oNorm = ConvertTo-GissueComparablePath $o.Path
        $isProtected = $protectNorm.Contains($oNorm)
        if (-not $isProtected) {
            foreach ($pp in $protectNorm) { if ($pp.StartsWith($oNorm + '\')) { $isProtected = $true; break } }
        }
        if ($isProtected) {
            & $say "PROTECTED(명시 지정 — 다른 세션 작업 중이거나 보호 경로의 상위): $($o.Path)"
            $result.Protected += [pscustomobject]@{ Path = $o.Path; Reason = '-Protect 로 명시 지정됨(또는 그 상위 경로)' }
            continue
        }
        # (b) 디렉터리 자체의 최근 수정.
        if ($o.LastWriteTime -and ($o.LastWriteTime -gt $cutoff)) {
            & $say "PROTECTED(최근 $ProtectRecentMinutes 분 내 수정 $($o.LastWriteTime)): $($o.Path)"
            $result.Protected += [pscustomobject]@{ Path = $o.Path; Reason = "최근 $ProtectRecentMinutes 분 내 수정됨($($o.LastWriteTime))" }
            continue
        }
        # (c) 트리 안 최신 수정시각 — 사람/다른 세션이 작업 중일 수 있음(rule 55 "사용 중 worktree 보호").
        if ($MinIdleMinutes -gt 0 -and $o.NewestWriteUtc) {
            $idleMin = ([datetime]::UtcNow - $o.NewestWriteUtc).TotalMinutes
            if ($idleMin -lt $MinIdleMinutes) {
                & $say ("PROTECTED(트리 안 파일이 {0:N0}분 전 변경 — MinIdleMinutes={1}): {2}" -f $idleMin, $MinIdleMinutes, $o.Path)
                $result.Protected += [pscustomobject]@{ Path = $o.Path; Reason = ("최근 활동 감지({0:N0}분 전)" -f $idleMin) }
                continue
            }
        }
        # (d) 경로 형태 가드.
        $underRoot = $false
        foreach ($r in $ScanRoot) {
            if ($oNorm.StartsWith((ConvertTo-GissueComparablePath $r) + '\')) { $underRoot = $true }
        }
        if (-not $underRoot) {
            & $say "MANUAL-REVIEW(ScanRoot 밖 경로 — 삭제 거부): $($o.Path)"
            $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = 'ScanRoot 밖 경로' }
            continue
        }
        $selfItem = Get-Item -LiteralPath $o.Path -Force -ErrorAction SilentlyContinue
        if ($selfItem -and $selfItem.LinkType) {
            & $say "MANUAL-REVIEW(대상 자체가 링크/정션 — 삭제 거부): $($o.Path)"
            $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = '대상 디렉터리 자체가 심볼릭 링크/정션' }
            continue
        }

        # (e) rule 55 §1-2 링크 판정 + §2-예외.
        $exemption = $null
        if ($o.ScanFailed -or $o.LinkCount -gt 0) {
            $exemption = Get-GissueJunctionExemption -WorktreePath $o.Path -ExtraLiveRoots $verify
            if (-not $exemption.Eligible) {
                & $say "MANUAL-REVIEW(심볼릭 링크/정션 — rule 55 §1-2, 자동삭제 금지): $($o.Path) — $($exemption.Reason)"
                foreach ($d in $o.LinkDetail) { & $say "      link: $d" }
                $result.ManualReview += [pscustomobject]@{
                    Path = $o.Path
                    Reason = "링크/정션 포함 — 자동삭제 금지(rule 55 §1-2): $($exemption.Reason)"
                    Links = $o.LinkDetail
                }
                continue
            }
            & $say "LINK-EXEMPT(rule 55 §2-예외, giip #2438): $($o.Path) — $($exemption.Reason)"
        }

        if ($DryRun) {
            if ($exemption) {
                & $say "[DRY-RUN] 삭제 예정(§2-예외 적용): $($o.Path) / 제거할 정션=$($exemption.JunctionPath) -> 대상(보존)=$($exemption.TargetPath)"
            } else {
                & $say "[DRY-RUN] 삭제 예정(링크 없음 확인됨): $($o.Path) (최상위 항목 $($o.TopEntries)개)"
            }
            $result.Removed += [pscustomobject]@{ Path = $o.Path; Exempt = [bool]$exemption }
            continue
        }

        $preSnap = Get-GissueRepoIntegritySnapshot $verify

        if ($exemption) {
            $preHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $preHealth.Ok) {
                & $say "MANUAL-REVIEW(정션 대상이 이미 비정상 — 예외 미적용): $($o.Path) — $($preHealth.Detail)"
                $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = "정션 대상 사전검증 실패: $($preHealth.Detail)" }
                continue
            }
            & $say "  정션 대상 사전검증 OK — $($preHealth.Detail)"
            $rmJunction = Remove-GissueJunctionOnly -JunctionPath $exemption.JunctionPath
            if (-not $rmJunction.Ok) {
                & $say "MANUAL-REVIEW(정션 제거 실패 — 디렉터리는 건드리지 않음): $($o.Path) — $($rmJunction.Detail)"
                $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = "정션 제거 실패: $($rmJunction.Detail)" }
                continue
            }
            & $say "  $($rmJunction.Detail)"
            $postHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $postHealth.Ok) {
                & $say "CRITICAL: 정션 제거 직후 대상이 비정상 — 즉시 중단. $($postHealth.Detail)"
                $result.Aborted = $true; $result.AbortReason = "정션 제거 후 대상 검증 실패: $($postHealth.Detail)"
                break
            }
            & $say "  정션 대상 사후검증 OK — $($postHealth.Detail)"
        }

        # 선검사와 삭제 사이의 경합 차단용 2차 링크 재검사 — 예외 경로에서는 정션 제거가 실제로
        # 먹혔는지(0건이 됐는지) 확인하는 역할도 겸한다. 여기서 1건이라도 나오면 절대 지우지 않는다.
        $reScan = Get-GissueWorktreeLinkScan -Path $o.Path -MaxLinks 1
        if ($reScan.ScanFailed -or $reScan.Links.Count -gt 0) {
            & $say "MANUAL-REVIEW(삭제 직전 2차 링크 검사에서 링크 발견/스캔실패 — 중단): $($o.Path)"
            $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = '삭제 직전 2차 링크 검사 실패(링크 발견 또는 스캔 실패)' }
            continue
        }

        $del = Remove-GissueDirectoryTreeSafely -Path $o.Path -Log $Log
        $delOk = $del.Ok
        if (-not $delOk) {
            & $say "WARN: 잔해 삭제 실패($($o.Path)) — $($del.Detail)"
            $result.ManualReview += [pscustomobject]@{ Path = $o.Path; Reason = "삭제 실패: $($del.Detail)" }
        }

        # rule 55 §3 — 삭제 시도 직후(성공/실패 무관) 즉시 재검증.
        $postSnap = Get-GissueRepoIntegritySnapshot $verify
        $integrity = Compare-GissueRepoIntegrity $preSnap $postSnap
        # giip #2466 — 다른 세션의 정상 커밋으로 HEAD 가 움직인 것은 손상이 아니다. 기록만 남기고 진행.
        # (이 경로가 바로 giip #2449 실행에서 3회 abort 당한 곳이다.)
        foreach ($w in $integrity.Warnings) { & $say "WARN(rule 55 §3, giip #2466): $w" }
        $violations = @($integrity.Violations)
        if ($violations.Count -gt 0) {
            foreach ($v in $violations) { & $say "CRITICAL: '$($o.Path)' 삭제 직후 — $v (giip #2232 재발 의심)" }
            & $say 'CRITICAL: 즉시 중단합니다. 남은 항목은 처리하지 않습니다.'
            $result.Aborted = $true; $result.AbortReason = ($violations -join ' / ')
            break
        }
        if ($exemption) {
            $finalHealth = Test-GissueJunctionTargetHealthy -TargetPath $exemption.TargetPath -TargetRepoRoot $exemption.TargetRepoRoot
            if (-not $finalHealth.Ok) {
                & $say "CRITICAL: '$($o.Path)' 삭제 직후 정션 대상이 비정상 — 즉시 중단. $($finalHealth.Detail)"
                $result.Aborted = $true; $result.AbortReason = "삭제 후 정션 대상 검증 실패: $($finalHealth.Detail)"
                break
            }
            & $say "  삭제 후 정션 대상 재검증 OK — $($finalHealth.Detail)"
        }
        if ($delOk) {
            & $say "삭제됨(잔해, 인접 레포 $($verify.Count)개 무결성 재검증 통과): $($o.Path)"
            $result.Removed += [pscustomobject]@{ Path = $o.Path; Exempt = [bool]$exemption }
        }
    }
    & $publish
}
