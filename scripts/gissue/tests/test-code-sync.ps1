# test-code-sync.ps1 — 자동 반영(자기 갱신) 로직 회귀 테스트 (giip #6214)
#
# 왜 필요한가:
#   러너 기동 초입에 넣은 자동 반영이 "조용히 실패하면" 사람이 알아채는 방법이 없다 — 실행은 계속되고
#   只是 옛 코드로 돈다(그래서 §11 의 운영 함정이 영영 닫히지 않는다). 그래서 다음을 **네트워크 없이**
#   로컬 git 저장소로 검증한다:
#     A. 상태 조회 — 저장소 아님 / 커밋 있는 저장소 / 로컬 변경 있음
#     B. 동기화 — 이미 최신 / 원격 반영(fast-forward) / 로컬 변경이라 보류 / main 이 아닌 브랜치라 보류
#                / 원격 확인 생략 / 대상 없음
#     C. 스크립트 디렉터리 동기화 — 트랙 파일만 복사, 로컬 전용 파일은 삭제되지 않는다
#     D. 러너 소스 배치 — 자동 반영이 "정리 엔진 닷소싱"과 "낡은 코드 가드 스냅샷"보다 **앞**에 있고,
#        회귀 테스트 진입점(-FunctionsOnly)에서는 실행되지 않는다.
#
# 네트워크는 쓰지 않는다. "원격"은 로컬 경로의 bare 저장소로 대체한다 — fetch/merge 는 그대로 돈다.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-code-sync.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# terminating 오류가 나면 **즉시 실패**해야 한다 — 'Continue' 로 두면 중간에 죽은 뒤에도
# "ALL PASS" 가 찍히는 **빈 통과(false pass)** 가 생긴다(실측: Set-Content 파라미터 오류가 그랬다).
# git 호출 구간은 아래 Invoke-Git 헬퍼가 EAP 를 'Continue' 로 임시 낮춘다(Windows PS 5.1 의
# native stderr terminating 함정 회피).
$ErrorActionPreference = 'Stop'

$gissueDir = Split-Path -Parent $PSScriptRoot
$libFile   = Join-Path $gissueDir 'lib/code-sync.ps1'
$runnerFile = Join-Path $gissueDir 'run-gissue-claude.ps1'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}

. $libFile

# ── git 헬퍼 ──────────────────────────────────────────────────────────────────────
function Invoke-Git { param([string]$RepoPath, [string[]]$GitArgs)
    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = (& git -C $RepoPath @GitArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }
    return [pscustomobject]@{ Exit = $code; Text = $out }
}

# 브랜치 이름이 환경에 따라 master/main 으로 갈리지 않도록 **항상 main** 으로 고정한다.
function New-GitRepo([string]$Path, [switch]$Bare) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    if ($Bare) { $null = Invoke-Git $Path @('init', '--bare', '-q') }
    else {
        $null = Invoke-Git $Path @('init', '-q')
        $null = Invoke-Git $Path @('symbolic-ref', 'HEAD', 'refs/heads/main')
        $null = Invoke-Git $Path @('config', 'user.email', 'test@example.com')
        $null = Invoke-Git $Path @('config', 'user.name', 'test')
        $null = Invoke-Git $Path @('config', 'commit.gpgsign', 'false')
    }
}

function New-Commit([string]$Path, [string]$RelFile, [string]$Content, [string]$Message) {
    $full = Join-Path $Path $RelFile
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $full -Value $Content -Encoding UTF8
    $null = Invoke-Git $Path @('add', '--', $RelFile)
    $null = Invoke-Git $Path @('commit', '-q', '-m', $Message)
}

# ── 임시 트리 ────────────────────────────────────────────────────────────────────
$tmpRoot = [System.IO.Path]::GetTempPath()
$tmp = Join-Path $tmpRoot ("gissue-code-sync-test-" + $PID)
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }

