# ==============================================================================
# code-freshness.ps1 — "지금 메모리에 올라와 있는 코드가 아직 최신인가" 판정 (giip #2471)
# ==============================================================================
#
# ── 왜 필요한가 (실측 사고, 2026-09-14) ──
# run-gissue-claude.ps1 은 실행 **시작 시점에만** self-pull 한다(giip #2386, PR #706). 그 뒤
# `. worktree-safety.ps1` 로 정리 엔진을 **닷소싱**하므로, 판정 로직 전체가 프로세스 기동 시각의
# 스냅샷으로 메모리에 고정된다. 잡 예산($RunTimeoutMin)은 105분이라 **최대 두 시간 가까이 낡은
# 코드가 파괴적 작업을 계속한다.**
#
#   12:07:00  :07 스케줄러 기동 → self-pull → 구 worktree-safety.ps1 을 메모리에 적재
#   12:54:53  PR #744(giip #2438/#2440) 머지 — 위험한 `clean+pushed` 삭제판정 제거
#   13:03:59  그 구 판정으로 giip #2445 세션의 **작업 중 worktree 를 삭제** ← 피해 발생
#
# 즉 안전수정을 아무리 빨리 머지해도 **이미 돌고 있는 실행에는 원리적으로 닿지 않는다.** 급한
# 안전수정일수록(= 지금 피해가 나서 고치는 것) 이 갭이 그대로 피해 시간으로 남는다.
#
# ── 이 모듈이 하는 일 ──
# 프로세스 기동 직후(= 닷소싱으로 코드를 메모리에 올린 직후) 감시 대상 스크립트들의 blob 해시를
# 스냅샷으로 잡아두고, **파괴적 작업 직전마다** "그 해시가 아직 유효한가"를 되묻는다. 달라졌다면
# 지금 메모리에 있는 판정 로직은 낡은 것이므로 그 작업을 건너뛰고 다음 :07(= 새 프로세스, 새 코드)에
# 넘긴다. 정리 작업은 멱등하고 매 CSN 잡 종료마다 다시 돌므로, 건너뛰기의 비용은 최대 한 사이클
# 지연뿐이다 — 반면 낡은 판정으로 지운 남의 작업물은 되돌릴 수 없다.
#
# ── 두 개의 층 (둘 다 필요하다) ──
#   Layer A (로컬, 항상): 기동 시 해시 vs **지금 디스크의 해시**.
#       공유 체크아웃은 사람 세션/서브에이전트가 수시로 `git pull` 한다. 그러면 디스크의 스크립트는
#       새것인데 메모리는 구것인 상태가 된다 — 이번 사고가 정확히 이 경우다.
#   Layer B (원격, 스로틀): 기동 시 해시 vs **origin/main 의 해시**.
#       아무도 pull 하지 않았다면 Layer A 는 아무 변화도 못 본다. 그래도 머지는 이미 일어났고,
#       다음 :07 은 self-pull 로 그 수정을 받는다. 그러니 "원격에 새 안전수정이 있다"만으로도
#       이번 실행의 파괴적 작업은 미루는 편이 맞다. git fetch 비용이 있어 기본 10분에 한 번만 확인한다.
#       단, 그 파일에 **로컬 미커밋 변경**이 있으면 origin 과 다른 게 정상이므로 비교에서 제외한다
#       (그렇지 않으면 개발 중인 체크아웃에서 정리가 영구히 멈춘다).
#
# ── 설계 원칙 ──
#   1) **fail-open**: 초기화 안 됨 / git 실패 / 예외 → "낡지 않음"으로 본다. 이 가드가 고장 나서
#      정리가 통째로 멈추면 그것도 결함이다(C드라이브 고갈 인시던트, giip #2220). 가드는 "확실히
#      낡았다"는 증거가 있을 때만 막는다.
#   2) **latch(한 번 낡으면 그 프로세스 내내 낡음)**: 판정이 실행마다 뒤집히면(= 플래핑) 어떤 작업은
#      막히고 어떤 작업은 통과하는 비결정적 동작이 된다. 낡음이 확인되면 그 프로세스가 끝날 때까지
#      유지한다 — 어차피 메모리의 코드는 그 프로세스가 죽어야 갱신된다.
#   3) **스위치 없음**: "가드 끄기" 환경변수를 두지 않는다. 그런 스위치는 호출부가 항상 넘기게 되어
#      금지 자체가 무력화된다. 단명 프로세스(cleanup-worktrees.ps1 등)는 Initialize 를 부르지
#      않으므로 자동으로 가드 대상이 아니다 — 애초에 이 갭이 없기 때문이다.
#
# ── 한계 (숨기지 않고 명시한다) ──
# 이 가드는 **이 파일이 머지된 이후에 기동한 프로세스**만 보호한다. 이미 구 코드를 메모리에 올린 채
# 돌고 있는 프로세스에는 이 가드 자체가 존재하지 않는다. 이건 in-process 접근이든 별도 프로세스
# 호출이든 동일하다 — "그 별도 프로세스를 부르자"는 결정 자체가 낡은 부모의 코드이기 때문이다.
# 원리적으로 피할 수 없고, 다음 :07 부터 효력이 생긴다.
# ==============================================================================

