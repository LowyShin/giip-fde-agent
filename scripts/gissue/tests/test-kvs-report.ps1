# kvs-report.ps1 순수 함수 + 페이로드 단위 테스트(네트워크 없음 — 전송 포트를 가짜로 교체).
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-kvs-report.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/kvs-report.ps1')
function Assert-Eq($a, $b, $m) { if ($a -ne $b) { throw "FAIL $m : expected [$b] got [$a]" } }
function Assert-True($a, $m) { if (-not $a) { throw "FAIL $m : expected true" } }
function Assert-False($a, $m) { if ($a) { throw "FAIL $m : expected false" } }

# 호스트 식별: hostname 은 비어 있지 않은 문자열, ips 는 배열
$hostId = Get-GissueHostIdentity
Assert-True ($hostId.hostname -is [string] -and $hostId.hostname.Length -gt 0) 'hostname 비어 있지 않음'
Assert-True ($null -ne $hostId.ips) 'ips 배열 존재'

# limit 서명 판정
Assert-True (Test-GissueLimitSignature 'error 429 Too Many Requests') '429'
Assert-True (Test-GissueLimitSignature 'Token Plan usage limit reached (2056)') 'Token Plan'
Assert-True (Test-GissueLimitSignature '사용량 한도 초과로 중단') '사용량 한도'
Assert-True (Test-GissueLimitSignature 'OAuth access token has been revoked') 'token revoked'
Assert-True (Test-GissueLimitSignature 'insufficient credit') 'insufficient credit'
Assert-False (Test-GissueLimitSignature '정상 완료') '정상 문구는 아님'
Assert-False (Test-GissueLimitSignature '') '빈 문자열'
Assert-False (Test-GissueLimitSignature $null) 'null'

# 알람 종류 판정 — limit 이 상태보다 우선, DONE+정상 = 알람 없음
Assert-Eq (Get-GissueAlarmKind 'DONE' 'engine output: 429 rate limit') 'LIMIT' 'DONE 이어도 limit 서명이면 LIMIT'
Assert-Eq (Get-GissueAlarmKind 'TIMEOUT (105분) — 중단' '') 'TIMEOUT' 'TIMEOUT'
Assert-Eq (Get-GissueAlarmKind 'ZOMBIE-WATCHDOG (giip #1550)' '') 'ZOMBIE' 'ZOMBIE'
Assert-Eq (Get-GissueAlarmKind 'OVERTIME-SPLIT (giip 4429)' '') 'OVERTIME' 'OVERTIME'
Assert-Eq (Get-GissueAlarmKind 'FAILED' '') 'RUN_FAIL' '그 외 비정상'
Assert-Eq (Get-GissueAlarmKind 'DONE' '정상 처리 완료') $null 'DONE+정상 = 알람 없음'

# 전송 포트 캡처 — 페이로드 구조(kType/kKey/kFactor/kValue) 검증
$script:captured = $null
$script:GissueKvsTransport = { param($JsonData, $Sk) $script:captured = $JsonData; $script:capturedSk = $Sk; return $true }

$ok = Send-GissueSchedulerAlarmRecord -Lssn '99999' -Sk 'SKTEST' -Kind 'LIMIT' -Csn '47' -RunId 'run-1' -Status 'DONE' -Detail 'engine 429'
Assert-True $ok '알람 전송 성공(포트)'
Assert-Eq $script:capturedSk 'SKTEST' 'SK 전달'
Assert-True ($script:captured -match '"kType":"lssn"') 'kType=lssn'
Assert-True ($script:captured -match '"kKey":"99999"') 'kKey=LSSN'
Assert-True ($script:captured -match '"kFactor":"scheduler_alarm"') 'kFactor=scheduler_alarm'
Assert-True ($script:captured -match '"kind":"LIMIT"') 'kind=LIMIT'
Assert-True ($script:captured -match '"hostname":"[^"]+"') 'hostname 포함'
Assert-True ($script:captured -match '"ips":\[') 'ips 포함'

