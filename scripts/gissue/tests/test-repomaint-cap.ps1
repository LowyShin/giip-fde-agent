# [giip 4431 항목 2] REPO-MAINT(저장소 정비) 세션 시간 캡 검증.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-repomaint-cap.ps1
# 네트워크/파일 쓰기 없음. lib/capped-wait.ps1 의 순수 함수(가짜 IsRunning/Wait 포트)와, 러너 소스의
# 배선(캡 상수·내부 Start-Job 래핑·캡 초과 시 Stop-Job 후 이슈 순회 진행)이 맞는지 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/capped-wait.ps1')).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

# 가짜 잡 상태: runningPolls 만큼의 Wait 사이클 동안 running 이다가 멈춘다. Wait 호출 수도 센다.
$script:runningPolls = 0
$script:waitCalls = 0
$ports = @{
    IsRunning = { $script:runningPolls -gt 0 }
    Wait      = { param($sec) $script:runningPolls--; $script:waitCalls++ }
}

# ── (A) 캡 안에서 완료: 2 폴링 뒤 끝나면 TimedOut=false ──
$script:runningPolls = 2; $script:waitCalls = 0
$resA = Invoke-GissueCappedJobWait 40 10 $ports
Check 'A1 캡 내 완료 → TimedOut=false' (-not $resA.TimedOut) "TimedOut=$($resA.TimedOut)"
Check 'A2 실제 센 대기 20분(폴링 2회)' ($resA.ElapsedMin -eq 20 -and $script:waitCalls -eq 2) "Elapsed=$($resA.ElapsedMin) waitCalls=$($script:waitCalls)"

# ── (B) 캡 초과: 계속 running 이면 캡(20분)까지만 대기하고 TimedOut=true ──
$script:runningPolls = 999; $script:waitCalls = 0
$resB = Invoke-GissueCappedJobWait 20 10 $ports
Check 'B1 캡 초과 → TimedOut=true' ($resB.TimedOut) "TimedOut=$($resB.TimedOut)"
Check 'B2 캡(20분)까지만 대기(폴링 2회)' ($resB.ElapsedMin -eq 20 -and $script:waitCalls -eq 2) "Elapsed=$($resB.ElapsedMin) waitCalls=$($script:waitCalls)"

# ── (C) 즉시 완료(한 번도 running 아님): 대기 0, TimedOut=false ──
$script:runningPolls = 0; $script:waitCalls = 0
$resC = Invoke-GissueCappedJobWait 20 10 $ports
Check 'C1 즉시 완료 → TimedOut=false, 대기 0회' ((-not $resC.TimedOut) -and $resC.ElapsedMin -eq 0 -and $script:waitCalls -eq 0) "Elapsed=$($resC.ElapsedMin) waitCalls=$($script:waitCalls)"

# ── (D) PollMin 0/음수 방어: 1분으로 보정해 무한루프 안 돈다 ──
$script:runningPolls = 1; $script:waitCalls = 0
$resD = Invoke-GissueCappedJobWait 3 0 $ports
Check 'D1 PollMin 0 → 1분 보정, 유한 종료' ($script:waitCalls -ge 1 -and $resD.ElapsedMin -ge 1) "Elapsed=$($resD.ElapsedMin) waitCalls=$($script:waitCalls)"

# ── (E) 러너 소스 배선 점검 ──
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
Check 'E1 캡 상수 $RepoMaintDeadlineMin 가 있고 기본 20분' ($src -match '(?m)^\$RepoMaintDeadlineMin\s*=.*20') ''
Check 'E2 잡 스코프에서 lib/capped-wait.ps1 를 소싱한다' ($src -match "lib/capped-wait\.ps1") ''
Check 'E3 정비 세션 엔진 호출을 내부 Start-Job(repoMaintJob)으로 감싼다' ($src -match '\$repoMaintJob\s*=\s*Start-Job') ''
Check 'E4 캡 판정에 Invoke-GissueCappedJobWait 를 쓴다' ($src -match 'Invoke-GissueCappedJobWait\s+\$repoMaintDeadlineMin') ''
Check 'E5 캡 초과 시 Stop-Job 으로 정리한다' ($src -match '\$repoMaintWait\.TimedOut' -and $src -match 'Stop-Job \$repoMaintJob') ''
# 잡 param 목록(camelCase $repoMaintDeadlineMin)으로 받고, ArgumentList(PascalCase $RepoMaintDeadlineMin)로
# 넘긴다. -cmatch 로 대소문자를 구분해 둘 다 존재하는지 본다.
Check 'E6 잡 param 목록이 camelCase $repoMaintDeadlineMin 를 받는다' ($src -cmatch '\$repoMaintDeadlineMin\)') ''
Check 'E7 PascalCase 상수/인자 $RepoMaintDeadlineMin 가 소스에 있다' ($src -cmatch '\$RepoMaintDeadlineMin') ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
