# run-audit-review-prs.ps1 — "REVIEW 인데 PR 0" 감사(audit-review-prs.mjs)의 스케줄러 래퍼
# Windows Task Scheduler `GIIP_AuditReviewPrs_Hourly`(매시 :07)에서 실행한다.
#
# 원본: lowyworkenv `scripts/gissue/run-audit-review-prs.ps1` (giip #2395/#2431).
# 이 레포로의 이식은 giip #2645.
#
# ── 하는 일 ────────────────────────────────────────────────────────────────────
#   1) `node audit-review-prs.mjs --csn <n> --json` 실행
#   2) 결과 JSON 을 `audit-results/audit-review-prs-csn<n>-<stamp>.json` 으로 보존
#   3) 요약(reviewed / suspects)을 `audit-results/audit-review-prs-csn<n>.log` 에 기록
#
# ── 원본의 3단계(DB 적재)를 이 레포에서 수행하지 않는 이유 (지우지 않고 남기는 기록) ──
#   [용도] 원본은 감사 결과를 giipdb 테이블 `tAuditReviewPrsResult` 에 INSERT 했다.
#   [처리] `giipdb/mgmt/execSQLFile.ps1` + `dbconfig.json` 으로 SQL 파일을 실행(500행 배치 INSERT).
#   [저장처] giipdb 의 `tAuditReviewPrsResult`
#           (컬럼: csn, isn, title, branch, pr_repo, pr_number, pr_state, pr_url, checked_at, has_pr).
#   [소비처] giip 대시보드의 "REVIEW인데 PR 없음" 배지 / 감사 리포트.
#   [왜 여기선 안 하나] `giip-fde-agent` 에는 DB 직접접속 수단(`dbconfig.json`, `execSQLFile.ps1`,
#           `Invoke-Sqlcmd` 자격증명)이 **존재하지 않는다**. 정본 문서
#           `docs/60-operations/hourly-issue-scheduler.md` §4 는 없는 경로를 참조하는 "혼용 이식"을
#           금지한다 — 참조하면 매 실행이 그 단계에서 조용히 실패한다.
#   [언제부터] giip #2645(2026-09-17) 이식 시점부터. 그 이전에 이 레포에 이 파일이 있던 적은 없다.
#   [대체] DB 적재가 필요한 배포(lowyworkenv, csn 47)에는 원본 러너가 그대로 남아 있어 계속 적재한다.
#           이 레포 배포에서는 JSON 파일이 정본 산출물이다. 나중에 API 적재 엔드포인트가 생기면
#           아래 `-NoDb` 분기 자리에 붙이면 된다.
#
# ⚠ 종료코드 규약 — `audit-review-prs.mjs` 는 **의심 건이 있으면 1** 을 돌려준다(정상 동작이며 실패가
#   아니다). 2 이상만 실제 실패다. 이 구분을 놓치면 "ERROR: node exit code 1" 로그만 쌓인다(실측 이력).
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-audit-review-prs.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-audit-review-prs.ps1 -Csn 47
param(
    # 감사 대상 CSN. 0 이면 giip-accounts.json 에 등록된 전체 CSN(감사 스크립트 기본 동작).
    [int]$Csn = 0,
    # 원본과의 인터페이스 호환을 위해 남겨 둔 스위치. 이 레포에는 DB 적재 단계 자체가 없으므로
    # 지정 여부와 무관하게 동작은 같다(위 "원본의 3단계" 기록 참고).
    [switch]$NoDb
)
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ResultDir = Join-Path $ScriptDir 'audit-results'
if (-not (Test-Path $ResultDir)) { New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }

$LogFile = Join-Path $ResultDir "audit-review-prs-csn${Csn}.log"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-RunLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Output $line
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

Write-RunLog "Starting audit-review-prs for csn=$Csn"

