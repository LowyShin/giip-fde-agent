# task-cadence-guard.ps1 — Windows 작업 스케줄러 "이름과 실제 실행 주기가 맞는가" 사전검증 게이트
#
# 배경 (giip #2480, 2026-09-14):
#   `GIIP_StalePending_Hourly` / `GIIP_StaleReview_Hourly` 두 태스크가 **이름은 _Hourly 인데 실제로는
#   하루 1회만** 돌고 있었다. 등록 스크립트가
#       New-ScheduledTaskTrigger -Weekly -DaysOfWeek <7일> -At 00:07
#   로 트리거를 만들면서 반복(Repetition)을 아예 넣지 않았기 때문이다. 등록은 성공하고 태스크는 Ready 로
#   보이며 LastTaskResult 도 0 이라, **아무도 실패를 눈치채지 못한 채** 대시보드 ③층의
#   STALE_PENDING / STALE_REVIEW 배지가 최대 24시간 묵은 판정을 띄웠다(실측: tAuditStalePendingResult
#   최신 checked_at 이 17시간 넘게 묵어 있었고 그 사이 상태가 바뀐 isn 2398 이 잘못된 배지를 달고 있었다).
#
#   더 나쁜 것은 이 불일치가 **사람 눈으로도 두 번 통과했다**는 점이다. giip #2429 에서 같은 파일을
#   직접 읽으며 파싱 에러를 고쳤는데, 바로 옆 줄의 `-Weekly ... -At 00:07` 과 이름의 `Hourly` 가
#   어긋난 것은 지적되지 않았다. 그래서 "사람이 보면 안다"에 기대지 않고 **등록 직전 기계 검사**로 막는다.
#
#   선행 게이트인 task-target-guard.ps1(giip #2431)은 "대상 .ps1 이 존재/파싱/비-worktree 인가"를 본다.
#   그건 **무엇을 실행하는가**의 검사이고, 이 파일은 **얼마나 자주 실행하는가**의 검사다. 관심사가 달라
#   파일을 나눈다(이 환경 방침: 파일은 최대한 분리).
#
# 사용(등록 스크립트에서 dot-source, `Register-ScheduledTask` 직전에 호출):
#   . (Join-Path $PSScriptRoot 'task-cadence-guard.ps1')
#   Assert-ScheduledTaskCadence -TaskName $TaskName -Trigger $trigger
#
# 판정 (태스크 이름 기준, 대소문자 무시):
#   · 이름에 'Hourly' 가 있으면 → 반복 간격이 **정확히 1시간**이어야 한다. 반복이 없거나 다른 값이면 거부.
#     반복 기간(Duration)은 비어 있거나(무기한) 1일 이상이어야 한다 — 몇 시간짜리 기간을 주면 그 뒤로
#     조용히 멈춘다.
#   · 이름에 'Daily' 가 있으면 → 반복 간격이 없거나 1일 이상이어야 한다(1시간 반복인데 이름이 Daily 면 거짓).
#   · 둘 다 아니면 통과(주기를 이름으로 약속하지 않은 태스크).
#
# 참고 — 정상 형태 2종 (둘 다 실제로 매시 :07 에 돈다):
#   (A) GIIP_Gissue_Claude / GIIP_AuditReviewPrs_Hourly / GIIP_SlackbotRestart_Hourly
#       New-ScheduledTaskTrigger -Once -At <시각> -RepetitionInterval (New-TimeSpan -Hours 1) `
#                                -RepetitionDuration (New-TimeSpan -Days 3650)
#       ⚠️ RepetitionDuration 에 [TimeSpan]::MaxValue 를 쓰면 Task Scheduler XML 상한을 넘겨 등록이
#          HRESULT 0x80041318 로 거부된다(giip #1275). 약 10년(3650일)을 쓴다.
#   (B) GIIP_GateEscalation_Hourly
#       Daily 트리거(매일 재무장) + Repetition PT1H / P1D. 매일 00:07 에 다시 시작해 24시간 동안 매시 반복.
#
# 실패 시 사유를 출력하고 **호출 스크립트를 종료코드 1 로 즉시 종료**한다(등록 안 됨).

# task-target-guard.ps1 과 같은 이유로 콘솔 출력을 UTF-8 로 고정한다(이 PC 기본은 cp932 라 한글이 깨진다).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function ConvertFrom-TaskIso8601Duration {
    <#
        Task Scheduler 트리거의 Repetition.Interval / .Duration 은 'PT1H', 'P3650D' 같은 ISO 8601
        문자열이다(설정하지 않으면 $null). TimeSpan 으로 바꿔 돌려주고, 비었거나 해석 불가면 $null.
    #>
    param([string]$Iso)

    if ([string]::IsNullOrWhiteSpace($Iso)) { return $null }
    try { return [System.Xml.XmlConvert]::ToTimeSpan($Iso) } catch { return $null }
}

function Assert-ScheduledTaskCadence {
    <#
        Register-ScheduledTask 직전에 호출한다. 태스크 이름이 약속한 주기와 트리거의 실제 반복 설정이
        어긋나면 사유를 출력하고 exit 1 한다.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)]$Trigger
    )

    $intervalIso = $null
    $durationIso = $null
    if ($Trigger -and $Trigger.Repetition) {
        $intervalIso = [string]$Trigger.Repetition.Interval
        $durationIso = [string]$Trigger.Repetition.Duration
    }
    $interval = ConvertFrom-TaskIso8601Duration -Iso $intervalIso
    $duration = ConvertFrom-TaskIso8601Duration -Iso $durationIso

    $shown = if ($intervalIso) { $intervalIso } else { '(없음)' }
    $shownDur = if ($durationIso) { $durationIso } else { '(무기한)' }
    Write-Output "[CADENCE-GUARD] $TaskName — Repetition.Interval=$shown Duration=$shownDur"

    $problems = @()

    if ($TaskName -match '(?i)hourly') {
        if ($null -eq $interval) {
            $problems += "이름에 'Hourly' 가 있는데 반복 간격이 전혀 없습니다(하루 1회만 실행됨) — giip #2480 과 동일한 결함"
        } elseif ($interval -ne [TimeSpan]::FromHours(1)) {
            $problems += "이름에 'Hourly' 가 있는데 반복 간격이 1시간이 아닙니다(Interval=$intervalIso)"
        }
        if ($null -ne $duration -and $duration -lt [TimeSpan]::FromDays(1)) {
            $problems += "반복 기간이 1일 미만입니다(Duration=$durationIso) — 그 뒤로는 조용히 멈춥니다"
        }
    } elseif ($TaskName -match '(?i)daily') {
        if ($null -ne $interval -and $interval -lt [TimeSpan]::FromDays(1)) {
            $problems += "이름에 'Daily' 가 있는데 반복 간격이 1일 미만입니다(Interval=$intervalIso) — 실제로는 더 자주 돕니다"
        }
    } else {
        Write-Output "[CADENCE-GUARD][SKIP] 이름이 주기를 약속하지 않음 — 검사 없음"
        return
    }

    if ($problems.Count -gt 0) {
        Write-Output ""
        Write-Output "[CADENCE-GUARD][BLOCKED] $TaskName 등록을 중단합니다($($problems.Count)건):"
        foreach ($p in $problems) { Write-Output "  - $p" }
        Write-Output "  정상 형태: New-ScheduledTaskTrigger -Once -At <시각> -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)"
        exit 1
    }

    Write-Output "[CADENCE-GUARD][PASS] 이름과 실제 반복 주기가 일치"
}
