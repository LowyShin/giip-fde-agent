# test-gissue-liveness.ps1 — gissue 처리 무소식 점검(check-gissue-liveness.ps1 / lib) 회귀 테스트 (giip 4411)
#
# 고정하는 것(가짜 로그 디렉터리 + mtime 픽스처, 임시 디렉터리 아래에서만 동작 — 실제 로그/태스크는 건드리지 않는다):
#   (A) 정상 / 일부 무소식 / 전체 무소식 구분과 종료코드 0/1
#   (B) 살아있는 락(처리 중)은 로그가 오래돼도 오탐하지 않는다
#   (C) 죽은 PID 락 / 오래 묵은 락은 무소식이며 사유에 표시된다
#   (D) 로그 없음 = NO_LOG(무소식), 점검 대상 0건 = NO_TARGETS(정상 아님)
#   (E) enabled=false 와 예시 키("<CSN番号>")는 대상이 아니다
#   (F) 읽기 전용 증명: 점검 실행 전후로 픽스처 디렉터리의 파일·mtime·내용이 동일(-Notify 없이)
#   (G) 알림 쿨다운: 첫 알림 / 같은 상태 쿨다운 중 / 쿨다운 경과 / 상태 변화 즉시 / 정상은 알림 없음
#   (H) -Notify 라도 -OpsCsn 이 없으면 상태 파일을 쓰지 않는다
#   (I) 에피소드 상태·상태 서명·침묵 시작(추정)·진행 보고 본문·회복 보고 본문(순수 함수)
#   (J) 스크립트 동작(스텁 도구 주입):
#       열린 같은 제목 이슈가 있으면 **새로 등록하지 않고** 진행 보고 코멘트를 남긴다(중복 방지),
#       열려 있는 이슈가 없으면 등록한다, 목록 조회가 실패하면 등록하지 않는다(LIST-FAIL),
#       회복(정상 복귀)이면 열린 이슈에 회복 코멘트를 남기고 DONE 으로 닫는다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gissue-liveness.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $gissueDir 'lib') 'gissue-liveness-lib.ps1')
$runner = Join-Path $gissueDir 'check-gissue-liveness.ps1'

