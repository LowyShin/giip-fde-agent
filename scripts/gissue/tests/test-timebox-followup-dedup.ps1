# test-timebox-followup-dedup.ps1 — 시간 캡 초과 후속(캐리어오버) 이슈의 "중복 등록 방지" 회귀 테스트 (giip 6679)
#
# 왜 필요한가 (실측, 2026-11-28):
#   시간 캡(40분) 초과로 강제 정리되면 러너는 잔여 작업을 담은 후속(캐리어오버) 이슈를 새로 등록한다.
#   그런데 **같은 원본의 미해결 후속이 이미 있는데도 또 등록**하는 경로가 있었다.
#   실측: isn=5141 에 대해 후속이 5208(11-13) · 6606(11-27) · 6679(11-28) 3건 — 같은 잔여 작업이 증식된다.
#   중복 판정의 키는 제목 안의 "(원본 giip #N)" 표식인데,
#     · 제목 절단(giip #6620)은 PR #584 로 `--title-file` 경유로 이미 수리됐다(표식이 살아남는다),
#     · 그런데 **표식이 살아있는데도 "이미 미해결 후속이 있는지"를 조회하는 코드가 없었다.**
#   → 정본에 순수 판정(lib/timebox-followup.ps1) 을 두고 러너가 등록 전에 호출하도록 배선한다.
#
# 이 테스트가 잡는 것:
#   A. 순수 판정 — 미해결 후속을 찾는가 / 종료 상태는 제외하는가 / 다른 원본·표식 없는 제목은 걸리지 않는가
#   B. 러너 배선 가드 — 판정을 닷소싱하고, 조회(중복 확인)가 등록보다 **앞에** 있는가, 재사용 분기가 있는가,
#      그리고 제목이 파일 경유로 등록되어 표식(=판정 키)이 살아남는가
#   C. 자기 검증 — 위 판정을 "항상 못 찾는다"로 바꾼 돌연변이 구현에 대해 같은 검사가 **FAIL 을 감지**하는가
#      (rule 42: 항상 PASS 하는 검사기는 통과와 구분되지 않는다 — 두 방향을 모두 실증한다)
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-timebox-followup-dedup.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 등록(issueCreate)은 하지 않는다 — 순수 판정 함수와 러너 소스만 검사한다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$LibPs1 = Join-Path $RepoRoot 'scripts\gissue\lib\timebox-followup.ps1'
$RunnerPs1 = Join-Path $RepoRoot 'scripts\gissue\run-gissue-claude.ps1'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Equal($expected, $actual, $name) {
    if ($expected -ceq $actual) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name — expected='$expected' actual='$actual'" }
}

# 판정 결과를 boolean 으로 감싸는 공통 검사기 — C(자기 검증) 에서 돌연변이 구현에도 같은 검사를 쓴다.
function Test-ExistingFollowupFound {
    param($Rows, $OriginIsn, $Finder)
    $found = & $Finder $Rows $OriginIsn
    return ($null -ne $found)
}

