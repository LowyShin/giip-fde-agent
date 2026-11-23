# test-run-summary.ps1 — 실행 기록(실행 종료 summary) 조립 로직 회귀 테스트 (giip #6214)
#
# 왜 필요한가:
#   실행 이력(tSchedulerAgentRun.summary)에 "종료 상태 한 줄"만 남으면 사후에 답할 수 없는 것이 남는다 —
#   (a) 이 실행이 어느 코드로 돌았는가(HEAD) (b) 어떤 엔진 경로였나(gair/종전/폴백 사유)
#   (c) 기록 호출 자체가 실패했나. 특히 (c) 는 **"기록이 없음"과 "기록 실패"가 구분되지 않는** 상태라
#   조용한 실패로 남는다(사양서 "근본 원인"이 바로 그 실패였다).
#   → 줄 파싱·집계·문구 조립을 순수 함수로 두고 여기서 검증한다(네트워크·파일 없음).
#
# 검증 항목:
#   A. 마커 판정 — [REPO-MAINT][GAIR] 와 [GAIR] 의 포함 관계(정비 쪽 우선) 등
#   B. 집계 — 호출 지점별 카운트와 폴백 사유
#   C. 요약 문구 — 엔진 경로 요약 / 최종 summary 조립 / 길이 제한
#   D. 기록 호출 실패 추출 — 잡이 실제로 남기는 표식 형식
#   E. 러너 소스 배치 — 집계·요약이 실제 러너에 배선돼 있는가
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-run-summary.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$gissueDir  = Split-Path -Parent $PSScriptRoot
$libFile    = Join-Path $gissueDir 'lib/run-summary.ps1'
$runnerFile = Join-Path $gissueDir 'run-gissue-claude.ps1'

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Eq($actual, $expected, $name) {
    Assert-True ("$actual" -eq "$expected") $name "expected=[$expected] actual=[$actual]"
}

. $libFile

# ── A. 마커 판정 ─────────────────────────────────────────────────────────────────
Assert-Eq (Get-GissueEngineLineKind -Line '[REPO-MAINT][GAIR] AK 파생 성공 — 정비 세션 엔진은 gair 경유(모델 미고정)') 'maint-probe-ok' 'A-1 정비 프로브 성공'
Assert-Eq (Get-GissueEngineLineKind -Line '[REPO-MAINT][GAIR] AK 파생 실패 — 기존 MiniMax→Claude 경로로 폴백(fail-soft)') 'maint-probe-fail' 'A-2 정비 프로브 실패'
Assert-Eq (Get-GissueEngineLineKind -Line '[REPO-MAINT][GAIR] GISSUE_REPO_MAINT_GAIR=0 — gair 경유 끔(기존 MiniMax→Claude 경로)') 'maint-probe-disabled' 'A-3 정비 프로브 끔'
Assert-Eq (Get-GissueEngineLineKind -Line '[GAIR] CSN 47 AK 파생 성공 — 일반 이슈 세션 엔진은 gair 경유(모델 미고정)') 'issue-probe-ok' 'A-4 일반 프로브 성공'
Assert-Eq (Get-GissueEngineLineKind -Line '[GAIR] CSN 47 AK 파생 실패 — 기존 MiniMax→Claude 경로로 폴백(fail-soft)') 'issue-probe-fail' 'A-5 일반 프로브 실패'
Assert-Eq (Get-GissueEngineLineKind -Line '[GAIR] GISSUE_GAIR=0 — 일반 이슈 경로 gair 경유 끔(기존 MiniMax→Claude 경로)') 'issue-probe-disabled' 'A-6 일반 프로브 끔'
Assert-Eq (Get-GissueEngineLineKind -Line '[ENGINE] gair 우선 시도 (모델 미고정 — gair 라우터가 선택)') 'path-gair' 'A-7 gair 경로 시도'
Assert-Eq (Get-GissueEngineLineKind -Line '[ENGINE] gair 시도 실패(exit=1) → 기존 MiniMax→Claude 경로로 폴백 (fail-soft)') 'path-gair-failed' 'A-8 gair 실패(폴백)'
Assert-Eq (Get-GissueEngineLineKind -Line '[ENGINE] MiniMax 우선 시도 (model=MiniMax-M3)') 'path-legacy' 'A-9 종전 경로 선택'
Assert-Eq (Get-GissueEngineLineKind -Line '[ENGINE] REVIEW 재검증 — claude(claude-opus-4-8) 강제 기동, MiniMax 시도 건너뜀.') 'path-claude-forced' 'A-10 강제 claude'
Assert-Eq (Get-GissueEngineLineKind -Line '[ISSUE] isn=123 status=READY 처리 시작') '' 'A-11 마커가 아닌 줄은 빈 결과'
Assert-Eq (Get-GissueEngineLineKind -Line '') '' 'A-12 빈 줄은 빈 결과'

