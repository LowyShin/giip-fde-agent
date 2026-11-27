# test-checklist-judge-stderr.ps1 — 의뢰 체크리스트 판정의 claude CLI 호출 회귀 테스트
#
# 왜 필요한가:
#   판정 호출(Invoke-GissueJudge)이 `$prompt | & claude ... 2>&1` 형태로 네이티브 CLI 를 부르는데,
#   호출자 스코프의 $ErrorActionPreference='Stop' (pr-gate-sweep.ps1:121 / review-done-audit.ps1:94)
#   아래에서 PS 5.1 은 **자식 stderr 한 줄**을 NativeCommandError(ErrorRecord) 로 감싸 종료성 오류로
#   만든다. 실측: claude CLI 는 "⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or
#   another auth source is set..." 을 stderr 에 찍는다(gair 경로에서는 항상 ANTHROPIC_API_KEY 가
#   설정되므로 항상 발생) → 판정이 exit=-1 / ok=$false / HOLD 로 죽었다.
#   같은 자리에 다른 결함도 있었다 — (D2) gair 라우터는 --model 을 honor 하지 않아 응답이
#   **에이전트 마크업**이라 ITEM| 파싱 0건 → HOLD, (D3) 무한 대기(실측 9분+ 무응답).
#
# 이 테스트가 고정하는 것:
#   (1) 자식이 stderr 에 쓰고 exit 0 -> 판정 **성공**. (D1 회귀 — 종전엔 exit=-1 로 죽었다)
#   (2) 자식이 stderr 에 쓰고 exit 1 -> 판정 **실패**(ok=$false). 예외로 죽지 않는다.
#   (3) 실패 사유에 실제 종료코드·경로·stderr 요약이 들어간다. (과거엔 "exit=<n>" 뿐이었다)
#   (4) 유한 대기 — 멈춘 자식은 한도 안에 잘리고 **실패**로 처리된다(타임아웃을 성공으로 보지 않는다).
#   (5) 프롬프트가 자식의 stdin 으로 전달된다 (한글까지 바이트 그대로 — 개행/깨짐 없음).
#   (6) gair 응답 형식 불일치(ITEM| 0건) -> 직접 경로로 1회 폴백하고, 폴백 응답을 쓴다.
#   (7) 폴백까지 0건이면 HOLD 유지 — 실패를 성공으로 뒤집지 않는다.
#
# LLM/네트워크 미사용 · 환경 비의존 · 가짜 CLI 스텁 사용
#   판정 호출이 실제로 실행하는 claude CLI 를 임시 디렉터리의 **가짜 .cmd** 로 대체한다
#   (env GISSUE_CLAUDE_EXE). 모델·계정·네트워크가 전혀 개입하지 않고, 결정론적으로 돈다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-checklist-judge-stderr.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 종전 결함의 재현 조건 — 호출자 스코프가 EAP='Stop' 인 상태로 돈다.
$ErrorActionPreference = 'Stop'

$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'gissue-audit-lib.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

# ─────────────────────────────────────────────────────────────────────────────────
# 가짜 CLI 스텁 — 실제로 실행되는 claude 대신 이 .cmd 가 자식 프로세스가 된다.
# FAKE_CLAUDE_MODE 로 동작을 바꾼다(ok/fail/hang/markup/nomarkup/stdin).
#   markup    : gair(BASE_URL 있음)일 때만 에이전트 마크업, 아니면 정상 ITEM| 줄.
#   nomarkup  : 언제나 에이전트 마크업(ITEM| 0건) — 폴백까지 실패하는 경로 검증용.
#   stdin     : stdin 을 **바이트 그대로** stdout 으로 복사한다(인코딩 변환 없음).
# FAKE_CLAUDE_LOG 로 호출 1회마다 (mode|ANTHROPIC_BASE_URL) 을 남긴다 — 폴백 여부를 세는 데 쓴다.
# ─────────────────────────────────────────────────────────────────────────────────
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue-judge-stderr-test-$PID")
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$fakeCli = Join-Path $tempRoot 'fake-claude.cmd'
$fakeBody = @'
@echo off
setlocal enabledelayedexpansion
set "MODE=%FAKE_CLAUDE_MODE%"
set "LOG=%FAKE_CLAUDE_LOG%"
if defined LOG echo %MODE%^|%ANTHROPIC_BASE_URL%>>"%LOG%"
if "%MODE%"=="hang" goto hang
if "%MODE%"=="fail" goto fail
if "%MODE%"=="markup" goto markup
if "%MODE%"=="nomarkup" goto nomarkup
if "%MODE%"=="stdin" goto stdin
goto ok
:hang
ping -n 30 127.0.0.1 >nul
exit /b 0
:fail
echo fake-stderr-error: judgment call failed 1>&2
exit /b 1
:markup
if not "%ANTHROPIC_BASE_URL%"=="" goto markup_gair
goto ok
:nomarkup
:markup_gair
echo {"type":"tool_call","name":"Bash","input":{"command":"ls"}}
echo fake-stderr-warning: gair agent markup 1>&2
exit /b 0
:stdin
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b=[Console]::OpenStandardInput();$ms=New-Object System.IO.MemoryStream;$b.CopyTo($ms);$a=$ms.ToArray();[Console]::OpenStandardOutput().Write($a,0,$a.Length)"
exit /b 0
:ok
echo ITEM^|other^|MET^|fake item^|ok
echo fake-stderr-warning: claude.ai connectors are disabled 1>&2
exit /b 0
'@
[System.IO.File]::WriteAllText($fakeCli, ($fakeBody -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding $false))
$callLog = Join-Path $tempRoot 'calls.log'

