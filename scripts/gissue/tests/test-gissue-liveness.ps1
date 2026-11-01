# test-gissue-liveness.ps1 — gissue 처리 무소식 점검(check-gissue-liveness.ps1 / lib) 회귀 테스트 (giip 4411)
#
# 고정하는 것(가짜 로그 디렉터리 + mtime 픽스처, $env:TEMP 아래에서만 동작 — 실제 로그/태스크는 건드리지 않는다):
#   (A) 정상 / 일부 무소식 / 전체 무소식 구분과 종료코드 0/1
#   (B) 살아있는 락(처리 중)은 로그가 오래돼도 오탐하지 않는다
#   (C) 죽은 PID 락 / 오래 묵은 락은 무소식이며 사유에 표시된다
#   (D) 로그 없음 = NO_LOG(무소식), 점검 대상 0건 = NO_TARGETS(정상 아님)
#   (E) enabled=false 와 예시 키("<CSN番号>")는 대상이 아니다
#   (F) 읽기 전용 증명: 점검 실행 전후로 픽스처 디렉터리의 파일·mtime·내용이 동일(-Notify 없이)
#   (G) 알림 쿨다운: 첫 알림 / 같은 상태 쿨다운 중 / 쿨다운 경과 / 상태 변화 즉시 / 정상은 알림 없음
#   (H) -Notify 라도 -OpsCsn 이 없으면 상태 파일을 쓰지 않는다
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gissue-liveness.ps1

$ErrorActionPreference = 'Stop'
$gissueDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $gissueDir 'lib\gissue-liveness-lib.ps1')
$runner = Join-Path $gissueDir 'check-gissue-liveness.ps1'

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path $env:TEMP ("liveness-test-" + [guid]::NewGuid().ToString('N'))
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
    $out = & powershell.exe @a @extra 2>$null | Out-String
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
    Assert (@($r.Csns).Count -eq 1 -and $r.Healthy) 'enabled=false CSN 과 "<CSN番号>" 키는 점검 대상 아님'

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
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS'
exit 0
