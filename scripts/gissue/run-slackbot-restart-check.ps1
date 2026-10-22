# run-slackbot-restart-check.ps1 — slack-bot 배포 커밋 변경 감지 + 유휴 시에만 pm2 재시작 (giip #2148)
#
# ── 배경 ───────────────────────────────────────────────────────────────────────
# giip #2147/#2044/#2117 실측: slack-bot 코드가 main 에 머지·반영돼도 pm2 로 돌고 있는 프로세스는
# 옛 코드를 그대로 유지한다(3일 미재시작 사례). 그래서 "이미 고친 버그가 여전히 재현되는 것처럼" 보였고,
# 같은 오인이 반복될 구조적 갭이었다.
#
# ── 오너 결정(2026-09-14, giip #2148 cSn 14412) ─────────────────────────────────
# 옵션 (b) 채택: "시간별 스케줄러에서 slack-bot HEAD 가 바뀌었으면 pm2 restart 하되, 유휴 판정을
# 통과할 때만 재시작한다. 유휴가 아니면 건너뛰고 다음 시간에 재시도한다(최대 1시간 지연 수용)."
#   - (a) git post-merge 훅 즉시 재시작: 불채택(진행 중 라이브 태스크/서브에이전트 강제 종료 위험).
#   - (c) 수동 체크리스트: 불채택(#2147 재발을 구조적으로 못 막음).
# 유휴 판정은 설계 코멘트(cSn 12692 §3)의 3신호를 그대로 쓴다 — 새로 창작하지 않는다.
#
# ── 구현 위치 방침 ──────────────────────────────────────────────────────────────
# run-gissue-claude.ps1(3000+줄 단일 파일) 본문에 끼워넣지 않고 독립 스크립트로 분리했다
# (이 환경의 "파일은 최대한 분리" 방침 + 선례: GIIP_StalePending_Hourly / GIIP_StaleReview_Hourly 가
#  각각 별도 러너 + 별도 Task Scheduler 항목). 등록은 register-slackbot-restart-task.ps1 이 담당한다.
#
# ── 이 레포로의 이식 (giip #2645) ───────────────────────────────────────────────
# 판정 로직은 원본 그대로다. 배포 종속값만 파라미터로 뺐다:
#   · pm2 프로세스 이름 / 감시 경로 → `-ProcessName` / `-WatchPath` (원본은 'slack-bot' 하드코딩)
#   · repo-lock 파일 → 레포 이름이 박힌 단일 파일명 대신 `.agent/locks/*.lock` 디렉터리 스캔
# 이 스크립트는 DB 도 giip API 도 쓰지 않으므로 그 외에는 이식 변경이 없다.
#
# ── 감지 방식(설계 §2) ──────────────────────────────────────────────────────────
# 감시 대상(`-WatchPath`, 기본 slack-bot)은 별도 레포가 아니라 이 레포의 하위 디렉터리이고
# (실측: slack-bot/.git 없음), pm2 는 이 워킹트리의 그 폴더를 cwd 로 돌고 있다. 따라서 "지금 돌고
# 있는 코드"의 기준은 로컬 워킹트리에서 그 경로를 마지막으로 바꾼 커밋이다:
#     git -C <repoRoot> log -1 --format=%H -- <WatchPath>
# 이 값을 재시작 시점마다 마커 파일(logs/slackbot_deployed_head.txt)에 기록하고, 매 실행마다 현재
# 값과 비교한다. 다르면 "새 배포 미반영"으로 판정한다. 마커가 없으면(최초 도입) 기록만 하고 재시작하지
# 않는다(도입 시점 불필요 재시작 방지 — 설계 §2 마지막 항목).
# origin/main 비교는 정보성 로그로만 남긴다. 이 스크립트는 공유 체크아웃에서 fetch/pull/checkout 등
# 워킹트리를 바꾸는 git 명령을 절대 실행하지 않는다(매시 :07 스케줄러와의 경합 방지).
#
# ── 유휴 판정 3신호(설계 §3) — 하나라도 걸리면 재시작 보류, 다음 실행에서 재시도 ──────────────
#   1) Get-GissueBusyRepo($repoRoot): slack-bot task-manager.js 는 작업 중 nested repo 를
#      bot/task-<id> 브랜치로 체크아웃했다가 끝나면 base(main/master)로 복원한다 → "base 브랜치가
#      아님" = 태스크 실행 중. (원본 로직: run-gissue-claude.ps1 Get-RepoBaseBranch /
#      Get-GissueGitRepoPaths / Get-GissueBusyRepo — 그 파일은 함수를 export 하지 않는 단일 스크립트라
#      동일 로직을 복제한다. run-gissue-claude.ps1 자신도 메인/잡 스코프에 같은 함수를 중복 정의하는
#      기존 컨벤션을 따른다.)
#   2) 레포 락(.agent/locks/*.lock) 보유 여부 — 살아있는 락(보유 프로세스 생존 + 120분 미만)이 하나라도
#      있으면 보류.
#   3) pm2 out/err 로그 staleness — 최근 $QuietMinutes(기본 5분) 이내 활동이 있으면 보류.
#      (좀비 워치독의 25분 기준보다 짧게 잡아 짧은 태스크 중 재시작을 피한다 — 설계 §3-3.)
#
# 보류가 연속 $HoldWarnThreshold(기본 6회 ≈ 6시간) 넘으면 로그에 [ALERT] 를 남겨 사람이 인지하게 한다.
# 강제 재시작은 하지 않는다(진행 중 태스크 손실 방지 우선 — 설계 §3 마지막 항목).
#
# ── 사용법 ─────────────────────────────────────────────────────────────────────
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-slackbot-restart-check.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-slackbot-restart-check.ps1 -DryRun
# -DryRun: 판정만 하고 pm2 restart / 마커·상태 파일 쓰기를 전부 생략한다(로그만 [DRYRUN] 으로 기록).