# 이 프로세스의 스냅샷 상태. $null 이면 "가드 미적용"(fail-open).
$script:GissueCodeFreshness = $null

# 감시 대상(레포 루트 상대경로, 슬래시 표기 고정 — `git rev-parse origin/main:<path>` 가 그 형식만 받는다).
# 부모 프로세스가 **자기 메모리 코드로 직접** 파괴적 작업을 수행하는 경로만 넣는다.
# `powershell -File` 로 매번 새로 띄우는 스크립트(pr-gate-sweep / review-done-audit /
# pr-attribution-sweep / merge-standing-prs)는 호출 시점에 디스크에서 다시 읽히므로 여기 넣지 않는다.
$script:GissueCodeFreshnessDefaultPaths = @(
    'scripts/gissue/worktree-safety.ps1',
    'scripts/gissue/run-gissue-claude.ps1'
)

function Get-GissueFileBlobHash {
    # 워킹트리 파일의 git blob 해시. `--path` 를 주어 checkin 필터(줄끝 정규화 등)를 그 경로 기준으로
    # 적용시킨다 — 그래야 `git rev-parse <rev>:<path>` 가 돌려주는 해시와 같은 기준이 된다.
    param([string]$RepoRoot, [string]$RelPath)
    $abs = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path -LiteralPath $abs)) { return $null }
    $h = & git -C $RepoRoot hash-object --path $RelPath -- $abs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $h = "$(@($h) | Select-Object -First 1)".Trim()
    if ($h -match '^[0-9a-f]{40}$') { return $h }
    return $null
}

function Initialize-GissueCodeFreshness {
    <#
    .SYNOPSIS
      지금 메모리에 올라온 코드의 기준 해시를 기록한다. 닷소싱 **직후** 한 번만 호출한다.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$WatchPaths = $null,
        [int]$RemoteCheckIntervalMin = 10,
        [scriptblock]$Log = $null
    )
    $say = { param($m) if ($Log) { & $Log $m } }
    if (-not $WatchPaths) { $WatchPaths = $script:GissueCodeFreshnessDefaultPaths }
    $snapshot = @{}
    try {
        $root = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
        foreach ($rel in $WatchPaths) {
            $h = Get-GissueFileBlobHash -RepoRoot $root -RelPath $rel
            if ($h) { $snapshot[$rel] = $h }
            else { & $say "WARN: '$rel' 해시를 구하지 못함 — 이 파일은 감시에서 제외" }
        }
    } catch {
        & $say "WARN: 스냅샷 실패(가드 미적용으로 계속 진행) — $($_.Exception.Message)"
        return
    }
    if ($snapshot.Count -eq 0) {
        & $say 'WARN: 감시 대상 스냅샷이 비어 있음 — 가드 미적용으로 계속 진행'
        return
    }
    $script:GissueCodeFreshness = [pscustomobject]@{
        RepoRoot               = $root
        Snapshot               = $snapshot
        RemoteCheckIntervalMin = $RemoteCheckIntervalMin
        LastRemoteCheck        = $null
        Stale                  = $false
        Reason                 = $null
    }
    $brief = (@($snapshot.Keys | Sort-Object) | ForEach-Object { "$_=$($snapshot[$_].Substring(0,8))" }) -join ', '
    & $say "기준 코드 스냅샷 기록($($snapshot.Count)개): $brief"
}

