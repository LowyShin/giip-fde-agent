# code-sync.ps1 — 러너 기동 초입의 "자동 반영"(자기 갱신) 로직 (giip #6214)
#
# ── 왜 필요한가 (실측) ────────────────────────────────────────────────────────────
# 사양서 §11 은 "PR 머지 ≠ 스케줄러가 새 코드로 도는 것"을 운영 함정으로 못박아 두었고, §17-5 는
# "러너는 시작 시 self-pull 로 에이전트 레포를 최신화한다"고 적어 두었다. **그런데 정본 러너에는
# 실제 pull 이 없었다.** `git pull` 이 등장하는 곳은 `Invoke-GissueSelfPullNotOnMainCheck` 안쪽
# 뿐인데, 그 함수는 HEAD 가 main 이면 **아무 것도 하지 않고 return** 한다(= NOT-ON-MAIN 복귀 전용).
# 즉 main 체크아웃에서 도는 정상 경로에서는 **원격에 머지된 코드가 영영 반영되지 않았다.**
#   → 2026-11 실측(호스트 lowy-dp01): 마지막 실행 기록 2026-11-01, 마지막 하트비트 2026-11-11.
#     서버 쪽 기록 경로(SP·디스패처)는 정상인데 기록이 없었고, 원인은 호스트의 러너 복사본이
#     `lib/scheduler-state.ps1` 을 아예 참조하지 않는 옛 버전이었다(호스트 복사본에 파일 자체가 없음).
#
# ── 이 파일이 하는 일 ─────────────────────────────────────────────────────────────
# 러너 기동 초입(아직 어떤 CSN 잡도 시작하지 않은 시점)에 **정본 체크아웃을 최신화**하고,
# 실행 위치가 그 체크아웃과 다르면 `scripts/gissue` 를 실행 위치로 **동기화**한다.
#   1) git 포트(명령 실행) — `Get-GissueGitOutput` 한 곳에만 있다(EAP 함정 회피 목적).
#   2) 상태 조회 — `Get-GissueRepoHeadInfo` (HEAD·브랜치·변경 dirty 여부).
#   3) 동기화 — `Sync-GissueAgentRepo` (fetch → fast-forward merge → scripts/gissue 복사).
#
# ── 안전 계약 ─────────────────────────────────────────────────────────────────────
#   - **파괴적 동작을 하지 않는다.** reset --hard / checkout --force / stash / clean 을 쓰지 않는다.
#     로컬에 tracked 변경이 있으면 pull 하지 않고 "변경 있음"으로 보고만 한다(사람의 작업 보존).
#   - **실패해도 실행을 막지 않는다(fail-open).** 동기화 실패는 사유를 기록만 남기고 옛 코드로 계속한다.
#   - **기록을 남긴다.** 전후 HEAD·상태·사유는 호출부가 실행 기록(RunEnd summary·시작 기록)에 싣는다.
#   - **가드를 해치지 않는다.** `code-freshness.ps1` 의 기준 해시 스냅샷보다 **앞**에서 돈다 —
#     스냅샷 뒤에 pull 이 일어나면 그 실행은 즉시 "낡은 코드"로 latch 되어 파괴적 작업을 통째로
#     건너뛴다(오탐). 반대로 pull 이 먼저 끝나면 새 코드가 메모리에 적재되고 스냅샷도 새 코드 기준이 된다.
#
# 이 파일은 러너의 다른 함수를 부르지 않는다(자기완결). PowerShell 5.1 호환.
# 소비처: run-gissue-claude.ps1(기동 초입) + tests/test-code-sync.ps1(네트워크 없는 로컬 git 검증).