param(
    # 판정만 하고 실제 재시작·상태 파일 갱신은 하지 않는다(검증용).
    [switch]$DryRun,
    # pm2 프로세스 이름. 배포마다 다를 수 있어 인자로 뺐다(원본은 'slack-bot' 하드코딩 — giip #2645).
    [string]$ProcessName = 'slack-bot',
    # 배포 커밋 변경을 감시할 레포 하위 경로(= pm2 가 돌리는 코드가 들어 있는 폴더).
    [string]$WatchPath = 'slack-bot',
    # 유휴 신호 3: pm2 out/err 로그가 이 분 수 이내에 쓰였으면 "활동 중"으로 보고 보류한다.
    [int]$QuietMinutes = 5,
    # 연속 보류가 이 횟수를 넘으면 [ALERT] 로그를 남긴다(강제 재시작은 하지 않음).
    [int]$HoldWarnThreshold = 6
)

$ErrorActionPreference = 'Stop'

$ScriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $ScriptDir)   # scripts/gissue -> scripts -> repo root
$SlackBotDir = Join-Path $RepoRoot $WatchPath
$LogDir     = Join-Path $ScriptDir 'logs'
$LogFile    = Join-Path $LogDir 'gissue_slackbot_restart.log'
$MarkerFile = Join-Path $LogDir 'slackbot_deployed_head.txt'
$StateFile  = Join-Path $LogDir 'slackbot_restart_state.json'
# 유휴 신호 2 의 대상. 원본은 `.agent\locks\lowyworkenv-repo.lock` 이라는 **레포 이름이 박힌 단일
# 파일명**을 봤다(다른 레포에 그대로 옮기면 영원히 락을 못 본다). 이식하면서 락 디렉터리 전체를
# 훑도록 바꾼다 — 그 디렉터리에 있는 어떤 레포-락이든 살아 있으면 보류한다(giip #2645).
$LockDir    = Join-Path $RepoRoot '.agent\locks'
$LockStaleMinutes = 120   # repo-lock.ps1 의 기본 -StaleMinutes 와 동일

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-RestartLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = if ($DryRun) { '[DRYRUN]' } else { '' }
    $line = "[$ts] $prefix$msg"
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Output "[slackbot-restart] $prefix$msg"
}