# ── B. 집계 ─────────────────────────────────────────────────────────────────────
$marker = New-GissueEnginePathMarker
$null = Add-GissueEnginePathMarker -Marker $marker -Lines @(
    '[REPO-MAINT][GAIR] AK 파생 성공 — 정비 세션 엔진은 gair 경유(모델 미고정)',
    '[GAIR] CSN 47 AK 파생 성공 — 일반 이슈 세션 엔진은 gair 경유(모델 미고정)',
    '[ENGINE] gair 우선 시도 (모델 미고정 — gair 라우터가 선택)',
    '[ENGINE] gair 시도 실패(exit=1) → 기존 MiniMax→Claude 경로로 폴백 (fail-soft)',
    '[ENGINE] MiniMax 우선 시도 (model=MiniMax-M3)',
    '[ENGINE] REVIEW 재검증 — claude(claude-opus-4-8) 강제 기동, MiniMax 시도 건너뜀.',
    '[ENGINE] MiniMax 우선 시도 (model=MiniMax-M3)'
)
Assert-Eq $marker.Gair 1 'B-1 gair 경로 시도 1건'
Assert-Eq $marker.GairFailed 1 'B-2 gair 실패 1건'
Assert-Eq $marker.Legacy 2 'B-3 종전 경로 2건'
Assert-Eq $marker.ClaudeForced 1 'B-4 강제 claude 1건'
Assert-Eq $marker.MaintProbe 'ok' 'B-5 정비 프로브 결과'
Assert-Eq $marker.IssueProbe 'ok' 'B-6 일반 프로브 결과'
Assert-Eq $marker.FallbackReasons['gair호출실패'] 1 'B-7 폴백 사유 집계'

# 프로브 실패·끔이 기록되면 결과가 'fail'/'disabled' 로 남는다
$marker2 = New-GissueEnginePathMarker
$null = Add-GissueEnginePathMarker -Marker $marker2 -Lines @('[REPO-MAINT][GAIR] AK 파생 실패 — 기존 MiniMax→Claude 경로로 폴백(fail-soft)')
Assert-Eq $marker2.MaintProbe 'fail' 'B-8 프로브 실패 기록'
$marker3 = New-GissueEnginePathMarker
$null = Add-GissueEnginePathMarker -Marker $marker3 -Lines @('[GAIR] GISSUE_GAIR=0 — 일반 이슈 경로 gair 경유 끔(기존 MiniMax→Claude 경로)')
Assert-Eq $marker3.IssueProbe 'disabled' 'B-9 프로브 끔 기록'

# 빈 입력은 모든 값이 0
$marker0 = New-GissueEnginePathMarker
Assert-Eq $marker0.Gair 0 'B-10 초기값 gair 0'
Assert-Eq $marker0.Legacy 0 'B-11 초기값 종전 0'

# ── C. 요약 문구 ─────────────────────────────────────────────────────────────────
$sum = Format-GissueEnginePathSummary -Marker $marker
Assert-True ($sum -match 'gair=1') 'C-1 요약에 gair 횟수' "요약=$sum"
Assert-True ($sum -match '실패=1') 'C-2 요약에 gair 실패 횟수' "요약=$sum"
Assert-True ($sum -match '종전=2') 'C-3 요약에 종전 경로 횟수' "요약=$sum"
Assert-True ($sum -match 'claude강제=1') 'C-4 요약에 강제 claude 횟수' "요약=$sum"
Assert-True ($sum -match '정비=성공') 'C-5 요약에 정비 프로브 결과' "요약=$sum"
Assert-True ($sum -match '일반=성공') 'C-6 요약에 일반 프로브 결과' "요약=$sum"
Assert-True ($sum -match '폴백사유') 'C-7 요약에 폴백 사유' "요약=$sum"
$sumEmpty = Format-GissueEnginePathSummary -Marker (New-GissueEnginePathMarker)
Assert-Eq $sumEmpty '엔진경로 기록없음' 'C-8 마커 없으면 "기록없음"(0 을 "문제없음"으로 읽지 않게)'
$sumNull = Format-GissueEnginePathSummary -Marker $null
Assert-Eq $sumNull '엔진경로 기록없음' 'C-9 마커가 null 이어도 "기록없음"'