# ── git 호출 포트 ─────────────────────────────────────────────────────────────────
# Windows PowerShell 5.1 은 native 명령의 stderr 를 ErrorRecord(NativeCommandError)로 올리고,
# 전역 $ErrorActionPreference='Stop' 아래에서는 그것만으로 terminating 이 된다(러너 기본값이 Stop).
# → git 호출 구간만 EAP 를 'Continue' 로 임시 낮추고 **종료 코드**로 판정한다.
# 반환: Exit(종료 코드) / Text(합친 출력).
function Get-GissueGitOutput {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$GitArgs
    )
    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = (& git -C $RepoRoot @GitArgs 2>&1 | Out-String)
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    return [pscustomobject]@{ Exit = [int]$exit; Text = "$raw" }
}

# ── 체크아웃 상태 조회 ────────────────────────────────────────────────────────────
# 반환: IsRepo / Sha / ShortSha / Branch / Dirty(변경 있음 여부) / DirtyCount(변경 파일 수)
#   - 저장소가 아니면( .git 없음 / git 실패) IsRepo=$false 로 돌려주고 나머지는 비운다.
#   - Sha 는 40자 hex 여야 한다(그 외는 '없음'으로 본다 — 추측 금지).
#   - Dirty 는 **추적(tracked) 파일의 변경만** 센다(untracked 제외). 운영 호스트에는 로그 디렉터리·
#     운영자가 채운 로컬 설정(csn-projects.json) 같은 untracked 항목이 항상 남아 있다 — 이것까지
#     "변경"으로 보면 pull 이 영영 보류되어 자동 반영이 아예 동작하지 않게 된다(실측 위험).
function Get-GissueRepoHeadInfo {
    param([string]$RepoRoot)
    $empty = [pscustomobject]@{
        IsRepo = $false; Sha = ''; ShortSha = ''; Branch = ''; Dirty = $false; DirtyCount = 0
    }
    if (-not $RepoRoot) { return $empty }
    if (-not (Test-Path -LiteralPath $RepoRoot)) { return $empty }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { return $empty }

    $shaRes = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', 'HEAD')
    if ($shaRes.Exit -ne 0) { return $empty }
    $sha = "$($shaRes.Text)".Trim()
    if ($sha -notmatch '^[0-9a-f]{40}$') { return $empty }

    $branchRes = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
    $branch = "$($branchRes.Text)".Trim()
    if ($branchRes.Exit -ne 0 -or -not $branch) { $branch = '' }

    # `--untracked-files=no` — untracked(로그·로컬 설정 등)는 "사람의 작업"이 아니므로 pull 을 막지 않는다.
    $dirtyRes = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('status', '--porcelain', '--untracked-files=no')
    $dirtyCount = 0
    if ($dirtyRes.Exit -eq 0) {
        $dirtyCount = @(("$($dirtyRes.Text)" -split "`r?`n") | Where-Object { $_.Trim() }).Count
    }

    return [pscustomobject]@{
        IsRepo     = $true
        Sha        = $sha
        ShortSha   = $sha.Substring(0, 7)
        Branch     = $branch
        Dirty      = ($dirtyCount -gt 0)
        DirtyCount = $dirtyCount
    }
}

# ── 실행 위치 결정 ────────────────────────────────────────────────────────────────
# 동기화 대상 = "정본 체크아웃". 러너가 체크아웃 밖의 복사본에서 돌면 자기 자신은 pull 대상이 아니다.
#   1) 환경변수 GIIP_FDE_REPO_ROOT (운영자가 명시한 정본 체크아웃) — 최우선
#   2) 러너 자신으로부터 유도한 저장소 루트 — 그것이 git 체크아웃일 때
# 둘 다 아니면 $null(= 동기화 불가 사유를 남기고 옛 코드로 계속).
function Resolve-GissueSyncRepoRoot {
    param([string]$RunnerRepoRoot)
    $envRoot = "$($env:GIIP_FDE_REPO_ROOT)".Trim()
    if ($envRoot) {
        if (Test-Path -LiteralPath (Join-Path $envRoot '.git')) { return $envRoot }
        return $null   # 환경변수는 지정했는데 체크아웃이 아니다 → 사유는 호출부가 남긴다
    }
    if ($RunnerRepoRoot -and (Test-Path -LiteralPath (Join-Path $RunnerRepoRoot '.git'))) { return $RunnerRepoRoot }
    return $null
}

