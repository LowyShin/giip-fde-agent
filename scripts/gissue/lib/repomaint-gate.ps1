# repomaint-gate.ps1 — 저장소 정비(REPO-MAINT) 세션 "사전 체크 게이트" 판정 (giip #5671 · 정비 세션 토큰 절감)
#
# 배경: CSN 마다 매시간 REPO-MAINT 세션을 엔진으로 기동한다. 정비 대상이 0건인 회차에도 세션이
#   기동돼 토큰을 쓰고 work_history 기록(PR 포함)까지 연다. 대상 0건이면 **세션 자체를 띄우지
#   않는 것**이 가장 확실한 절감이라 "대상 수를 세고 합계 0이면 건너뛴다"를 스크립트(LLM 이전)
#   단계로 옮긴다. 판정 정본은 이 파일 한 곳이다(규칙 48).
#
# 단계별 대상 정의(정비 프롬프트의 [0]/[E]/[F]/[H] 블록과 1:1):
#   [0] 열린 PR 중 mergeable == 'CONFLICTING' 인 PR 수            → conflict 해소 대상
#   [E] 열린 PR 중 statusCheckRollup 에 'FAILURE' 가 있는 PR 수   → CI/검증 실패 대상
#   [F] git stash 목록 중 메시지가 'auto-unblock ' 로 시작하는 수  → orphan stash 구조 대상
#   [H] 최근 2시간 내 코멘트가 있는 이슈 수                       → 최근 코멘트 재검증 대상
#
# 대상에 넣지 않는 것: 머지된 PR 의 워크트리 회수 같은 호스트 로컬 정리는 정비 대상이 아니다.
#   그 정리는 스케줄러의 잡 종료 후처리 스크립트 단계(Invoke-GissueWorktreeCleanup)가 AI 없이
#   수행하므로 합계에 세지 않고, 세션 안에서도 기록 파일·PR 의 근거가 되지 않는다 — 회수가
#   필요한 워크트리가 있다는 이유만으로 세션을 띄우거나 기록 PR 을 만들지 않는다.
#
# 순수성: 실제 조회(gh pr list / git stash list / list-issues.js)는 **호출부가 포트로 주입**한다
#   (lib/capped-wait.ps1 와 같은 컨벤션). 테스트는 가짜 포트로 합계·판정만 검증한다
#   (tests/test-repomaint-gate.ps1). PowerShell 5.1 호환.
#
# fail-open: 게이트는 "어디까지 했는가"만 알려 주는 보조 장치다. 조회가 실패하면(git hub 불가 등)
#   판정 자체가 실패한 것이므로 호출부가 예외를 받아 종전대로 세션을 기동한다. 이 파일은 예외를
#   삼키지 않는다 — 삼키면 "조회 실패"와 "대상 0건"이 구분되지 않는다.
#
# 정비 전면 중지 (2026-11-21 운영 지시): Test-RepoMaintEnabled 가 $false 인 동안은 대상 수와
#   무관하게 정비 세션을 기동하지 않는다. 수정 0건 회차의 기록 PR 이 반복 생성돼 토큰만 소모된
#   것이 계기다. 재개는 이 함수의 반환값을 바꾸는 PR 로만 한다 — 환경변수나 호스트 로컬 설정
#   으로는 켤 수 없다(켜는 경로가 흩어지면 중지 상태가 조용히 풀리는 사고가 재발한다).

# [E] 판정: 열린 PR 의 statusCheckRollup 에 실패(FAILURE) 체크가 하나라도 있는가.
# gh 의 statusCheckRollup 항목은 CheckRun(conclusion/state) 과 StatusContext(state) 가 섞여
# 나올 수 있어 conclusion·state 두 필드를 모두 본다.
function Test-RepoMaintPrHasFailure($pr) {
    if (-not $pr) { return $false }
    foreach ($chk in @($pr.statusCheckRollup)) {
        if (-not $chk) { continue }
        foreach ($field in @('conclusion', 'state')) {
            $val = "$($chk.$field)"
            if ($val -and $val.ToUpperInvariant() -eq 'FAILURE') { return $true }
        }
    }
    return $false
}

# [F] 판정: git stash 목록 한 줄에서 stash 메시지 부분만 뽑아 'auto-unblock ' 접두사인지 본다.
# 목록 줄 형식: "stash@{0}: auto-unblock 2026-11-20 10:00: rescued from merged branch <브랜치>"
# (메시지 안에도 ':' 가 들어갈 수 있어 뒤쪽은 전부 메시지로 본다).
function Test-RepoMaintStashIsAutoUnblock([string]$line) {
    if (-not $line) { return $false }
    # -match 로 검사한다 — -notmatch 로 검사하면 "일치하지 않아서 $Matches 가 이전 값으로 남는" 함정이 있다.
    if ($line -match '^\s*stash@\{\d+\}:\s*(.*)$') {
        return ($Matches[1] -match '^auto-unblock ')
    }
    return $false
}

# 단계별 대상 수 + 합계를 센다.
# Ports:
#   OpenPrs                = { @([pscustomobject]@{ number; mergeable; statusCheckRollup }) }  ← 열린 PR 목록
#   StashList              = { @('stash@{0}: auto-unblock …') }                              ← git stash list 출력 줄
#   RecentCommentIssueCount= { <int> }                                                     ← 최근 2시간 내 코멘트 이슈 수
# 반환: [pscustomobject]@{ Stage0; StageE; StageF; StageH; Total }
function Get-RepoMaintTargetCounts {
    param([Parameter(Mandatory)]$Ports)

    $stage0 = 0   # [0] conflict 난 열린 PR
    $stageE = 0   # [E] CI/검증 실패 열린 PR
    $stageF = 0   # [F] orphan auto-unblock stash
    $stageH = 0   # [H] 최근 2시간 내 코멘트 이슈

    foreach ($pr in @(& $Ports.OpenPrs)) {
        if (-not $pr) { continue }
        if ("$($pr.mergeable)".ToUpperInvariant() -eq 'CONFLICTING') { $stage0++ }
        if (Test-RepoMaintPrHasFailure $pr) { $stageE++ }
    }
    foreach ($line in @(& $Ports.StashList)) {
        if (Test-RepoMaintStashIsAutoUnblock "$line") { $stageF++ }
    }
    $recentRaw = & $Ports.RecentCommentIssueCount
    if ($null -ne $recentRaw) { $stageH = [int](@($recentRaw)[0]) }

    [pscustomobject]@{
        Stage0 = $stage0
        StageE = $stageE
        StageF = $stageF
        StageH = $stageH
        Total  = ($stage0 + $stageE + $stageF + $stageH)
    }
}

# 정비 마스터 스위치 — $true 일 때만 정비가 동작한다.
# 2026-11-21 운영 지시로 $false(전면 중지). 재개 절차는 파일 헤더의 "정비 전면 중지" 주석 참조.
function Test-RepoMaintEnabled {
    return $false
}

# 정비 세션을 띄워야 하는가 — 정비 중지 중이면 무조건 false, 아니면 합계 1건 이상이면 true.
# Counts 는 Get-RepoMaintTargetCounts 의 반환값이다.
function Test-RepoMaintNeeded {
    param([Parameter(Mandatory)]$Counts)
    if (-not (Test-RepoMaintEnabled)) { return $false }
    $total = 0
    if ($null -ne $Counts.Total) {
        $total = [int]$Counts.Total
    } else {
        foreach ($field in @('Stage0', 'StageE', 'StageF', 'StageH')) { $total += [int]$Counts.$field }
    }
    return ($total -ge 1)
}