try {
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $originPath = Join-Path $tmp 'origin.git'
    $workPath   = Join-Path $tmp 'work'
    $execPath   = Join-Path $tmp 'exec'
    $plainPath  = Join-Path $tmp 'plain'

    New-GitRepo -Path $originPath -Bare
    New-GitRepo -Path $workPath
    New-Item -ItemType Directory -Path $execPath -Force | Out-Null
    New-Item -ItemType Directory -Path $plainPath -Force | Out-Null

    # work 저장소: 첫 커밋 + 원격 연결 + push
    New-Commit -Path $workPath -RelFile 'scripts/gissue/demo.ps1' -Content 'v1' -Message 'init'
    $null = Invoke-Git $workPath @('remote', 'add', 'origin', $originPath)
    $null = Invoke-Git $workPath @('push', '-q', '-u', 'origin', 'main')

    # ── A. 상태 조회 ───────────────────────────────────────────────────────────────
    $info = Get-GissueRepoHeadInfo -RepoRoot $workPath
    Assert-True ($info.IsRepo -eq $true) 'A-1 커밋 있는 저장소 → IsRepo=true' "IsRepo=$($info.IsRepo)"
    Assert-True ($info.Sha -match '^[0-9a-f]{40}$') 'A-2 HEAD SHA 40자 hex' "Sha=$($info.Sha)"
    Assert-True ($info.ShortSha.Length -eq 7) 'A-3 짧은 SHA 7자' "ShortSha=$($info.ShortSha)"
    Assert-True ($info.Branch -eq 'main') 'A-4 브랜치 main' "Branch=$($info.Branch)"
    Assert-True ($info.Dirty -eq $false) 'A-5 깨끗한 저장소 → Dirty=false' "Dirty=$($info.Dirty)"

    $plainInfo = Get-GissueRepoHeadInfo -RepoRoot $plainPath
    Assert-True ($plainInfo.IsRepo -eq $false) 'A-6 저장소가 아닌 디렉터리 → IsRepo=false' "IsRepo=$($plainInfo.IsRepo)"
    Assert-True ($plainInfo.Sha -eq '') 'A-7 저장소가 아니면 Sha 비어 있음' "Sha=$($plainInfo.Sha)"

    $noneInfo = Get-GissueRepoHeadInfo -RepoRoot ''
    Assert-True ($noneInfo.IsRepo -eq $false) 'A-8 빈 경로 → IsRepo=false(예외 없음)' ''

    # 로컬 변경(추적 파일 수정) → Dirty=true
    Set-Content -LiteralPath (Join-Path $workPath 'scripts/gissue/demo.ps1') -Value 'v2-local' -Encoding UTF8
    $dirtyInfo = Get-GissueRepoHeadInfo -RepoRoot $workPath
    Assert-True ($dirtyInfo.Dirty -eq $true) 'A-9 로컬 변경 있음 → Dirty=true' "Dirty=$($dirtyInfo.Dirty) count=$($dirtyInfo.DirtyCount)"
    $null = Invoke-Git $workPath @('checkout', '--', 'scripts/gissue/demo.ps1')
    $cleanInfo = Get-GissueRepoHeadInfo -RepoRoot $workPath
    Assert-True ($cleanInfo.Dirty -eq $false) 'A-10 변경 되돌리면 Dirty=false' "Dirty=$($cleanInfo.Dirty)"

    # untracked 파일(로그 디렉터리·운영자가 채운 로컬 설정 등)은 "사람의 작업"이 아니다.
    # 이것까지 변경으로 보면 pull 이 영영 보류되어 자동 반영이 아예 동작하지 않게 된다.
    Set-Content -LiteralPath (Join-Path $workPath 'scripts/gissue/local-only.json') -Value '{"local":true}' -Encoding UTF8
    $untrackedInfo = Get-GissueRepoHeadInfo -RepoRoot $workPath
    Assert-True ($untrackedInfo.Dirty -eq $false) 'A-11 untracked 파일만 있으면 Dirty=false(pull 을 막지 않는다)' "Dirty=$($untrackedInfo.Dirty) count=$($untrackedInfo.DirtyCount)"
    Remove-Item -LiteralPath (Join-Path $workPath 'scripts/gissue/local-only.json') -Force

    # ── B. 동기화 ─────────────────────────────────────────────────────────────────
    # B-1 이미 최신
    $res1 = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($res1.Status -eq 'already-current') 'B-1 원격과 같으면 already-current' "Status=$($res1.Status) reason=$($res1.Reason)"
    Assert-True ($res1.ShaBefore -eq $res1.ShaAfter) 'B-2 already-current 면 전후 HEAD 동일' "before=$($res1.ShaBefore) after=$($res1.ShaAfter)"

    # B-3 로컬 변경이 있으면 pull 하지 않는다(사람의 작업 보존)
    Set-Content -LiteralPath (Join-Path $workPath 'scripts/gissue/demo.ps1') -Value 'v2-local' -Encoding UTF8
    $resDirty = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($resDirty.Status -eq 'skipped-dirty') 'B-3 로컬 변경 있으면 skipped-dirty' "Status=$($resDirty.Status)"
    Assert-True ($resDirty.ShaBefore -eq $resDirty.ShaAfter) 'B-4 skipped-dirty 면 HEAD 불변' "before=$($resDirty.ShaBefore) after=$($resDirty.ShaAfter)"
    $null = Invoke-Git $workPath @('checkout', '--', 'scripts/gissue/demo.ps1')

    # B-5 원격이 앞서 있으면 fast-forward 로 반영된다
    $otherPath = Join-Path $tmp 'other'
    New-GitRepo -Path $otherPath
    $null = Invoke-Git $otherPath @('remote', 'add', 'origin', $originPath)
    $null = Invoke-Git $otherPath @('fetch', '-q', 'origin', 'main')
    $null = Invoke-Git $otherPath @('checkout', '-q', '-B', 'main', 'origin/main')
    New-Commit -Path $otherPath -RelFile 'scripts/gissue/demo.ps1' -Content 'v2-remote' -Message 'remote change'
    $null = Invoke-Git $otherPath @('push', '-q', 'origin', 'main')
    $resUpd = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($resUpd.Status -eq 'updated') 'B-5 원격 앞섬 → updated' "Status=$($resUpd.Status) reason=$($resUpd.Reason)"
    Assert-True ($resUpd.ShaAfter -ne $resUpd.ShaBefore) 'B-6 updated 면 전후 HEAD 다름' "before=$($resUpd.ShaBefore) after=$($resUpd.ShaAfter)"
    Assert-True ($resUpd.ShaAfter -match '^[0-9a-f]{40}$') 'B-7 갱신 후 SHA 40자 hex' "Sha=$($resUpd.ShaAfter)"
    $afterContent = Get-Content -LiteralPath (Join-Path $workPath 'scripts/gissue/demo.ps1') -Raw
    Assert-True ($afterContent -match 'v2-remote') 'B-8 실제 파일 내용이 원격 버전으로 갱신됨' "내용=$afterContent"

    # B-9 갱신 후 다시 돌리면 already-current
    $res2 = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($res2.Status -eq 'already-current') 'B-9 반영 후 재실행 → already-current' "Status=$($res2.Status)"

    # B-10 main 이 아닌 브랜치면 pull 하지 않는다
    $null = Invoke-Git $workPath @('checkout', '-q', '-b', 'feature/x')
    $resBranch = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($resBranch.Status -eq 'skipped-not-main') 'B-10 main 아닌 브랜치 → skipped-not-main' "Status=$($resBranch.Status)"
    $null = Invoke-Git $workPath @('checkout', '-q', 'main')

    # B-11 원격 확인 생략
    $resNoRemote = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath -NoRemote
    Assert-True ($resNoRemote.Status -eq 'skipped-no-remote') 'B-11 -NoRemote → skipped-no-remote' "Status=$($resNoRemote.Status)"

    # B-12 대상이 아예 없음 / 저장소가 아님
    $resNone = Sync-GissueAgentRepo -RepoRoot '' -ExecRoot $execPath
    Assert-True ($resNone.Status -eq 'skipped-no-target') 'B-12 대상 없음 → skipped-no-target' "Status=$($resNone.Status)"
    $resNotRepo = Sync-GissueAgentRepo -RepoRoot $plainPath -ExecRoot $execPath
    Assert-True ($resNotRepo.Status -eq 'skipped-not-repo') 'B-13 저장소 아님 → skipped-not-repo' "Status=$($resNotRepo.Status)"

    # B-14 untracked 파일(로컬 설정·로그)만 있는 상태에서도 pull 이 막히지 않는다
    Set-Content -LiteralPath (Join-Path $workPath 'scripts/gissue/local-only.json') -Value '{"local":true}' -Encoding UTF8
    $resUntracked = Sync-GissueAgentRepo -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($resUntracked.Status -ne 'skipped-dirty') 'B-14 untracked 파일만 있으면 skipped-dirty 가 아니다(자동 반영이 막히지 않는다)' "Status=$($resUntracked.Status) reason=$($resUntracked.Reason)"
    Remove-Item -LiteralPath (Join-Path $workPath 'scripts/gissue/local-only.json') -Force

    # ── C. 스크립트 디렉터리 동기화 ────────────────────────────────────────────────
    $tracked = @(Get-GissueTrackedFiles -RepoRoot $workPath -RelDir 'scripts/gissue')
    Assert-True ($tracked -contains 'scripts/gissue/demo.ps1') 'C-1 트랙 파일 목록에 demo.ps1 있음' "목록=$($tracked -join ',')"

    # 실행 위치에 로컬 전용 파일(운영자가 채운 설정)을 둔다 — 동기화가 지우면 안 된다.
    $localCfg = Join-Path $execPath 'csn-projects.json'
    Set-Content -LiteralPath $localCfg -Value '{"local":true}' -Encoding UTF8
    # 실행 위치의 demo.ps1 을 오래된 내용으로 만든다 → 갱신 대상이 되어야 한다.
    Set-Content -LiteralPath (Join-Path $execPath 'demo.ps1') -Value 'OLD' -Encoding UTF8

    $copy = Sync-GissueScriptDir -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($copy.Copied -ge 1) 'C-2 내용이 다른 트랙 파일은 복사된다' "Copied=$($copy.Copied) Skipped=$($copy.Skipped) Failed=$($copy.Failed)"
    $copiedText = Get-Content -LiteralPath (Join-Path $execPath 'demo.ps1') -Raw
    Assert-True ($copiedText -match 'v2-remote') 'C-3 복사된 내용은 체크아웃 최신본' "내용=$copiedText"
    Assert-True (Test-Path -LiteralPath $localCfg) 'C-4 실행 위치의 로컬 전용 파일은 삭제되지 않는다' ''
    $localCfgText = Get-Content -LiteralPath $localCfg -Raw
    Assert-True ($localCfgText -match 'local') 'C-5 로컬 전용 파일 내용도 보존된다' "내용=$localCfgText"

    # 두 번째 동기화 → 같으므로 건너뛴다(불필요한 쓰기 방지)
    $copy2 = Sync-GissueScriptDir -RepoRoot $workPath -ExecRoot $execPath
    Assert-True ($copy2.Copied -eq 0) 'C-6 이미 같으면 재복사하지 않는다' "Copied=$($copy2.Copied) Skipped=$($copy2.Skipped)"

    # ── D. 요약 문자열 ────────────────────────────────────────────────────────────
    $sum = Format-GissueCodeSyncSummary -Sync $resUpd
    Assert-True ($sum -match 'updated') 'D-1 요약에 상태가 들어간다' "요약=$sum"
    Assert-True ($sum -match $resUpd.ShaAfter.Substring(0,7)) 'D-2 요약에 반영 후 HEAD(7자)가 들어간다' "요약=$sum"
    $sumNull = Format-GissueCodeSyncSummary -Sync $null
    Assert-True ($sumNull -eq '없음') 'D-3 동기화 결과가 없으면 "없음"' "요약=$sumNull"

    # D-4 사유가 길어도 요약은 제한된다 — 실행 기록의 500자 제한에 다른 항목(기록 호출 실패)이
    #     밀려나지 않게 한다.
    $longReasonSync = [pscustomobject]@{
        Status = 'failed'; ShaBefore = ('a' * 40); ShaAfter = ('b' * 40)
        Reason = ('z' * 500)
    }
    $sumLong = Format-GissueCodeSyncSummary -Sync $longReasonSync
    Assert-True ($sumLong.Length -le 200) 'D-4 긴 사가는 요약에서 잘린다' "길이=$($sumLong.Length)"
    Assert-True ($sumLong -match 'z') 'D-5 잘리기 전 사유 내용은 남아 있다' "요약=$($sumLong.Substring(0, [Math]::Min(60, $sumLong.Length)))"

    # ── E. 대상 체크아웃 해석 ─────────────────────────────────────────────────────
    $prevEnv = $env:GIIP_FDE_REPO_ROOT
    try {
        $env:GIIP_FDE_REPO_ROOT = $workPath
        $resolved = Resolve-GissueSyncRepoRoot -RunnerRepoRoot $plainPath
        Assert-True ($resolved -eq $workPath) 'E-1 환경변수가 정본 체크아웃을 지정한다' "resolved=$resolved"
        $env:GIIP_FDE_REPO_ROOT = $plainPath
        $resolvedBad = Resolve-GissueSyncRepoRoot -RunnerRepoRoot $workPath
        Assert-True ($null -eq $resolvedBad) 'E-2 환경변수가 체크아웃이 아니면 null(사유는 호출부가 남긴다)' "resolved=$resolvedBad"
        $env:GIIP_FDE_REPO_ROOT = ''
        $resolvedSelf = Resolve-GissueSyncRepoRoot -RunnerRepoRoot $workPath
        Assert-True ($resolvedSelf -eq $workPath) 'E-3 환경변수 없으면 러너 자신의 저장소를 쓴다' "resolved=$resolvedSelf"
        $resolvedNone = Resolve-GissueSyncRepoRoot -RunnerRepoRoot $plainPath
        Assert-True ($null -eq $resolvedNone) 'E-4 어디에도 체크아웃이 없으면 null' "resolved=$resolvedNone"
    } finally {
        $env:GIIP_FDE_REPO_ROOT = $prevEnv
    }

    # ── F. 러너 소스 배치(순서 계약) ──────────────────────────────────────────────
    $src = Get-Content -LiteralPath $runnerFile -Raw -Encoding UTF8
    $posSync = $src.IndexOf('Sync-GissueAgentRepo -RepoRoot')
    $posWs   = $src.IndexOf('. $WorktreeSafetyLib')
    $posFresh = $src.IndexOf('Initialize-GissueCodeFreshness -RepoRoot')
    Assert-True ($posSync -gt 0) 'F-1 러너가 자동 반영을 호출한다' "pos=$posSync"
    Assert-True ($posWs -gt 0 -and $posSync -lt $posWs) 'F-2 자동 반영이 정리 엔진 닷소싱보다 앞이다(새 코드가 메모리에 적재된다)' "sync=$posSync ws=$posWs"
    Assert-True ($posFresh -gt 0 -and $posSync -lt $posFresh) 'F-3 자동 반영이 낡은 코드 가드 스냅샷보다 앞이다(가드 오탐 방지)' "sync=$posSync fresh=$posFresh"
    Assert-True ($src -match 'if \(-not \$FunctionsOnly -and \$script:GissueCodeSyncLibReady\)') 'F-4 회귀 테스트 진입점(-FunctionsOnly)에서는 자동 반영을 건너뛴다' ''
    Assert-True ($src -match 'Format-GissueRunEndSummary -Status \$status -CodeVersion \$codeVersion') 'F-5 RunEnd summary 에 코드 버전이 들어간다' ''
    Assert-True ($src -match '-EnginePath \$engineSummary -SyncInfo \$syncSummary -RecordFailures \$recordFailures') 'F-6 RunEnd summary 에 엔진 경로·자동 반영·기록 실패가 들어간다' ''
    Assert-True ($src -match 'Add-GissueEnginePathMarker -Marker \$r\.EnginePath') 'F-7 잡 출력의 엔진 경로 마커를 집계한다' ''
    Assert-True ($src -match 'Get-GissueSchedulerStateFailures -Lines') 'F-8 기록 호출 실패를 추출한다' ''
    # heartbeat 처리 건수는 실제 처리 건수(큐 인덱스 $qi 가 아니다)
    Assert-True ($src -notmatch 'Record-SchedulerState -Action heartbeat[^\r\n]*-Processed \$qi') 'F-9 heartbeat 처리 건수가 큐 인덱스($qi)가 아니다' ''
    Assert-True ($src -match 'Record-SchedulerState -Action heartbeat[^\r\n]*-Processed \$runProcessed') 'F-10 heartbeat 처리 건수는 $runProcessed 다' ''
}
finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:Fail -gt 0) { Write-Output "FAILED: $($script:Fail) 건"; exit 1 }
Write-Output "ALL PASS ($($script:Pass) 건)"
exit 0