# ── scripts/gissue 트랙 파일 목록 ─────────────────────────────────────────────────
# 복사 대상은 **git 이 추적하는 파일만**이다. 로컬 전용 설정(예: csn-projects.json · 로그)은
# untracked 이므로 건드리지 않는다 — 운영자가 채워 둔 값을 동기화가 지우면 안 된다.
# 반환: 저장소 루트 기준 상대경로 배열(항상 'scripts/gissue/' 로 시작).
function Get-GissueTrackedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$RelDir = 'scripts/gissue'
    )
    $res = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('ls-files', '--', $RelDir)
    if ($res.Exit -ne 0) { return @() }
    $out = @()
    foreach ($line in @("$($res.Text)" -split "`r?`n")) {
        $t = "$line".Trim()
        if ($t) { $out += $t }
    }
    return @($out)
}

# ── 스크립트 디렉터리 동기화(체크아웃 → 실행 위치) ────────────────────────────────
# 규칙: (a) **삭제하지 않는다**(실행 위치에 남는 로컬 파일 보존) (b) **대상 파일이 없거나 내용이 다를
# 때만** 복사한다(불필요한 쓰기·mtime 변경 방지) (c) 복사 실패는 그 파일만 실패로 세고 계속한다.
# 반환: Copied(복사 건수) / Skipped(같아서 건너뜀) / Failed(실패 건수) / FailedPaths(실패 경로)
function Sync-GissueScriptDir {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ExecRoot,
        [string]$RelDir = 'scripts/gissue'
    )
    $result = [pscustomobject]@{ Copied = 0; Skipped = 0; Failed = 0; FailedPaths = @() }
    if (-not (Test-Path -LiteralPath $ExecRoot)) {
        $result.Failed = 1
        $result.FailedPaths = @($ExecRoot)
        return $result
    }
    $prefix = "$RelDir/"
    $failed = @()
    foreach ($rel in @(Get-GissueTrackedFiles -RepoRoot $RepoRoot -RelDir $RelDir)) {
        if (-not $rel.StartsWith($prefix)) { continue }
        $inner = $rel.Substring($prefix.Length)
        if (-not $inner) { continue }
        $src = Join-Path $RepoRoot ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $dst = Join-Path $ExecRoot ($inner -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
        $needCopy = $true
        if (Test-Path -LiteralPath $dst -PathType Leaf) {
            try {
                $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256 -ErrorAction Stop).Hash
                $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($srcHash -eq $dstHash) { $needCopy = $false }
            } catch {
                $needCopy = $true   # 비교 실패 → 복사 시도(원본이 정본)
            }
        }
        if (-not $needCopy) { $result.Skipped++; continue }
        try {
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
            $result.Copied++
        } catch {
            $result.Failed++
            $failed += $inner
        }
    }
    $result.FailedPaths = @($failed)
    return $result
}