# 러너를 띄울 엔진(Windows=Windows PowerShell 5.1, 그 외=pwsh). 5.1 에는 $IsLinux 이 없다 → $null → else.
$psExe = if ($IsLinux) { 'pwsh' } else { 'powershell.exe' }

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("liveness-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$now = Get-Date

function New-Fixture($name, $logsAgeHours, $cfgEnabled) {
    # $logsAgeHours: @{ csn = 시간(null 이면 로그 없음) }, $cfgEnabled: @{ csn = $true/$false } (null 이면 설정 파일 없음)
    $dir = Join-Path $root $name
    $logs = Join-Path $dir 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    foreach ($k in $logsAgeHours.Keys) {
        if ($null -eq $logsAgeHours[$k]) { continue }
        $p = Join-Path $logs "gissue_csn$k.log"
        '[x] [CSN x] fixture' | Out-File -FilePath $p -Encoding UTF8
        (Get-Item $p).LastWriteTime = $now.AddHours(-1 * $logsAgeHours[$k])
    }
    $cfg = $null
    if ($cfgEnabled) {
        $obj = [ordered]@{ csn = [ordered]@{ '<CSN番号>' = @{ enabled = $true } } }
        foreach ($k in $cfgEnabled.Keys) { $obj.csn["$k"] = @{ project = 'p'; workdir = 'w'; enabled = $cfgEnabled[$k] } }
        $cfg = Join-Path $dir 'csn-projects.json'
        ($obj | ConvertTo-Json -Depth 5) | Out-File -FilePath $cfg -Encoding UTF8
    }
    return [pscustomobject]@{ Logs = $logs; Config = $cfg }
}
function Run($fx, $extra = @()) {
    $ErrorActionPreference = 'Continue'   # 러너가 표준오류로 안내를 내보내도 테스트가 죽지 않게
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-LogDir', $fx.Logs, '-Json')
    if ($fx.Config) { $a += @('-ConfigPath', $fx.Config) } else { $a += @('-ConfigPath', (Join-Path $fx.Logs 'none.json')) }
    $out = & $psExe @a @extra 2>$null | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}
# 알림 경로(스텁 도구 주입) 러너. -Json 없이 돌려서 안내 문구(stdout)를 함께 확인한다.
function RunNotify($fx, $stub, $opsCsn = '999', $extra = @()) {
    $ErrorActionPreference = 'Continue'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-LogDir', $fx.Logs, '-Notify', '-OpsCsn', $opsCsn, '-OpsHelper', $stub)
    if ($fx.Config) { $a += @('-ConfigPath', $fx.Config) } else { $a += @('-ConfigPath', (Join-Path $fx.Logs 'none.json')) }
    $out = & $psExe @a @extra 2>$null | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}
function Get-DeadPid { $p = 900001; while (Get-Process -Id $p -ErrorAction SilentlyContinue) { $p++ }; return $p }
function Write-Lock($fx, $csn, $lockPid, $startAgeHours) {
    $start = $now.AddHours(-1 * $startAgeHours).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    "$lockPid|$start|$start" | Out-File -FilePath (Join-Path $fx.Logs "gissue_csn$csn.lock") -Encoding ASCII
}

try {
    Write-Host '(A) 정상 / 일부 / 전체 무소식'
    $fx = New-Fixture 'a-ok' @{ 1 = 0.5; 2 = 1.2 } @{ 1 = $true; 2 = $true }
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Overall -eq 'OK' -and $r.Healthy) '모두 신선 -> OK'
    $x = Run $fx; Assert ($x.Exit -eq 0) 'runner 종료코드 0'

    $fx = New-Fixture 'a-part' @{ 1 = 0.5; 2 = 9 } @{ 1 = $true; 2 = $true }
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Overall -eq 'PARTIAL_SILENT') '한 건만 오래됨 -> PARTIAL_SILENT'
    Assert (@($r.Silent).Count -eq 1 -and $r.Silent[0] -eq 2) '무소식 CSN = 2'
    $x = Run $fx; Assert ($x.Exit -eq 1) 'runner 종료코드 1'
    $j = $x.Out | ConvertFrom-Json; Assert ($j.Overall -eq 'PARTIAL_SILENT') '-Json 출력 파싱 가능'

    $fx = New-Fixture 'a-all' @{ 1 = 150; 2 = 148 } @{ 1 = $true; 2 = $true }
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Overall -eq 'ALL_SILENT') '전부 오래됨(6일) -> ALL_SILENT'
    Assert ($r.Summary -like '*스케줄러 자체*') '요약에 스케줄러 정지 의심 명시'
    Assert ((Run $fx).Exit -eq 1) 'runner 종료코드 1'

    $fx = New-Fixture 'a-edge' @{ 1 = 2.9 } @{ 1 = $true }
    Assert ((Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now).Healthy) '기준(3h) 이내 경계 -> 정상'
    $fx = New-Fixture 'a-edge2' @{ 1 = 3.1 } @{ 1 = $true }
    Assert (-not (Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now).Healthy) '기준(3h) 초과 -> 무소식'
    Assert ((Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -MaxSilentHours 4 -Now $now).Healthy) '-MaxSilentHours 설정 가능'

    Write-Host '(B) 살아있는 락 = 처리 중'
    $fx = New-Fixture 'b-live' @{ 1 = 5 } @{ 1 = $true }
    Write-Lock $fx 1 $PID 1.0
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Csns[0].Status -eq 'RUNNING' -and $r.Healthy) '락 PID 생존 + 1h -> RUNNING(오탐 없음)'

    Write-Host '(C) stale 락'
    $dead = Get-DeadPid
    $fx = New-Fixture 'c-dead' @{ 1 = 5 } @{ 1 = $true }
    Write-Lock $fx 1 $dead 5
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Csns[0].Status -eq 'SILENT' -and $r.Csns[0].Reason -like '*죽은 프로세스*') '죽은 PID 락 + 오래된 로그 -> SILENT, 사유 표시'
    $fx = New-Fixture 'c-old' @{ 1 = 5 } @{ 1 = $true }
    Write-Lock $fx 1 $PID 4
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Csns[0].Status -eq 'SILENT' -and $r.Csns[0].Reason -like '*멈춘 실행*') '살아있어도 4h 묵은 락 -> SILENT(멈춘 실행 의심)'
    $fx = New-Fixture 'c-deadfresh' @{ 1 = 0.5 } @{ 1 = $true }
    Write-Lock $fx 1 $dead 0.5
    Assert ((Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now).Healthy) '죽은 락이어도 로그가 신선하면 정상(다음 실행이 정리)'

    Write-Host '(D) 로그 없음 / 대상 없음'
    $fx = New-Fixture 'd-nolog' @{ 1 = 0.5; 2 = $null } @{ 1 = $true; 2 = $true }
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert (($r.Csns | Where-Object Csn -eq 2).Status -eq 'NO_LOG' -and $r.Overall -eq 'PARTIAL_SILENT') '설정엔 있고 로그 없음 -> NO_LOG(무소식)'
    $fx = New-Fixture 'd-empty' @{} $null
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert ($r.Overall -eq 'NO_TARGETS' -and -not $r.Healthy) '대상 0건 -> NO_TARGETS(정상 아님)'
    Assert ((Run $fx).Exit -eq 1) 'NO_TARGETS 종료코드 1'
    $fx = New-Fixture 'd-nocfg' @{ 7 = 0.2; 8 = 20 } $null
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert (@($r.Csns).Count -eq 2 -and $r.Overall -eq 'PARTIAL_SILENT') '설정 파일 없으면 로그 파일명에서 대상 추출'

    Write-Host '(E) enabled=false / 예시 키 제외'
    $fx = New-Fixture 'e-dis' @{ 1 = 0.5; 2 = 90 } @{ 1 = $true; 2 = $false }
    $r = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    Assert (@($r.Csns).Count -eq 1 -and $r.Healthy) 'enabled=false CSN 과 "<CSN번호>" 키는 점검 대상 아님'

    Write-Host '(F) 읽기 전용 증명'
    $fx = New-Fixture 'f-ro' @{ 1 = 9; 2 = 0.5 } @{ 1 = $true; 2 = $true }
    Write-Lock $fx 1 (Get-DeadPid) 9
    # 디렉터리 mtime 은 NTFS 가 지연 갱신하므로 파일만 비교한다.
    function Snap($d) { (Get-ChildItem -LiteralPath $d -Recurse -Force -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }) -join "`n" }
    $before = Snap (Split-Path -Parent $fx.Logs)
    $null = Run $fx
    $null = Run $fx @('-Notify')
    $after = Snap (Split-Path -Parent $fx.Logs)
    Assert ($before -eq $after) '실행 전후 파일 목록/크기/mtime 동일(-Notify 도 OpsCsn 없으면 쓰기 없음)'
    Assert (-not (Test-Path (Join-Path $fx.Logs 'gissue_liveness_state.json'))) '(H) -Notify + OpsCsn 없음 -> 상태 파일 없음'

    Write-Host '(G) 알림 쿨다운'
    $bad = Get-GissueLiveness -LogDir $fx.Logs -ConfigPath $fx.Config -Now $now
    $d = Test-LivenessNotifyDue -Result $bad -State $null -CooldownHours 6 -Now $now
    Assert ($d.Due) '상태 없음 -> 첫 알림'
    $st = [pscustomobject]@{ lastNotifiedAt = $now.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ss'); signature = $d.Signature }
    Assert (-not (Test-LivenessNotifyDue -Result $bad -State $st -CooldownHours 6 -Now $now).Due) '같은 상태 1h 전 알림 -> 쿨다운 중'
    $st.lastNotifiedAt = $now.AddHours(-7).ToString('yyyy-MM-ddTHH:mm:ss')
    Assert ((Test-LivenessNotifyDue -Result $bad -State $st -CooldownHours 6 -Now $now).Due) '7h 전 알림 -> 쿨다운 경과'
    $st.lastNotifiedAt = $now.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ss'); $st.signature = 'ALL_SILENT:1,2'
    Assert ((Test-LivenessNotifyDue -Result $bad -State $st -CooldownHours 6 -Now $now).Due) '상태 변화(서명 다름) -> 쿨다운 무시하고 즉시'
    $okR = Get-GissueLiveness -LogDir (New-Fixture 'g-ok' @{ 1 = 0.1 } @{ 1 = $true }).Logs -ConfigPath (Join-Path $root 'g-ok\csn-projects.json') -Now $now
    Assert (-not (Test-LivenessNotifyDue -Result $okR -State $null -Now $now).Due) '정상 -> 알림 없음'

    Write-Host '(I) 에피소드 상태 / 서명 / 침묵 시작 / 코멘트 본문'
    $fxI = New-Fixture 'i-silent' @{ 1 = 10; 2 = 5 } @{ 1 = $true; 2 = $true }
    $badI = Get-GissueLiveness -LogDir $fxI.Logs -ConfigPath $fxI.Config -Now $now
    Assert ((Get-LivenessSignature -Result $badI) -eq 'ALL_SILENT:1,2') '상태 서명 = 판정:무소식 CSN 목록'
    $since = Get-LivenessSilentSince -Result $badI -Now $now
    Assert ($since -and [math]::Abs(($since - $now.AddHours(-7)).TotalMinutes) -lt 1) '침묵 시작(추정) = 마지막 로그 + 기준시간'
    $iss = @([pscustomobject]@{ isn = 4870; cSn = 9001; status = 'PENDING'; title = '[OPS] gissue 처리 무소식 감지' })
    $stI = [pscustomobject]@{ episode = (Get-LivenessEpisodeState -State $null -Issues $iss -Result $badI -Now $now) }
    Assert ($stI.episode.isn -eq 4870 -and $stI.episode.commentCount -eq 1) '에피소드 첫 기록(이슈/횟수)'
    Assert ((Test-LivenessEpisodeCommentDue -Result $badI -State $null -Issues $iss -CooldownHours 6 -Now $now).Due) '에피소드 처음 발견 -> 즉시 보고'
    Assert (-not (Test-LivenessEpisodeCommentDue -Result $badI -State $stI -Issues $iss -CooldownHours 6 -Now $now.AddHours(1)).Due) '같은 상태 + 쿨다운 중 -> 생략'
    Assert ((Test-LivenessEpisodeCommentDue -Result $badI -State $stI -Issues $iss -CooldownHours 6 -Now $now.AddHours(7)).Due) '쿨다운 경과 -> 주기적 경과 보고'
    $badI2 = Get-GissueLiveness -LogDir (New-Fixture 'i-part' @{ 1 = 10; 2 = 0.2 } @{ 1 = $true; 2 = $true }).Logs -ConfigPath (Join-Path $root 'i-part\csn-projects.json') -Now $now
    Assert ((Test-LivenessEpisodeCommentDue -Result $badI2 -State $stI -Issues $iss -CooldownHours 6 -Now $now).Due) '상태 변화 -> 즉시 보고'
    $body = New-LivenessStatusComment -Result $badI -State $stI -Now $now
    Assert ($body -like '*침묵 중인 CSN: 1, 2*') '진행 보고 본문에 침묵 중인 CSN 목록'
    Assert ($body -like '*침묵 시작(추정):*') '진행 보고 본문에 침묵 시작 시각'
    Assert ($body -like '*경과:*h*') '진행 보고 본문에 경과'
    Assert ($body -like '*상태 서명: ALL_SILENT:1,2*') '진행 보고 본문에 상태 서명'
    $okI = Get-GissueLiveness -LogDir (New-Fixture 'i-ok' @{ 1 = 0.2 } @{ 1 = $true }).Logs -ConfigPath (Join-Path $root 'i-ok\csn-projects.json') -Now $now
    $rbody = New-LivenessRecoveryComment -Result $okI -State $stI -Now $now
    Assert ($rbody -like '*회복 감지*') '회복 보고 본문'
    Assert ($rbody -like '*총 경과:*') '회복 보고 본문에 총 경과'

    Write-Host '(J) 스크립트 동작: 중복 방지 / 코멘트 누적 / 회복 종료 / 조회 실패 시 미등록'
    $stubDir = Join-Path $root 'stub'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    $stub = Join-Path $stubDir 'stub-liveness-ops-issue.js'
    @'
// 테스트 스텁 — 실제 도구(liveness-ops-issue.js)를 대신한다. 호출 기록을 남기고 시나리오대로 답한다.
const fs = require('fs');
const scenario = JSON.parse(fs.readFileSync(process.env.GISSUE_LIVENESS_STUB, 'utf8').replace(/^﻿/, ''));
const verb = process.argv[2];
const args = process.argv.slice(3);
const logFile = process.env.GISSUE_LIVENESS_STUB_LOG;
if (logFile) fs.appendFileSync(logFile, verb + '\t' + JSON.stringify(args) + '\n');
let res;
if (verb === 'find') {
  if (scenario.findFail) {
    console.error('stub: 목록 조회 실패');
    process.stdout.write(JSON.stringify({ ok: false, error: 'stub 목록 조회 실패' }) + '\n');
    process.exit(1);
  }
  res = { ok: true, issues: scenario.issues || [] };
} else if (verb === 'comment') {
  const fileArg = args[args.indexOf('--file') + 1];
  const body = fileArg && fs.existsSync(fileArg) ? fs.readFileSync(fileArg, 'utf8') : '';
  if (logFile) fs.appendFileSync(logFile, 'body\t' + body.replace(/\r?\n/g, ' | ') + '\n');
  res = { ok: true, cSn: 1, verified: true };
} else if (verb === 'close') {
  res = { ok: true };
} else if (verb === 'register') {
  res = { ok: true, isn: scenario.registerIsn || 9001, stdout: 'stub: giip issue #' + (scenario.registerIsn || 9001) + ' 등록 완료' };
} else {
  res = { ok: false, error: 'stub: unknown verb ' + verb };
}
process.stdout.write(JSON.stringify(res) + '\n');
'@ | Out-File -FilePath $stub -Encoding UTF8
    $scenarioFile = Join-Path $root 'scenario.json'
    $callLog = Join-Path $root 'calls.log'
    $env:GISSUE_LIVENESS_STUB = $scenarioFile
    $env:GISSUE_LIVENESS_STUB_LOG = $callLog
    function Set-Scenario($obj) {
        $obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $scenarioFile -Encoding UTF8
        if (Test-Path -LiteralPath $callLog) { Remove-Item -LiteralPath $callLog -Force -ErrorAction SilentlyContinue }
    }
    function Get-Calls { if (Test-Path -LiteralPath $callLog) { @(Get-Content -LiteralPath $callLog -Encoding UTF8) } else { @() } }

    # J1 — 열린 같은 제목 이슈가 있으면 새로 등록하지 않고 진행 보고 코멘트를 남긴다.
    $fxJ = New-Fixture 'j-dup' @{ 1 = 10 } @{ 1 = $true }
    Set-Scenario @{ issues = @(@{ isn = 4870; cSn = 9001; status = 'PENDING'; title = '[OPS] gissue 처리 무소식 감지' }) }
    $rJ = RunNotify $fxJ $stub
    $calls = (Get-Calls) -join "`n"
    Assert ($calls -match '(?m)^comment') '열린 이슈가 있으면 진행 보고 코멘트 남김'
    Assert ($calls -notmatch '(?m)^register') '열린 이슈가 있으면 새 이슈 등록 안 함(중복 방지)'
    Assert ($calls -match '침묵 중인 CSN: 1') '진행 보고 본문에 침묵 CSN 목록'
    Assert ($rJ.Out -like '*진행 보고*') '출력에 진행 보고 표시'
    # 쓰기 CSN 계약: 코멘트는 **이슈가 실제 위치한 CSN** 으로 건다(요청한 OpsCsn 이 아니라 응답 행의 cSn).
    Assert ($calls -match '--csn","9001') '코멘트는 이슈가 실제 위치한 CSN(응답 행의 cSn)으로 건다'
    $stJ = Get-Content -LiteralPath (Join-Path $fxJ.Logs 'gissue_liveness_state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($stJ.episode.isn -eq 4870) '상태 파일에 에피소드 이슈 기록'

    # J2 — 열린 이슈가 없으면 에피소드 첫 이슈를 등록한다.
    $fxJ2 = New-Fixture 'j-new' @{ 1 = 10 } @{ 1 = $true }
    Set-Scenario @{ issues = @() }
    $rJ2 = RunNotify $fxJ2 $stub
    $calls2 = (Get-Calls) -join "`n"
    Assert ($calls2 -match '(?m)^register') '열린 이슈가 없으면 등록'
    Assert ($calls2 -notmatch '(?m)^comment') '등록만 수행(중복 코멘트 없음)'
    Assert ($rJ2.Out -like '*POSTED*') '출력에 등록 표시'

    # J3 — 목록 조회가 실패하면 등록하지 않는다(중복 등록 방지 우선).
    $fxJ3 = New-Fixture 'j-listfail' @{ 1 = 10 } @{ 1 = $true }
    Set-Scenario @{ findFail = $true }
    $rJ3 = RunNotify $fxJ3 $stub
    $calls3 = (Get-Calls) -join "`n"
    Assert ($calls3 -notmatch '(?m)^register') '조회 실패 -> 등록 안 함'
    Assert ($calls3 -notmatch '(?m)^comment') '조회 실패 -> 코멘트도 안 함'
    Assert ($rJ3.Out -like '*LIST-FAIL*') '조회 실패 -> LIST-FAIL 출력'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fxJ3.Logs 'gissue_liveness_state.json'))) '조회 실패 -> 상태 파일 안 남김'

    # J4 — 회복(처리 흔적 복귀)이면 열린 이슈에 회복 코멘트 후 DONE 으로 닫는다.
    $fxJ4 = New-Fixture 'j-recover' @{ 1 = 0.2 } @{ 1 = $true }
    Set-Scenario @{ issues = @(@{ isn = 4870; cSn = 9001; status = 'PENDING'; title = '[OPS] gissue 처리 무소식 감지' }) }
    $rJ4 = RunNotify $fxJ4 $stub
    $calls4 = (Get-Calls) -join "`n"
    Assert ($rJ4.Exit -eq 0) '회복(정상) 시 종료코드 0'
    Assert ($calls4 -match '(?m)^comment') '회복 코멘트 남김'
    Assert ($calls4 -match '(?m)^close') '회복 시 이슈 닫기'
    # 본문에도 "DONE" 이 들어갈 수 있으므로 **close 호출 인자**로 검증한다.
    Assert ($calls4 -match '--status","DONE') '회복 시 close 호출이 DONE 을 전달한다'
    Assert ($calls4 -match '회복 감지') '회복 코멘트 본문'
    Assert ($calls4 -match '--csn","9001') '종료도 이슈가 실제 위치한 CSN 으로 건다'

    # J5 — 에피소드 이슈가 외부(처리 스케줄러 등)에 의해 닫혔고 침묵이 계속되면 새 이슈를 만들지 않는다.
    #      (여기서 등록하면 "한 침묵에 여러 이슈" = 2026-11-11 중복 등록 사고의 재발 경로다.)
    $fxJ5 = New-Fixture 'j-episode' @{ 1 = 10 } @{ 1 = $true }
    $st5 = [ordered]@{
        lastNotifiedAt = $now.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ss')
        signature      = 'ALL_SILENT:1'
        episode        = [pscustomobject]@{
            isn = 4870; cSn = 9001; silentCsns = @(1)
            silentSince = $now.AddHours(-9).ToString('yyyy-MM-ddTHH:mm:ss')
            firstSeenAt = $now.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ss')
            lastCommentAt = $now.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ss')
            commentCount = 2; lastSignature = 'ALL_SILENT:1'
        }
    }
    $st5 | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $fxJ5.Logs 'gissue_liveness_state.json') -Encoding UTF8
    Set-Scenario @{ issues = @() }
    $rJ5 = RunNotify $fxJ5 $stub
    $calls5 = (Get-Calls) -join "`n"
    Assert ($calls5 -notmatch '(?m)^register') '에피소드 이슈가 외부 종료됐다면 새 이슈를 등록하지 않음(중복 방지)'
    Assert ($rJ5.Out -like '*에피소드 이슈*') '에피소드 이슈 외부 종료를 출력'
    Assert ($rJ5.Out -notlike '*POSTED*') '외부 종료 상태에서 등록하지 않음'

    # J6 — 회복하면 에피소드 기록이 정리된다(다음 침묵에서 새 에피소드를 시작할 수 있어야 한다).
    $fxJ6 = New-Fixture 'j-recover-clear' @{ 1 = 0.2 } @{ 1 = $true }
    $st6 = [ordered]@{
        lastNotifiedAt = $now.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ss')
        signature      = 'ALL_SILENT:1'
        episode        = [pscustomobject]@{
            isn = 4870; cSn = 9001; silentCsns = @(1)
            silentSince = $now.AddHours(-9).ToString('yyyy-MM-ddTHH:mm:ss')
            firstSeenAt = $now.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ss')
            lastCommentAt = $now.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ss')
            commentCount = 3; lastSignature = 'ALL_SILENT:1'
        }
    }
    $st6 | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $fxJ6.Logs 'gissue_liveness_state.json') -Encoding UTF8
    Set-Scenario @{ issues = @(@{ isn = 4870; cSn = 9001; status = 'PENDING'; title = '[OPS] gissue 처리 무소식 감지' }) }
    $rJ6 = RunNotify $fxJ6 $stub
    $stJ6 = Get-Content -LiteralPath (Join-Path $fxJ6.Logs 'gissue_liveness_state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (-not ($stJ6.PSObject.Properties.Name -contains 'episode')) '회복 후 상태 파일에서 에피소드 기록이 제거됨'
    Assert (@($stJ6.closedIsns) -contains 4870) '종료한 이슈 번호가 기록됨(같은 이슈 재종료 방지)'
    $calls6 = (Get-Calls) -join "`n"
    Assert ($calls6 -match '총 경과') '회복 코멘트 본문에 총 경과'
}
finally {
    Remove-Item Env:GISSUE_LIVENESS_STUB -ErrorAction SilentlyContinue
    Remove-Item Env:GISSUE_LIVENESS_STUB_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS'
exit 0