$mjs = Join-Path $ScriptDir 'audit-review-prs.mjs'
if (-not (Test-Path -LiteralPath $mjs -PathType Leaf)) {
    # 감사 본체는 같은 이슈(giip #2645)의 별도 작업으로 이 레포에 들어온다. 없으면 여기서 멈춘다 —
    # 조용히 성공으로 넘기면 "돌고 있는데 아무것도 안 하는" 상태가 된다(giip #2431 의 함정).
    Write-RunLog "SKIP: 감사 본체가 아직 이 레포에 없습니다: $mjs"
    exit 0
}

$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) {
    Write-RunLog 'ERROR: node 실행파일을 찾을 수 없습니다(PATH 확인)'
    exit 1
}

# --- 1) 감사 실행 ------------------------------------------------------------------------------
$nodeArgs = @($mjs, '--json')
if ($Csn -gt 0) { $nodeArgs += @('--csn', "$Csn") }

# ⚠ 인코딩 — `& node ...` 로 그냥 받으면 안 된다(실측, giip #2431):
#   PowerShell 은 네이티브 프로세스 stdout 을 [Console]::OutputEncoding 으로 디코딩한다. 콘솔이 붙은
#   대화형 실행에서는 어쩌다 통과하지만, **작업 스케줄러가 콘솔 없이 실행하면 cp932(shift_jis)로
#   디코딩**돼 한글 title 이 mojibake 가 되고 ConvertFrom-Json 이
#   "Invalid object passed in, ':' or '}' expected. (256)" 로 죽는다.
#   그래서 StandardOutputEncoding 을 UTF-8 로 명시한 Process 로 직접 띄운다.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $nodeExe
$psi.Arguments              = (($nodeArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
$psi.WorkingDirectory       = $ScriptDir
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.StandardOutputEncoding = $utf8NoBom
$psi.StandardErrorEncoding  = $utf8NoBom

$proc = [System.Diagnostics.Process]::Start($psi)
# stderr 는 비동기로 받아 파이프 버퍼 교착을 피한다(stdout 이 수십 KB 라 동기 2중 ReadToEnd 는 위험).
$errTask  = $proc.StandardError.ReadToEndAsync()
$jsonText = $proc.StandardOutput.ReadToEnd()
$proc.WaitForExit()
$rc       = $proc.ExitCode
$stderr   = $errTask.Result

# rc: 0 = 의심 0건, 1 = 의심 있음(정상), 2+ = 실패
if ($rc -ge 2 -or [string]::IsNullOrWhiteSpace($jsonText)) {
    Write-RunLog "ERROR: node exit code $rc (의심건 유무와 무관한 실제 실패)"
    if ($stderr) {
        $e = ($stderr -replace '\s+', ' ').Trim()
        if ($e.Length -gt 500) { $e = $e.Substring(0, 500) + ' …(생략)' }
        Write-RunLog "STDERR: $e"
    }
    exit 1
}

try {
    $report = $jsonText | ConvertFrom-Json
} catch {
    # 예외 메시지에 입력 JSON 전체가 실려 로그가 수백 줄로 부풀 수 있어 잘라 기록한다.
    $msg = ($_.Exception.Message -replace '\s+', ' ').Trim()
    if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + ' …(생략)' }
    Write-RunLog "ERROR: JSON 파싱 실패 — $msg"
    exit 1
}

# --- 2) JSON 보존 ------------------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonFile = Join-Path $ResultDir ("audit-review-prs-csn{0}-{1}.json" -f $Csn, $stamp)
[System.IO.File]::WriteAllText($jsonFile, $jsonText, $utf8NoBom)

# ⚠ PS5.1: ConvertFrom-Json 은 빈 배열을 $null 로, 1건 배열을 단일 객체로 돌려준다. $null 을 걸러야
#   빈 목록이 1건으로 세어지지 않는다(실측 사고 이력).
$suspects = @(@($report.suspects) | Where-Object { $null -ne $_ })
$okList   = @(@($report.ok)       | Where-Object { $null -ne $_ })
Write-RunLog "audit done: reviewed=$($okList.Count + $suspects.Count), suspects=$($suspects.Count), json=$jsonFile"
Write-RunLog "SUCCESS: saved JSON (이 레포 배포는 DB 적재를 하지 않는다 — 파일 상단 '원본의 3단계' 참고)"
exit 0