$final = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' -EnginePath $sum -SyncInfo 'updated(aaaaaaa→bbbbbbb)' -RecordFailures @()
Assert-True ($final -match '^DONE') 'C-10 최종 summary 는 상태로 시작한다' "요약=$final"
Assert-True ($final -match '코드 abc1234\(main\)') 'C-11 최종 summary 에 코드 버전' "요약=$final"
Assert-True ($final -match '자동반영 updated') 'C-12 최종 summary 에 자동 반영 결과' "요약=$final"
$finalFail = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' -EnginePath $sum -SyncInfo '없음' -RecordFailures @('heartbeat: 실패했습니다', 'upsert: 실패했습니다')
Assert-True ($finalFail -match '기록호출실패 2건') 'C-13 최종 summary 에 기록 호출 실패 건수' "요약=$finalFail"
Assert-True ($finalFail -match 'heartbeat') 'C-14 최종 summary 에 실패 사유 예시' "요약=$finalFail"

# 길이 제한 — 잘려도 상태(중요도 최상위)는 살아남아야 한다
$longText = 'x' * 900
$trunc = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' -EnginePath $longText -SyncInfo '없음' -RecordFailures @() -MaxLength 100
Assert-True ($trunc.Length -le 100) 'C-15 최종 summary 는 길이 제한을 지킨다' "길이=$($trunc.Length)"
Assert-True ($trunc -match '^DONE') 'C-16 잘려도 상태는 살아남는다' "요약=$trunc"
Assert-Eq (Format-GissueRunEndSummary -Status '' -CodeVersion '' -EnginePath '' -SyncInfo '' -RecordFailures @()) '' 'C-17 아무것도 없으면 빈 문자열'

# 기록 호출 실패는 **길이 제한과 무관하게** 살아남아야 한다(요약의 두 번째 자리).
# 앞 항목(엔진 경로·자동 반영)이 길어도 실패 신호가 밀려나 사라지면 안 된다.
$hugeEngine = 'e' * 2000
$hugeSync = 's' * 2000
$finalLong = Format-GissueRunEndSummary -Status 'DONE' -CodeVersion 'abc1234(main)' -EnginePath $hugeEngine -SyncInfo $hugeSync -RecordFailures @('heartbeat: 500 서버 오류')
Assert-True ($finalLong -match '기록호출실패 1건') 'C-18 기록 호출 실패는 길이 제한으로 잘려도 살아남는다' "요약=$finalLong"
Assert-True ($finalLong.Length -le 500) 'C-19 요약은 길이 제한을 지킨다' "길이=$($finalLong.Length)"
Assert-True ($finalLong -match '^DONE \| 기록호출실패') 'C-20 실패 항목은 상태 바로 다음에 온다(뒤로 밀리지 않는다)' "요약=$finalLong"
Assert-True ($finalLong -match 'heartbeat') 'C-21 실패 사유 예시가 남는다' "요약=$finalLong"

