# capped-wait.ps1 — 잡(Start-Job) 하나를 상한 시간 안에서만 대기하는 순수 오케스트레이션 (giip 4431 항목 2)
#
# 배경: REPO-MAINT(저장소 정비) 세션은 Invoke-GissueEngine 를 시간박스 없이 직접 호출해, 엔진이 멈추면
#   정비 세션이 러너 전체 예산(TIMEOUT 105분)을 통째로 삼켰다(giip 4428 실측: TIMEOUT 으로 회수된 잡
#   출력이 전부 정비 세션의 엔진 호출 줄에서 끝났다). 이슈 1건 처리에는 이미 캡이 있지만(giip #1565)
#   정비 세션엔 없었다. 이 함수는 이슈 1건 timebox 와 같은 "Start-Job + Wait-Job -Timeout 폴링 + 캡"
#   판정을 포트 주입으로 분리해, 정비 세션도 캡(기본 20분) 안에서만 대기하고 넘으면 정리 후 이슈 순회로
#   진행하게 한다.
#
# 순수성: 실제 대기(Wait-Job)·상태 조회(Job.State)는 호출부가 넘기는 포트로 한다. 테스트는 가짜 포트로
#   "캡 내 완료"와 "캡 초과" 두 경로를 검증한다(tests/test-repomaint-cap.ps1). PowerShell 5.1 호환.

# CapMin 안에서 PollMin 간격으로 잡을 대기한다. Ports: IsRunning = { [bool] }, Wait = { param($sec) }.
# 반환: TimedOut(캡까지 대기한 뒤에도 아직 running 이면 $true), ElapsedMin(실제로 센 대기 분).
function Invoke-GissueCappedJobWait([int]$CapMin, [int]$PollMin, $Ports) {
    if ($PollMin -le 0) { $PollMin = 1 }
    $elapsed = 0
    while ((& $Ports.IsRunning) -and $elapsed -lt $CapMin) {
        & $Ports.Wait ($PollMin * 60)
        $elapsed += $PollMin
    }
    [pscustomobject]@{ TimedOut = [bool](& $Ports.IsRunning); ElapsedMin = $elapsed }
}
