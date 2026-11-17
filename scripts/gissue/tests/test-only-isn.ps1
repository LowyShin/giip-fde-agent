# test-only-isn.ps1 — lib/only-isn.ps1 회귀 테스트 (giip 5544)
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-only-isn.ps1
# 네트워크·실제 스케줄러를 건드리지 않는다 — 판정 순수 함수와 [OPS] 접두사 커플링만 검증한다.
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Assert-True([bool]$Cond, [string]$Name) {
    if ($Cond) { $script:Pass++; Write-Host "  PASS: $Name" }
    else { $script:Fail++; Write-Host "  FAIL: $Name" }
}
function Assert-Eq($Actual, $Expected, [string]$Name) {
    Assert-True ("$Actual" -eq "$Expected") "$Name (기대=$Expected 실제=$Actual)"
}

$gissueRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $gissueRoot 'lib/only-isn.ps1')

function Verdict($overrides) {
    $p = @{
        Found = $true; Status = 'READY'; RowCsn = '47'; TargetCsn = '47'
        Title = '일반 작업 이슈'; InQueue = $false; QueueStatus = ''
    }
    foreach ($k in $overrides.Keys) { $p[$k] = $overrides[$k] }
    Get-GissueOnlyIsnVerdict @p
}

Write-Host '== 지정 성공 =='
$v = Verdict @{ InQueue = $true; QueueStatus = 'READY' }
Assert-Eq $v.Action 'RUN' '큐에 있는 READY 는 RUN'
Assert-Eq $v.QueueStatus 'READY' '큐 라벨 유지'
$v = Verdict @{ Status = 'READY'; InQueue = $false }
Assert-Eq $v.Action 'RUN' '경과 부족으로 큐에 없는 READY 도 RUN(60분 조건 우회)'
Assert-Eq $v.QueueStatus 'READY' '우회 실행의 라벨은 READY'
$v = Verdict @{ Status = 'PENDING'; InQueue = $true; QueueStatus = 'PENDING' }
Assert-Eq $v.Action 'RUN' '큐에 있는 PENDING 은 RUN'
$v = Verdict @{ Status = 'IN_PROGRESS'; InQueue = $true; QueueStatus = 'STALE_IN_PROGRESS' }
Assert-Eq $v.Action 'RUN' '정체 IN_PROGRESS 는 큐 라벨(STALE) 그대로 회수 RUN'
$v = Verdict @{ Status = 'REVIEW'; InQueue = $true; QueueStatus = 'REVIEW' }
Assert-Eq $v.Action 'RUN' '큐에 있는 REVIEW 는 RUN(쿨다운은 잡 루프 게이트가 판정)'

Write-Host '== CSN 불일치 차단 (giip #1053) =='
$v = Verdict @{ RowCsn = '33' }
Assert-Eq $v.Action 'SKIP' '타 CSN 소속이면 SKIP'
Assert-Eq $v.Reason 'CSN_MISMATCH' '사유 CSN_MISMATCH'
$v = Verdict @{ RowCsn = '' }
Assert-Eq $v.Action 'RUN' '응답에 cSn 이 없으면(서버 미제공) 가드 생략하고 진행'

Write-Host '== 안전 게이트 유지 =='
$v = Verdict @{ Status = 'NEEDS_DECISION'; InQueue = $false }
Assert-Eq $v.Action 'SKIP' 'NEEDS_DECISION 은 SKIP'
Assert-Eq $v.Reason 'NEEDS_DECISION' '사유 NEEDS_DECISION'
$v = Verdict @{ Status = 'NEEDS_DECISION'; InQueue = $true; QueueStatus = 'NEEDS_DECISION' }
Assert-Eq $v.Reason 'NEEDS_DECISION' '큐에 있어도 NEEDS_DECISION 은 게이트 우선'
$v = Verdict @{ Status = 'IN_PROGRESS'; InQueue = $false }
Assert-Eq $v.Action 'SKIP' '신선한 IN_PROGRESS 는 중복 실행 금지로 SKIP'
Assert-Eq $v.Reason 'IN_PROGRESS_ACTIVE' '사유 IN_PROGRESS_ACTIVE'
$v = Verdict @{ Title = '[OPS] gissue 처리 무소식 감지'; Status = 'PENDING'; InQueue = $false }
Assert-Eq $v.Action 'SKIP' '자동 감지 [OPS] 이슈는 SKIP'
Assert-Eq $v.Reason 'AUTO_OPS' '사유 AUTO_OPS'
$v = Verdict @{ Title = '[OPS] gissue 처리 무소식 감지 (CSN 47)'; Status = 'PENDING' }
Assert-Eq $v.Reason 'AUTO_OPS' '접두사 뒤에 부가 설명이 붙어도 AUTO_OPS'
$v = Verdict @{ Title = '[후속] [OPS] gissue 처리 무소식 감지 정리'; Status = 'PENDING'; InQueue = $true; QueueStatus = 'PENDING' }
Assert-Eq $v.Action 'RUN' '제목 중간에 [OPS] 가 포함된 후속 이슈는 제외하지 않음(접두사 전체 일치만)'
$v = Verdict @{ Status = 'DONE'; InQueue = $false }
Assert-Eq $v.Reason 'STATUS_NOT_PROCESSABLE' 'DONE 은 처리 대상 아님'
$v = Verdict @{ Status = 'REVIEW'; InQueue = $false }
Assert-Eq $v.Reason 'REVIEW_NO_NEW_SIGNAL' '큐에서 dedup 으로 빠진 REVIEW 는 SKIP'
$v = Verdict @{ Found = $false; Status = ''; RowCsn = '' }
Assert-Eq $v.Action 'SKIP' '찾지 못하면 SKIP'
Assert-Eq $v.Reason 'NOT_FOUND' '사유 NOT_FOUND'

Write-Host '== 스킵 코멘트 문구 =='
foreach ($r in @('CSN_MISMATCH', 'AUTO_OPS', 'NEEDS_DECISION', 'IN_PROGRESS_ACTIVE', 'REVIEW_NO_NEW_SIGNAL', 'STATUS_NOT_PROCESSABLE')) {
    $note = Get-GissueOnlyIsnSkipNote -Reason $r -Isn 1234 -Status 'DONE'
    Assert-True ($note -match 'ONLYISN-SKIP' -and $note -match '1234' -and $note.Length -gt 30) "사유 $r 의 코멘트 문구가 만들어진다"
}

Write-Host '== [OPS] 접두사 커플링 (list-issues.js 와 일치) =='
$listIssues = Get-Content -Raw -Encoding UTF8 (Join-Path $gissueRoot 'list-issues.js')
Assert-True ($listIssues -match [regex]::Escape("const AUTO_OPS_TITLE_PREFIX = '$script:GissueAutoOpsTitlePrefix'")) 'lib 접두사가 list-issues.js 의 AUTO_OPS_TITLE_PREFIX 와 동일'
Assert-True (Test-GissueAutoOpsTitle '[OPS] gissue 처리 무소식 감지') '정확 일치 제목은 자동 감지'
Assert-True (-not (Test-GissueAutoOpsTitle '')) '빈 제목은 자동 감지 아님'
Assert-True (-not (Test-GissueAutoOpsTitle '일반 [OPS] 포함 제목')) '중간 포함은 자동 감지 아님'

Write-Host ''
Write-Host "결과: PASS=$script:Pass FAIL=$script:Fail"
if ($script:Fail -gt 0) { exit 1 }