# ── D. 기록 호출 실패 추출 ───────────────────────────────────────────────────────
$fails = @(Get-GissueSchedulerStateFailures -Lines @(
    '[WARN][SchedulerState-upsert] 실패: Upsert 실패: 500 서버 오류',
    '[WARN][SchedulerState-runStart] 실패: RunStart 실패: 500 서버 오류',
    '[WARN][SchedulerState-heartbeat] 실패: Heartbeat 실패: 500 서버 오류',
    '[WARN][SchedulerState-init] 초기화 실패: 뭐시기',
    '[SchedulerState-runEnd] 실패: RunEnd 실패: 500 서버 오류',
    '[ISSUE] isn=1 처리 시작',
    '[RUN-COUNTS] processed=3'
))
Assert-Eq $fails.Count 5 'D-1 기록 호출 실패 5건이 추출된다' "추출=$($fails -join ' / ')"
Assert-True ($fails[0] -like 'upsert*') 'D-2 동작 이름이 함께 기록된다' "추출=$($fails[0])"
Assert-True ($fails[0] -match '500') 'D-3 사유가 함께 기록된다' "추출=$($fails[0])"
Assert-True ($fails[3] -like 'init*') 'D-4 초기화 실패도 잡힌다' "추출=$($fails[3])"
Assert-Eq (@(Get-GissueSchedulerStateFailures -Lines @('[ISSUE] isn=1 처리 시작')).Count) 0 'D-5 실패가 없으면 0건'

# 사유가 비어 있으면 "(사유 없음)" 으로 명시한다(빈 값이 조용히 사라지지 않게)
$failsNoReason = @(Get-GissueSchedulerStateFailures -Lines @('[WARN][SchedulerState-upsert] 실패'))
Assert-Eq $failsNoReason.Count 1 'D-6 사유 없는 실패도 잡힌다' "추출=$($failsNoReason -join ' / ')"
Assert-True ($failsNoReason[0] -match '사유 없음') 'D-7 사유가 비면 "(사유 없음)" 으로 명시' "추출=$($failsNoReason[0])"

# 긴 사유는 잘린다(요약이 무한정 길어지지 않게)
$longFail = @(Get-GissueSchedulerStateFailures -Lines @("[WARN][SchedulerState-upsert] 실패: $('y' * 500)"))
Assert-True ($longFail[0].Length -le 200) 'D-8 긴 사가는 잘린다' "길이=$($longFail[0].Length)"

# ── E. 러너 소스 배치 ────────────────────────────────────────────────────────────
$src = Get-Content -LiteralPath $runnerFile -Raw -Encoding UTF8
Assert-True ($src -match "lib/code-sync\.ps1") 'E-1 러너가 code-sync 라이브러리를 적재한다' ''
Assert-True ($src -match "lib/run-summary\.ps1") 'E-2 러너가 run-summary 라이브러리를 적재한다' ''
Assert-True ($src -match 'Add-GissueEnginePathMarker -Marker \$r\.EnginePath') 'E-3 러너가 엔진 경로 마커를 집계한다' ''
Assert-True ($src -match 'Format-GissueEnginePathSummary -Marker \$r\.EnginePath') 'E-4 러너가 엔진 경로 요약을 만든다' ''
Assert-True ($src -match 'Get-GissueSchedulerStateFailures -Lines') 'E-5 러너가 기록 호출 실패를 추출한다' ''
Assert-True ($src -match 'Format-GissueRunEndSummary -Status \$status') 'E-6 러너가 최종 summary 를 조립한다' ''
Assert-True ($src -match '\$exitCode, \$runEndSummary\)') 'E-7 RunEnd 호출이 확장된 summary 를 보낸다(구 $status 그대로가 아님)' ''
Assert-True ($src -notmatch '\$exitCode, \$status\)') 'E-8 RunEnd 호출이 구 summary(상태만)를 쓰지 않는다' ''
# 기록 호출 실패가 조용히 삼켜지지 않는지(요구: "기록 호출 실패는 예외로 드러나 … 남는다")
Assert-True ($src -match '\[WARN\]\[SchedulerState-\$Action\] 실패: SK 없음') 'E-9 러너가 SK 없음(기록 불가)을 실패로 드러낸다' ''
Assert-True ($src -match '\[WARN\]\[SchedulerState-heartbeat\] 실패') 'E-10 heartbeat 실패를 삼키지 않는다' ''
Assert-True ($src -match '\[SchedulerState-runEnd\] 실패: SK 없음') 'E-11 종료 기록을 못 남긴 경우도 실패로 드러낸다' ''
Assert-True ($src -match 'Send-GissueSchedulerStartRecord[^\r\n]*-CodeSync') 'E-12 시작 기록에도 자동 반영 결과가 실린다' ''

if ($script:Fail -gt 0) { Write-Output "FAILED: $($script:Fail) 건"; exit 1 }
Write-Output "ALL PASS ($($script:Pass) 건)"
exit 0