# ── 동기화 본체 ───────────────────────────────────────────────────────────────────
# 순서: 상태 조회(전) → fetch → fast-forward merge → 상태 조회(후) → scripts/gissue 동기화.
# 반환(모두 pscustomobject):
#   Status      : updated | already-current | skipped-not-repo | skipped-not-main | skipped-dirty
#                 | skipped-no-remote | skipped-no-target | failed
#   Reason      : 사유(사람이 읽는 한 줄)
#   RepoRoot    : 동기화 대상 체크아웃(없으면 '')
#   Branch      : 대상 브랜치
#   ShaBefore   : 동기화 전 HEAD(없으면 '')
#   ShaAfter    : 동기화 후 HEAD(없으면 '')
#   ExecRoot    : 실행 위치(scripts/gissue 디렉터리)
#   CopyResult  : 스크립트 디렉터리 동기화 결과(Copied/Skipped/Failed) — 실행 위치가 체크아웃과
#                 같으면 null(= 같은 위치이므로 복사가 필요 없다)
#   FetchError  : fetch 실패 사유(있으면)
#   MergeError  : fast-forward 실패 사유(있으면)
function Sync-GissueAgentRepo {
    param(
        [string]$RepoRoot = '',
        [string]$ExecRoot = '',
        [string]$Remote = 'origin',
        [string]$Branch = 'main',
        [scriptblock]$Log = $null,
        [switch]$NoRemote
    )
    $say = { param($m) if ($Log) { & $Log $m } }
    $result = [pscustomobject]@{
        Status = 'skipped-no-target'; Reason = ''; RepoRoot = ''; Branch = $Branch
        ShaBefore = ''; ShaAfter = ''; ExecRoot = $ExecRoot; CopyResult = $null
        FetchError = ''; MergeError = ''
    }
    if (-not $RepoRoot) {
        $result.Reason = '동기화 대상 체크아웃을 찾지 못함(GIIP_FDE_REPO_ROOT 미설정, 러너 위치도 체크아웃이 아님)'
        & $say "[CODE-SYNC] SKIP: $($result.Reason)"
        return $result
    }
    $result.RepoRoot = $RepoRoot
    $before = Get-GissueRepoHeadInfo -RepoRoot $RepoRoot
    if (-not $before.IsRepo) {
        $result.Status = 'skipped-not-repo'
        $result.Reason = "동기화 대상이 git 체크아웃이 아님: $RepoRoot"
        & $say "[CODE-SYNC] SKIP: $($result.Reason)"
        return $result
    }
    $result.ShaBefore = $before.Sha
    $result.ShaAfter  = $before.Sha

    # NOT-ON-MAIN 이면 pull 하지 않는다 — 브랜치 복귀는 러너의 기존 NOT-ON-MAIN 경로가 담당한다
    # (두 구현을 두면 어느 쪽이 판정했는지 알 수 없다 — 단일 출처 원칙).
    if ($before.Branch -and $before.Branch -ne $Branch) {
        $result.Status = 'skipped-not-main'
        $result.Reason = "HEAD 가 '$Branch' 가 아님(현재 $($before.Branch)) — 브랜치 복귀 없이 pull 하지 않음"
        & $say "[CODE-SYNC] SKIP: $($result.Reason)"
        return $result
    }
    # 로컬 변경이 있으면 덮어쓰지 않는다(사람의 작업을 지우는 사고를 막는다).
    if ($before.Dirty) {
        $result.Status = 'skipped-dirty'
        $result.Reason = "로컬 변경 $($before.DirtyCount)건이 있어 pull 하지 않음(사람의 작업 보존)"
        & $say "[CODE-SYNC] SKIP: $($result.Reason)"
        return $result
    }
    if ($NoRemote) {
        $result.Status = 'skipped-no-remote'
        $result.Reason = '원격 확인 생략(-NoRemote)'
        & $say "[CODE-SYNC] SKIP: $($result.Reason)"
        return $result
    }

    # ── fetch ──
    $fetch = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('fetch', $Remote, $Branch, '--quiet')
    if ($fetch.Exit -ne 0) {
        $result.Status = 'failed'
        $result.FetchError = "$($fetch.Text)".Trim()
        $result.Reason = "fetch 실패(exit=$($fetch.Exit)): $($result.FetchError)"
        & $say "[CODE-SYNC][WARN] $($result.Reason) — 옛 코드로 계속"
        return $result
    }
    # ── fast-forward merge ──(로컬이 앞서 있으면 실패한다 — reset 하지 않는다)
    $merge = Get-GissueGitOutput -RepoRoot $RepoRoot -GitArgs @('merge', '--ff-only', "$Remote/$Branch")
    if ($merge.Exit -ne 0) {
        $result.Status = 'failed'
        $result.MergeError = "$($merge.Text)".Trim()
        $result.Reason = "fast-forward 실패(exit=$($merge.Exit)): $($result.MergeError)"
        & $say "[CODE-SYNC][WARN] $($result.Reason) — 옛 코드로 계속"
        return $result
    }

    $after = Get-GissueRepoHeadInfo -RepoRoot $RepoRoot
    if ($after.IsRepo) { $result.ShaAfter = $after.Sha }
    if ($result.ShaAfter -and $result.ShaAfter -ne $result.ShaBefore) {
        $result.Status = 'updated'
        $result.Reason = "원격 반영 완료: $($result.ShaBefore.Substring(0,7)) → $($result.ShaAfter.Substring(0,7))"
    } else {
        $result.Status = 'already-current'
        $result.Reason = "이미 최신($($result.ShaBefore.Substring(0,7)))"
    }
    & $say "[CODE-SYNC] $($result.Status): $($result.Reason)"

    # ── 실행 위치가 체크아웃과 다르면 scripts/gissue 를 동기화 ──
    $checkoutDir = Join-Path $RepoRoot 'scripts/gissue'
    if ($ExecRoot) {
        $execFull = ''
        $checkoutFull = ''
        try { $execFull = (Resolve-Path -LiteralPath $ExecRoot -ErrorAction Stop).Path } catch { $execFull = '' }
        try { $checkoutFull = (Resolve-Path -LiteralPath $checkoutDir -ErrorAction Stop).Path } catch { $checkoutFull = '' }
        if ($execFull -and $checkoutFull -and ($execFull -ne $checkoutFull)) {
            $copy = Sync-GissueScriptDir -RepoRoot $RepoRoot -ExecRoot $ExecRoot
            $result.CopyResult = $copy
            $result.Reason += "; 스크립트 동기화 복사 $($copy.Copied)건/변경없음 $($copy.Skipped)건/실패 $($copy.Failed)건"
            & $say "[CODE-SYNC] scripts/gissue 동기화: 복사 $($copy.Copied)건 / 동일 $($copy.Skipped)건 / 실패 $($copy.Failed)건"
            if ($copy.Failed -gt 0) {
                $result.Status = 'failed'
                $result.Reason += " (실패 경로: $(@($copy.FailedPaths) -join ', '))"
            }
        }
    }
    return $result
}

