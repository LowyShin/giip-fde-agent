# soft-budget.ps1 - gissue 러너 "소프트 예산" 판정 순수 함수 (giip 3615)
#
# 배경: 러너의 하드 타임아웃($RunTimeoutMin=105분)은 "잡을 죽이는 시간"이다. 큐가 빌 때까지 이슈를 계속 집는 구조라
#   한 번의 실행이 92~101분 동안 CSN 락을 쥐고, 그동안 20분 틱(:07/:27/:47)은 전부 "SKIP: 실행 중"으로 버려진다.
#   소프트 예산은 "새 이슈를 시작해도 되는 시간"만 따로 정한다. 넘으면 새 이슈 세션을 시작하지 않고 루프를 빠져나가며,
#   이미 시작한 이슈 세션은 끝까지 마친다(중간에 죽이면 IN_PROGRESS 가 남고 60분 뒤에야 회수된다).
#
# 설정(기본 비활성 = 기존 동작 유지):
#   1) csn-projects.json 최상위 선택 키 softBudgetMin (분, 0 이하/생략 = 해당 단계 없음)
#   2) 환경변수 GISSUE_SOFT_BUDGET_MIN (docker entrypoint 가 20분 cron 에서 기본값 15 를 넣는다)
#   우선순위는 1) > 2) 이다. 이미지 재빌드 없이 csn-projects.json 만 고쳐 entrypoint 기본값을 덮어쓰거나(0 이면 끔)
#   끌 수 있어야 하기 때문이다.
#
# 이 파일은 순수 함수만 둔다(파일/네트워크 접근 없음) - tests/test-soft-budget.ps1 이 직접 불러 검증한다.

# 값을 0 이상의 정수 분으로 바꾼다. 비어 있거나 숫자가 아니거나 음수면 $null(=지정 없음).
function ConvertTo-GissueSoftBudgetMin($Value) {
    if ($null -eq $Value) { return $null }
    $text = "$Value".Trim()
    if (-not $text) { return $null }
    $d = 0.0
    if (-not [double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $null }
    if ($d -lt 0) { return $null }
    return [int][math]::Floor($d)
}

# 설정 우선순위 적용: csn-projects.json 값 > 환경변수 > 0(비활성). 반환은 항상 0 이상의 정수 분.
function Resolve-GissueSoftBudgetMin($ConfigValue, $EnvValue) {
    $fromConfig = ConvertTo-GissueSoftBudgetMin $ConfigValue
    if ($null -ne $fromConfig) { return $fromConfig }
    $fromEnv = ConvertTo-GissueSoftBudgetMin $EnvValue
    if ($null -ne $fromEnv) { return $fromEnv }
    return 0
}

# 새 이슈를 시작해도 되는가.
#   - SoftBudgetMin <= 0 : 비활성, 항상 $true (기존 동작과 동일)
#   - StartedCount -eq 0 : 이번 실행에서 아직 한 건도 시작하지 않았으면 항상 $true.
#       저장소 정비 세션이 예산을 다 써 버려도 실행이 "0건 처리"로 끝나는 기아를 막는다(최소 1건 보장).
#   - 그 외 : 경과(분)가 예산 미만일 때만 $true
# 이미 시작한 이슈 세션은 이 함수로 끊지 않는다 - 호출부는 "이슈를 시작하기 직전"에만 부른다.
function Test-GissueSoftBudgetAllowsNewIssue([int]$SoftBudgetMin, [double]$ElapsedMin, [int]$StartedCount) {
    if ($SoftBudgetMin -le 0) { return $true }
    if ($StartedCount -le 0) { return $true }
    return ($ElapsedMin -lt $SoftBudgetMin)
}

# 로그용 설정 한 줄.
function Format-GissueSoftBudgetSetting([int]$SoftBudgetMin, [int]$HardTimeoutMin) {
    if ($SoftBudgetMin -le 0) { return "비활성(기존 동작: 큐가 빌 때까지, 하드 타임아웃 ${HardTimeoutMin}분)" }
    return "${SoftBudgetMin}분(넘으면 새 이슈 미착수, 진행 중 이슈는 끝까지, 하드 타임아웃 ${HardTimeoutMin}분 유지)"
}