# gair 계획 스텁 — 활성/비활성을 전환한다(활성일 때 판정 호출이 gair 경로로 env 를 심는다).
$script:FakeGairActive = $true
function Get-GissueJudgeGairPlan {
    if ($script:FakeGairActive) {
        return @{ Active = $true; Required = $false; Csn = '33'; BaseUrl = 'https://fake-gair.invalid/api/gair'; Ak = 'sk-fake-ak-000000'; CustomHeaders = '' }
    }
    return @{ Active = $false; Required = $false; Csn = '33'; BaseUrl = ''; Ak = ''; CustomHeaders = '' }
}

$script:savedExe = $env:GISSUE_CLAUDE_EXE
$script:savedMode = $env:FAKE_CLAUDE_MODE
$script:savedLog = $env:FAKE_CLAUDE_LOG
$script:savedTimeout = $env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC
$env:GISSUE_CLAUDE_EXE = $fakeCli
$env:FAKE_CLAUDE_LOG = $callLog
$env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC = '30'

$prNone = @{ Known = $true; HasMerged = $false; HasAny = $false }

try {
    # ── (1) stderr + exit 0 -> 판정 성공 (D1 회귀) ─────────────────────────────
    Write-Host '== (1) 자식 stderr + exit 0 -> 판정 성공 =='
    $script:FakeGairActive = $false
    $env:FAKE_CLAUDE_MODE = 'ok'
    $j = $null
    $threw = $false
    try { $j = Invoke-GissueJudge "STDIN-MARKER-1`n둘째 줄" } catch { $threw = $true; Write-Host "    예외: $($_.Exception.Message)" }
    Assert (-not $threw) 'stderr 를 쓴 자식(종료 0)이 예외를 던지지 않는다(종전: NativeCommandError 로 죽었다)'
    Assert ($j -and $j.ok) '판정 성공(ok=$true) — stderr 출력만으로는 실패가 아니다'
    Assert ($j -and $j.exit -eq 0) '종료 코드가 그대로 보고된다(exit=0)'
    Assert ($j -and $j.route) "경로 표기가 있다(route=$($j.route))"
    Assert ($j -and ("$($j.text)".Contains('ITEM|other|MET|'))) '판정 본문은 stdout 에서 온다'
    Assert ($j -and -not ("$($j.text)".Contains('fake-stderr-warning'))) 'stderr 는 판정 본문에 섞이지 않는다'
    Assert ($j -and ("$($j.stderr)".Contains('fake-stderr-warning'))) 'stderr 는 진단용으로 따로 담긴다'

    # ── (2) stderr + exit 1 -> 판정 실패, 예외 아님 ───────────────────────────
    Write-Host '== (2) 자식 stderr + exit 1 -> 판정 실패(예외 아님) =='
    $env:FAKE_CLAUDE_MODE = 'fail'
    $j2 = $null
    $threw2 = $false
    try { $j2 = Invoke-GissueJudge '프롬프트' } catch { $threw2 = $true; Write-Host "    예외: $($_.Exception.Message)" }
    Assert (-not $threw2) '종료 1 인 자식도 예외로 죽지 않는다'
    Assert ($j2 -and -not $j2.ok) '판정 실패(ok=$false) — 실패를 성공으로 뒤집지 않는다'
    Assert ($j2 -and $j2.exit -eq 1) '실제 종료 코드가 1 로 보고된다'

    # ── (3) 실패 사유에 종료코드·경로·stderr 요약 ─────────────────────────────
    Write-Host '== (3) 실패 사유에 종료코드·경로·stderr 요약 =='
    $a = Invoke-ChecklistAssessment 1 'content' @() $prNone
    Assert (-not $a.Ok -and $a.Decision -eq 'HOLD') '판정 실패 -> HOLD (전이가 없다)'
    Assert ("$($a.Reason)".Contains('exit=1')) '사유에 실제 종료 코드가 있다'
    Assert ("$($a.Reason)".Contains('route=')) '사유에 경로가 있다'
    Assert ("$($a.Reason)".Contains('fake-stderr-error')) '사유에 stderr 요약이 있다'

    # ── (4) 유한 대기 — 멈춘 자식은 실패로 처리된다 ───────────────────────────
    Write-Host '== (4) 멈춘 자식(무한 대기) -> 유한 대기 후 실패 =='
    $env:FAKE_CLAUDE_MODE = 'hang'
    $env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC = '3'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $j3 = $null
    $threw3 = $false
    try { $j3 = Invoke-GissueJudge '프롬프트' } catch { $threw3 = $true }
    $sw.Stop()
    Assert (-not $threw3) '멈춘 자식도 예외로 죽지 않는다'
    Assert ($j3 -and -not $j3.ok) '타임아웃은 실패다(성공으로 보지 않는다)'
    Assert ($j3 -and $j3.timedout) '타임아웃이 표면화된다(timedout)'
    Assert ($sw.Elapsed.TotalSeconds -lt 25) ("무한 대기가 아니다(측정 {0:N1}초)" -f $sw.Elapsed.TotalSeconds)
    $a3 = Invoke-ChecklistAssessment 1 'content' @() $prNone
    Assert ("$($a3.Reason)".Contains('timedout=1')) '실패 사유에 timedout=1 이 남는다'
    $env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC = '30'

    # ── (5) 프롬프트가 stdin 으로 전달된다(한글까지 바이트 그대로) ─────────────
    Write-Host '== (5) 프롬프트가 자식 stdin 으로 전달된다 =='
    $env:FAKE_CLAUDE_MODE = 'stdin'
    $j4 = Invoke-GissueJudge "STDIN-MARKER-9999`n둘째 줄 한글"
    Assert ($j4 -and $j4.ok) 'stdin 으로 받은 프롬프트를 자식이 그대로 되읽었다'
    Assert ($j4 -and ("$($j4.text)".Contains('STDIN-MARKER-9999'))) 'ASCII 마커가 그대로 전달된다'
    Assert ($j4 -and ("$($j4.text)".Contains('둘째 줄 한글'))) '한글이 깨지지 않고 그대로 전달된다(UTF-8 BOM 없음)'

    # ── (6) gair 응답 형식 불일치 -> 직접 경로 1회 폴백 ──────────────────────────
    Write-Host '== (6) gair 형식 불일치(ITEM| 0건) -> 직접 경로 1회 폴백 =='
    $script:FakeGairActive = $true
    $env:FAKE_CLAUDE_MODE = 'markup'
    if (Test-Path -LiteralPath $callLog) { Remove-Item -LiteralPath $callLog -Force }
    $a5 = Invoke-ChecklistAssessment 1 'content' @() $prNone
    Assert ($a5.Ok -and $a5.Decision -eq 'KEEP') 'gair 0건 -> 직접 경로 폴백 응답으로 판정 성공'
    $logLines = @()
    if (Test-Path -LiteralPath $callLog) { $logLines = @(Get-Content -LiteralPath $callLog) }
    Assert ($logLines.Count -eq 2) ("폴백은 정확히 1회다(호출 {0}회)" -f $logLines.Count)
    Assert ($logLines.Count -ge 1 -and $logLines[0] -like 'markup|*fake-gair.invalid*') '1차 호출은 gair 경로다(BASE_URL 이 심어졌다)'
    Assert ($logLines.Count -ge 2 -and $logLines[1] -like 'markup|*') '2차 호출은 직접 경로다(BASE_URL 이 비었다)'

    # ── (7) 폴백까지 0건이면 HOLD 유지(성공으로 뒤집지 않는다) ─────────────────
    Write-Host '== (7) 폴백도 0건이면 HOLD 유지 =='
    $env:FAKE_CLAUDE_MODE = 'nomarkup'
    if (Test-Path -LiteralPath $callLog) { Remove-Item -LiteralPath $callLog -Force }
    $a7 = Invoke-ChecklistAssessment 1 'content' @() $prNone
    Assert (-not $a7.Ok -and $a7.Decision -eq 'HOLD') '폴백 후에도 ITEM| 0건 -> HOLD (근거 없이 되돌리지 않는다)'
    Assert ("$($a7.Reason)".Contains('gair-fallback-direct')) '사유에 폴백 경로 표기가 있다'
} finally {
    if ($null -eq $script:savedExe) { Remove-Item Env:GISSUE_CLAUDE_EXE -ErrorAction SilentlyContinue } else { $env:GISSUE_CLAUDE_EXE = $script:savedExe }
    if ($null -eq $script:savedMode) { Remove-Item Env:FAKE_CLAUDE_MODE -ErrorAction SilentlyContinue } else { $env:FAKE_CLAUDE_MODE = $script:savedMode }
    if ($null -eq $script:savedLog) { Remove-Item Env:FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue } else { $env:FAKE_CLAUDE_LOG = $script:savedLog }
    if ($null -eq $script:savedTimeout) { Remove-Item Env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC -ErrorAction SilentlyContinue } else { $env:GISSUE_CLAUDE_CALL_TIMEOUT_SEC = $script:savedTimeout }
    if (Test-Path -LiteralPath $tempRoot) { try { Remove-Item -LiteralPath $tempRoot -Recurse -Force -Confirm:$false } catch {} }
}

if ($fail -gt 0) { Write-Host "`n$fail 건 실패" -ForegroundColor Red; exit 1 }
Write-Host "`n전체 통과"
exit 0
