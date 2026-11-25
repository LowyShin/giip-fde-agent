# 잡 InitializationScript 에서 gissue-audit-lib.ps1 을 닷소싱해도 잡이 시작 단계에서 죽지 않는지 검증.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-job-init-audit-lib-guard.ps1
# 배경: 최상위 적재 가드가 Get-Command <없는 명령> -ErrorAction SilentlyContinue 로 존재를 확인하면,
#   없는 명령의 오류가 $Error 에 남고 잡 인프라가 시작 스크립트 오류로 잡 전체를 State=Failed 로 만든다
#   (실측: "Running startup script threw an error"). 존재 검사는 Test-Path function: 으로 해야 한다.
# 기대 PASS(A1·C1)와 기대 FAIL(F1, 구 패턴의 실패를 재현하는 음성 대조군)을 둘 다 넣는다.
$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
$auditLib = Join-Path $gissueDir 'gissue-audit-lib.ps1'

$fail = 0; $count = 0
function Check($name, [bool]$ok, $detail) {
    $script:count++
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

function Invoke-JobInitProbe($initText, $jobText) {
    $init = [scriptblock]::Create($initText)
    $jb = [scriptblock]::Create($jobText)
    $job = Start-Job -InitializationScript $init -ScriptBlock $jb
    try {
        $null = Wait-Job $job -Timeout 60
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = @(Receive-Job $job -ErrorAction SilentlyContinue) } finally { $ErrorActionPreference = $prevEap }
        return @{ State = "$($job.State)"; Out = $out; Reason = "$($job.ChildJobs[0].JobStateInfo.Reason.Message)" }
    } finally {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

# A1: audit-lib 을 잡 init 에서 닷소싱하면 잡이 시작되고 가드 대상 함수(lib/gair-gate.ps1)가 잡 안에 적재된다.
$auditInit = ". '" + ($auditLib -replace "'", "''") + "'"
$r = Invoke-JobInitProbe $auditInit "if (Test-Path function:\Test-GissueGairCsnAllowed) { 'FN-DEFINED' } else { 'FN-MISSING' }"
Check 'A1 잡 init 에서 audit-lib 닷소싱 후 잡이 완료되고 판정 함수가 적재된다' (($r.State -eq 'Completed') -and ($r.Out -contains 'FN-DEFINED')) ("State=$($r.State) Out=[$($r.Out -join ',')] Reason=$($r.Reason)")

# F1 [기대 FAIL — 음성 대조군]: 구 패턴(Get-Command 존재 확인)이 잡 init 에 있으면 잡이 시작 단계에서 죽는다.
#   이 단언이 실패하면(구 패턴 잡이 살아남으면) 이 테스트는 구 가드를 검출하지 못한다는 뜻이라 테스트 자체가 무용하다.
$oldInit = "if (-not (Get-Command NoSuchFnForInitGuardTest -ErrorAction SilentlyContinue)) { Write-Output 'guard-ok' }"
$r2 = Invoke-JobInitProbe $oldInit "'JOB-RAN'"
Check 'F1 [기대 FAIL] 구 Get-Command 가드가 잡 init 에 있으면 잡이 "Running startup script threw an error" 로 실패한다' (($r2.State -eq 'Failed') -and ($r2.Reason -match 'Running startup script threw an error')) ("State=$($r2.State) Reason=$($r2.Reason)")

# C1: audit-lib 최상위(첫 function 정의 앞)의 코드 줄에 Get-Command 존재 확인이 없다 — 소스 수준 재발 방지.
#   주석 줄은 제외한다(설명문에 이름이 나와도 코드가 아니다).
$src = Get-Content -LiteralPath $auditLib -Encoding UTF8
$firstFn = -1
for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i] -match '^function ') { $firstFn = $i; break } }
$topLines = if ($firstFn -ge 0) { $src[0..($firstFn - 1)] } else { $src }
$codeHits = @($topLines | Where-Object { ($_.Trim() -notmatch '^#') -and ($_ -match 'Get-Command') })
Check 'C1 audit-lib 최상위 코드 줄에 Get-Command 존재 확인이 없다' ($codeHits.Count -eq 0) ("hits=$($codeHits.Count)")

Write-Output "TOTAL: $count checks, $fail failed"
if ($fail -gt 0) { exit 1 }