# ── 유휴 신호 1 구현 (run-gissue-claude.ps1 의 동일 로직 복제) ──
function Get-RepoBaseBranch($repoPath) {
    try {
        $ref = git -C $repoPath symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $ref) { return ($ref -replace '^refs/remotes/origin/', '') }
    } catch {}
    foreach ($cand in @('main', 'master')) {
        git -C $repoPath show-ref --verify --quiet "refs/heads/$cand" 2>$null
        if ($LASTEXITCODE -eq 0) { return $cand }
    }
    return 'main'
}
function Get-GissueGitRepoPaths($workdir) {
    $paths = @()
    if (Test-Path (Join-Path $workdir '.git')) { $paths += $workdir }
    if (-not (Test-Path $workdir)) { return $paths }
    foreach ($item in Get-ChildItem -Path $workdir -ErrorAction SilentlyContinue) {
        $target = $null
        if ($item.PSIsContainer) {
            $target = $item.FullName
        } elseif ($item.Extension -eq '.lnk') {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $t = $sh.CreateShortcut($item.FullName).TargetPath
                if ($t -and (Test-Path $t)) { $target = $t }
            } catch {}
        }
        if ($target -and (Test-Path (Join-Path $target '.git'))) { $paths += $target }
    }
    return $paths
}
function Get-GissueBusyRepo($workdir) {
    foreach ($repo in (Get-GissueGitRepoPaths $workdir)) {
        $branch = (git -C $repo rev-parse --abbrev-ref HEAD 2>$null)
        if (-not $branch) { continue }
        $base = Get-RepoBaseBranch $repo
        if ($branch -ne $base) { return [pscustomobject]@{ Repo = $repo; Branch = $branch; Base = $base } }
    }
    return $null
}

# ── 유휴 신호 2 구현: repo-lock.ps1 락이 살아있는지 ──
# repo-lock.ps1 의 Test-LockStale 과 동일 판정(프로세스 생존 + 나이).
function Get-LiveRepoLock {
    if (-not (Test-Path -LiteralPath $LockDir)) { return $null }
    foreach ($f in @(Get-ChildItem -LiteralPath $LockDir -Filter '*.lock' -File -ErrorAction SilentlyContinue)) {
        $lock = $null
        try { $lock = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $lock -or -not $lock.pid) { continue }
        $alive = $false
        try { $null = Get-Process -Id $lock.pid -ErrorAction Stop; $alive = $true } catch { $alive = $false }
        if (-not $alive) { continue }
        try {
            $age = (Get-Date).ToUniversalTime() - [datetime]::Parse($lock.startedAt).ToUniversalTime()
            if ($age.TotalMinutes -ge $LockStaleMinutes) { continue }
        } catch { continue }
        return $lock
    }
    return $null
}