# ── 실행 기록용 요약 문자열 ───────────────────────────────────────────────────────
# 동기화 결과를 사람·기록이 읽을 한 줄로 접는다. SHA 는 7자만(기록 가독성), 사유는 함께 싣는다.
# 사유는 길이를 제한한다 — fetch 실패 문구가 수백 자일 수 있는데 그대로 넣으면 실행 기록의
# 500자 제한에 밀려 **다른 항목(기록 호출 실패 등)이 잘려 나간다.**
function Format-GissueCodeSyncSummary {
    param($Sync, [int]$MaxReasonLength = 160)
    if ($null -eq $Sync) { return '없음' }
    $status = "$($Sync.Status)"
    $before = "$($Sync.ShaBefore)"
    $after  = "$($Sync.ShaAfter)"
    $b = if ($before) { $before.Substring(0, [Math]::Min(7, $before.Length)) } else { '?' }
    $a = if ($after)  { $after.Substring(0, [Math]::Min(7, $after.Length)) }  else { '?' }
    $text = "$status($b→$a)"
    $reason = "$($Sync.Reason)".Trim()
    if ($reason) {
        if ($MaxReasonLength -gt 0 -and $reason.Length -gt $MaxReasonLength) {
            $reason = $reason.Substring(0, [Math]::Max(1, $MaxReasonLength - 1)) + '…'
        }
        $text += " $reason"
    }
    return $text
}
