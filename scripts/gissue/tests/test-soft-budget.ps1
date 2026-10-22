# [giip 3615] 소프트 예산 판정 단위 테스트
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-soft-budget.ps1
# 네트워크/파일 쓰기 없음. lib/soft-budget.ps1 의 순수 함수와, 러너 소스에서 판정 위치가 맞는지만 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/soft-budget.ps1')).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

# (a) 비활성이면 기존과 동일: 얼마나 지났든 항상 시작
Check 'a1 예산 0 = 비활성, 경과 999분이어도 시작' (Test-GissueSoftBudgetAllowsNewIssue 0 999 10) ''
Check 'a2 예산 음수 = 비활성' (Test-GissueSoftBudgetAllowsNewIssue -5 999 10) ''
Check 'a3 설정 없음 -> Resolve 는 0' ((Resolve-GissueSoftBudgetMin $null $null) -eq 0) "반환: $(Resolve-GissueSoftBudgetMin $null $null)"

# (b) 예산 전이면 시작
Check 'b1 15분 예산, 경과 0분 시작' (Test-GissueSoftBudgetAllowsNewIssue 15 0 3) ''
Check 'b2 15분 예산, 경과 14.9분 시작' (Test-GissueSoftBudgetAllowsNewIssue 15 14.9 3) ''

# (c) 예산 후면 새 이슈 시작 안 함
Check 'c1 15분 예산, 경과 15분 미착수' (-not (Test-GissueSoftBudgetAllowsNewIssue 15 15 3)) ''
Check 'c2 15분 예산, 경과 90분 미착수' (-not (Test-GissueSoftBudgetAllowsNewIssue 15 90 3)) ''

# 최소 1건 보장: 저장소 정비가 예산을 다 써도 첫 이슈는 시작한다(0건 처리 기아 방지)
Check 'c3 예산 초과여도 아직 0건 시작이면 첫 이슈는 시작' (Test-GissueSoftBudgetAllowsNewIssue 15 40 0) ''
Check 'c4 1건 시작한 뒤에는 예산 초과 시 미착수' (-not (Test-GissueSoftBudgetAllowsNewIssue 15 40 1)) ''

# (d) 진행 중 이슈는 끝까지: 판정은 이슈 "시작 직전"에만 호출된다. 루프를 흉내 내서 확인한다.
#     이슈 1건이 소프트 예산(15분)을 넘겨 20분 걸려도 그 이슈는 끝까지 처리되고, 그 다음 이슈부터 미착수여야 한다.
$queue = 1..5
$clock = 0.0       # 실행 시작 후 경과(분)
$started = 0
$completed = @()
$stopAt = $null
foreach ($i in $queue) {
    if (-not (Test-GissueSoftBudgetAllowsNewIssue 15 $clock $started)) { $stopAt = $i; break }
    $started++
    $clock += if ($i -eq 2) { 20 } else { 4 }   # 2번 이슈가 예산을 가로질러 오래 걸린다
    $completed += $i                              # 시작한 이슈는 중단 없이 완료된다
}
Check 'd1 예산을 가로지른 2번 이슈도 끝까지 완료' ($completed -contains 2) "완료: $($completed -join ',')"
Check 'd2 그 다음(3번)부터 미착수' ($stopAt -eq 3) "중단 지점: $stopAt"
Check 'd3 완료 목록은 1,2 뿐' (($completed -join ',') -eq '1,2') "완료: $($completed -join ',')"

# 설정 해석: csn-projects.json 값 > 환경변수 > 0
Check 'r1 json 값이 환경변수보다 우선' ((Resolve-GissueSoftBudgetMin 30 '15') -eq 30) ''
Check 'r2 json 0 은 환경변수 기본값을 끈다' ((Resolve-GissueSoftBudgetMin 0 '15') -eq 0) ''
Check 'r3 json 없으면 환경변수 사용' ((Resolve-GissueSoftBudgetMin $null '15') -eq 15) ''
Check 'r4 환경변수가 숫자가 아니면 무시(0)' ((Resolve-GissueSoftBudgetMin $null 'abc') -eq 0) ''
Check 'r5 json 이 숫자가 아니면 환경변수로 폴백' ((Resolve-GissueSoftBudgetMin 'x' '15') -eq 15) ''
Check 'r6 음수는 무시' ((Resolve-GissueSoftBudgetMin -3 $null) -eq 0) ''
Check 'r7 문자열 숫자(json 이 문자열로 적힌 경우)도 허용' ((Resolve-GissueSoftBudgetMin '20' $null) -eq 20) ''
Check 'r8 소수는 내림' ((Resolve-GissueSoftBudgetMin 12.9 $null) -eq 12) ''

# 로그 문구
Check 'l1 비활성 문구' ((Format-GissueSoftBudgetSetting 0 105) -match '비활성') ''
Check 'l2 활성 문구에 분 수와 하드 타임아웃 포함' ((Format-GissueSoftBudgetSetting 15 105) -match '^15분.*105분') ''

# 러너 소스 위치 점검: 판정은 이슈 세션 시작(Start-Job) 앞에 있어야 하고, 하드 타임아웃 값은 105 그대로여야 한다.
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
$posGate = $src.IndexOf('Test-GissueSoftBudgetAllowsNewIssue $softBudgetMin')
$posInner = $src.IndexOf('$innerJob = Start-Job -InitializationScript')
Check 's1 러너에 소프트 예산 판정이 있다' ($posGate -gt 0) ''
Check 's2 판정이 이슈 세션 Start-Job 보다 앞이다' (($posGate -gt 0) -and ($posGate -lt $posInner)) "gate=$posGate inner=$posInner"
Check 's3 하드 타임아웃 105 유지' ($src -match '(?m)^\$RunTimeoutMin = 105\s*$') ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