# ── 상태 파일(연속 보류 카운터) ──
function Read-RestartState {
    if (-not (Test-Path $StateFile)) { return [pscustomobject]@{ pendingCommit = ''; holdCount = 0; lastHoldAt = ''; lastRestartAt = ''; lastRestartCommit = '' } }
    try { return Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return [pscustomobject]@{ pendingCommit = ''; holdCount = 0; lastHoldAt = ''; lastRestartAt = ''; lastRestartCommit = '' } }
}
function Write-RestartState($state) {
    if ($DryRun) { return }
    $state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

try {
    if (-not (Test-Path $SlackBotDir)) {
        Write-RestartLog "[SKIP] 감시 대상 디렉터리 없음: $SlackBotDir (-WatchPath)"
        exit 0
    }

    # ── 1. 배포 커밋 변경 감지 ──
    $currentCommit = (git -C $RepoRoot log -1 --format=%H -- $WatchPath 2>$null)
    if (-not $currentCommit) {
        Write-RestartLog "[SKIP] '$WatchPath' 경로의 커밋을 조회하지 못함(git 오류?) — 이번 실행 건너뜀"
        exit 0
    }
    $currentCommit = $currentCommit.Trim()

    # 정보성: origin/main 쪽 최신 커밋(네트워크 fetch 하지 않음, 기존 remote-tracking ref 만 읽음)
    $originCommit = (git -C $RepoRoot log -1 --format=%H origin/main -- $WatchPath 2>$null)
    if ($originCommit) { $originCommit = $originCommit.Trim() }
    if ($originCommit -and $originCommit -ne $currentCommit) {
        Write-RestartLog "[INFO] origin/main 의 '$WatchPath' 커밋($($originCommit.Substring(0,8)))이 로컬 워킹트리($($currentCommit.Substring(0,8)))와 다름 — 로컬 반영(pull)은 이 스크립트 소관 아님(:07 스케줄러/세션이 수행)"
    }

    if (-not (Test-Path $MarkerFile)) {
        if (-not $DryRun) { $currentCommit | Set-Content -Path $MarkerFile -Encoding UTF8 }
        Write-RestartLog "[INIT] 마커 파일 최초 생성 — 현재 배포 커밋 $($currentCommit.Substring(0,8)) 기록만 하고 재시작하지 않음"
        exit 0
    }

    $deployedCommit = (Get-Content $MarkerFile -Raw -Encoding UTF8).Trim()
    $state = Read-RestartState

    if ($deployedCommit -eq $currentCommit) {
        if ($state.holdCount -ne 0 -or $state.pendingCommit -ne '') {
            $state.pendingCommit = ''
            $state.holdCount = 0
            Write-RestartState $state
        }
        Write-RestartLog "OK: 재시작 불필요(실행 중 커밋 = 워킹트리 커밋 $($currentCommit.Substring(0,8)))"
        exit 0
    }

    Write-RestartLog "[DETECT] '$WatchPath' 배포 커밋 변경: 실행 중 $($deployedCommit.Substring(0,8)) -> 워킹트리 $($currentCommit.Substring(0,8)) — 유휴 판정 시작"

    # pendingCommit 이 바뀌면 연속 보류 카운터를 초기화한다(다른 배포 건이므로).
    if ($state.pendingCommit -ne $currentCommit) {
        $state.pendingCommit = $currentCommit
        $state.holdCount = 0
    }

    function Invoke-Hold($reason) {
        $state.holdCount = [int]$state.holdCount + 1
        $state.lastHoldAt = (Get-Date).ToUniversalTime().ToString('o')
        Write-RestartState $state
        Write-RestartLog "[HOLD] 재시작 보류($($state.holdCount)회 연속) — $reason / 다음 실행에서 재시도"
        if ([int]$state.holdCount -ge $HoldWarnThreshold) {
            Write-RestartLog "[ALERT] 연속 보류 $($state.holdCount)회(기준 $HoldWarnThreshold) — '$ProcessName' 이 $($currentCommit.Substring(0,8)) 코드로 계속 미반영 상태다. 사람 확인 필요(강제 재시작은 하지 않음 — giip #2148 설계 §3)."
        }
    }

    # ── 2. pm2 상태 확인 ──
    # 주의: pm2 jlist(JSON)는 이 머신에서 pm2_env.env 중복 키 때문에 ConvertFrom-Json 이 깨진다
    # (run-gissue-claude.ps1 Phase 0.5 주석의 2026-08-05 실측). describe 텍스트를 정규식으로 읽는다.
    $describeOut = $null
    try { $describeOut = pm2 describe $ProcessName 2>$null } catch { $describeOut = $null }
    $statusLine = $describeOut | Where-Object { $_ -match '│\s*status\s*│\s*(\S+)\s*│' } | Select-Object -First 1
    if (-not $statusLine) {
        Invoke-Hold "pm2 프로세스 목록에 '$ProcessName' 없음 또는 pm2 조회 실패(신규 기동은 :07 스케줄러 Phase 0.5 워치독 소관)"
        exit 0
    }
    $status = 'unknown'
    if ($statusLine -match '│\s*status\s*│\s*(\S+)\s*│') { $status = $Matches[1] }
    if ($status -ne 'online') {
        Invoke-Hold "pm2 status=$status (online 아님) — 비정상 상태 복구는 :07 워치독 소관"
        exit 0
    }

    # ── 3. 유휴 신호 1: busy repo(bot/task-* 체크아웃) ──
    $busy = Get-GissueBusyRepo $RepoRoot
    if ($busy) {
        Invoke-Hold "유휴신호1 실패 — 레포 점유 중: $($busy.Repo) 가 base '$($busy.Base)' 아닌 '$($busy.Branch)' 브랜치"
        exit 0
    }

    # ── 4. 유휴 신호 2: repo-lock 보유 ──
    $lock = Get-LiveRepoLock
    if ($lock) {
        Invoke-Hold "유휴신호2 실패 — repo-lock 보유 중: holder=$($lock.holder), purpose=$($lock.purpose), pid=$($lock.pid)"
        exit 0
    }

    # ── 5. 유휴 신호 3: pm2 로그 staleness ──
    $outLogPath = Join-Path $HOME (".pm2\logs\$ProcessName-out.log")
    $errLogPath = Join-Path $HOME (".pm2\logs\$ProcessName-error.log")
    $outAgeMin = if (Test-Path $outLogPath) { [int]((Get-Date) - (Get-Item $outLogPath).LastWriteTime).TotalMinutes } else { [int]::MaxValue }
    $errAgeMin = if (Test-Path $errLogPath) { [int]((Get-Date) - (Get-Item $errLogPath).LastWriteTime).TotalMinutes } else { [int]::MaxValue }
    $quietMin = [Math]::Min($outAgeMin, $errAgeMin)
    if ($quietMin -lt $QuietMinutes) {
        Invoke-Hold "유휴신호3 실패 — pm2 로그 최근 활동 ${quietMin}분 전(기준 ${QuietMinutes}분 이상 조용해야 함)"
        exit 0
    }

    # ── 6. 3신호 모두 통과 → 재시작 ──
    Write-RestartLog "[IDLE-OK] 유휴 3신호 통과(점유 레포 없음 / repo-lock 없음 / pm2 로그 ${quietMin}분 무활동) — pm2 restart $ProcessName 실행"
    if ($DryRun) {
        Write-RestartLog "[DRYRUN] 실제 pm2 restart 와 마커 갱신은 생략했다(검증 모드)."
        exit 0
    }

    pm2 restart $ProcessName 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $afterOut = $null
    try { $afterOut = pm2 describe $ProcessName 2>$null } catch { $afterOut = $null }
    $afterLine = $afterOut | Where-Object { $_ -match '│\s*status\s*│\s*(\S+)\s*│' } | Select-Object -First 1
    $afterStatus = 'unknown'
    if ($afterLine -and ($afterLine -match '│\s*status\s*│\s*(\S+)\s*│')) { $afterStatus = $Matches[1] }

    if ($afterStatus -eq 'online') {
        $currentCommit | Set-Content -Path $MarkerFile -Encoding UTF8
        $state.pendingCommit = ''
        $state.holdCount = 0
        $state.lastRestartAt = (Get-Date).ToUniversalTime().ToString('o')
        $state.lastRestartCommit = $currentCommit
        Write-RestartState $state
        Write-RestartLog "[RESTARTED] 재시작 완료 — 배포 커밋 마커를 $($currentCommit.Substring(0,8)) 로 갱신(status=online)"
    } else {
        # 마커를 갱신하지 않는다 — 다음 실행에서 다시 시도하게 둔다.
        Write-RestartLog "[WARN] pm2 restart 후 status=$afterStatus (online 아님) — 마커 미갱신, 다음 실행에서 재시도"
    }
    exit 0
} catch {
    Write-RestartLog "[ERROR] 체크 실패: $($_.Exception.Message)"
    exit 1
}