try {
    . $LibPs1

    # isn=5141 원본에 대한 실제 후속 3건(실측 저장 제목)과 정상 제목 1건.
    $rows = @(
        [pscustomobject]@{ isn = 5208; title = '[후속] slack-bot 이 소켓은'; status = 'READY' }   # 표식이 잘린 과거 잔재
        [pscustomobject]@{ isn = 6606; title = '[후속] slack-bot 이 소켓은'; status = 'READY' }   # 표식이 잘린 과거 잔재
        [pscustomobject]@{ isn = 6679; title = '[후속] slack-bot 이 소켓은'; status = 'READY' }   # 표식이 잘린 과거 잔재
        [pscustomobject]@{ isn = 6700; title = '[후속] 다른 원본 - 40분 캡 초과 잔여 작업 (원본 giip #9999)'; status = 'READY' }
        [pscustomobject]@{ isn = 6701; title = '[후속] slack-bot 이 "소켓은" - 40분 캡 초과 잔여 작업 (원본 giip #5141)'; status = 'READY' }
        [pscustomobject]@{ isn = 6702; title = '[후속] slack-bot 이 "소켓은" - 40분 캡 초과 잔여 작업 (원본 giip #5141)'; status = 'DONE' }
        [pscustomobject]@{ isn = 6703; title = '[후속] slack-bot 이 "소켓은" - 40분 캡 초과 잔여 작업 (원본 giip #5141)'; status = 'CLOSED' }
    )

    # ────────────────────────────────────────────────────────────────────────────
    # A. 순수 판정
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'A. 순수 판정 (Find-GissueOpenTimeboxFollowup)'

    $found = Find-GissueOpenTimeboxFollowup -Rows $rows -OriginIsn 5141
    Assert-True ($null -ne $found) 'A-1 미해결 후속이 있으면 그 행을 찾는다' "found=$($found)"
    Assert-Equal '6701' "$($found.Isn)" 'A-2 찾은 행이 미해결 후속(READY)이다'

    $foundDone = Find-GissueOpenTimeboxFollowup -Rows @($rows | Where-Object { $_.isn -eq 6702 }) -OriginIsn 5141
    Assert-True ($null -eq $foundDone) 'A-3 종료 상태(DONE)는 미해결이 아니므로 걸리지 않는다'

    $foundClosed = Find-GissueOpenTimeboxFollowup -Rows @($rows | Where-Object { $_.isn -eq 6703 }) -OriginIsn 5141
    Assert-True ($null -eq $foundClosed) 'A-4 종료 상태(CLOSED)도 걸리지 않는다'

    $foundOther = Find-GissueOpenTimeboxFollowup -Rows @($rows | Where-Object { $_.isn -eq 6700 }) -OriginIsn 5141
    Assert-True ($null -eq $foundOther) 'A-5 다른 원본(#9999)의 후속은 걸리지 않는다'

    $foundLegacy = Find-GissueOpenTimeboxFollowup -Rows @($rows | Where-Object { $_.isn -eq 5208 }) -OriginIsn 5141
    Assert-True ($null -eq $foundLegacy) 'A-6 표식이 잘린 제목(과거 잔재)은 찾지 못한다 — 알려진 한계'

    # 구분자 안전: "#5141)" 가 "#51410)" 에 걸리지 않아야 한다(닫는 괄호까지 키에 포함).
    $foundPrefix = Find-GissueOpenTimeboxFollowup -Rows @(
        [pscustomobject]@{ isn = 6710; title = '[후속] x - 40분 캡 초과 잔여 작업 (원본 giip #51410)'; status = 'READY' }
    ) -OriginIsn 5141
    Assert-True ($null -eq $foundPrefix) 'A-7 닫는 괄호가 구분자다 — #51410 은 #5141 로 오인되지 않는다'

    $marker = Get-GissueTimeboxFollowupMarker 5141
    Assert-Equal '(원본 giip #5141)' $marker 'A-8 마커는 닫는 괄호까지 포함한다'

    # ────────────────────────────────────────────────────────────────────────────
    # B. 러너 배선 가드
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'B. 러너 배선 가드'

    $runnerSrc = [System.IO.File]::ReadAllText($RunnerPs1, [System.Text.Encoding]::UTF8)
    Assert-True ($runnerSrc.Contains("lib/timebox-followup.ps1")) 'B-1 러너가 판정 lib 을 닷소싱한다'
    Assert-True ($runnerSrc.Contains('Find-GissueOpenTimeboxFollowup -Rows $timeboxRows')) 'B-2 러너가 판정 함수를 호출한다'
    Assert-True ($runnerSrc.Contains('Find-GissueOpenTimeboxFollowup -Rows $timeboxRows -OriginIsn $issue.Isn')) 'B-3 판정에 원본 이슈 번호를 넘긴다'

    # 조회(중복 확인)가 등록보다 앞에 있어야 한다 — 순서 역전이면 판정이 무의미하다.
    $idxLookup = $runnerSrc.IndexOf('Find-GissueOpenTimeboxFollowup -Rows $timeboxRows')
    $idxRegister = $runnerSrc.IndexOf('--title-file $timeboxTitleTmp')
    Assert-True ($idxLookup -gt 0 -and $idxRegister -gt 0 -and $idxLookup -lt $idxRegister) 'B-4 중복 조회가 후속 등록보다 먼저 수행된다' "lookup=$idxLookup register=$idxRegister"

    Assert-True ($runnerSrc.Contains('$timeboxExisting')) 'B-5 기존 후속 재사용 분기가 있다'
    Assert-True ($runnerSrc.Contains('--title-file $timeboxTitleTmp')) 'B-6 제목은 파일 경유로 등록된다 (표식 = 판정 키 보존)'
    Assert-True (-not $runnerSrc.Contains('--title $timeboxFollowupTitle')) 'B-7 네이티브 --title 직접 전달을 쓰지 않는다 (표식 보존)'

    # ────────────────────────────────────────────────────────────────────────────
    # C. 자기 검증 — 이 검사가 실제로 FAIL 을 감지하는가 (rule 42)
    # ────────────────────────────────────────────────────────────────────────────
    Write-Output 'C. 자기 검증 (검사기가 FAIL 을 잡는지)'

    $realFound = Test-ExistingFollowupFound -Rows $rows -OriginIsn 5141 -Finder { param($r, $i) Find-GissueOpenTimeboxFollowup -Rows $r -OriginIsn $i }
    Assert-True $realFound 'C-1 정상 구현으로는 미해결 후속을 찾는다'

    $mutantFound = Test-ExistingFollowupFound -Rows $rows -OriginIsn 5141 -Finder { param($r, $i) $null }
    Assert-True (-not $mutantFound) 'C-2 돌연변이 구현(항상 못 찾음)은 같은 검사에서 FAIL 로 판정된다'

    Assert-True ($realFound -ne $mutantFound) 'C-3 정상/돌연변이 결과가 갈린다 — 검사가 무의미하지 않다'
} finally {
}

Write-Output ''
Write-Output ("결과: PASS {0}건 / FAIL {1}건" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
