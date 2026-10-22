# test-task-cadence-guard.ps1 — task-cadence-guard.ps1 회귀 테스트 (giip #2480)
#
# 왜 필요한가: `GIIP_StalePending_Hourly` / `GIIP_StaleReview_Hourly` 는 이름이 _Hourly 인데
#   트리거에 반복(Repetition)이 없어 **하루 1회만** 돌았다. 등록은 성공하고 LastTaskResult 도 0 이라
#   실패로 보이지 않았고, giip #2429 에서 같은 파일을 사람이 직접 읽으면서도 못 잡았다.
#   게이트가 그 상황을 실제로 막는지, 그리고 정상 형태를 잘못 막지는 않는지 양방향으로 고정한다.
#
# 네트워크/스케줄러 등록 없이 트리거 객체만 만들어 검사한다(태스크를 만들거나 건드리지 않는다).
# 게이트 실패 경로는 `exit 1` 이라 자식 powershell 프로세스로 돌려 종료코드를 확인한다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-task-cadence-guard.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$guard = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\task-cadence-guard.ps1')).Path
$fail = 0

# 각 케이스: 태스크 이름 + 트리거를 만드는 표현식 + 기대 종료코드(0=통과, 1=거부)
$cases = @(
    @{ name = 'GIIP_StalePending_Hourly'; expect = 1
       label = '이름 Hourly + 반복 없음(#2480 실제 결함 재현)'
       expr  = "New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday -At 00:07" },
    @{ name = 'GIIP_StaleReview_Hourly'; expect = 1
       label = '이름 Hourly + 반복 없음(Daily 트리거)'
       expr  = "New-ScheduledTaskTrigger -Daily -At 00:07" },
    @{ name = 'GIIP_Something_Hourly'; expect = 1
       label = '이름 Hourly + 반복 간격 2시간'
       expr  = "New-ScheduledTaskTrigger -Once -At 00:07 -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Days 3650)" },
    @{ name = 'GIIP_Something_Hourly'; expect = 1
       label = '이름 Hourly + PT1H 지만 기간이 3시간(곧 조용히 멈춤)'
       expr  = "New-ScheduledTaskTrigger -Once -At 00:07 -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 3)" },
    @{ name = 'GIIP_AuditReviewPrs_Hourly'; expect = 0
       label = '정상 형태 A: Once + PT1H / P3650D'
       expr  = "New-ScheduledTaskTrigger -Once -At 00:07 -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)" },
    @{ name = 'GIIP_GateEscalation_Hourly'; expect = 0
       label = '정상 형태 B: Daily + PT1H / P1D (매일 재무장)'
       expr  = "`$t = New-ScheduledTaskTrigger -Daily -At 00:07; `$t.Repetition = (New-ScheduledTaskTrigger -Once -At 00:07 -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition; `$t" },
    @{ name = 'GIIP_BranchIntegrator_Daily'; expect = 0
       label = '이름 Daily + 반복 없음(정상)'
       expr  = "New-ScheduledTaskTrigger -Daily -At 02:00" },
    @{ name = 'GIIP_BranchIntegrator_Daily'; expect = 1
       label = '이름 Daily 인데 실제로는 매시 반복'
       expr  = "New-ScheduledTaskTrigger -Once -At 02:00 -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)" },
    @{ name = 'GIIP Agent Task (v3)'; expect = 0
       label = '이름이 주기를 약속하지 않음 → 검사 생략'
       expr  = "New-ScheduledTaskTrigger -Once -At 00:00 -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)" }
)

foreach ($c in $cases) {
    $script = ". '$guard'; `$trigger = $($c.expr); Assert-ScheduledTaskCadence -TaskName '$($c.name)' -Trigger `$trigger"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command $script 2>&1
    $rc = $LASTEXITCODE
    if ($rc -eq $c.expect) {
        Write-Output ("PASS  [{0}] {1} (exit={2})" -f $c.name, $c.label, $rc)
    } else {
        $fail++
        Write-Output ("FAIL  [{0}] {1} — 기대 exit={2}, 실제 exit={3}" -f $c.name, $c.label, $c.expect, $rc)
        foreach ($l in $out) { Write-Output "        $l" }
    }
}

if ($fail -gt 0) { Write-Output "`n결과: $fail 건 FAIL"; exit 1 }
Write-Output "`n결과: $($cases.Count) 건 전부 PASS"
exit 0