function Get-GissueCodeStaleReason {
    # 마지막으로 확정된 낡음 사유(없으면 $null).
    if ($script:GissueCodeFreshness) { return $script:GissueCodeFreshness.Reason }
    return $null
}

function Test-GissueCodeStale {
    <#
    .SYNOPSIS
      "지금 메모리의 코드가 낡았는가"를 판정한다. 파괴적 작업 **직전**에 호출한다.
    .OUTPUTS
      [bool] — $true 면 그 작업을 수행하지 말고 다음 실행에 넘겨야 한다.
    #>
    param(
        [scriptblock]$Log = $null,
        [switch]$NoRemote   # 원격 확인 생략(테스트/오프라인). 로컬 비교는 그대로 수행한다.
    )
    $st = $script:GissueCodeFreshness
    if (-not $st) { return $false }          # 미초기화 = 단명 프로세스 → 이 갭이 없다
    $say = { param($m) if ($Log) { & $Log $m } }
    if ($st.Stale) { return $true }          # latch: 한 번 낡으면 이 프로세스 내내 낡음

    $latch = {
        param($reason)
        $st.Stale = $true
        $st.Reason = $reason
        & $say "STALE-CODE: $reason — 이 프로세스의 판정 로직은 낡았다. 파괴적 작업을 건너뛰고 다음 :07(새 프로세스, 새 코드)에 넘긴다."
    }

    # ── Layer A: 디스크가 우리 발밑에서 갱신됐는가 ──
    try {
        foreach ($rel in @($st.Snapshot.Keys)) {
            $now = Get-GissueFileBlobHash -RepoRoot $st.RepoRoot -RelPath $rel
            if (-not $now) { continue }      # 읽기 실패 → fail-open(이 파일만 건너뜀)
            if ($now -ne $st.Snapshot[$rel]) {
                & $latch "로컬 체크아웃의 '$rel' 이 이 프로세스 기동 이후 바뀜(메모리 $($st.Snapshot[$rel].Substring(0,8)) → 디스크 $($now.Substring(0,8)))"
                return $true
            }
        }
    } catch {
        & $say "WARN: 로컬 최신성 비교 실패(가드 통과시킴) — $($_.Exception.Message)"
    }

    # ── Layer B: 아무도 pull 하지 않았어도 origin/main 에 새 코드가 있는가 ──
    if (-not $NoRemote) {
        $due = (-not $st.LastRemoteCheck) -or (((Get-Date) - $st.LastRemoteCheck).TotalMinutes -ge $st.RemoteCheckIntervalMin)
        if ($due) {
            $st.LastRemoteCheck = Get-Date
            $prevEap = $ErrorActionPreference
            try {
                # git 은 진행상황을 stderr 로 내보낸다. 전역 $ErrorActionPreference='Stop' 아래에서는
                # 그것만으로 종료오류로 승격되므로(giip #2386 과 같은 함정) 이 블록에서만 낮춘다.
                $ErrorActionPreference = 'Continue'
                & git -C $st.RepoRoot fetch origin main --quiet 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { return $false }   # 네트워크/인증 실패 → fail-open
                foreach ($rel in @($st.Snapshot.Keys)) {
                    # 로컬 미커밋 변경이 있으면 origin 과 다른 게 정상이다 — 비교 대상에서 제외한다.
                    $dirty = & git -C $st.RepoRoot status --porcelain -- $rel 2>$null
                    if ($dirty) { continue }
                    $remote = & git -C $st.RepoRoot rev-parse "origin/main:$rel" 2>$null
                    if ($LASTEXITCODE -ne 0) { continue }
                    $remote = "$(@($remote) | Select-Object -First 1)".Trim()
                    if ($remote -notmatch '^[0-9a-f]{40}$') { continue }
                    if ($remote -ne $st.Snapshot[$rel]) {
                        & $latch "origin/main 의 '$rel' 이 이 프로세스가 적재한 코드와 다름(메모리 $($st.Snapshot[$rel].Substring(0,8)) → origin/main $($remote.Substring(0,8))) — 실행 도중 새 수정이 머지됨"
                        return $true
                    }
                }
            } catch {
                & $say "WARN: 원격 최신성 비교 실패(가드 통과시킴) — $($_.Exception.Message)"
            } finally {
                $ErrorActionPreference = $prevEap
            }
        }
    }

    return $false
}
