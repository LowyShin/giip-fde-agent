# run-finalize.ps1 — gissue Phase 2 잡 종료 후처리 분리(giip 4431 항목 1) 순수 로직 + 포트 주입
#
# 배경(giip 4431 항목 1): Phase 2 대기 루프에서 한 CSN 잡이 끝나면 Complete-Run 이 PR 게이트 스윕·
#   REVIEW/DONE 감사·귀속 스윕·worktree 정리·로그 전송 등 5~7개 사후 스윕을 **동기적으로 연달아**
#   수행했다. 이 스윕 합계가 1시간 이상 걸리면(CSN 47 실측 02:50~04:09, 약 1h19m) 그동안 `foreach`
#   루프가 그 Complete-Run 줄에서 블로킹돼 **다른 잡의** 과시간/TIMEOUT/좀비 판정이 전혀 수행되지
#   않았다. 이 파일은 "잡 종료 즉시 수행할 선점 해제/기록"과 "느려도 되는 사후 스윕"을 분리하는
#   순수 로직을 둔다 — 스윕을 큐에 쌓고, 루프가 한 바퀴 돌 때마다 **반복당 시간예산** 안에서만
#   처리해, 한 스윕이 길어도 다음 바퀴의 마감 판정을 막지 않게 한다(giip 4429 Option A).
#
# 처리 내용 / 저장 위치 / 소비처
#   - 이 파일은 파일/DB/네트워크에 직접 아무것도 쓰지 않는다. 실제 스윕 실행·시각 조회는 호출부가
#     넘기는 포트(스크립트블록)를 통한다.
#   - 소비처: run-gissue-claude.ps1 Phase 2 대기 루프(Complete-Run 의 빠른 종료 경로 + 큐 처리 +
#             루프 종료 후 drain), tests/test-complete-run-nonblocking.ps1(가짜 포트로 전 경로 검증).
#
# 이 파일은 자기완결적이다(러너의 다른 함수를 부르지 않는다). 테스트 가능하도록 현재 시각·스윕 실행은
# 전부 포트로 받는다. PowerShell 5.1 호환.

$script:GissuePostProcessStepNames = @(
    'PrGateSweep', 'ReviewDoneAudit', 'PrAttributionSweep',
    'WorktreeCleanup', 'WorktreeDailySweep', 'LogShip', 'RepairRootOwned'
)
# 반복당 사후 스윕 처리 시간예산(초). 넘으면 (최소 1건 처리 후) 루프로 양보해 다른 잡의 마감 판정이
# 돌게 한다. GISSUE_POSTPROC_BUDGET_SEC 로 덮어쓸 수 있다(기본 90초).
$script:GissuePostProcessDefaultBudgetSec = 90

# 종료한 잡 1건이 남길 사후 스윕 큐 항목(순수). Action 스크립트블록에 $r 를 가두지 않도록 Csn/Workdir 를
# 값으로 담아 두고, 실제 실행은 호출부의 Run 포트가 Label 로 분기한다(PowerShell 스크립트블록은 클로저가
# 아니라 실행 스코프의 변수를 늦게 바인딩하므로, 루프에서 캡처한 $r 를 그대로 쓰면 틀어진다).
function Get-GissuePostProcessItems($Csn, $Workdir) {
    @($script:GissuePostProcessStepNames | ForEach-Object {
        [pscustomobject]@{ Key = "csn${Csn}:$_"; Label = $_; Csn = $Csn; Workdir = $Workdir }
    })
}

# 예산 파싱: 양의 정수 초. 비었거나 0 이하면 기본값.
function Resolve-GissuePostProcessBudgetSec($Value) {
    if ($null -eq $Value) { return $script:GissuePostProcessDefaultBudgetSec }
    $s = "$Value".Trim()
    $n = 0
    if ([int]::TryParse($s, [ref]$n) -and $n -gt 0) { return $n }
    return $script:GissuePostProcessDefaultBudgetSec
}

# 큐를 반복당 예산 안에서 처리(순수 오케스트레이션). $Queue 는 ArrayList(앞에서부터 꺼낸다).
#   Ports: Now = { [datetime] }, Run = { param($item) 스윕 실행(예외는 이 함수가 삼켜 Errors 에 담는다) }
#   -Drain: 예산 무시하고 남은 전부 처리(루프 종료 후 호출용).
# 동작: 최소 1건은 반드시 처리(기아 방지)하고, 그 뒤에는 (Now-start) >= BudgetSeconds 이면 멈춰 양보한다.
#   한 스윕이 예산보다 오래 걸려도(동기 실행이라 중간에 끊을 수 없다) 그 1건만 처리하고 즉시 반환하므로,
#   예전처럼 5~7개를 연달아 다 돌 때까지 블로킹되지 않는다.
function Step-GissuePostProcessQueue {
    param(
        $Queue,
        [double]$BudgetSeconds,
        $Ports,
        [switch]$Drain
    )
    $ran = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $start = & $Ports.Now
    $processedAtLeastOne = $false
    while (@($Queue).Count -gt 0) {
        if (-not $Drain -and $processedAtLeastOne) {
            $elapsed = (( & $Ports.Now ) - $start).TotalSeconds
            if ($elapsed -ge $BudgetSeconds) { break }
        }
        $item = $Queue[0]
        $Queue.RemoveAt(0)
        try { $null = & $Ports.Run $item; [void]$ran.Add($item.Key) }
        catch { [void]$errors.Add("$($item.Key): $($_.Exception.Message)") }
        $processedAtLeastOne = $true
    }
    [pscustomobject]@{ Ran = $ran; Errors = $errors; Remaining = @($Queue).Count }
}
