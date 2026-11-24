# gair 허용 목록 게이트 + 게이트 판정 gair 경유 계획 검증.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gair-gate.ps1
# 네트워크 없음 — 허용 목록 해석(lib/gair-gate.ps1 순수 함수)과 판정 계획
# (gissue-audit-lib.ps1 Get-GissueJudgeGairPlan, AK 해석은 가짜 포트 주입)을 검증하고,
# 러너·감사 라이브러리의 배선(공통 게이트 사용)을 소스 점검으로 확인한다.
$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'lib/gair-gate.ps1')

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

$prevCsns = $env:GISSUE_GAIR_CSNS; $prevGair = $env:GISSUE_GAIR; $prevFk = $env:GAIR_FUNCTION_KEY
try {
    # ── A. 허용 목록 해석 ────────────────────────────────────────────────────
    Remove-Item Env:GISSUE_GAIR_CSNS -ErrorAction SilentlyContinue
    $listDefault = @(Get-GissueGairCsnList)
    Check 'A1 env 미설정 시 기본 목록은 플랫폼 CSN 1개' ($listDefault.Count -eq 1 -and $listDefault[0] -eq '47') "count=$($listDefault.Count)"
    Check 'A2 env 미설정 시 기본 CSN 허용' (Test-GissueGairCsnAllowed -Csn '47') ''
    Check 'A3 env 미설정 시 임의 CSN 차단' (-not (Test-GissueGairCsnAllowed -Csn '99999')) ''
    $env:GISSUE_GAIR_CSNS = '47, 12345'
    Check 'A4 목록 안 CSN 허용(공백 무시)' (Test-GissueGairCsnAllowed -Csn '12345') ''
    Check 'A5 목록 밖 CSN 차단' (-not (Test-GissueGairCsnAllowed -Csn '99999')) ''
    $env:GISSUE_GAIR_CSNS = '*'
    Check 'A6 * 면 임의 CSN 허용' (Test-GissueGairCsnAllowed -Csn '99999') ''
    Check 'A7 * 면 기본 CSN 도 허용' (Test-GissueGairCsnAllowed -Csn '47') ''
    $env:GISSUE_GAIR_CSNS = '47,*'
    Check 'A8 목록에 * 가 섞여 있어도 전 CSN 허용' (Test-GissueGairCsnAllowed -Csn '99999') ''
    # $env: 에 빈 문자열을 대입하면 변수 자체가 지워져 "미설정"과 같아지므로(PowerShell 동작),
    #   빈 목록의 의미는 -Raw '' 명시로 검증한다.
    $emptyList = @(Get-GissueGairCsnList -Raw '')
    Check 'A9 빈 목록이면 아무 CSN 도 허용 안 함' ($emptyList.Count -eq 0 -and -not (Test-GissueGairCsnAllowed -Csn '47' -List $emptyList)) ''
    Check 'A10 -Raw 명시값이 env 보다 우선' (Test-GissueGairCsnAllowed -Csn '99999' -List @(Get-GissueGairCsnList -Raw '*')) ''

    # ── B. 판정 계획 (AK 해석은 가짜 포트) ───────────────────────────────────
    . (Join-Path $gissueDir 'gissue-audit-lib.ps1')
    $env:GISSUE_GAIR_CSNS = '*'
    $script:Csn = 12345
    $env:GISSUE_GAIR = '0'
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B1 GISSUE_GAIR=0 이면 필수가 아니다(긴급 차단 유지)' (-not $p.Required -and -not $p.Active) ''
    Remove-Item Env:GISSUE_GAIR -ErrorAction SilentlyContinue
    $script:Csn = 0
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B2 CSN 미특정이면 계획 없음(종전 직접 호출)' (-not $p.Required -and -not $p.Active) ''
    $script:Csn = 12345
    $env:GISSUE_GAIR_CSNS = '47'
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B3 허용 목록 밖 CSN 은 필수가 아니다' (-not $p.Required -and -not $p.Active) ''
    $env:GISSUE_GAIR_CSNS = '*'
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B4 * 허용 + AK 파생 성공이면 Active' ($p.Required -and $p.Active -and $p.Csn -eq '12345') ''
    Check 'B5 Active 계획은 gair 베이스 URL 을 쓴다' ($p.BaseUrl -match '/api/gair$') ''
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) '' }
    Check 'B6 허용 CSN + AK 실패면 Required 인 채로 비활성(직접 폴백 금지 상태)' ($p.Required -and -not $p.Active) ''
    $env:GAIR_FUNCTION_KEY = 'fk-dummy'
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B7 GAIR_FUNCTION_KEY 가 있으면 커스텀 헤더에 실린다' ($p.CustomHeaders -like 'x-functions-key:*') ''
    Remove-Item Env:GAIR_FUNCTION_KEY -ErrorAction SilentlyContinue
    $p = Get-GissueJudgeGairPlan -AkResolver { param($c) 'ak-dummy' }
    Check 'B8 함수 키가 없으면 헤더를 싣지 않는다' (-not $p.CustomHeaders) ''

    # ── C. 소스 배선 점검 ────────────────────────────────────────────────────
    $runnerSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'run-gissue-claude.ps1') -Raw -Encoding UTF8
    Check 'C1 러너가 gair-gate 라이브러리를 적재한다' ($runnerSrc -match 'lib/gair-gate\.ps1') ''
    Check 'C2 러너 게이트가 Test-GissueGairCsnAllowed 로 판정한다' ($runnerSrc -match 'Test-GissueGairCsnAllowed -Csn') ''
    Check 'C3 러너에 종전 인라인 목록 해석이 남아 있지 않다' ($runnerSrc -notmatch '\$gairCsnListRaw') ''
    $auditSrc = Get-Content -LiteralPath (Join-Path $gissueDir 'gissue-audit-lib.ps1') -Raw -Encoding UTF8
    Check 'C4 감사 라이브러리에 판정 계획 함수가 있다' ($auditSrc -match 'function Get-GissueJudgeGairPlan') ''
    Check 'C5 판정이 gair 경유 로그를 남긴다' ($auditSrc -match '\[GAIR\] 판정 gair 경유') ''

    # ── D. 판정 함수 레벨: 필수인데 AK 를 못 구하면 직접 호출로 새지 않는다 ──
    # 가짜 CSN 이라 get-ak.sh 가 계정을 찾지 못해 AK 파생이 실패하는 것이 확정적이다
    # (계정 파일에 없는 CSN 은 네트워크 호출 전에 실패한다).
    $script:Csn = 12345
    $env:GISSUE_GAIR_CSNS = '*'
    Remove-Item Env:GISSUE_GAIR -ErrorAction SilentlyContinue
    $j = Invoke-GissueJudge '판정 테스트 프롬프트'
    Check 'D1 gair 필수 + AK 파생 불가면 ok=false 로 표면화' (-not $j.ok) ''
    Check 'D2 직접 폴백이 아니라 gair-blocked(exit=-2)다' ($j.exit -eq -2 -and $j.route -eq 'gair-blocked') ''
} finally {
    if ($null -eq $prevCsns) { Remove-Item Env:GISSUE_GAIR_CSNS -ErrorAction SilentlyContinue } else { $env:GISSUE_GAIR_CSNS = $prevCsns }
    if ($null -eq $prevGair) { Remove-Item Env:GISSUE_GAIR -ErrorAction SilentlyContinue } else { $env:GISSUE_GAIR = $prevGair }
    if ($null -eq $prevFk) { Remove-Item Env:GAIR_FUNCTION_KEY -ErrorAction SilentlyContinue } else { $env:GAIR_FUNCTION_KEY = $prevFk }
}

if ($fail -gt 0) { Write-Output "FAILED: $fail 건"; exit 1 }
Write-Output 'ALL PASS'
exit 0