$script:captured = $null
$ok = Send-GissueSchedulerStartRecord -Lssn '99999' -Sk 'SKTEST' -RunId 'run-2' -CsnList @('47', '33') -Commit 'abc1234'
Assert-True $ok '시작 기록 전송 성공(포트)'
Assert-True ($script:captured -match '"kFactor":"scheduler_run_start"') 'kFactor=scheduler_run_start'
Assert-True ($script:captured -match '"event":"start"') 'event=start'
Assert-True ($script:captured -match '"agentCommit":"abc1234"') 'agentCommit 포함'

# [giip #6214] 자동 반영 결과가 시작 기록에 실린다 — 실행이 도중에 죽어도 남아야 하는 사실이다.
$script:captured = $null
$ok = Send-GissueSchedulerStartRecord -Lssn '99999' -Sk 'SKTEST' -RunId 'run-3' -CsnList @('47') -Commit 'abc1234' -CodeSync 'updated(abc1234->def5678)'
Assert-True $ok '시작 기록 전송 성공(포트, codeSync 포함)'
Assert-True ($script:captured -match '"codeSync":"updated') 'codeSync 포함(자동 반영 결과)'
# 지정하지 않으면 키 자체를 넣지 않는다(기존 기록 형태를 깨지 않기 위해)
$script:captured = $null
$ok = Send-GissueSchedulerStartRecord -Lssn '99999' -Sk 'SKTEST' -RunId 'run-4' -CsnList @('47') -Commit 'abc1234'
Assert-False ($script:captured -match '"codeSync"') 'codeSync 미지정 시 키 없음'

$script:captured = $null
$ok = Send-GissueSchedulerRunReport -Lssn '99999' -Sk 'SKTEST' -Csn '47' -Status 'DONE' -Processed 3 -Skipped 1 -Failed 0 -RunId 'run-2'
Assert-True $ok '리포트 전송 성공(포트)'
Assert-True ($script:captured -match '"kFactor":"scheduler_run_report"') 'kFactor=scheduler_run_report'
Assert-True ($script:captured -match '"processed":3') 'processed=3'

# 포트가 실패를 돌려주면 래퍼도 $false (throw 하지 않음)
$script:GissueKvsTransport = { param($JsonData, $Sk) return $false }
Assert-False (Send-GissueSchedulerRunReport -Lssn '99999' -Sk 'SKTEST' -Csn '47' -Status 'DONE') '포트 실패 = $false'

# SK 가 비면 전송하지 않고 $false
$script:GissueKvsTransport = $null
Assert-False (Send-GissueKvsPut -Lssn '99999' -Factor 'scheduler_alarm' -Value @{ a = 1 } -Sk '') 'SK 없음 = $false'


# 토큰 사용량 기록 — 페이로드 구조(4분류 원형) 검증
$script:GissueKvsTransport = { param($JsonData, $Sk) $script:captured = $JsonData; return $true }
$script:captured = $null
$enginesFixture = @(
    [ordered]@{ model = 'MiniMax-M3.1-Flash'; calls = 2; freshIn = 100; cacheCreate = 10; cacheRead = 5000; out = 40 },
    [ordered]@{ model = 'claude-opus-4-8'; calls = 1; freshIn = 7; cacheCreate = 3; cacheRead = 900; out = 11 }
)
$ok = Send-GissueTokenUsageRecord -Lssn '99999' -Sk 'SKTEST' -Csn '47' -Engines $enginesFixture -RunId 'run-3'
Assert-True $ok '토큰 사용량 전송 성공(포트)'
Assert-True ($script:captured -match '"kFactor":"scheduler_token_usage"') 'kFactor=scheduler_token_usage'
Assert-True ($script:captured -match '"event":"token_usage"') 'event=token_usage'
Assert-True ($script:captured -match '"model":"MiniMax-M3.1-Flash"') 'engines 모델 포함'
Assert-True ($script:captured -match '"freshIn":100') 'freshIn 원형 포함'
Assert-True ($script:captured -match '"cacheRead":5000') 'cacheRead 원형 포함'

# 포트가 실패를 돌려주면 래퍼도 $false (throw 하지 않음)
$script:GissueKvsTransport = { param($JsonData, $Sk) return $false }
Assert-False (Send-GissueTokenUsageRecord -Lssn '99999' -Sk 'SKTEST' -Csn '47' -Engines $enginesFixture) '토큰 사용량 포트 실패 = $false'

Write-Host 'PASS test-kvs-report'
